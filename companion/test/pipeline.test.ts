import { describe, expect, it } from "vitest";
import type { QHEvent } from "../src/types.js";
import { findSittings } from "../src/pipeline/segment.js";
import { dateSitting, VOYAGE_DAYS } from "../src/pipeline/calendar.js";
import { classify, matchHooks, scoreEvent } from "../src/pipeline/score.js";
import { buildDigest } from "../src/pipeline/digest.js";
import { normalizeBody } from "../src/llm/write.js";

describe("normalizeBody", () => {
  it("turns double-escaped newlines into paragraph breaks", () => {
    expect(normalizeBody("One.\\n\\nTwo.\\nThree.  \n\n\n\nFour.")).toBe("One.\n\nTwo.\nThree.\n\nFour.");
  });
});

let seq = 0;
let clock = 1_800_000_000;
function ev(type: string, extra: Partial<QHEvent> = {}): QHEvent {
  seq += 1;
  clock += 300;
  return { seq, t: clock, type, zone: "Westfall", continent: "Eastern Kingdoms", level: 15, ...extra };
}

describe("segment", () => {
  it("splits events into sittings closed by rests and leaves the tail pending", () => {
    seq = 0;
    const events = [ev("quest_done"), ev("rest"), ev("rest"), ev("zone"), ev("quest_done"), ev("rest"), ev("death")];
    const sittings = findSittings(events, 0);
    expect(sittings.map((s) => s.rest.seq)).toEqual([2, 3, 6]);
    expect(sittings[1].events).toEqual([]); // two rests in a row
    expect(sittings[2].events.map((e) => e.seq)).toEqual([4, 5]);
    // the death after the last rest waits for the next rest
    expect(findSittings(events, 6)).toEqual([]);
  });
});

describe("calendar", () => {
  it("adds voyage days on continent changes and a day after long idle gaps", () => {
    seq = 0;
    const a = ev("quest_done");
    const b = ev("zone", { continentChanged: true, from: "Wetlands", zone: "Darkshore", continent: "Kalimdor" });
    const c = { ...ev("quest_done"), t: b.t + 8 * 3600 };
    const { dated, endDay } = dateSitting([a, b, c], 3);
    expect(dated.map((d) => d.day)).toEqual([3, 3 + VOYAGE_DAYS, 4 + VOYAGE_DAYS]);
    expect(dated[1].timeSkip?.reason).toBe("voyage");
    expect(dated[2].timeSkip?.reason).toBe("idle");
    expect(endDay).toBe(4 + VOYAGE_DAYS);
  });
});

describe("score", () => {
  it("matches hooks on word starts", () => {
    expect(matchHooks("slay rockhide boars near the farm", ["boar"])).toEqual(["boar"]);
    expect(matchHooks("climb aboard the ship", ["boar"])).toEqual([]);
  });

  it("makes a character's fear a key moment", () => {
    seq = 0;
    const plain = scoreEvent(ev("quest_done", { title: "Collect Wool" }), ["boar"]);
    const fear = scoreEvent(ev("quest_done", { title: "Boar Hunting", objectives: "Kill 10 Rockhide Boars" }), ["boar"]);
    expect(fear.score).toBeGreaterThan(plain.score);
    expect(fear.hooks).toEqual(["boar"]);
  });

  it("caps the number of key moments", () => {
    seq = 0;
    const events = Array.from({ length: 10 }, () => ev("death"));
    const result = classify(events, []);
    expect([...result.values()].filter((r) => r.importance === "key")).toHaveLength(6);
  });
});

describe("digest", () => {
  it("always keeps the player's notes as key moments, even past the cap", () => {
    seq = 0;
    const events = [...Array.from({ length: 8 }, () => ev("death")), ev("note", { text: "I miss home." })];
    const d = buildDigest(events, ev("rest", { kind: "rested" }), 1, []);
    const notes = d.threads.flatMap((t) => t.moments).filter((m) => m.note);
    expect(notes).toHaveLength(1);
    expect(notes[0].importance).toBe("key");
    expect(notes[0].note).toBe("I miss home.");
  });

  it("groups by thread, folds accept into turn-in, narrates travel and collapses errands", () => {
    seq = 0;
    const events = [
      ev("quest_accept", { questID: 1, title: "The Defias Brotherhood", questLine: "The Defias Brotherhood", text: "Gryan Stoutmantle needs you." }),
      ev("quest_done", { questID: 2, title: "Small Errand A" }),
      ev("quest_done", { questID: 3, title: "Small Errand B" }),
      ev("zone", { from: "Westfall", zone: "Wetlands", firstVisit: true }),
      ev("zone", { from: "Wetlands", zone: "Darkshore", continent: "Kalimdor", fromContinent: "Eastern Kingdoms", continentChanged: true }),
      ev("quest_done", { questID: 1, title: "The Defias Brotherhood", questLine: "The Defias Brotherhood", rewardText: "Well done." }),
    ];
    const rest = ev("rest", { zone: "Darkshore", subzone: "Auberdine", kind: "rested" });
    const d = buildDigest(events, rest, 1, []);

    const defias = d.threads.find((t) => t.name === "The Defias Brotherhood")!;
    expect(defias.moments).toHaveLength(1); // accept folded into the turn-in
    expect(defias.moments[0].story).toBe("Gryan Stoutmantle needs you.");
    expect(defias.moments[0].outcome).toBe("Well done.");
    expect(defias.moments[0].day).toBe(1 + 4);

    expect(d.journey.some((j) => j.description.startsWith("Voyaged from Eastern Kingdoms to Kalimdor"))).toBe(true);
    expect(d.collapsed).toEqual(["2 small errands and odd jobs around Westfall"]);
    expect(d.restPlace).toBe("Auberdine, Darkshore");
    expect(d.endDay).toBe(5);
  });
});
