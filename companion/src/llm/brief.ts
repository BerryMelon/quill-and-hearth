// Character Brief: distil the profile (TRP3 sheet or onboarding answers) into a writing guide
// plus keyword "hooks" used to spot events that matter to this character.
import { createHash } from "node:crypto";
import { z } from "zod";
import type { QHMeta, QHProfile } from "../types.js";
import { cleanText } from "../pipeline/digest.js";
import type { LLM } from "./client.js";

export const BriefSchema = z.object({
  name: z.string().describe("How the character refers to themselves / signs their journal"),
  identity: z.string().describe("One or two sentences: who they are (race, calling, background)"),
  voice: z.string().describe("2-4 sentences of concrete writing-style guidance for their first-person journal"),
  personality: z.string().describe("A short description of their temperament and values"),
  fears: z.array(z.string()),
  loves: z.array(z.string()),
  goals: z.array(z.string()),
  hooks: z
    .array(z.string())
    .describe("8-20 lowercase single words or short phrases (creatures, places, people, themes) that would make an event personally meaningful, e.g. 'boar', 'water', 'undead', 'stormwind'"),
});
export type Brief = z.infer<typeof BriefSchema>;

export function profileHash(profile: QHProfile | undefined, meta: QHMeta | undefined): string {
  const relevant = {
    profile: profile ? { ...profile, createdAt: undefined, updatedAt: undefined } : null,
    race: meta?.race,
    class: meta?.class,
    sex: meta?.sex,
    faction: meta?.faction,
  };
  return createHash("sha1").update(JSON.stringify(relevant)).digest("hex");
}

/** Plain-text description of everything we know about the character. */
export function describeCharacter(profile: QHProfile | undefined, meta: QHMeta | undefined): string {
  const lines: string[] = [];
  const gender = meta?.sex === 3 ? "female" : meta?.sex === 2 ? "male" : undefined;
  lines.push(`Name: ${profile?.name ?? meta?.name ?? "Unknown"}`);
  lines.push(`Race: ${profile?.trp3?.race ?? meta?.race ?? "unknown"}${gender ? ` (${gender})` : ""}`);
  lines.push(`Class / calling: ${profile?.class ?? meta?.class ?? "adventurer"}`);
  if (meta?.faction) lines.push(`Faction: ${meta.faction}`);

  const t = profile?.traits;
  if (t) {
    if (t.temperament) lines.push(`Temperament: ${t.temperament}`);
    if (t.outlook) lines.push(`Outlook: ${t.outlook}`);
    if (t.upbringing) lines.push(`Upbringing: ${t.upbringing}`);
    if (t.drive) lines.push(`Driven by: ${t.drive}`);
    if (t.voice) lines.push(`Way with words: ${t.voice}`);
  }
  if (profile?.fear) lines.push(`Fears: ${profile.fear}`);
  if (profile?.past) lines.push(`Past: ${profile.past}`);

  const d = profile?.trp3;
  if (d) {
    const field = (label: string, v?: string) => v && lines.push(`${label}: ${cleanText(v, 300)}`);
    field("Title", d.fullTitle ?? d.title);
    field("Age", d.age);
    field("Eyes", d.eyes);
    field("Height", d.height);
    field("Build", d.weight);
    field("Birthplace", d.birthplace);
    field("Residence", d.residence);
    for (const m of d.misc ?? []) field(m.name, m.value);
    for (const p of d.personality ?? []) {
      const leftPct = Math.round((p.leftStrength / p.max) * 100);
      lines.push(`Personality: ${leftPct}% ${p.left} / ${100 - leftPct}% ${p.right}`);
    }
    const a = d.about;
    if (a) {
      field("About", a.text);
      a.sections?.forEach((s, i) => field(`About (part ${i + 1})`, s));
      field("Appearance", a.physical);
      field("Personality notes", a.personality);
      field("History", a.history);
    }
    field("Currently", d.currently);
  }
  return lines.join("\n");
}

const SYSTEM = `You help a World of Warcraft roleplayer. You read a character sheet and produce a concise "character brief" that another writer will use to write the character's personal, first-person journal.
Stay faithful to the sheet; infer sensibly where it is thin, but never contradict it. Hooks must be lowercase and concrete enough to match quest text (creature types, places, factions, people, elements, themes).`;

export async function generateBrief(llm: LLM, profile: QHProfile | undefined, meta: QHMeta | undefined): Promise<Brief> {
  const prompt = `Character sheet:\n${describeCharacter(profile, meta)}\n\nWrite the character brief as JSON.`;
  const brief = await llm.generateJson({ system: SYSTEM, prompt, schema: BriefSchema, temperature: 0.4 });
  brief.hooks = [...new Set(brief.hooks.map((h) => h.toLowerCase().trim()).filter(Boolean))];
  return brief;
}
