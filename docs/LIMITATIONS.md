# Limitations

These limits are part of the Seal claim. They are not footnotes.

This is the canonical copy of the non-claims list. The README mirrors it
verbatim; edit here first.

<!-- claims:begin -->
- Seal proves properties of the mediation KERNEL, not of the whole deployed system.
- Seal does NOT prove anything about real SHA-256 in Lean: the named assumption A-CR is an IDEALISED perfect-injectivity premise, strictly stronger than collision resistance and unsatisfiable by any fixed-output hash over unbounded inputs; the commitment theorems hold only in that idealised collision-free model, and the deployed guarantee is the trust assumption that no SHA-256 collision is findable for the relevant inputs (see docs/ASSUMPTIONS.md).
- The deployed Rust / wasm / JS are NOT proven bug-free; they are tied to the proof by byte-exact conformance testing over a corpus, not for every possible input.
- Seal guarantees AUTHORIZATION match, not INTENT match: if a human approves a malicious-but-valid request, Seal will execute it.
- Seal does NOT prevent compromise of hosts, browsers, build systems, keys, operators, or downstream tools.
- Seal's audit chain is tamper-EVIDENT, not tamper-IMPOSSIBLE.
- Seal does NOT make the AI smarter or prevent hallucinations; it stops an unapproved effect.
- For kernel logical soundness of regular declarations, the module gate assigns 24 kernel modules to `{propext, Classical.choice, Quot.sound}`. Separately, the unsafe compiled-code root `Ffi` is assigned to `{propext, Classical.choice, Quot.sound, lcProof}`; this characterization says nothing about runtime, memory-safety, or observational purity of its six unsafe wrappers.
<!-- claims:end -->
