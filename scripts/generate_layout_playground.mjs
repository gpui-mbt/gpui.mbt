import { execFileSync } from "node:child_process";
import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { readFileSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { fileURLToPath } from "node:url";

const root = new URL("../examples/layout_playground/", import.meta.url);
const evidence = JSON.parse(readFileSync(new URL("evidence.json", root), "utf8"));
const sourceFlag = process.argv.indexOf("--verify-source");
if (sourceFlag !== -1) {
  const repo = process.argv[sourceFlag + 1];
  const revision = execFileSync("git", ["-C", repo, "rev-parse", "HEAD"], { encoding: "utf8" }).trim();
  assert.equal(revision, evidence.source_revision);
  const raw = readFileSync(join(repo, evidence.source_path));
  assert.equal(createHash("sha256").update(raw).digest("hex"), evidence.source_sha256);
  const source = JSON.parse(raw);
  const inputs = JSON.parse(readFileSync(join(repo, "minmax_scenarios.json"), "utf8")).cases;
  const before = source.executions["limits-baseline"].comparison.cases;
  const after = source.executions["limits-reviewed"].comparison.cases;
  assert.deepEqual(evidence.cases, inputs.map((input, i) => {
    assert.equal(input.id, before[i].id);
    assert.equal(input.id, after[i].id);
    assert.equal(after[i].status, "pass");
    return { input, upstream: after[i].upstream.bounds, before: before[i].moonbit.bounds,
      candidate: after[i].moonbit.bounds, before_status: before[i].status };
  }));
  console.log("Published source excerpt: PASS (raw runtime artifacts are not revalidated)");
}
const number = (value) => Number.isInteger(value) ? `${value}.0` : String(value);
const array = (values) => `[${values.map(number).join(", ")}]`;
const bounds = (values) => `[${values.map(array).join(", ")}]`;
const presets = evidence.cases.map(({ input: s, upstream, before }) => {
  const column = s.direction === "column";
  return `  {
    id: ${JSON.stringify(s.id)},
    config: {
      extent: ${number(column ? s.height : s.width)},
      cross: ${number(column ? s.width : s.height)},
      column: ${column},
      gap: ${number(s.gap)},
      wrap: 0,
      justify: ${["start", "center", "end"].indexOf(s.justify || "start")},
      children: [${s.children.map((child, i) => `{
        basis: ${number(child[column ? 1 : 0])},
        grow: ${number(s.grow[i])}, shrink: ${number(s.shrink[i])},
        minimum: ${number(s.min_main?.[i] ?? 0)},
        maximum: ${s.max_main?.[i] == null ? "None" : `Some(${number(s.max_main[i])})`},
      }`).join(", ")}],
    },
    upstream: ${bounds(upstream)},
    before: ${bounds(before)},
  }`;
});
const source = `///|\n// Generated from evidence.json; hand edits would sever the published-record binding.\nlet presets : Array[Preset] = [\n${presets.join(",\n")},\n]\n`;
const output = execFileSync(process.env.MOONFMT_BIN || "moonfmt", ["-"], { input: source, encoding: "utf8" });
const path = new URL("presets.mbt", root);
if (process.argv.includes("--check")) {
  if (readFileSync(path, "utf8") !== output) throw new Error("Regenerate layout presets: node scripts/generate_layout_playground.mjs");
} else {
  writeFileSync(path, output);
}
console.log(`Layout presets: ${evidence.cases.length} (${fileURLToPath(path)})`);
