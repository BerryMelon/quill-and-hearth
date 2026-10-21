// Split the event log into "sittings": everything between two rests.
import type { QHEvent } from "../types.js";

export interface Sitting {
  /** Events since the previous processed rest, excluding the closing rest marker. */
  events: QHEvent[];
  /** The rest marker that closes this sitting (the moment the character writes). */
  rest: QHEvent;
}

/**
 * Returns every complete sitting after `processedThrough` (a seq number), oldest first.
 * Events after the last rest are left alone: they belong to a journal entry not yet written.
 * Sittings with no events at all (e.g. two rests in a row) are skipped.
 */
export function findSittings(events: QHEvent[], processedThrough: number): Sitting[] {
  const pending = events.filter((e) => e.seq > processedThrough).sort((a, b) => a.seq - b.seq);
  const sittings: Sitting[] = [];
  let current: QHEvent[] = [];
  for (const e of pending) {
    if (e.type === "rest") {
      sittings.push({ events: current, rest: e });
      current = [];
    } else {
      current.push(e);
    }
  }
  return sittings;
}
