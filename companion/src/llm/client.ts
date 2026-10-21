// LLM access: a tiny interface with a Gemini implementation and a deterministic mock.
import { GoogleGenAI } from "@google/genai";
import { z } from "zod";

export interface JsonRequest<T> {
  system: string;
  prompt: string;
  schema: z.ZodType<T>;
  temperature?: number;
}

export interface LLM {
  readonly name: string;
  generateJson<T>(request: JsonRequest<T>): Promise<T>;
}

function stripFences(text: string): string {
  return text.trim().replace(/^```(?:json)?\s*/i, "").replace(/\s*```$/, "");
}

const REQUEST_TIMEOUT_MS = 120_000;
const BACKOFF_MS = [0, 3_000, 8_000, 20_000];

const sleep = (ms: number) => new Promise((resolve) => setTimeout(resolve, ms));

/** Overloaded (503), rate limited (429), timeouts and network hiccups are worth retrying. */
function isTransient(err: unknown): boolean {
  const text = String(err);
  return /\b(503|429|500|UNAVAILABLE|RESOURCE_EXHAUSTED|INTERNAL)\b|timeout|aborted|ECONNRESET|fetch failed/i.test(text);
}

export class GeminiLLM implements LLM {
  readonly name: string;
  private ai: GoogleGenAI;
  private models: string[];

  /** `fallbackModel` is tried on alternate attempts when the main model is overloaded. */
  constructor(apiKey: string, model: string, fallbackModel?: string) {
    this.ai = new GoogleGenAI({ apiKey });
    this.models = fallbackModel && fallbackModel !== model ? [model, fallbackModel] : [model];
    this.name = `gemini:${this.models.join(" (fallback ")}${this.models.length > 1 ? ")" : ""}`;
  }

  async generateJson<T>({ system, prompt, schema, temperature = 0.9 }: JsonRequest<T>): Promise<T> {
    let lastError: unknown;
    for (let attempt = 0; attempt < BACKOFF_MS.length; attempt++) {
      await sleep(BACKOFF_MS[attempt]);
      const model = this.models[attempt % this.models.length];
      try {
        const response = await this.ai.models.generateContent({
          model,
          contents: prompt,
          config: {
            systemInstruction: system,
            temperature,
            responseMimeType: "application/json",
            responseJsonSchema: z.toJSONSchema(schema),
            // Never hang forever: some models occasionally stall.
            abortSignal: AbortSignal.timeout(REQUEST_TIMEOUT_MS),
          },
        });
        const text = response.text;
        if (!text) throw new Error("Empty response from Gemini");
        return schema.parse(JSON.parse(stripFences(text)));
      } catch (err) {
        lastError = err;
        // Bad JSON is retried once more; permanent API errors (bad key, unknown model) are not.
        const badJson = err instanceof SyntaxError || err instanceof z.ZodError;
        if (!badJson && !isTransient(err)) break;
      }
    }
    throw new Error(`Gemini request failed: ${String(lastError)}`);
  }
}

/** Offline stand-in for tests and --mock-llm runs. `respond` builds the object for each request. */
export class MockLLM implements LLM {
  readonly name = "mock";
  readonly calls: JsonRequest<unknown>[] = [];

  constructor(private respond: (request: JsonRequest<unknown>) => unknown) {}

  async generateJson<T>(request: JsonRequest<T>): Promise<T> {
    this.calls.push(request as JsonRequest<unknown>);
    return request.schema.parse(this.respond(request as JsonRequest<unknown>));
  }
}
