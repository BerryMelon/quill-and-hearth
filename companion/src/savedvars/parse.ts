// Parse a WoW SavedVariables file (Lua) into plain JS values.
import { readFileSync } from "node:fs";
import luaparse from "luaparse";

type Node = any; // luaparse's AST typings are loose; we validate shapes as we go.

/**
 * WoW writes SavedVariables as UTF-8. luaparse works on JS strings, so we read the file as
 * latin1 (one char per byte), parse with "pseudo-latin1" string decoding, then turn each
 * decoded string back into bytes and decode those as UTF-8. This keeps escapes like \n and
 * multi-byte characters (e.g. accented RP names) intact.
 */
function decodeString(node: Node): string {
  const latin1: string = node.value ?? "";
  return Buffer.from(latin1, "latin1").toString("utf8");
}

function convert(node: Node): unknown {
  switch (node.type) {
    case "StringLiteral":
      return decodeString(node);
    case "NumericLiteral":
      return node.value;
    case "BooleanLiteral":
      return node.value;
    case "NilLiteral":
      return null;
    case "UnaryExpression":
      if (node.operator === "-" && node.argument.type === "NumericLiteral") return -node.argument.value;
      throw new Error(`Unsupported unary expression: ${node.operator}`);
    case "TableConstructorExpression":
      return convertTable(node);
    default:
      throw new Error(`Unsupported Lua value: ${node.type}`);
  }
}

function convertTable(node: Node): unknown {
  const entries: [string | number, unknown][] = [];
  let arrayIndex = 1;
  for (const field of node.fields) {
    if (field.type === "TableValue") {
      entries.push([arrayIndex++, convert(field.value)]);
    } else if (field.type === "TableKeyString") {
      entries.push([field.key.name, convert(field.value)]);
    } else if (field.type === "TableKey") {
      const key = convert(field.key);
      if (typeof key !== "string" && typeof key !== "number") throw new Error("Unsupported table key");
      entries.push([key, convert(field.value)]);
    }
  }

  // A table whose keys are exactly 1..n becomes an array; anything else an object.
  const isArray =
    entries.length > 0 &&
    entries.every(([k]) => typeof k === "number") &&
    [...entries.map(([k]) => k as number)].sort((a, b) => a - b).every((k, i) => k === i + 1);

  if (isArray) {
    const arr: unknown[] = [];
    for (const [k, v] of entries) arr[(k as number) - 1] = v;
    return arr;
  }
  const obj: Record<string, unknown> = {};
  for (const [k, v] of entries) obj[String(k)] = v;
  return obj;
}

/** Parse Lua source and return every top-level `Name = value` assignment. */
export function parseSavedVariablesSource(source: string): Record<string, unknown> {
  const ast = luaparse.parse(source, {
    luaVersion: "5.1",
    encodingMode: "pseudo-latin1",
    comments: false,
    locations: false,
  } as any) as Node;

  const result: Record<string, unknown> = {};
  for (const statement of ast.body) {
    if (statement.type !== "AssignmentStatement") continue;
    statement.variables.forEach((variable: Node, i: number) => {
      if (variable.type === "Identifier" && statement.init[i]) {
        result[variable.name] = convert(statement.init[i]);
      }
    });
  }
  return result;
}

export function parseSavedVariablesFile(path: string): Record<string, unknown> {
  return parseSavedVariablesSource(readFileSync(path, "latin1"));
}
