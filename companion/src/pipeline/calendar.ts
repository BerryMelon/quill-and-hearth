// In-character calendar: real play time is not story time.
//   - Each rest is a night's sleep: the next sitting starts on a new day.
//   - Crossing to another continent (by boat or zeppelin) takes days.
//   - A long real-time break between events without resting still counts as a new day.
import type { QHEvent } from "../types.js";

export const VOYAGE_DAYS = 4;
export const IDLE_GAP_SECONDS = 6 * 60 * 60;

export interface DatedEvent {
  event: QHEvent;
  day: number;
  /** Set on the first event after a jump in time, describing why time passed. */
  timeSkip?: { days: number; reason: "voyage" | "idle" };
}

/** Assign an in-world day to each event of a sitting that starts on `startDay`. */
export function dateSitting(events: QHEvent[], startDay: number): { dated: DatedEvent[]; endDay: number } {
  let day = startDay;
  let prevT: number | undefined;
  const dated: DatedEvent[] = [];

  for (const event of events) {
    let timeSkip: DatedEvent["timeSkip"];
    if (event.type === "zone" && event.continentChanged) {
      day += VOYAGE_DAYS;
      timeSkip = { days: VOYAGE_DAYS, reason: "voyage" };
    } else if (prevT !== undefined && event.t - prevT > IDLE_GAP_SECONDS) {
      day += 1;
      timeSkip = { days: 1, reason: "idle" };
    }
    dated.push({ event, day, timeSkip });
    prevT = event.t;
  }
  return { dated, endDay: day };
}
