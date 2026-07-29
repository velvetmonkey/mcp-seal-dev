#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0

"""M.4 stage-1 live-host regression: every MRTR retry is mediated."""

from test_seal import rpc, run_case


ARGS = {"database": "prod", "sql": "drop table users"}


def approval_target(response):
    assert response["result"]["isError"] is True
    text = response["result"]["content"][0]["text"]
    assert "approval required" in text
    return text.split(": ", 1)[1].strip()


def main() -> int:
    initial = rpc(1, "db.execute", ARGS)
    retry = rpc(2, "db.execute", ARGS)
    retry["params"]["requestState"] = "opaque-state-a"
    retry["params"]["inputResponses"] = {
        "confirm": {"action": "accept", "content": True}
    }

    initial_target = approval_target(run_case([initial])[0])
    retry_target = approval_target(run_case([retry])[0])
    assert initial_target != retry_target

    # An approval for the original round cannot authorize a retry carrying
    # MRTR state/responses. If the live host forwarded retries without
    # mediation, this response would be the mock server's successful result.
    old_approval_retry = run_case([retry], [{"target": initial_target}])[0]
    assert old_approval_retry["result"]["isError"] is True
    assert approval_target(old_approval_retry) == retry_target

    # Positive mediation control: a fresh approval for the exact retry target
    # authorizes that retry once.
    fresh_approval_retry = run_case([retry], [{"target": retry_target}])[0]
    assert fresh_approval_retry["result"]["isError"] is False

    print(
        "MRTR-LIVE-MEDIATION GREEN "
        "initial-target!=retry-target old-approval=block fresh-approval=allow"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
