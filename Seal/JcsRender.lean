/- SPDX-License-Identifier: Apache-2.0 -/

import Lean.Data.Json

/-!
# JSON rendering with RFC 8785 string escaping

This renderer deliberately preserves `Lean.Json.compress`'s traversal and
number rendering.  Its only behavioral difference is string escaping:
RFC 8785 section 3.2.2.2's five named C0 escapes are used, every other C0
control is rendered as lowercase `\uhhhh`, and all other characters are
emitted unchanged except quotation mark and reverse solidus.

In particular, this is not a post-processing pass over rendered JSON.  Each
parsed string value and object key is escaped directly, so literal text such
as `\u0008` cannot be confused with an encoded control character.
-/

namespace Lean.Json

private def jcsEscapeChar (acc : String) (c : Char) : String :=
  if c == '"' then
    acc ++ "\\\""
  else if c == '\\' then
    acc ++ "\\\\"
  else if c == '\x08' then
    acc ++ "\\b"
  else if c == '\x09' then
    acc ++ "\\t"
  else if c == '\x0a' then
    acc ++ "\\n"
  else if c == '\x0c' then
    acc ++ "\\f"
  else if c == '\x0d' then
    acc ++ "\\r"
  else if c.toNat < 0x20 then
    let n := c.toNat
    acc ++ "\\u"
      |>.push (Nat.digitChar (n / 4096))
      |>.push (Nat.digitChar ((n % 4096) / 256))
      |>.push (Nat.digitChar ((n % 256) / 16))
      |>.push (Nat.digitChar (n % 16))
  else
    acc.push c

/-- Render one JSON string using RFC 8785 section 3.2.2.2 escaping. -/
def jcsRenderString (s : String) (acc : String := "") : String :=
  (s.foldl jcsEscapeChar (acc ++ "\"")) ++ "\""

private inductive JcsWorkItemKind where
  | json
  | arrayElem
  | arrayEnd
  | objectField
  | objectEnd
  | comma

private structure JcsWorkQueue where
  kinds : Array JcsWorkItemKind
  values : Array Json
  objectFieldKeys : Array String

private def JcsWorkQueue.pushKind
    (q : JcsWorkQueue) (kind : JcsWorkItemKind) : JcsWorkQueue :=
  { q with kinds := q.kinds.push kind }

private def JcsWorkQueue.pushValue
    (q : JcsWorkQueue) (value : Json) : JcsWorkQueue :=
  { q with values := q.values.push value }

private def JcsWorkQueue.pushObjectFieldKey
    (q : JcsWorkQueue) (key : String) : JcsWorkQueue :=
  { q with objectFieldKeys := q.objectFieldKeys.push key }

private def JcsWorkQueue.popKind
    (q : JcsWorkQueue) (h : q.kinds.size ≠ 0) :
    JcsWorkItemKind × JcsWorkQueue :=
  let kind := q.kinds[q.kinds.size - 1]
  (kind, { q with kinds := q.kinds.pop })

private def JcsWorkQueue.popValue! (q : JcsWorkQueue) : Json × JcsWorkQueue :=
  let value := q.values[q.values.size - 1]!
  (value, { q with values := q.values.pop })

private def JcsWorkQueue.popObjectFieldKey!
    (q : JcsWorkQueue) : String × JcsWorkQueue :=
  let key := q.objectFieldKeys[q.objectFieldKeys.size - 1]!
  (key, { q with objectFieldKeys := q.objectFieldKeys.pop })

/-- Compact JSON rendering with RFC 8785 string escaping and otherwise the
    same value traversal, object ordering, and number rendering as
    `Lean.Json.compress`. -/
partial def jcsRender (j : Json) : String :=
  go "" { kinds := #[.json], values := #[j], objectFieldKeys := #[] }
where
  go (acc : String) (q : JcsWorkQueue) : String :=
    if h : q.kinds.size = 0 then
      acc
    else
      let (kind, q) := q.popKind h
      match kind with
      | .json =>
          let (j, q) := q.popValue!
          match j with
          | .null => go (acc ++ "null") q
          | .bool b => go (acc ++ toString b) q
          | .num n => go (acc ++ toString n) q
          | .str s => go (jcsRenderString s acc) q
          | .arr elems =>
              let q := q.pushKind .arrayEnd
              go (acc ++ "[")
                (elems.foldr (init := q) fun e q =>
                  q.pushKind .arrayElem |>.pushValue e)
          | .obj fields =>
              let q := q.pushKind .objectEnd
              go (acc ++ "{")
                (fields.foldr (init := q) fun key value q =>
                  q.pushKind .objectField
                    |>.pushObjectFieldKey key
                    |>.pushValue value)
      | .arrayElem =>
          let (j, q) := q.popValue!
          if h : q.kinds.size = 0 then
            go acc { kinds := #[.comma, .json], values := #[j], objectFieldKeys := #[] }
          else
            let next := q.kinds[q.kinds.size - 1]
            if next matches .arrayEnd then
              go acc (q.pushKind .json |>.pushValue j)
            else
              go acc (q.pushKind .comma |>.pushKind .json |>.pushValue j)
      | .arrayEnd => go (acc ++ "]") q
      | .objectField =>
          let (key, q) := q.popObjectFieldKey!
          let (j, q) := q.popValue!
          if h : q.kinds.size = 0 then
            go (jcsRenderString key acc ++ ":")
              { kinds := #[.comma, .json], values := #[j], objectFieldKeys := #[] }
          else
            let next := q.kinds[q.kinds.size - 1]
            if next matches .objectEnd then
              go (jcsRenderString key acc ++ ":") (q.pushKind .json |>.pushValue j)
            else
              go (jcsRenderString key acc ++ ":")
                (q.pushKind .comma |>.pushKind .json |>.pushValue j)
      | .objectEnd => go (acc ++ "}") q
      | .comma => go (acc ++ ",") q

end Lean.Json
