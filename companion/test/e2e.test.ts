import { describe, expect, it } from "vitest";
import { fileURLToPath } from "node:url";
import { parseSavedVariablesFile, parseSavedVariablesSource } from "../src/savedvars/parse.js";
import { processCharacter, readCharacters } from "../src/process.js";
import { createMockLLM } from "../src/llm/mock.js";
import { renderGenerated } from "../src/state/generated.js";
import type { CharacterState } from "../src/state/store.js";

const fixture = fileURLToPath(new URL("./fixtures/sample-savedvars.lua", import.meta.url));

function freshState(charKey: string): CharacterState {
  return { version: 1, charKey, processedThrough: 0, nextDay: 1, memory: { summary: "", people: [], places: [], openThreads: [] }, entries: [] };
}

describe("end-to-end with the mock LLM", () => {
  it("writes one entry per rest and produces a valid Entries.lua", async () => {
    const db = readCharacters(parseSavedVariablesFile(fixture));
    const charKey = "Flonsus-ClassicBetaPvE";
    const llm = createMockLLM();
    const { state, written } = await processCharacter(charKey, db.characters[charKey], freshState(charKey), llm);

    expect(written).toHaveLength(2);
    expect(written.map((e) => e.day)).toEqual([1, 2]);
    expect(state.processedThrough).toBe(5);
    expect(state.nextDay).toBe(3);
    expect(state.brief?.name).toBe("Flonsus");
    expect(written[1].body).toContain("Discipline");

    // Running again writes nothing new.
    const again = await processCharacter(charKey, db.characters[charKey], state, llm);
    expect(again.written).toHaveLength(0);

    // The generated Lua parses and carries processedThrough for pruning.
    const lua = renderGenerated([state], 123);
    const gen = parseSavedVariablesSource(Buffer.from(lua, "utf8").toString("latin1")).QuillAndHearth_Generated as any;
    expect(gen.characters[charKey].processedThrough).toBe(5);
    expect(gen.characters[charKey].entries).toHaveLength(2);
  });

  it("does not call the LLM when there is nothing to write", async () => {
    const db = readCharacters(parseSavedVariablesFile(fixture));
    const llm = createMockLLM();
    const { written } = await processCharacter("Grok-ClassicBetaPvE", db.characters["Grok-ClassicBetaPvE"], freshState("Grok-ClassicBetaPvE"), llm);
    expect(written).toHaveLength(0);
    expect(llm.calls).toHaveLength(0);
  });
});
