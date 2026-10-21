// The pipeline: SavedVariables -> sittings -> digest -> LLM -> journal entries -> Entries.lua
import type { JournalEntry, QHCharacter, QHSavedVariables } from "./types.js";
import { findSittings } from "./pipeline/segment.js";
import { buildDigest } from "./pipeline/digest.js";
import { generateBrief, profileHash } from "./llm/brief.js";
import { normalizeBody, writeEntry } from "./llm/write.js";
import type { LLM } from "./llm/client.js";
import type { CharacterState } from "./state/store.js";

export type Log = (message: string) => void;

/**
 * Write journal entries for every completed sitting of one character.
 * Mutates and returns `state`. Stops at the first failure so nothing is skipped:
 * processedThrough only advances past sittings that were actually written.
 */
export async function processCharacter(
  charKey: string,
  char: QHCharacter,
  state: CharacterState,
  llm: LLM,
  log: Log = () => {},
): Promise<{ state: CharacterState; written: JournalEntry[]; error?: unknown }> {
  const written: JournalEntry[] = [];

  // The addon's sequence counter restarted (e.g. SavedVariables deleted): start over.
  if ((char.nextSeq ?? 1) - 1 < state.processedThrough) {
    log(`${charKey}: event counter was reset in game; starting a fresh read of the log.`);
    state.processedThrough = 0;
  }

  // Entries written in game (copy-paste bridge) already cover these events.
  const writtenInGame = char.journal?.processedThrough ?? 0;
  if (writtenInGame > state.processedThrough) {
    state.processedThrough = writtenInGame;
    state.nextDay = Math.max(state.nextDay, (char.journal?.nextDay ?? 1));
  }

  const sittings = findSittings(char.events ?? [], state.processedThrough);
  if (sittings.length === 0) return { state, written };

  // Refresh the character brief when the profile changed.
  const hash = profileHash(char.profile, char.meta);
  if (!state.brief || state.briefHash !== hash) {
    log(`${charKey}: reading the character sheet...`);
    state.brief = await generateBrief(llm, char.profile, char.meta);
    state.briefHash = hash;
  }

  for (const sitting of sittings) {
    const startDay = state.nextDay;
    const digest = buildDigest(sitting.events, sitting.rest, startDay, state.brief.hooks);

    if (digest.isEmpty) {
      log(`${charKey}: rest #${sitting.rest.seq} had nothing to write about; skipping.`);
    } else {
      log(`${charKey}: writing the entry for rest #${sitting.rest.seq} (day ${digest.startDay}${digest.endDay !== digest.startDay ? `-${digest.endDay}` : ""})...`);
      let result;
      try {
        result = await writeEntry(llm, state.brief, state.memory, digest, state.entries.map((e) => e.title));
      } catch (err) {
        // Keep everything written so far; this sitting will be retried next time.
        log(`${charKey}: could not write the entry for rest #${sitting.rest.seq}: ${String(err)}`);
        return { state, written, error: err };
      }
      const entry: JournalEntry = {
        id: `${charKey}:${sitting.rest.seq}`,
        restSeq: sitting.rest.seq,
        day: digest.startDay,
        dayEnd: digest.endDay,
        title: result.title.trim(),
        body: normalizeBody(result.body),
        zone: sitting.rest.zone,
        subzone: sitting.rest.subzone,
        restKind: sitting.rest.kind,
        level: sitting.rest.level,
        t: sitting.rest.t,
      };
      state.entries.push(entry);
      state.memory = result.memory;
      written.push(entry);
    }

    // A night's sleep: the next sitting starts the following day.
    state.nextDay = digest.endDay + 1;
    state.processedThrough = sitting.rest.seq;
  }

  return { state, written };
}

export function readCharacters(sv: Record<string, unknown>): QHSavedVariables {
  const db = sv.QuillAndHearthDB as QHSavedVariables | undefined;
  if (!db || typeof db !== "object" || !db.characters) return { characters: {} };
  for (const char of Object.values(db.characters)) {
    // Empty Lua tables parse as {} rather than [].
    if (!Array.isArray(char.events)) char.events = [];
  }
  return db;
}
