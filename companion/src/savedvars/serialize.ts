// Serialize plain JS values to Lua source, and write files atomically.
import { renameSync, writeFileSync } from "node:fs";

function escapeString(s: string): string {
  let out = '"';
  for (const ch of s) {
    const code = ch.codePointAt(0)!;
    if (ch === "\\") out += "\\\\";
    else if (ch === '"') out += '\\"';
    else if (ch === "\n") out += "\\n";
    else if (ch === "\r") out += "\\r";
    else if (ch === "\t") out += "\\t";
    else if (code < 32 || code === 127) out += "\\" + code.toString().padStart(3, "0");
    else out += ch; // UTF-8 is written as-is (file is UTF-8)
  }
  return out + '"';
}

function isIdentifier(key: string): boolean {
  return /^[A-Za-z_][A-Za-z0-9_]*$/.test(key) && !LUA_KEYWORDS.has(key);
}

const LUA_KEYWORDS = new Set([
  "and", "break", "do", "else", "elseif", "end", "false", "for", "function", "if", "in",
  "local", "nil", "not", "or", "repeat", "return", "then", "true", "until", "while",
]);

export function toLua(value: unknown, indent = ""): string {
  if (value === null || value === undefined) return "nil";
  if (typeof value === "boolean") return value ? "true" : "false";
  if (typeof value === "number") {
    if (!Number.isFinite(value)) throw new Error("Cannot serialize non-finite number");
    return String(value);
  }
  if (typeof value === "string") return escapeString(value);

  const inner = indent + "    ";
  if (Array.isArray(value)) {
    if (value.length === 0) return "{}";
    const items = value.map((v) => `${inner}${toLua(v, inner)},`);
    return `{\n${items.join("\n")}\n${indent}}`;
  }
  if (typeof value === "object") {
    const entries = Object.entries(value as Record<string, unknown>).filter(([, v]) => v !== undefined && v !== null);
    if (entries.length === 0) return "{}";
    const items = entries.map(([k, v]) => {
      const key = isIdentifier(k) ? k : `[${escapeString(k)}]`;
      return `${inner}${key} = ${toLua(v, inner)},`;
    });
    return `{\n${items.join("\n")}\n${indent}}`;
  }
  throw new Error(`Cannot serialize ${typeof value}`);
}

/** Write to a temp file next to the target, then rename, so the game never sees a half-written file. */
export function writeFileAtomic(path: string, content: string): void {
  const tmp = `${path}.tmp`;
  writeFileSync(tmp, content, "utf8");
  renameSync(tmp, path);
}
