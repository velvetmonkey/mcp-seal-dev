# Assumptions

## A-CR: idealised injectivity of the target-commitment hash (canonical statement)

Seal's deployed target commitment is SHA-256 over the injective `encodeParts` netstring encoding. Lean proves the encoding is injective; the hash step is the named leaf assumption A-CR (`Seal.AssumptionCR`, `Seal/EffectCommitment.lean`).

**What A-CR actually says.** As written in Lean, A-CR is *perfect injectivity* of the digest-to-hex pipeline over all strings: no two distinct inputs share a digest. This is an **idealisation**, and it is **strictly stronger than — and not the same as — computational collision resistance**. Collision resistance says a collision is infeasible to *find*; perfect injectivity says no collision *exists*. No fixed-output hash over unbounded inputs can be injective (pigeonhole: 256-bit output, unbounded input space — collisions must exist), so **real SHA-256 does not satisfy A-CR**.

**What that means for the theorems.** The commitment theorems conditional on A-CR (`effect_commitment_injective`, `commitment_check_iff`, and downstream results that cite A-CR) are valid **in an idealised collision-free model only**. They do **not** instantiate as theorems about real SHA-256, and the clean axiom footprint (`propext`, `Classical.choice`, `Quot.sound`) cannot flag this: A-CR is a hypothesis, not an axiom, so the axiom gate is silent about whether the hypothesis is satisfiable in deployment.

**What the real-world guarantee is.** In deployment the guarantee is a **trust assumption**: that no SHA-256 collision is known or findable for the inputs Seal actually hashes. Lean does not and cannot prove this. This is the same epistemic posture as any system that relies on SHA-256 in practice — but it is trust, not theorem.

**What the structure honestly buys.** The theorem chain is still useful: it isolates the cryptographic trust to this single named leaf hypothesis. Everything else on the path — encoding injectivity (A-ENC, since proved in-repo), canonical serialization (A-COMPRESS) — is either proven or separately named. If SHA-256 is ever broken for the relevant input class, A-CR is the one place the damage enters.

## Approval issuance

A human or trusted approval provider must mint approvals for the intended target. Seal checks that a target commitment matches; it does not decide whether the human should have approved it.

## Integration

The MCP host must route guarded tool calls through Seal before the downstream tool can execute. A tool path that bypasses Seal is outside the kernel claim.

## Key management

Signing keys, control files, CI secrets, browser delivery, and operator workstations must be protected by ordinary operational controls. Seal does not remove that TCB.

## Build and artifact identity

Rust, wasm, and JavaScript artifacts must be built from the intended source and pinned by SHA-256. Conformance tests reduce integration risk over the corpus; they are not universal compiler correctness proofs.
