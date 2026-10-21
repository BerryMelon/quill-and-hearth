// Significance scoring: decide which events deserve a place in the journal.
import type { QHEvent } from "../types.js";

export type Importance = "key" | "minor" | "background";

export const KEY_THRESHOLD = 5;
export const MINOR_THRESHOLD = 2;
export const MAX_KEY_MOMENTS = 6;

export interface ScoredEvent {
  event: QHEvent;
  score: number;
  reasons: string[];
  /** Character-brief hooks (fears, goals, ...) this event touches. */
  hooks: string[];
}

function textOf(e: QHEvent): string {
  return [e.title, e.text, e.objectives, e.rewardText, e.questLine, e.instance, e.zone]
    .filter(Boolean)
    .join(" ")
    .toLowerCase();
}

/** Whole-word-ish match so "boar" matches "Boars" but not "aboard". */
export function matchHooks(text: string, hooks: string[]): string[] {
  return hooks.filter((hook) => {
    const h = hook.toLowerCase().trim();
    if (!h) return false;
    const escaped = h.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
    return new RegExp(`\\b${escaped}`, "i").test(text);
  });
}

export function scoreEvent(e: QHEvent, hooks: string[]): ScoredEvent {
  let score = 0;
  const reasons: string[] = [];
  const add = (n: number, why: string) => {
    score += n;
    reasons.push(why);
  };

  switch (e.type) {
    case "quest_done": {
      add(1, "quest completed");
      if ((e.rewardText?.length ?? 0) > 80) add(1, "has a story");
      if (e.questLine) add(2, "part of a quest line");
      if (e.elite || e.tag === "Elite") add(2, "elite");
      if ((e.suggestedGroup ?? 0) > 1 || e.tag === "Group" || e.tag === "Dungeon") add(2, "group quest");
      if ((e.rewardText?.length ?? 0) > 200) add(1, "rich story text");
      if (e.party?.length) add(1, "with companions");
      if (e.frequency) add(-3, "repeatable");
      break;
    }
    case "quest_accept":
      add(1, "quest accepted");
      if (e.text) add(1, "has a story");
      break;
    case "zone":
      if (e.continentChanged) add(5, "crossed to another continent");
      if (e.firstVisit) add(3, "first visit");
      break;
    case "instance_enter":
      add(6, "entered a dungeon");
      break;
    case "death":
      add(5, "died");
      break;
    case "level":
      add((e.level ?? 0) % 10 === 0 ? 5 : 2, (e.level ?? 0) % 10 === 0 ? "level milestone" : "grew stronger");
      break;
    case "bind":
      add(3, "found a new home");
      break;
    case "hearth":
    case "flight_start":
    case "flight_end":
    case "instance_leave":
      add(1, "travel");
      break;
  }

  const matched = matchHooks(textOf(e), hooks);
  if (matched.length) add(5, `touches the character: ${matched.join(", ")}`);

  return { event: e, score, reasons, hooks: matched };
}

/** Score a sitting and sort events into key / minor / background, capping key moments. */
export function classify(events: QHEvent[], hooks: string[]): Map<number, { scored: ScoredEvent; importance: Importance }> {
  const scored = events.map((e) => scoreEvent(e, hooks));
  const keyCandidates = scored
    .filter((s) => s.score >= KEY_THRESHOLD)
    .sort((a, b) => b.score - a.score || a.event.seq - b.event.seq);
  const keySeqs = new Set(keyCandidates.slice(0, MAX_KEY_MOMENTS).map((s) => s.event.seq));

  const result = new Map<number, { scored: ScoredEvent; importance: Importance }>();
  for (const s of scored) {
    const importance: Importance = keySeqs.has(s.event.seq)
      ? "key"
      : s.score >= MINOR_THRESHOLD
        ? "minor"
        : "background";
    result.set(s.event.seq, { scored: s, importance });
  }
  return result;
}
