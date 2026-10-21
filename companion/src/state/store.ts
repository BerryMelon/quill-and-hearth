// Companion state per character: the source of truth for written entries and story continuity.
import { existsSync, mkdirSync, readFileSync } from "node:fs";
import { join } from "node:path";
import type { JournalEntry } from "../types.js";
import type { Brief } from "../llm/brief.js";
import { EMPTY_MEMORY, type StoryMemory } from "../llm/write.js";
import { writeFileAtomic } from "../savedvars/serialize.js";

export interface CharacterState {
  version: 1;
  charKey: string;
  processedThrough: number;
  nextDay: number;
  brief?: Brief;
  briefHash?: string;
  memory: StoryMemory;
  entries: JournalEntry[];
}

function fileFor(dataDir: string, charKey: string): string {
  return join(dataDir, `${charKey.replace(/[^\w.-]/g, "_")}.json`);
}

export function loadState(dataDir: string, charKey: string): CharacterState {
  const path = fileFor(dataDir, charKey);
  if (existsSync(path)) return JSON.parse(readFileSync(path, "utf8")) as CharacterState;
  return {
    version: 1,
    charKey,
    processedThrough: 0,
    nextDay: 1,
    memory: structuredClone(EMPTY_MEMORY),
    entries: [],
  };
}

export function saveState(dataDir: string, state: CharacterState): void {
  mkdirSync(dataDir, { recursive: true });
  writeFileAtomic(fileFor(dataDir, state.charKey), JSON.stringify(state, null, 2));
}
