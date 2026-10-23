// Runs the addon's pure-Lua logic (Pipeline.lua) outside WoW, using the fengari Lua VM.
// Usage: node tools/lua-test.mjs
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import fengari from "fengari";

const { lua, lauxlib, lualib, to_luastring, to_jsstring } = fengari;
const root = fileURLToPath(new URL("..", import.meta.url));
const read = (p) => readFileSync(root + p, "utf8");

const L = lauxlib.luaL_newstate();
lualib.luaL_openlibs(L);

function setGlobalString(name, value) {
  lua.lua_pushstring(L, to_luastring(value));
  lua.lua_setglobal(L, to_luastring(name));
}
setGlobalString("PIPELINE_SRC", read("addon/QuillAndHearth/Pipeline.lua"));
setGlobalString("WRITER_SRC", read("addon/QuillAndHearth/Writer.lua"));
setGlobalString("EXPORT_SRC", read("addon/QuillAndHearth/Export.lua"));
setGlobalString("CAPTURE_SRC", read("addon/QuillAndHearth/Capture.lua"));
setGlobalString("FIXTURE_SRC", read("tools/fixtures/sample-savedvars.lua"));

const status = lauxlib.luaL_dostring(L, to_luastring(read("tools/pipeline_spec.lua")));
if (status !== lua.LUA_OK) {
  console.error("FAIL:", to_jsstring(lua.lua_tostring(L, -1)));
  process.exit(1);
}

// --live: send a real in-game prompt to Gemini as plain chat text (like a player pasting it
// into a chat window) and check that the addon's parser understands the reply.
if (process.argv.includes("--live")) {
  process.loadEnvFile(root + ".env"); // GEMINI_API_KEY, GEMINI_MODEL, GEMINI_FALLBACK_MODEL (git-ignored)
  lua.lua_getglobal(L, to_luastring("SAMPLE_PROMPT"));
  const prompt = to_jsstring(lua.lua_tostring(L, -1));
  lua.lua_pop(L, 1);

  let reply;
  for (const model of [process.env.GEMINI_MODEL, process.env.GEMINI_FALLBACK_MODEL || "gemini-3-flash-preview"]) {
    const res = await fetch(`https://generativelanguage.googleapis.com/v1beta/models/${model}:generateContent`, {
      method: "POST",
      headers: { "x-goog-api-key": process.env.GEMINI_API_KEY, "content-type": "application/json" },
      body: JSON.stringify({ contents: [{ parts: [{ text: prompt }] }] }),
      signal: AbortSignal.timeout(120_000),
    });
    const json = await res.json();
    reply = json.candidates?.[0]?.content?.parts?.map((p) => p.text).join("");
    if (reply) {
      console.log(`\n(prompt ${prompt.length} chars, answered by ${model})`);
      break;
    }
    console.log(`${model}: HTTP ${res.status}, trying fallback`);
  }
  if (!reply) process.exit(1);

  lua.lua_getglobal(L, to_luastring("PARSE"));
  lua.lua_pushstring(L, to_luastring(reply));
  lua.lua_call(L, 1, 1);
  if (lua.lua_isnil(L, -1)) {
    console.error("PARSE FAILED. Raw reply:\n" + reply);
    process.exit(1);
  }
  const field = (k) => {
    lua.lua_getfield(L, -1, to_luastring(k));
    const v = lua.lua_isnil(L, -1) ? null : to_jsstring(lua.lua_tostring(L, -1));
    lua.lua_pop(L, 1);
    return v;
  };
  console.log(`\nTITLE: ${field("title")}\n\n${field("body")}\n\nMEMORY: ${field("memory")}`);
}
