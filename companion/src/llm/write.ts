// Write one first-person journal entry for a sitting, and update the rolling story memory.
import { z } from "zod";
import type { Digest } from "../pipeline/digest.js";
import type { Brief } from "./brief.js";
import type { LLM } from "./client.js";

export const MemorySchema = z.object({
  summary: z.string().describe("The story so far, in under 150 words, third person, for continuity"),
  people: z.array(z.string()).describe("Named people met or mentioned that matter, with a few words each"),
  places: z.array(z.string()).describe("Places visited that matter, with a few words each"),
  openThreads: z.array(z.string()).describe("Unfinished business, promises, worries"),
});
export type StoryMemory = z.infer<typeof MemorySchema>;

export const EMPTY_MEMORY: StoryMemory = { summary: "", people: [], places: [], openThreads: [] };

export const EntrySchema = z.object({
  title: z.string().describe("A short evocative title for this journal entry (2-6 words)"),
  body: z.string().describe("The journal entry itself. Paragraphs separated by a blank line."),
  memory: MemorySchema.describe("The updated story memory after this entry"),
});
export type WrittenEntry = z.infer<typeof EntrySchema>;

const SYSTEM = `You are ghost-writing the private journal of a World of Warcraft character. Write ONLY as the character, in first person, past tense, as if they are writing tonight before sleep.

Rules:
- Stay in character and in the world. Never mention game mechanics: no "quest", "XP", "level", "loot", "NPC", "respawn", "server", "addon", "log in". Levels become growing stronger or more confident; quests become tasks, errands, requests, or jobs; deaths become near-death experiences, being struck down and waking at a spirit healer, or a narrow escape.
- Follow the character brief's voice closely. A terse soldier writes short and blunt; a poetic scholar writes lyrically.
- Organise the entry by storyline, not strictly by the order things happened. Moments in the same thread belong together.
- Make the journey believable. When the character moved between distant places, write the travel and WHY they went; never jump between regions without a reason. Respect the day numbers: different days need transitions such as "the next morning" or "after four days at sea".
- Give key moments real weight and connect them to the character's fears, loves, goals and past when the moment "touches" them. Minor moments get a sentence or a passing mention. Collapsed errands get at most one line.
- Use the quest story text for concrete detail (names, places, stakes), but retell it in the character's own words. Never copy it verbatim.
- Companions may be named, with their class as their calling, but invent nothing about their personalities.
- Stay consistent with the story memory. Do not repeat earlier entries.
- Length: about 120-350 words depending on how much happened and the character's voice. Do not add a date line; the journal shows the day separately.`;

function renderDigest(d: Digest): string {
  const lines: string[] = [];
  lines.push(`Writing tonight ${d.restKind} at ${d.restPlace}.`);
  lines.push(d.startDay === d.endDay ? `Covers day ${d.startDay}.` : `Covers days ${d.startDay} to ${d.endDay}.`);

  if (d.journey.length) {
    lines.push("", "JOURNEY (in order):");
    for (const j of d.journey) lines.push(`- Day ${j.day}: ${j.description}`);
  }
  if (d.threads.length) {
    lines.push("", "STORYLINES:");
    for (const t of d.threads) {
      lines.push(`* ${t.name}`);
      for (const m of t.moments) {
        lines.push(`  - [${m.importance.toUpperCase()}] Day ${m.day}, ${m.place}: ${m.kind}${m.title ? ` "${m.title}"` : ""}`);
        if (m.touches?.length) lines.push(`    TOUCHES THE CHARACTER: ${m.touches.join(", ")}`);
        if (m.companions?.length) lines.push(`    Companions: ${m.companions.join(", ")}`);
        if (m.story) lines.push(`    Story: ${m.story.replace(/\n+/g, " ")}`);
        if (m.outcome) lines.push(`    Outcome: ${m.outcome.replace(/\n+/g, " ")}`);
      }
    }
  }
  if (d.collapsed.length) {
    lines.push("", "MINOR ERRANDS (one line at most):");
    for (const c of d.collapsed) lines.push(`- ${c}`);
  }
  return lines.join("\n");
}

function renderBrief(b: Brief): string {
  return [
    `Name: ${b.name}`,
    `Identity: ${b.identity}`,
    `Voice: ${b.voice}`,
    `Personality: ${b.personality}`,
    b.fears.length ? `Fears: ${b.fears.join("; ")}` : "",
    b.loves.length ? `Loves: ${b.loves.join("; ")}` : "",
    b.goals.length ? `Goals: ${b.goals.join("; ")}` : "",
  ]
    .filter(Boolean)
    .join("\n");
}

function renderMemory(m: StoryMemory): string {
  if (!m.summary && !m.people.length && !m.places.length && !m.openThreads.length) {
    return "This is the first entry in the journal.";
  }
  return [
    `Story so far: ${m.summary}`,
    m.people.length ? `People: ${m.people.join("; ")}` : "",
    m.places.length ? `Places: ${m.places.join("; ")}` : "",
    m.openThreads.length ? `Unfinished business: ${m.openThreads.join("; ")}` : "",
  ]
    .filter(Boolean)
    .join("\n");
}

export function buildEntryPrompt(brief: Brief, memory: StoryMemory, digest: Digest, previousTitles: string[]): string {
  return [
    "CHARACTER BRIEF",
    renderBrief(brief),
    "",
    "STORY MEMORY",
    renderMemory(memory),
    previousTitles.length ? `Previous entry titles (avoid repeating): ${previousTitles.slice(-8).join(" | ")}` : "",
    "",
    "WHAT HAPPENED SINCE THE LAST ENTRY",
    renderDigest(digest),
    "",
    "Write tonight's journal entry and the updated story memory as JSON.",
  ]
    .filter((l) => l !== "")
    .join("\n");
}

export async function writeEntry(
  llm: LLM,
  brief: Brief,
  memory: StoryMemory,
  digest: Digest,
  previousTitles: string[],
): Promise<WrittenEntry> {
  const prompt = buildEntryPrompt(brief, memory, digest, previousTitles);
  return llm.generateJson({ system: SYSTEM, prompt, schema: EntrySchema, temperature: 0.9 });
}
