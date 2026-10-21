// A deterministic offline LLM for tests and `--mock-llm` runs (no API key needed).
import type { JsonRequest } from "./client.js";
import { MockLLM } from "./client.js";

function firstMatch(text: string, re: RegExp, fallback: string): string {
  return text.match(re)?.[1]?.trim() ?? fallback;
}

export function createMockLLM(): MockLLM {
  return new MockLLM((req: JsonRequest<unknown>) => {
    if (req.prompt.includes("CHARACTER BRIEF")) {
      const name = firstMatch(req.prompt, /^Name: (.+)$/m, "Someone");
      const tasks = [...req.prompt.matchAll(/(?:completed|took on) a task "([^"]+)"/g)].map((m) => m[1]);
      const place = firstMatch(req.prompt, /Writing tonight .* at (.+)\.$/m, "the inn");
      const body = [
        `[Mock entry] ${name} writes by candlelight at ${place}.`,
        tasks.length ? `Today I saw to: ${tasks.join(", ")}.` : "A quiet day on the road.",
      ].join("\n\n");
      return {
        title: tasks[0] ? `On ${tasks[0]}` : "A Quiet Day",
        body,
        memory: { summary: `${name} has been busy: ${tasks.join(", ") || "travelling"}.`, people: [], places: [place], openThreads: [] },
      };
    }
    const name = firstMatch(req.prompt, /^Name: (.+)$/m, "Someone");
    return {
      name,
      identity: `${name}, a mock adventurer.`,
      voice: "Plain and practical.",
      personality: "Steady.",
      fears: ["boars"],
      loves: [],
      goals: [],
      hooks: ["boar", "gnoll"],
    };
  });
}
