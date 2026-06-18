// SPDX-License-Identifier: Apache-2.0
//! seal v2 host (M7). Engineered glue (A3): owns transport, approver-key custody,
//! and the wall clock; drives the verified Lean core raw bytes -> Decision. The
//! consumed-nonce store lives in the Lean IO.Ref (the verified listReplayStore) —
//! A5 discharged for the live process. Every call is serialised by the LeanHost
//! Mutex (A4). In-memory only (A6: durability is out of scope, restart re-Allows).
//!
//! Modes:
//!   seal-v2-host selftest        -- run the end-to-end acceptance corpus (A4 probe too)
//!   seal-v2-host serve <cfg.json>-- init from cfg, then stdin request lines -> decision lines
mod lean;

use std::sync::Arc;

// --- M5 fixed test vector (the re-vectored validApproval / baseState) ---
const PUBKEY: &str = "03a107bff3ce10be1d70dd18e74bc09967e4d6309ba50d5f1ddc8664125531b8";
const SIG_A: &str = "ffbe15d60ae3d19a0f97465889f5e4927cdb3f36beebe649f546f9639fc3282966ecab0a0f7564af9cc1daa51a2903029f83f6b2668b710a7cb17dd20deeaf03";
// Canonical signed-message bytes for the base approval (M_A).
const SIGNED_RAW: &str = r#"{"target":{"tool":"db.execute","action":"write","toolVersion":"v1","manifestDigest":"manifest-001","arguments":{"database":"prod","table":"users","amount":12.34}},"session":"session-1","issuedAt":0,"expiry":120,"nonce":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"}"#;
const VALID_REQ: &str = r#"{"method":"tools/call","params":{"name":"db.execute","action":"write","arguments":{"database":"prod","table":"users","amount":12.34}}}"#;

fn config_json() -> String {
    format!(
        r#"{{"session":"session-1","publicKey":"{PUBKEY}","manifestDigest":"manifest-001","policyVersion":"policy-1","maxApprovalTtl":300,"tools":[{{"tool":"db.execute","version":"v1","actions":["write"]}}]}}"#
    )
}

fn is_ok(j: &str) -> bool { j.contains("\"ok\":true") }
fn is_allow(j: &str) -> bool { j.contains("\"decision\":\"Allow\"") }
fn is_block(j: &str) -> bool { j.contains("\"decision\":\"Block\"") }

fn expect(label: &str, cond: bool, got: &str) {
    if !cond {
        eprintln!("FAIL [{label}]: got {got}");
        std::process::exit(1);
    }
    println!("  ok  [{label}]");
}

/// Fresh session with the single legitimate approval loaded.
fn fresh_with_approval(h: &lean::LeanHost) {
    expect("init", is_ok(&h.init(&config_json())), "init");
    expect("add_approval", is_ok(&h.add_approval(SIGNED_RAW, SIG_A)), "add_approval");
}

