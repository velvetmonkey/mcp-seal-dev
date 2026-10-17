// SPDX-License-Identifier: Apache-2.0
// Regression: a fatal manifest read must not mask later claim drift.
import test from "node:test";
import assert from "node:assert/strict";
import { mkdirSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { spawnSync } from "node:child_process";

const ROOT = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const GUARD = resolve(ROOT, "scripts/claims-drift.mjs");
const README = resolve(ROOT, "README.md");
const DRIFT_FILE = readFileSync(README, "utf8").includes(":begin -->")
  ? README
  : resolve(ROOT, "index.html");
const UNREADABLE = resolve(ROOT, "docs/.claims-drift-unreadable");

test("fatal manifest read first still reports later drift", () => {
  const guard = readFileSync(GUARD, "utf8");
  const readme = readFileSync(DRIFT_FILE, "utf8");
  const rewritten = guard.replace(
    "const CLAIM_MANIFEST = [\n",
    'const CLAIM_MANIFEST = [\n  ["docs/.claims-drift-unreadable", "combined-test sentinel"],\n',
  );
  assert.notEqual(rewritten, guard, "test entry must be first in CLAIM_MANIFEST");
  const [, begin, end] = guard.match(/begin: "([^"]+)", end: "([^"]+)"/) ?? [];
  const start = readme.indexOf(begin);
  const finish = readme.indexOf(end, start);
  assert.ok(start !== -1 && finish !== -1, "a guarded mirror must contain the first guarded block");
  const drifted = `${readme.slice(0, finish)}\ncombined-test tampered sentence${readme.slice(finish)}`;

  mkdirSync(UNREADABLE);
  writeFileSync(GUARD, rewritten);
  writeFileSync(DRIFT_FILE, drifted);
  try {
    const run = spawnSync(process.execPath, [GUARD], { cwd: ROOT, encoding: "utf8" });
    const output = `${run.stdout}${run.stderr}`;
    assert.equal(run.status, 2, output);
    assert.ok(output.includes("ERROR  claim manifest entry docs/.claims-drift-unreadable"), output);
    assert.match(output, /CLAIMS DRIFT/);
  } finally {
    writeFileSync(GUARD, guard);
    writeFileSync(DRIFT_FILE, readme);
    rmSync(UNREADABLE, { recursive: true, force: true });
  }
});

test("reader kernel module counts match the module axiom gate", () => {
  const gate = readFileSync(resolve(ROOT, "Test/ModuleAxiomScan.lean"), "utf8");
  const gateCount = gate.match(/^private def expectedKernelBaselineModuleCount : Nat := (\d+)$/m);
  assert.ok(gateCount, "Test/ModuleAxiomScan.lean: expected kernel baseline module count is absent");
  const expected = Number(gateCount[1]);
  const errors = [];

  for (const [file, minimum] of [["README.md", 3], ["docs/LIMITATIONS.md", 1]]) {
    const lines = readFileSync(resolve(ROOT, file), "utf8").split("\n");
    let matches = 0;
    for (const [index, line] of lines.entries()) {
      for (const match of line.matchAll(/\b(\d+) (?:explicitly assigned )?kernel modules\b/g)) {
        matches++;
        const found = Number(match[1]);
        if (found !== expected) {
          errors.push(`${file}:${index + 1}: found ${found} kernel modules; expected ${expected}`);
        }
      }
    }
    if (matches < minimum) {
      errors.push(`${file}: found ${matches} kernel module counts; expected at least ${minimum}`);
    }
  }

  assert.deepEqual(errors, [], errors.join("\n"));
});
