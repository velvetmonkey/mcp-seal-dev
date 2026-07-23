#!/usr/bin/env python3
"""K5 Step 0: collision search for Seal.encodeParts framing.

Lean semantics replicated exactly:
  - Lean Char = Unicode scalar value; String.length = number of scalars.
  - encodeParts parts = "".join(f"{len(s)}:{s}" for s in parts)   (len = CHARS)
  - hash input = UTF-8 bytes of that string.

Question A (within-scheme): do distinct part-lists give identical UTF-8 bytes?
Question B (cross-scheme): the SAME framing but with len = BYTES (the natural
  Rust/Go/C reading of the spec) — does any byte-framed encoding of one list
  equal the char-framed encoding of a DIFFERENT list?
"""
import itertools, sys, hashlib

def enc_char(parts):  # Lean semantics: length in codepoints
    return "".join(f"{len(s)}:{s}" for s in parts).encode("utf-8")

def enc_byte(parts):  # natural byte-count reimplementation (Rust s.len())
    return b"".join(str(len(s.encode("utf-8"))).encode() + b":" + s.encode("utf-8") for s in parts)

# Adversarial alphabet: ASCII letter, digits, the separator, 2-byte, 3-byte, 4-byte chars
ALPHABET = ["a", "1", "2", ":", "é", "€", "\U0001f4a5"]

def all_parts(maxlen):
    parts = [""]
    for L in range(1, maxlen + 1):
        for tup in itertools.product(ALPHABET, repeat=L):
            parts.append("".join(tup))
    return parts

def all_lists(parts, maxitems):
    yield []
    for L in range(1, maxitems + 1):
        for tup in itertools.product(parts, repeat=L):
            yield list(tup)

def search_within(maxpartlen, maxitems):
    seen = {}
    n = 0
    for lst in all_lists(all_parts(maxpartlen), maxitems):
        n += 1
        key = enc_char(lst)
        if key in seen and seen[key] != lst:
            print(f"WITHIN-SCHEME COLLISION: {seen[key]!r} vs {lst!r} -> {key!r}")
            return False, n
        seen[key] = lst
    return True, n

def search_cross(maxpartlen, maxitems):
    """Distinct lists l1 != l2 with enc_char(l1) == enc_byte(l2)."""
    char_img = {}
    hits = []
    parts = all_parts(maxpartlen)
    for lst in all_lists(parts, maxitems):
        char_img[enc_char(lst)] = lst
    for lst in all_lists(parts, maxitems):
        b = enc_byte(lst)
        if b in char_img and char_img[b] != lst:
            hits.append((char_img[b], lst, b))
    return hits

def check_constructed_witness():
    """Hand-constructed cross-scheme witness (outside brute-force range)."""
    l_char = ["é1", "", "aaaaaaaa"]           # char-framed
    l_byte = ["é", "8:aaaaaaaa"]              # byte-framed
    a, b = enc_char(l_char), enc_byte(l_byte)
    print(f"constructed witness: char{l_char!r} -> {a!r}")
    print(f"                     byte{l_byte!r} -> {b!r}")
    print(f"  bytes equal: {a == b}, lists distinct: {l_char != l_byte}")
    if a == b:
        print(f"  shared SHA-256: {hashlib.sha256(a).hexdigest()}")
    return a == b and l_char != l_byte

if __name__ == "__main__":
    ok, n = search_within(2, 3)
    print(f"[A] within-scheme (parts<=2 chars, lists<=3 items, {n} lists over {len(ALPHABET)}-char alphabet): "
          + ("NO collision" if ok else "COLLISION"))
    ok2, n2 = search_within(3, 2)
    print(f"[A] within-scheme (parts<=3 chars, lists<=2 items, {n2} lists): "
          + ("NO collision" if ok2 else "COLLISION"))
    hits = search_cross(2, 3)
    print(f"[B] cross-scheme brute (same range): {len(hits)} hits")
    for h in hits[:5]:
        print(f"    char{h[0]!r} == byte{h[1]!r} -> {h[2]!r}")
    print("[B] constructed witness:", "CONFIRMED" if check_constructed_witness() else "FAILED")
