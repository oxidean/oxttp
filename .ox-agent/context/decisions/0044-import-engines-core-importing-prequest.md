# ADR-0044 — `posting import` engines live in `core/importing`, emit `PRequest`

- Status: accepted
- Date: 2026-11-28
- Work item: WI-0019 (M4c)

## Context

Upstream `internal/importing/` (~4600 lines Go across openapi/postman/
bruno + writer + layers) converts foreign formats into `model.Request`
values that `collection.MarshalRequest` serializes. Our collection layer
already owns the `.posting.yaml` schema as `collection.PRequest` with
`collection.encode`/`marshal`/`yaml.parse`+`decode`. The importer needs a
home that doesn't invert the dependency direction (collection must not
know about importers) and that both `tui` (CLI wiring) and tests can
reach.

## Decision

1. New package `core/importing` mirroring upstream file layout:
   `result.oxl` (Result/Environment/BracedOnly/safePart/safePath/
   numberedName/environmentFile/dotenvValue), `layers.oxl`
   (topological variable ordering + cycle warnings), `write.oxl`
   (never-overwrite writer + env files + existingBase),
   `openapi.oxl`, `postman.oxl`, `bruno.oxl` (+ `bruno_load.oxl`,
   `bruno_syntax.oxl` if size demands).
2. Engines emit an importer-local request record
   `{req: own collection.PRequest, file: str}` — `file` carries
   upstream's suggested collection-relative path (sanitized later by
   the writer, exactly like upstream `req.File`); `PRequest` itself is
   not extended with a non-schema field.
3. Writer verifies each marshaled request by round-tripping
   `yaml.parse`+`collection.decode` (upstream's `ParseRequest` check)
   before writing any file, preserving upstream's all-or-nothing
   admission.
4. `tui/cli.oxl` keeps only `cli_import_args` parsing (upstream
   flag-after-positional semantics) and calls `importing.*`; output
   stays the `Out{code,stdout,stderr}` contract.
5. Variables are importer-local `{name,value,source}` triples; the
   writer maps them to dotenv lines via a `dotenvValue` port and
   reads `existingBase` through `env.parse_dotenv`.

## Consequences

- `core/importing` depends on `core/collection`, `core/model`,
  `core/env`, `core/yaml`, `std/encoding/json` — no cycles.
- Model helpers upstream importers need (`FindVariables`,
  `Substitute`/`MapLookup`, `PathParamNames`, `Normalize`,
  `Variable`) are added to `core/model` as new files, matching
  upstream semantics.
- Deviations are recorded in ADR-0045 (DOM/YAML capability gaps).
