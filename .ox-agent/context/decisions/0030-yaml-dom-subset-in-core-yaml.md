# ADR-0030 — YAML DOM subset parser/emitter in `core/yaml`

- Status: accepted
- Date: 2026-11-26
- Work item: WI-0014 (S10)

## Context

`.posting.yaml` collections (corpus §5) are YAML and oxl std 0.26.0
ships no YAML package (`encoding/` = base64, binary, csv, gob, hex,
json, xml). S10 must read collection files, marshal saved requests
with `omitempty` non-defaults, and degrade malformed files into
sidebar placeholder rows (§5.1) rather than abort the load. S11's
40-key `config.yaml` is a second YAML consumer arriving one stage
later.

## Decision

1. **A generic DOM lives in a new `core/yaml` leaf package**:
   `parse(text) -> [own YNode, err]` builds an ordered node tree —
   `YNode{kind: scalar|map|list, s: str, pairs: []YPair, items:
   []own YNode, line: int}` with `YPair{key: str, val: own YNode}` —
   and `emit(node) -> str` serializes it. Scalars stay lexical
   strings; schema decode coerces bools/numbers/null per field.
2. **The grammar is a pinned subset**: indentation block maps,
   `- ` block sequences, plain/single/double-quoted scalars,
   `|`/`>` block scalars, comments, `key:` empty values. Anchors,
   aliases, tags, flow `[]`/`{}`, and multi-doc streams are parse
   errors — corpus §5.1 already defines the malformed-file
   placeholder path, so unsupported constructs fail corpus-shaped.
3. **Schema mapping lives in `core/collection`**: `decode(node) ->
   [own PRequest, err]` enforces corpus rules (exactly-one-body,
   validated methods, strict keys where corpus says strict),
   `encode(req) -> YNode` emits only non-default fields, and
   `scan`/`load_file`/`save_file` own directory walking and IO.
4. **Purpose-built single-pass readers rejected**: a direct
   text→PRequest walker would be re-written for config.yaml in S11
   and couples grammar errors to schema errors; the DOM split costs
   little and matches upstream's format.go ↔ kinds.go layering.

## Consequences

- `core/yaml` is headless-testable; collection fixtures pin both the
  accepted grammar and the decode/encode round-trip.
- Byte-compatible write-back is bounded by what the emitter produces
  (plain/quoted/block scalars, insertion order) — fixtures verify.
- S11's config parser becomes a decode-only consumer.
- Upstream gap recorded: a real YAML 1.2 port for oxl stays a
  candidate; the subset is documented in the S10 spec.
