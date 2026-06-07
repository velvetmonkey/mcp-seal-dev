#!/usr/bin/env python3
"""Per-call mediation latency for seal on the gate hot path.

Sends guarded tools/call requests (db.execute DROP -> default-deny block) through
the seal binary in front of the mock MCP server, and measures round-trip latency
per call. The blocked path is the pure decision cost (parse + classify + decide +
emit), with no upstream involvement.

Reproduce:
    lake build                       # produces .lake/build/bin/seal
    python3 test/bench/latency_bench.py

Honest scope: this measures the default-deny decision path. The allowed path
additionally forwards to the upstream server, whose latency is not seal's.
"""
import json
import statistics
import subprocess
import time
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
SEAL = str(REPO / ".lake/build/bin/seal")
POLICY = str(REPO / "config/policy.example.json")
MOCK = ["python3", str(REPO / "test/integration/mock_mcp_server.py")]

N = 2000
WARMUP = 100


def req(i):
    return json.dumps({
        "jsonrpc": "2.0", "id": i, "method": "tools/call",
        "params": {"name": "db.execute",
                   "arguments": {"sql": "DROP TABLE t", "database": "prod"}},
    })


def main():
    proc = subprocess.Popen(
        [SEAL, "--policy", POLICY, "--"] + MOCK,
        stdin=subprocess.PIPE, stdout=subprocess.PIPE,
        stderr=subprocess.DEVNULL, text=True, bufsize=1,
    )
    times, blocked = [], 0
    try:
        for i in range(N):
            t0 = time.perf_counter()
            proc.stdin.write(req(i) + "\n"); proc.stdin.flush()
            line = proc.stdout.readline()
            times.append((time.perf_counter() - t0) * 1000.0)
            if "approval required" in line:
                blocked += 1
    finally:
        try:
            proc.stdin.close(); proc.terminate()
        except Exception:
            pass

    m = sorted(times[WARMUP:])
    pct = lambda q: m[int(len(m) * q)]
    print(f"calls measured : {len(m)} (after {WARMUP} warmup); blocked: {blocked}/{N}")
    print(f"mean : {statistics.mean(m):.3f} ms")
    print(f"p50  : {pct(0.50):.3f} ms")
    print(f"p90  : {pct(0.90):.3f} ms")
    print(f"p99  : {pct(0.99):.3f} ms")
    print(f"min  : {m[0]:.3f} ms   max: {m[-1]:.3f} ms")


if __name__ == "__main__":
    main()
