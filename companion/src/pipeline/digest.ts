// Turn one sitting (events between two rests) into a compact, story-shaped digest for the LLM.
//
// Coherence rules:
//   - Moments are grouped into THREADS (quest line, otherwise zone), not listed in play order,
//     so interleaved questing reads as separate storylines.
//   - Travel is kept as a separate ordered JOURNEY, so jumps between places can be narrated.
//   - Low-value events are COLLAPSED into one-line summaries instead of being dropped silently.
import type { QHEvent } from "../types.js";
import { dateSitting, type DatedEvent } from "./calendar.js";
import { classify, type Importance } from "./score.js";

export interface DigestMoment {
  day: number;
  importance: Exclude<Importance, "background">;
  kind: string;
  title?: string;
  place: string;
  story?: string;
  outcome?: string;
  companions?: string[];
  touches?: string[];
  why: string[];
}

export interface DigestThread {
  name: string;
  moments: DigestMoment[];
}

export interface JourneyBeat {
  day: number;
  description: string;
}

export interface Digest {
  startDay: number;
  endDay: number;
  restPlace: string;
  restKind: string;
  threads: DigestThread[];
  journey: JourneyBeat[];
  collapsed: string[];
  isEmpty: boolean;
}

const STORY_MAX = 600;

/** Remove WoW color/escape codes and TRP3 markup, collapse whitespace. */
export function cleanText(s: string | undefined, max = STORY_MAX): string | undefined {
  if (!s) return undefined;
  let t = s
    .replace(/\|c[0-9a-fA-F]{8}/g, "")
    .replace(/\|r/g, "")
    .replace(/\|n/g, "\n")
    .replace(/\{[^}]*\}/g, "")
    .replace(/\r\n?/g, "\n")
    .replace(/[ \t]+/g, " ")
    .replace(/\n{3,}/g, "\n\n")
    .trim();
  if (!t) return undefined;
  if (t.length > max) t = t.slice(0, max).replace(/\s+\S*$/, "") + "...";
  return t;
}

function placeOf(e: QHEvent): string {
  return e.subzone && e.subzone !== e.zone ? `${e.subzone}, ${e.zone}` : (e.zone ?? "somewhere");
}

function journeyText(e: QHEvent, timeSkip: DatedEvent["timeSkip"]): string | undefined {
  switch (e.type) {
    case "zone":
      if (e.continentChanged) {
        return `Voyaged from ${e.fromContinent ?? e.from} to ${e.continent}, arriving in ${e.zone} (about ${timeSkip?.days ?? "several"} days at sea or in the air)`;
      }
      return `Travelled from ${e.from} into ${e.zone}${e.firstVisit ? " (first time here)" : ""}`;
    case "flight_start":
      return `Took a flight${e.destination ? ` toward ${e.destination}` : ""} from ${placeOf(e)}`;
    case "flight_end":
      return `Landed at ${placeOf(e)}`;
    case "hearth":
      return `Used a hearthstone to return home to ${e.home ?? "the inn"}`;
    case "bind":
      return `Made ${e.home ?? placeOf(e)} their new home`;
    case "instance_enter":
      return `Entered ${e.instance}`;
    case "instance_leave":
      return `Left ${e.instance}`;
    default:
      return undefined;
  }
}

export function buildDigest(events: QHEvent[], rest: QHEvent, startDay: number, hooks: string[]): Digest {
  const { dated, endDay } = dateSitting(events, startDay);
  const classified = classify(events, hooks);

  // Quest text: the accept event carries the story, the turn-in carries the outcome.
  const acceptByQuest = new Map<number, QHEvent>();
  const doneQuests = new Set<number>();
  for (const e of events) {
    if (e.type === "quest_accept" && e.questID) acceptByQuest.set(e.questID, e);
    if (e.type === "quest_done" && e.questID) doneQuests.add(e.questID);
  }

  const threads = new Map<string, DigestThread>();
  const journey: JourneyBeat[] = [];
  const backgroundTasks = new Map<string, number>(); // zone -> count of small quests

  for (const { event: e, day, timeSkip } of dated) {
    const travel = journeyText(e, timeSkip);
    if (travel) journey.push({ day, description: travel });

    const info = classified.get(e.seq)!;
    const isQuest = e.type === "quest_done" || e.type === "quest_accept";

    // An accepted quest that was also finished in this sitting is folded into the turn-in.
    if (e.type === "quest_accept" && e.questID && doneQuests.has(e.questID)) continue;

    if (info.importance === "background") {
      if (e.type === "quest_done") {
        const zone = e.zone ?? "the area";
        backgroundTasks.set(zone, (backgroundTasks.get(zone) ?? 0) + 1);
      }
      continue;
    }
    // Pure travel is already narrated in the journey; only keep it as a moment if it matters.
    if (travel && info.importance !== "key" && e.type !== "zone") continue;

    const accept = e.questID ? acceptByQuest.get(e.questID) : undefined;
    const moment: DigestMoment = {
      day,
      importance: info.importance,
      kind: e.type === "quest_done" ? "completed a task" : e.type === "quest_accept" ? "took on a task (NOT finished yet)" : e.type,
      title: e.title ?? e.instance,
      place: placeOf(e),
      story: isQuest ? cleanText(accept?.text ?? e.text) : undefined,
      outcome: e.type === "quest_done" ? cleanText(e.rewardText, 400) : undefined,
      companions: e.party?.map((p) => (p.class ? `${p.name} (${p.class})` : p.name)),
      touches: info.scored.hooks.length ? info.scored.hooks : undefined,
      why: info.scored.reasons,
    };
    if (e.type === "level") moment.title = `Reached level ${e.level}`;
    if (e.type === "zone") moment.title = e.continentChanged ? `Arrived in ${e.continent}` : `First time in ${e.zone}`;

    const threadName = e.questLine ?? e.zone ?? "Wandering";
    if (!threads.has(threadName)) threads.set(threadName, { name: threadName, moments: [] });
    threads.get(threadName)!.moments.push(moment);
  }

  const collapsed = [...backgroundTasks].map(([zone, n]) =>
    n === 1 ? `One small errand around ${zone}` : `${n} small errands and odd jobs around ${zone}`,
  );

  return {
    startDay,
    endDay,
    restPlace: placeOf(rest),
    restKind: rest.kind === "campfire" ? "by a campfire" : "at an inn",
    threads: [...threads.values()],
    journey,
    collapsed,
    isEmpty: threads.size === 0 && collapsed.length === 0 && journey.length === 0,
  };
}
