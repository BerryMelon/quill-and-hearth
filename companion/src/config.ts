// Configuration from companion/.env (or the environment).
import { existsSync, readdirSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

export const COMPANION_ROOT = resolve(dirname(fileURLToPath(import.meta.url)), "..");

export interface Config {
  geminiApiKey?: string;
  geminiModel: string;
  wowDir: string;
  account: string;
  savedVariablesPath: string;
  addonDir: string;
  dataDir: string;
}

export function loadConfig(): Config {
  const envFile = join(COMPANION_ROOT, ".env");
  if (existsSync(envFile)) process.loadEnvFile(envFile);

  const wowDir = process.env.WOW_DIR || "C:\\Program Files (x86)\\World of Warcraft\\_classic_beta_";
  const accountRoot = join(wowDir, "WTF", "Account");

  let account = process.env.WOW_ACCOUNT || "";
  if (!account) {
    const candidates = existsSync(accountRoot)
      ? readdirSync(accountRoot, { withFileTypes: true })
          .filter((d) => d.isDirectory() && d.name !== "SavedVariables")
          .map((d) => d.name)
      : [];
    if (candidates.length !== 1) {
      throw new Error(
        candidates.length === 0
          ? `No WoW account folder found in ${accountRoot}. Check WOW_DIR in companion/.env.`
          : `Several account folders found (${candidates.join(", ")}). Set WOW_ACCOUNT in companion/.env.`,
      );
    }
    account = candidates[0];
  }

  return {
    geminiApiKey: process.env.GEMINI_API_KEY || undefined,
    geminiModel: process.env.GEMINI_MODEL || "gemini-2.5-flash",
    wowDir,
    account,
    savedVariablesPath: join(accountRoot, account, "SavedVariables", "QuillAndHearth.lua"),
    addonDir: join(wowDir, "Interface", "AddOns", "QuillAndHearth"),
    dataDir: join(COMPANION_ROOT, "data"),
  };
}
