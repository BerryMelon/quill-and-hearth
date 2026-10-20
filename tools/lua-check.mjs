// Syntax-checks every .lua file in the addon using luaparse (Lua 5.1 grammar).
// Usage: node tools/lua-check.mjs
import { readFileSync, readdirSync, statSync } from "node:fs";
import { join, relative } from "node:path";
import luaparse from "luaparse";

const root = new URL("../addon", import.meta.url).pathname.replace(/^\/(\w:)/, "$1");

function walk(dir) {
  return readdirSync(dir).flatMap((name) => {
    const p = join(dir, name);
    return statSync(p).isDirectory() ? walk(p) : p.endsWith(".lua") ? [p] : [];
  });
}

let failed = 0;
for (const file of walk(root)) {
  try {
    luaparse.parse(readFileSync(file, "utf8"), { luaVersion: "5.1" });
    console.log(`ok    ${relative(root, file)}`);
  } catch (err) {
    failed++;
    console.error(`FAIL  ${relative(root, file)}: ${err.message}`);
  }
}
process.exit(failed ? 1 : 0);
