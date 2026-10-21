import { describe, expect, it } from "vitest";
import { fileURLToPath } from "node:url";
import { parseSavedVariablesFile, parseSavedVariablesSource } from "../src/savedvars/parse.js";
import { toLua } from "../src/savedvars/serialize.js";
import { readCharacters } from "../src/process.js";

const fixture = fileURLToPath(new URL("./fixtures/sample-savedvars.lua", import.meta.url));

describe("SavedVariables parsing", () => {
  it("reads the real addon SavedVariables", () => {
    const db = readCharacters(parseSavedVariablesFile(fixture));
    const flonsus = db.characters["Flonsus-ClassicBetaPvE"];
    expect(flonsus.meta?.class).toBe("Priest");
    expect(flonsus.events.map((e) => e.type)).toEqual(["quest_accept", "rest", "quest_done", "quest_done", "rest"]);
    expect(flonsus.events[0].text).toContain("Mass Graves");
    expect(flonsus.events[0].text).toContain("\n"); // escapes decoded

    // Empty event list ({} in Lua) becomes an empty array.
    expect(db.characters["Grok-ClassicBetaPvE"].events).toEqual([]);
    expect(db.characters["Grok-ClassicBetaPvE"].profile?.traits?.voice).toBe("Plain");
  });

  it("keeps UTF-8 text intact", () => {
    const parsed = parseSavedVariablesSource(Buffer.from('X = { name = "Aélindra Ševčík — 영웅" }', "utf8").toString("latin1"));
    expect((parsed.X as { name: string }).name).toBe("Aélindra Ševčík — 영웅");
  });

  it("round-trips through the Lua serializer", () => {
    const value = {
      version: 1,
      characters: {
        "Name-Realm": {
          processedThrough: 5,
          entries: [{ title: 'A "quoted" title', body: "Line one\n\nLine two \\ backslash", day: 2 }],
        },
      },
    };
    const lua = `Gen = ${toLua(value)}`;
    const back = parseSavedVariablesSource(Buffer.from(lua, "utf8").toString("latin1")).Gen;
    expect(back).toEqual(value);
  });
});
