// Quill & Hearth companion CLI.
//   npm start              watch SavedVariables and write entries whenever the character rests
//   npm run once           process once and exit
// Flags:
//   --mock-llm             use an offline fake writer (no API key needed)
//   --dry-run              don't save state or write Entries.lua; print the entries instead
import { existsSync } from "node:fs";
import chokidar from "chokidar";
import { loadConfig, type Config } from "./config.js";
import { parseSavedVariablesFile } from "./savedvars/parse.js";
import { processCharacter, readCharacters } from "./process.js";
import { GeminiLLM, type LLM } from "./llm/client.js";
import { createMockLLM } from "./llm/mock.js";
import { loadState, saveState } from "./state/store.js";
import { loadAllStates, writeGenerated } from "./state/generated.js";

const args = new Set(process.argv.slice(2));
const watchMode = !args.has("--once");
const dryRun = args.has("--dry-run");

function log(message: string): void {
  const time = new Date().toLocaleTimeString();
  console.log(`[${time}] ${message}`);
}

function createLLM(config: Config): LLM {
  if (args.has("--mock-llm")) return createMockLLM();
  if (!config.geminiApiKey) {
    throw new Error("GEMINI_API_KEY is missing. Copy companion/.env.example to companion/.env and add your key (or use --mock-llm).");
  }
  return new GeminiLLM(config.geminiApiKey, config.geminiModel);
}

async function runOnce(config: Config, llm: LLM): Promise<void> {
  if (!existsSync(config.savedVariablesPath)) {
    log(`Waiting for ${config.savedVariablesPath} (log in once with the addon enabled).`);
    return;
  }
  const db = readCharacters(parseSavedVariablesFile(config.savedVariablesPath));
  let anyWritten = false;

  for (const [charKey, char] of Object.entries(db.characters)) {
    const state = loadState(config.dataDir, charKey);
    const { written } = await processCharacter(charKey, char, state, llm, log);
    if (dryRun) {
      for (const e of written) {
        console.log(`\n=== ${charKey} | Day ${e.day} | ${e.title} ===\n${e.body}\n`);
      }
      continue;
    }
    saveState(config.dataDir, state);
    if (written.length) anyWritten = true;
    for (const e of written) log(`${charKey}: wrote "${e.title}".`);
  }

  if (!dryRun) {
    const path = writeGenerated(config.addonDir, loadAllStates(config.dataDir));
    if (anyWritten) log(`Journal updated (${path}). It appears in game after your next login or /reload.`);
  }
}

async function main(): Promise<void> {
  const config = loadConfig();
  const llm = createLLM(config);
  log(`Quill & Hearth companion (${llm.name}${dryRun ? ", dry run" : ""})`);
  log(`Account: ${config.account}`);

  let running = false;
  let again = false;
  const trigger = async () => {
    if (running) {
      again = true;
      return;
    }
    running = true;
    try {
      do {
        again = false;
        await runOnce(config, llm);
      } while (again);
    } catch (err) {
      log(`Error: ${err instanceof Error ? err.message : String(err)}`);
    } finally {
      running = false;
    }
  };

  await trigger();
  if (!watchMode) return;

  log("Watching for rests... (Ctrl+C to stop)");
  chokidar
    .watch(config.savedVariablesPath, { ignoreInitial: true, awaitWriteFinish: { stabilityThreshold: 1500, pollInterval: 250 } })
    .on("add", trigger)
    .on("change", trigger);
}

main().catch((err) => {
  console.error(err instanceof Error ? err.message : err);
  process.exit(1);
});