fn selftest() {
    let host = Arc::new(lean::LeanHost::new());

    // Case A — fresh token Allows, replay Blocks (single-use through the C ABI).
    fresh_with_approval(&host);
    expect("fresh token -> Allow", is_allow(&host.decide(VALID_REQ, "10")), "A1");
    expect("replay -> Block", is_block(&host.decide(VALID_REQ, "10")), "A2");

    // Case B — valid signature but EXPIRED (now > expiry) Blocks (origin != authorization).
    fresh_with_approval(&host);
    expect("expired (now>expiry) -> Block", is_block(&host.decide(VALID_REQ, "200")), "B");

    // Case C — tampered signature Blocks (real Ed25519 verify fails).
    {
        expect("init", is_ok(&host.init(&config_json())), "C.init");
        let mut bad = SIG_A.to_string();
        bad.replace_range(0..2, "00"); // flip the first sig byte
        expect("add tampered-sig approval", is_ok(&host.add_approval(SIGNED_RAW, &bad)), "C.add");
        expect("tampered sig -> Block", is_block(&host.decide(VALID_REQ, "10")), "C");
    }

    // Case D — malformed / forged request Blocks (verified parser, fail-closed).
    fresh_with_approval(&host);
    expect("malformed request -> Block", is_block(&host.decide(r#"{"method":"tools/call""#, "10")), "D1");
    expect("target mismatch -> Block",
        is_block(&host.decide(r#"{"method":"tools/call","params":{"name":"db.execute","action":"write","arguments":{"database":"prod","table":"payments","amount":12.34}}}"#, "10")), "D2");

    // A4 concurrency probe — N threads race one single-use token; EXACTLY ONE Allows.
    fresh_with_approval(&host);
    let n = 16;
    let mut handles = Vec::new();
    for _ in 0..n {
        let h = Arc::clone(&host);
        handles.push(std::thread::spawn(move || {
            if is_allow(&h.decide(VALID_REQ, "10")) { 1u32 } else { 0u32 }
        }));
    }
    let allows: u32 = handles.into_iter().map(|h| h.join().unwrap()).sum();
    expect(&format!("A4: {n} concurrent decides -> exactly 1 Allow (got {allows})"), allows == 1, "A4");

    println!("M7 host selftest passed: e2e Allow/replay/expired/tampered/forged + A4 concurrency (1 of {n}).");
}

/// Minimal standard-alphabet base64 decode (std-only; payloads on the serve command
/// protocol are base64 so the raw bytes the verified parser sees are exact).
fn b64_decode(s: &str) -> Option<Vec<u8>> {
    fn val(c: u8) -> Option<u32> {
        Some(match c {
            b'A'..=b'Z' => (c - b'A') as u32,
            b'a'..=b'z' => (c - b'a' + 26) as u32,
            b'0'..=b'9' => (c - b'0' + 52) as u32,
            b'+' => 62,
            b'/' => 63,
            _ => return None,
        })
    }
    let mut out = Vec::with_capacity(s.len() * 3 / 4);
    let (mut acc, mut nbits): (u32, u32) = (0, 0);
    for c in s.bytes() {
        if c == b'=' {
            continue;
        }
        acc = (acc << 6) | val(c)?;
        nbits += 6;
        if nbits >= 8 {
            nbits -= 8;
            out.push((acc >> nbits) as u8);
        }
    }
    Some(out)
}

/// serve: init from cfg, then a line command protocol on stdin. One process, one store
/// (the consumed-nonce store lives in the Lean IO.Ref). Commands (payloads base64):
///   decide <now> <b64raw>
///   challenge <issuedAt> <expiry> <nonceHex> <b64raw>
///   add_approval <sigHex> <b64signed>
/// The reply is the host's JSON, one line per command.
fn serve(cfg_path: &str) {
    let host = lean::LeanHost::new();
    let cfg = std::fs::read_to_string(cfg_path).expect("read config");
    let r = host.init(&cfg);
    if !is_ok(&r) {
        eprintln!("init failed: {r}");
        std::process::exit(1);
    }
    let bad = || "{\"ok\":false,\"error\":\"bad base64/utf8\"}".to_string();
    let decode = |b64: &str| b64_decode(b64).and_then(|b| String::from_utf8(b).ok());

    use std::io::BufRead;
    for line in std::io::stdin().lock().lines() {
        let line = line.unwrap_or_default();
        if line.trim().is_empty() {
            continue;
        }
        let t: Vec<&str> = line.split_whitespace().collect();
        let resp = match t.as_slice() {
            ["decide", now, b64] => decode(b64).map(|raw| host.decide(&raw, now)).unwrap_or_else(bad),
            ["challenge", issued, expiry, nonce, b64] => {
                decode(b64).map(|raw| host.challenge(&raw, issued, expiry, nonce)).unwrap_or_else(bad)
            }
            ["add_approval", sig, b64] => {
                decode(b64).map(|signed| host.add_approval(&signed, sig)).unwrap_or_else(bad)
            }
            _ => "{\"ok\":false,\"error\":\"unknown command\"}".to_string(),
        };
        println!("{resp}");
    }
}

fn main() {
    let args: Vec<String> = std::env::args().collect();
    match args.get(1).map(String::as_str) {
        Some("serve") => serve(args.get(2).map(String::as_str).unwrap_or("config.json")),
        _ => selftest(),
    }
}
