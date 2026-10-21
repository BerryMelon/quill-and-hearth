// Diagnostic: list models visible to this key, then time a raw REST call (no SDK).
import { loadConfig } from "../src/config.js";

const config = loadConfig();
const key = config.geminiApiKey!;
const base = "https://generativelanguage.googleapis.com/v1beta";

const list = await fetch(`${base}/models?pageSize=200`, { headers: { "x-goog-api-key": key } });
const models = ((await list.json()) as { models?: { name: string; supportedGenerationMethods?: string[] }[] }).models ?? [];
console.log(`list: HTTP ${list.status}, ${models.length} models`);
for (const m of models.filter((m) => /flash|pro/.test(m.name))) {
  console.log(" ", m.name, (m.supportedGenerationMethods ?? []).join(","));
}

const model = process.argv[2] ?? config.geminiModel;
const start = Date.now();
const controller = new AbortController();
const timer = setTimeout(() => controller.abort(), 45_000);
try {
  const res = await fetch(`${base}/models/${model}:generateContent`, {
    method: "POST",
    signal: controller.signal,
    headers: { "x-goog-api-key": key, "content-type": "application/json" },
    body: JSON.stringify({ contents: [{ parts: [{ text: "Say hi in 3 words." }] }] }),
  });
  const body = await res.text();
  console.log(`generateContent(${model}): HTTP ${res.status} in ${((Date.now() - start) / 1000).toFixed(1)}s`);
  console.log(body.slice(0, 600));
} catch (err) {
  console.log(`generateContent(${model}): FAILED after ${((Date.now() - start) / 1000).toFixed(1)}s: ${String(err)}`);
} finally {
  clearTimeout(timer);
}
