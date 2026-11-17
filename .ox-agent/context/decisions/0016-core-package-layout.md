# 0016 — core/ package layout and domain representations

Status: accepted (2026-11-17, WI-0003 specification)

`core/` splits into per-concept packages rather than one domain blob:

- `core/model` — transport-agnostic domain: `Req`, `Resp`, `Header`,
  body kinds, trace timings (posting §4.15 TraceStage parity).
- `core/item` — xh REQUEST_ITEM grammar: `RequestItem` enum + parse.
- `core/http` — transport port interface (`Transport.send`) that the
  S3 h1 implementation satisfies.
- `core/session` — xh session file model + path naming.
- `core/collection` — `.posting.yaml` schema types verbatim (no IO).
- `core/term` — `Screen`/`Key` abstractions the TUI driver (S8)
  implements.

Import direction is strictly `cli`/`tui` → `item|session|term|collection`
→ `model`; `http` → `model`. `tui` never imports `item`; `cli` never
imports `term`.

Representations chosen for oxl v0.15.0 (no `Option[T]`, no str-keyed
std map, `enum` payloads + interfaces present):

- `RequestItem` is an `enum` mirroring `request_items.rs` 1:1 —
  named-payload variants keep corpus field sets per variant.
- Optional sub-objects are `own T` (nil = absent); optional scalars use
  `has_` bools so "key omitted" stays distinguishable from "key: ""
  (posting `omitempty` fidelity).
- str→str maps (posting `captures`, `variable_scope`, env layering)
  are ordered `KV` lists — std `collections.Map` is int-payload only.
- `:=` validates its value eagerly through `std/encoding/json` at
  parse time (corpus: parse error at parse time); the parsed tree is
  kept on the variant for the body builder (S6).

Consequence: every later stage imports these packages rather than
re-deciding boundaries; grammar quirks documented in
`context/references/xh-request-item-grammar.md` are implemented
verbatim, not smoothed over.
