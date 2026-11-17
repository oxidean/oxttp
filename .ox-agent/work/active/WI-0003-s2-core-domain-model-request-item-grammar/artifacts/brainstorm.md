# WI-0003 brainstorm - S2 core domain model + request-item grammar

Scope: this WI is one stage of the approved WI-0001 plan. The big calls
(monorepo split, transport port, verbatim posting schema, Screen/Key in
core) are ADR-settled - this brainstorm only covers stage-level choices.

## Open questions worth diverging on

### Q1 - RequestItem representation

- **A: oxl `enum` with payload variants** (chosen)
  `RequestItem{HttpHeader{key,value}, HttpHeaderFromFile{key,value},
  HttpHeaderToUnset{key}, UrlParam{key,value}, UrlParamFromFile{key,value},
  DataField{key,raw_key,value}, DataFieldFromFile{key,raw_key,value},
  JsonField{raw_key,value}, JsonFieldFromFile{raw_key,value},
  FormFile{key,file_name,file_type,file_name_header}}` - mirrors the
  Rust enum 1:1; `match` exhaustiveness helps every consumer; tags map
  to the corpus table.
  Tradeoff: named-payload variants only (no positional), slightly
  more verbose construction. JsonField value stored as parsed `own
  json.Json`? - see Q3.
- **B: one struct + kind tag** - flatter, loses payload-type safety and
  forces dead fields per variant (FormFile's two params vs others).
- **C: interface per variant** - 10 impls for a pure-AST type; dispatch
  buys nothing match doesn't already give.

### Q2 - Package granularity inside core/

- **A: one package per concern** (chosen): `model` `item` `http`
  `session` `collection` `term` - matches spec's domain list, keeps
  import graph acyclic and lets `cli`/`tui` pull only what they need
  (tui never imports `item`; cli never imports `term`).
- **B: single `core/domain` package** - fewer dirs but couples
  xh-grammar to posting-schema to terminal ports; the module layout
  ADR wants domain-driven splits.
- **C: fold grammar into `cli`** - rejected: items feed `core` request
  building (S5) and need core-level tests anyway.

### Q3 - `:=` JsonField value validation now or later

- **A: validate at parse via `std/encoding/json`** (chosen) - xh
  rejects malformed `:=` at parse time (clap InvalidValue). oxl
  `json.jparse` exists; store the raw string + a parsed `own Json`
  (nil-checked). Tradeoff: xh uses serde_json (floats, deep unicode);
  oxl json is int/float-capable, `\uXXXX` ok - acceptable for v0.1,
  documented deviation risk low.
- **B: defer JSON validation to S6** - keeps grammar pure but parses
  `:==notjson` silently; corpus says parse error now.

### Q4 - Optional fields across posting/session types

- **A: `own T` for optional sub-objects, `has_` bools for scalars**
  (chosen) - no `Option[T]`; matches std idiom; `omitempty` semantics
  (only non-defaults written) need explicit presence anyway.
- **B: empty-string = absent** - can't distinguish omitted vs explicit
  empty (`proxy_url: ""` vs missing) - fidelity loss.

### Q5 - Screen/Key shape

- **A: `Key` tagged-union + `Screen` interface** (chosen) - corpus
  key vocabulary = modifiers (ctrl/alt/shift/meta/super) + named keys
  (enter..f12) + runes + mouse (SGR). Screen = cell-buffer port
  (size, set_cell, present, cursor) so stty-ANSI driver (S8) and a
  test driver both implement.
- **B: int keycodes + raw func table** - loses corpus names; dispatch
  tables in S9 would be unreadable.

## Recommendation

A across the board - faithful to upstream shapes, uses the oxl
features that exist, keeps stage boundaries clean. Residual
disagreements: JsonField stores raw string + lazily parsed Json vs
eager parse (chose eager - corpus says parse error at parse time);
posting `variables` is a JSON tree (std/encoding/json `own Json`)
rather than a str map.
