# WI-0019 brainstorm — M4c import / run / remote / themes / tools

Discovery: `artifacts/discovery.md`. Upstream pin re-verified @32c4566.

## Problem framing

Three subcommand surfaces need corpus-faithful completion on top of the
S11 scaffolding:

1. **`posting import`** — the only wholly missing engine: OpenAPI 3.x,
   Postman v2/v2.1 (+ env exports), Bruno .bru/collection-dir →
   `.posting.yaml` collection + layered dotenv env files.
2. **`posting run`** — working runner with 6 enumerated fidelity gaps.
3. **`posting remote`** — parse/output fidelity pass; the transport
   (UDS) cannot exist on oxl 0.26.0 → permanent degrade.
4. **Themes/tools** — verify-only spot checks (§8.1/§8.4/§8.5 landed).

## Divergent options considered

### Option A — faithful port, all three engines, full warning matrix
Port all ~4600 lines of Go importer logic 1:1 (DOM helpers, $ref
resolution, schema sampling, security alternatives, Bruno scopes +
deferred variables + environments, writer layering). Highest fidelity;
largest cost (~4-5k lines oxl, many edge-case tests). Risk: subtle
oxl DOM/regexp gaps force deviations anyway.

### Option B — staged port: writer+postman+bruno first, openapi trimmed
Same as A but descope OpenAPI's schema-sampling/$ref depth to upstream's
warning paths ("requires explicit example; no value synthesized") —
i.e., implement resolve() for $ref but skip deep schema *synthesis*
where upstream only warns anyway. Cheaper; still corpus-faithful on
outputs because upstream itself warns-and-omits in those paths.

### Option C — surface-faithful stub upgrade
Keep `import` returning structured "unsupported" errors per format.
Rejected: violates corpus-fidelity mandate; the WI title names import.

### Option D — remote over TCP instead of UDS
Rejected: upstream protocol is UDS-only; inventing a TCP transport is
a bigger deviation than the documented degrade. File oxl AF_UNIX issue
instead.

## Convergent direction (chosen): A-with-B-trims, recorded honestly

- Port all three engines and the writer faithfully — **including**
  upstream's warning matrix verbatim where representable.
- Where oxl capabilities force approximation, prefer upstream's own
  degrade path (warn + omit / fail with upstream-shaped error) over
  silent divergence:
  - OpenAPI YAML input limited to `core/yaml` subset (no anchors,
    aliases, tags, flow collections, multi-doc) — parse-shaped error;
    JSON input unaffected. Recorded deviation.
  - json.Json DOM loses number lexemes → `scalar()` formatting
    approximates Go `json.Marshal` (ints exact, floats shortest-repr);
    duplicate object keys: last-wins emulated at access time.
  - `os.Root` confinement → lexical `safePath`/`safePart` port +
    exists-check `-N` suffix loop (TOCTOU benign for CLI).
  - No Go `regexp` dependency assumption — hand-roll the four tiny
    matchers (identifier, `{{…}}`, `{…}`, `^3\.[01]\.\d+$`) unless
    std/regexp proves available.
- `run`: fix the 6 gaps (collection-root env scoping, `-c` alone,
  settings warnings, usage/parse text, error-carrying report, --json
  error field) — all small, high-fidelity-value.
- `remote`: strict upstream flag grammar + command set (drop
  `new`/`focus`), verbatim usage text, vendored SKILL.md (131 lines,
  `go:embed` equivalent → embed as a const or `//go:embed`-style
  generated asset — check how gen_assets works; simplest: const string
  in a `tui/remote_skill.oxl` generated/vendored file per ADR-0041),
  `list` output shape; keep UDS degrade message but align exit codes.
- Themes/tools: spot-verify §8.1 picker order + §8.4 f3/f4 already
  correct; no new work expected.

## Tradeoffs preserved

- Full-fidelity import is expensive; the alternative (warn-and-skip
  whole formats) was rejected — corpus-fidelity contract.
- Bruno `DeferredVariables`/`variable_scope` machinery is the subtlest
  piece; port `scopeConstants`/`expander` faithfully including the
  16 MiB aggregate budget.
- OpenAPI schema *synthesis* stays (it's upstream behavior, not
  optional) but bounded exactly as upstream (depth 16, budget 10000,
  materialized 32 MiB).

## Open questions → resolved in spec

- Where does the importer live? → new `core/importing` package
  (mirrors upstream `internal/importing`), engines as
  `openapi.oxl`/`postman.oxl`/`bruno.oxl`/`write.oxl`/`layers.oxl`/
  `result.oxl`; `tui/cli.oxl` keeps only arg parsing + Out wiring.
- Request model? → emit `collection.PRequest` (+ transient `file`
  suggestion carried in an importer-local wrapper), reusing
  `collection.encode/marshal` + `yaml.parse`+`decode` for the
  write-verify round-trip upstream performs.
- Variables? → importer-local `Variable{Name,Value,Source}`; writer
  maps to dotenv lines; `existingBase` reuses `env.parse_dotenv`.
