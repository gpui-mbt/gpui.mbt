import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";

const evidence = JSON.parse(readFileSync(new URL("../../examples/layout_playground/evidence.json", import.meta.url), "utf8"));

test("published excerpt retains all 29 input identities and the 9/20 baseline split", () => {
  assert.equal(evidence.cases.length, 29);
  assert.equal(new Set(evidence.cases.map((c) => c.input.id)).size, 29);
  assert.equal(evidence.cases.filter((c) => c.before_status === "pass").length, 9);
  assert.equal(evidence.cases.filter((c) => c.before_status === "mismatch").length, 20);
  for (const c of evidence.cases) {
    assert.equal(c.input.layer, "headless-layout");
    assert.equal(c.input.children.length, 2);
    assert.deepEqual(c.candidate, c.upstream);
    assert.equal(c.upstream.length, 3);
    assert.equal(c.before.length, 3);
    for (const row of [...c.before, ...c.upstream]) {
      assert.equal(row.length, 4);
      assert.ok(row.every(Number.isFinite));
    }
  }
});

test("the published source and measured revisions remain separately identified", () => {
  for (const key of ["source_revision", "suite_revision", "upstream_revision", "baseline_revision", "candidate_revision"]) {
    assert.match(evidence[key], /^[a-f0-9]{40}$/);
  }
  assert.match(evidence.source_sha256, /^[a-f0-9]{64}$/);
  assert.notEqual(evidence.source_revision, evidence.suite_revision);
  assert.notEqual(evidence.candidate_revision, evidence.baseline_revision);
  assert.equal(evidence.tolerance, 0.0001);
});
