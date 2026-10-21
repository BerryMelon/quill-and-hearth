// Quill & Hearth companion CLI.
//   npm start              watch SavedVariables and write entries whenever the character rests
//   npm run once           process once and exit
//   npm run stop           stop a companion running in the background
// Flags:
//   --mock-llm             use an offline fake writer (no API key needed)
//   --dry-run              don't save state or write Entries.lua; print the entries instead
import { appendFileSync, existsSync, mkdirSync, readFileSync, rmSync, statSync, writeFileSync } from "node:fs";
import { join } from "node:path";
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

/** The addon treats Entries.lua's timestamp as a heartbeat to tell whether the companion is running. */
const HEARTBEAT_MS = 60_000;
const MAX_LOG_BYTES = 1_000_000;

let logFile: string | undefined;

function log(message: string): void {
  const line = `[${new Date().toLocaleString()}] ${message}`;
  console.log(line);
  if (logFile) {
    try {
      appendFileSync(logFile, line + "\n");
    } catch {
      // logging must never crash the companion
    }
  }
}

function setupLogFile(config: Config): void {
  mkdirSync(config.dataDir, { recursive: true });
  logFile = join(config.dataDir, "companion.log");
  if (existsSync(logFile) && statSync(logFile).size > MAX_LOG_BYTES) rmSync(logFile);
}

function isAlive(pid: number): boolean {
  try {
    process.kill(pid, 0);
    return true;
  } catch {
    return false;
  }
}

function pidFile(config: Config): string {
  return join(config.dataDir, "companion.pid");
}

function readPid(config: Config): number | undefined {
  const file = pidFile(config);
  if (!existsSync(file)) return undefined;
  const pid = Number(readFileSync(file, "utf8").trim());
  return Number.isInteger(pid) && pid > 0 && isAlive(pid) ? pid : undefined;
}

/** Only one watcher at a time (autostart + a manual `npm start` must not both write). */
function acquireLock(config: Config): boolean {
  const existing = readPid(config);
  if (existing && existing !== process.pid) return false;
  writeFileSync(pidFile(config), String(process.pid));
  const release = () => {
    try {
      if (readFileSync(pidFile(config), "utf8").trim() === String(process.pid)) rmSync(pidFile(config));
    } catch {
      // already gone
    }
  };
  process.on("exit", release);
  for (const signal of ["SIGINT", "SIGTERM", "SIGBREAK"] as const) {
    process.on(signal, () => process.exit(0));
  }
  return true;
}

function createLLM(config: Config): LLM {
  if (args.has("--mock-llm")) return createMockLLM();
  if (!config.geminiApiKey) {
    throw new Error("GEMINI_API_KEY is missing. Copy companion/.env.example to companion/.env and add your key (or use --mock-llm).");
  }
  return new GeminiLLM(config.geminiApiKey, config.geminiModel, config.geminiFallbackModel);
}

function refreshGenerated(config: Config): string | undefined {
  try {
    return writeGenerated(config.addonDir, loadAllStates(config.dataDir));
  } catch (err) {
    // The game may briefly lock the file while loading; the next heartbeat will retry.
    log(`Could not update Entries.lua (will retry): ${err instanceof Error ? err.message : String(err)}`);
    return undefined;
  }
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
    const path = refreshGenerated(config);
    if (anyWritten && path) log("Journal updated. It appears in game after your next login or /reload.");
  }
}

function stopBackground(config: Config): void {
  const pid = readPid(config);
  if (!pid) {
    console.log("The companion is not running.");
    return;
  }
  process.kill(pid);
  rmSync(pidFile(config), { force: true }); // a killed process on Windows can't clean up after itself
  console.log(`Stopped the companion (pid ${pid}).`);
}

async function main(): Promise<void> {
  const config = loadConfig();
  if (args.has("--stop")) return stopBackground(config);

  if (watchMode && !dryRun) {
    setupLogFile(config);
    if (!acquireLock(config)) {
      log("Another Quill & Hearth companion is already running; exiting.");
      return;
    }
  }

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

  if (!dryRun) {
    setInterval(() => {
      if (!running) refreshGenerated(config);
    }, HEARTBEAT_MS);
  }
}

main().catch((err) => {
  log(`Fatal: ${err instanceof Error ? err.message : String(err)}`);
  process.exit(1);
});
