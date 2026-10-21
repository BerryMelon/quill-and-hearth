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

export class GeminiLLM implements LLM {
  readonly name: string;
  private ai: GoogleGenAI;

  constructor(apiKey: string, private model: string) {
    this.ai = new GoogleGenAI({ apiKey });
    this.name = `gemini:${model}`;
  }

  async generateJson<T>({ system, prompt, schema, temperature = 0.9 }: JsonRequest<T>): Promise<T> {
    let lastError: unknown;
    for (let attempt = 1; attempt <= 2; attempt++) {
      const response = await this.ai.models.generateContent({
        model: this.model,
        contents: prompt,
        config: {
          systemInstruction: system,
          temperature,
          responseMimeType: "application/json",
          responseJsonSchema: z.toJSONSchema(schema),
        },
      });
      const text = response.text;
      try {
        if (!text) throw new Error("Empty response from Gemini");
        return schema.parse(JSON.parse(stripFences(text)));
      } catch (err) {
        lastError = err;
      }
    }
    throw new Error(`Gemini returned invalid JSON twice: ${String(lastError)}`);
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
