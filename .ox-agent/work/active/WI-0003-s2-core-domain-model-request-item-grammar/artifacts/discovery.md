# WI-0003 discovery - S2 core domain model + request-item grammar

## Deliverable (plan.md S2)

Request/response/header/body-kind types; REQUEST_ITEM grammar -
9-sep longest-match scan, 12 variants, escaping rules,
`;type=`/`;filename=` right-scan params; session model;
`.posting.yaml` collection types (schema verbatim, no IO yet);
`Screen`/`Key` abstractions (types only); transport port interface the
h1 transport (S3) implements.

Gate: grammar unit matrix green incl. corpus edge cases (escaped seps,
empty-key `@file`, `key;` empty header).

## Corpus + source ground truth

- `docs/corpus/corpus-xh.md` section 3 - REQUEST_ITEM table, escaping,
  part params. Verified against the pinned clone
  `/tmp/oxttp-corpus/xh-src` @ 8b21cc07 `src/request_items.rs` +
  `src/utils.rs::unescape` - corpus is faithful. Exact algorithm +
  source-only quirks recorded in
  `context/references/xh-request-item-grammar.md`:
  - `:=`/`:=@` keep the RAW key (nested-JSON path source), DataField
    keeps both raw+unescaped, all others unescape.
  - `key;` empty-header branch runs only after the sep scan fails and
    does NOT unescape the key (upstream "technically too permissive").
  - `\` consumes the next char unconditionally during the sep scan.
- `docs/corpus/corpus-posting.md` section 5.2 - `.posting.yaml`
  17 top-level keys, verbatim types per decision 0010.
- `docs/corpus/corpus-xh.md` section 4.4 - session file model
  (meta/auth/cookies/headers) + path naming `<host>[_<port>]/name.json`.
- `docs/corpus/corpus-posting.md` sections 3-4 - key/modifier/mouse
  vocabulary for `Key`; section 4.15 TraceStage timings for `Resp`.

## Settled by WI-0001 (cite, do not re-litigate)

- 0002 monorepo: domain in `core/`, `cli`+`tui` consume.
- 0003 transport behind a `core/http` port; apps never see sockets.
- 0005 `Screen`/`Key` in `core/` so drivers swap.
- 0010 `.posting.yaml` verbatim - no oxttp-native keys.
- 0006 parse everything, degrade explicitly.

## oxl surface (context/references/oxl-toolchain-notes.md)

- `oxl test` with multiple dirs runs only the FIRST dir - test runs
  must loop per package dir (real coverage gap in the current
  test_command; flagged, not fixed here).
- No Option[T] / no str-keyed maps / no yaml - optional fields via
  `own T` + `has_` bools, maps via ordered KV lists.
- enums with payloads + interfaces exist - enough for the item
  variant union, Transport port, Screen port.
- `std/encoding/json` Json tree exists for `:=` value validation.

## Package sketch for implementation stage

- `core/model` - Method/Header/Body/Req/Resp (+ Trace stages).
- `core/item` - RequestItem enum + parse (grammar lives here).
- `core/http` - Transport port interface (S3 h1 implements).
- `core/session` - xh session model + pure path-naming fn.
- `core/collection` - .posting.yaml schema types verbatim.
- `core/term` - Screen/Key abstractions (types only).
