# ADR-0031 — `core/env`: dotenv layers + substitution engine

- Status: accepted
- Date: 2026-11-26
- Work item: WI-0014 (S10)

## Context

Corpus §6 defines dotenv environment files layered `posting.env` →
`posting.local.env` → `<name>.env` → `<name>.local.env` → session
values, plus `$NAME`/`${NAME}`/`$$` substitution with error-vs-
passthrough rules and expansion limits. oxl has no str-keyed maps,
and the variables screen (§4.11) needs source-labeled ordered rows.

## Decision

1. **A new `core/env` leaf owns §6 semantics**: `parse_dotenv`
   (`export ` prefix, `'`/`"` quoting, `#` comments, `${OTHER}`
   refs resolved against earlier layers), `EnvSet` = ordered
   `[]EnvLayer{name, source, vars: []model.KV}` so later-layer
   names shadow earlier ones while display order stays stable.
2. **`substitute(text, set, in_url)` implements §6.2**: `$NAME` and
   `${NAME}` forms, `$$` literal, unresolved → error inside
   URL-address/path positions and literal passthrough elsewhere,
   limits (>10000 refs, >16 MiB aggregate) → error.
   `${$uuid}`/`${$timestamp}`/`${$timestampMs}`/`${$isoTimestamp}`/
   `${$randomInt}` generated values resolve in the same pass via
   `crypto/rand` + `time.unix*` (isoTimestamp needs a small
   civil-from-days formatter — none in std).
3. **Session values are just the top EnvLayer** — the same
   mechanism serves env files, session vars, and (later) captures
   without a second lookup path.
4. **Env code does not live in `core/collection`** (rejected):
   corpus separates `internal/env` from `internal/collection`, and
   S11's config is not a collection concern either.

## Consequences

- All §6 behavior is headless-testable; the TUI owns only modal +
  display glue (`MEnvSwitch`, variables screen, URL preview).
- Generated values ride the substitution pass — kept despite the
  corpus's P3-only note because hand-authored files use them; the
  spec records the inclusion.
- `use_host_environment` (default false) and `environments.json`
  persistence stay S11 — session-scope env switching this stage.
