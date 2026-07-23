#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""
ttl_demo.py - watch seal's approval policy and TTL behaviour, live.

Drives the real `seal` binary in front of the official zero-auth MCP reference
server (@modelcontextprotocol/server-everything) and exercises every approval
behaviour end to end, printing PASS/FAIL for each:

  1. default-deny        - a guarded tool is blocked with no approval
  2. one-shot approval   - one approval row = exactly one allowed call
  3. wall-clock expiry   - an unused approval dies `ttl_seconds` after ingest
  4. mint-time issuedAt  - an approval minted in the past is dead on arrival

No API key, no network beyond a one-time `npx` fetch. Requires only Node/npx
and a built seal binary.

Usage:
  lake build                     # produces .lake/build/bin/seal
  python3 demo/ttl_demo.py       # or: SEAL_BIN=/abs/path/seal python3 demo/ttl_demo.py

Exits 0 if every scenario matches its expectation, 1 otherwise.
"""

import json
import os
import subprocess
import sys
import tempfile
import threading
import time

HERE = os.path.dirname(os.path.abspath(__file__))
SEAL_BIN = os.environ.get("SEAL_BIN", os.path.join(HERE, "..", ".lake", "build", "bin", "seal"))
SERVER_CMD = ["npx", "-y", "@modelcontextprotocol/server-everything", "stdio"]

# echo's target hash is derived at runtime from seal's own default-deny block
# message (seal emits a 64-hex SHA-256 target), so this demo never goes stale
# against a kernel hash change.
BOOT_SECONDS = 3.0  # cold npx start; the child must be ready before the first call


class Seal:
    """One seal+server process. Sends JSON-RPC, collects responses by id."""

    def __init__(self, policy_path):
        self.proc = subprocess.Popen(
            [SEAL_BIN, "--policy", policy_path, "--", *SERVER_CMD],
            stdin=subprocess.PIPE, stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL, text=True, bufsize=1)
        self.resp = {}
        threading.Thread(target=self._reader, daemon=True).start()

    def _reader(self):
        for line in self.proc.stdout:
            line = line.strip()
            if not line:
                continue
            try:
                obj = json.loads(line)
            except ValueError:
                continue
            if obj.get("id") is not None:
                self.resp[obj["id"]] = obj

    def _send(self, obj):
        self.proc.stdin.write(json.dumps(obj) + "\n")
        self.proc.stdin.flush()

    def initialize(self):
        self._send({"jsonrpc": "2.0", "id": 1, "method": "initialize",
                    "params": {"protocolVersion": "2024-11-05", "capabilities": {},
                               "clientInfo": {"name": "ttl-demo", "version": "0"}}})
        self._send({"jsonrpc": "2.0", "method": "notifications/initialized"})
        time.sleep(BOOT_SECONDS)

    def call(self, call_id, tool, **args):
        """Call a tool, return ('ALLOW'|'BLOCK', text)."""
        self._send({"jsonrpc": "2.0", "id": call_id, "method": "tools/call",
                    "params": {"name": tool, "arguments": args}})
        for _ in range(80):
            if call_id in self.resp:
                break
            time.sleep(0.1)
        result = self.resp.get(call_id, {}).get("result", {})
        text = result.get("content", [{}])[0].get("text", "") if result.get("content") else ""
        return ("BLOCK" if result.get("isError") else "ALLOW"), text

    def close(self):
        try:
            self.proc.stdin.close()
        except Exception:
            pass
        self.proc.terminate()


def write_policy(tmp, ttl_seconds, control_file):
    """Write a policy that guards echo + add, and return its path. Prints it."""
    policy = {
        "approval": {"control_file": control_file, "ttl_seconds": ttl_seconds},
        "tools": [
            {"name": "echo", "mode": "guarded", "match": {"type": "always"}, "target": [{"full_arguments": True}]},
            {"name": "add", "mode": "guarded", "match": {"type": "always"}, "target": [{"full_arguments": True}]},
        ],
    }
    path = os.path.join(tmp, f"policy.ttl{ttl_seconds}.json")
    with open(path, "w") as f:
        json.dump(policy, f, indent=2)
    return path


RESULTS = []


def check(name, got, expected, note=""):
    ok = got == expected
    RESULTS.append(ok)
    mark = "PASS" if ok else "FAIL"
    print(f"  [{mark}] {name}: got {got}, expected {expected}   {note}")


def banner(title):
    print(f"\n=== {title} ===")


def main():
    if not os.path.exists(SEAL_BIN):
        sys.exit(f"seal binary not found at {SEAL_BIN}. Run `lake build` first "
                 f"or set SEAL_BIN.")

    tmp = tempfile.mkdtemp(prefix="seal-ttl-demo-")
    print(f"seal:    {SEAL_BIN}")
    print(f"server:  {' '.join(SERVER_CMD)}")
    print(f"workdir: {tmp}")

    # --- Scenarios 1 + 2: default-deny and one-shot approval (ttl 120s) -------
    banner("Policy A (ttl_seconds = 120): default-deny + one-shot approval")
    ctrl_a = os.path.join(tmp, "approvals_a.ndjson")
    open(ctrl_a, "w").close()
    pol_a = write_policy(tmp, 120, ctrl_a)
    print(open(pol_a).read())
    a = Seal(pol_a)
    a.initialize()

    got, text = a.call(2, "echo", message="hi")
    echo_hash = text.split(": ", 1)[1].strip() if ": " in text else text.strip()
    check("1. default-deny (no approval)", got, "BLOCK",
          f"-> approval required: {echo_hash}")

    with open(ctrl_a, "a") as f:
        f.write(json.dumps({"target": echo_hash}) + "\n")
    print(f"  minted one approval: {{\"target\": {echo_hash}}}")
    got, text = a.call(3, "echo", message="hi")
    check("2a. one approval -> first call allowed", got, "ALLOW", f"-> {text!r}")
    got, _ = a.call(4, "echo", message="hi")
    check("2b. same approval -> second call blocked (consumed)", got, "BLOCK")
    a.close()

    # --- Scenario 3: wall-clock expiry of an unused approval (ttl 2s) ---------
    banner("Policy B (ttl_seconds = 2): an unused approval expires by the clock")
    ctrl_b = os.path.join(tmp, "approvals_b.ndjson")
    open(ctrl_b, "w").close()
    pol_b = write_policy(tmp, 2, ctrl_b)
    b = Seal(pol_b)
    b.initialize()
    with open(ctrl_b, "a") as f:
        f.write(json.dumps({"target": echo_hash}) + "\n")
    # Ingest the echo approval WITHOUT consuming it, by calling a different
    # guarded tool. This stamps echo's deadline at now + 2s.
    b.call(2, "add", a=1, b=2)
    print("  minted an echo approval and stamped its deadline (via an add call).")
    print("  waiting 3s (> 2s TTL) without using it...")
    time.sleep(3.0)
    got, _ = b.call(3, "echo", message="too late")
    check("3. unused approval blocked after TTL elapsed", got, "BLOCK")
    b.close()

    # --- Scenario 4: mint-time issuedAt, stale approval dead on arrival -------
    banner("Policy C (ttl_seconds = 60): issuedAt binds TTL to mint time")
    now_ms = int(time.time() * 1000)
    # Stale mint: issued 2 minutes ago under a 60s TTL.
    ctrl_c1 = os.path.join(tmp, "approvals_c1.ndjson")
    with open(ctrl_c1, "w") as f:
        f.write(json.dumps({"target": echo_hash, "issuedAt": now_ms - 120_000}) + "\n")
    pol_c1 = write_policy(tmp, 60, ctrl_c1)
    c1 = Seal(pol_c1)
    c1.initialize()
    got, _ = c1.call(2, "echo", message="stale")
    check("4a. stale mint (issuedAt = now-120s) blocked on first use", got, "BLOCK")
    c1.close()
    # Fresh mint.
    ctrl_c2 = os.path.join(tmp, "approvals_c2.ndjson")
    with open(ctrl_c2, "w") as f:
        f.write(json.dumps({"target": echo_hash, "issuedAt": now_ms}) + "\n")
    pol_c2 = write_policy(tmp, 60, ctrl_c2)
    c2 = Seal(pol_c2)
    c2.initialize()
    got, text = c2.call(2, "echo", message="fresh")
    check("4b. fresh mint (issuedAt = now) allowed", got, "ALLOW", f"-> {text!r}")
    c2.close()

    banner("Summary")
    passed, total = sum(RESULTS), len(RESULTS)
    line = f"{passed}/{total} checks passed"
    if passed == total:
        print(f"  PASS: {line}")
        sys.exit(0)
    print(f"  FAIL: {line}")
    sys.exit(1)


if __name__ == "__main__":
    main()
