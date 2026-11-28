# WI-0019 plan — M4c import / run / remote / themes / tools

Spec: `artifacts/spec.md`. ADRs: 0044 (layout), 0045 (DOM/fs
deviations), 0046 (remote degrade+surface), 0047 (run env), 0048
(test strategy). Upstream reference clone: `/tmp/posting-src-full`.

## Stage P1 — model + shared helpers (foundation)

Files: `core/model/vars.oxl` (new), maybe `core/model/kindbits.oxl`.

- Port `model.FindVariables` (VariableRef{name,start,end}; `$$`
  escape; `$NAME`/`${NAME}`/`${$name}` forms), `Substitute`,
  `SubstituteBraced`, `FindBracedVariables`, `isIdentifier`,
  `MapLookup` (map→lookup-fn equivalent: oxl has no fn values? —
  check; substitute takes lookup fn upstream; our env.substitute
  uses EnvSet. For import we need substitute-over-map: implement
  `subst_map(s, []KV)` directly, plus keep FindVariables for
  ordering/refs), `PathParamNames`, `Normalize`-equivalent for
  PRequest (kind field reset — port `Fields` per kind from
  kind.go), `Variable` struct.
- Tests: `core/model/vars_test.oxl` porting upstream
  variables_test/kind_test pathparam cases.
Gate: `oxl test ./core/model` (dir exists? model tests live in
core/model — test command covers ./cli ./tui ./core/session only;
run `oxl test ./core/model` explicitly).

## Stage P2 — import shared core (result/write/layers + DOM glue)

Files: `core/importing/{oxl.mod,result,write,layers,dom,jsondom,yamlconv}.oxl`.

- `oxl.mod` for new package (mirror core/collection/oxl.mod).
- result.oxl: Result/Environment/ImpRequest/BracedOnly/safePart/
  safePath/numberedName/environmentFile/dotenvValue/
  environmentDataMode/DirectoryName.
- layers.oxl: ordered()+cycleFrom+layers() (heap→simple sorted
  ready-list; indexHeap → insertion-sorted []int).
- write.oxl: Write() per spec — encode via collection.encode+
  yaml.emit, verify via yaml.parse+collection.decode, exists-check
  suffix loop, env files, existingBase via env.parse_dotenv,
  cleanup on failure.
- dom helpers: json.Json accessors (obj get/put-last-wins, arr
  iterate, scalar()), YAML→Json converter with scalar typing
  (bool/null/int/float/str per looks_like rules), sorted-keys.
- Tests: result_test/write_test ports (safePart table, dotenvValue
  quoting, numberedName, layering order+cycle, never-overwrite,
  env-only+existingBase warning, deferred header).
Gate: `oxl test ./core/importing`.

## Stage P3 — Postman engine

`core/importing/postman.oxl` + `postman_test.oxl` + testdata.
Port postman.go 1:1 (see spec S1c): envelope checks, walk, convert,
readURL/joinURLParts, readAuth, template/expand/scopedAliases,
convertPairs/decodeQuery/cutOutsideReference/splitOutsideReference/
escapeEncodedDollars, graphQLVariables, ParseEnvironment,
variables(). BracedOnly for graphql query; PRequest graphql fields.
Gate: unit tests green.

## Stage P4 — OpenAPI engine

`core/importing/openapi.oxl` (+ maybe `openapi_security.oxl`) +
tests + testdata. Port openapi.go+security.go+values.go+
budget.go+json.go per spec S1b: JSON via json.Json DOM (dup-key
reject needs custom check — jget first-match vs last-wins: verify
jparse dup behavior; if it keeps both, jget-last), YAML via
core/yaml→Json converter, resolve/resolveSchema/resolveObject,
scan, server, escapePath, parameters/parameter/parameterValues,
body/formValues, security/authPrefix/addVariable/placeholder/
cookie/appendCookie, example/sample, encodeJSON/jsonFits,
checkRequestBudget/requestBytes, keys/obj/array/str/boolean/
literal/isJSON/mediaType, warn/fail.
Gate: unit tests green.

## Stage P5 — Bruno engine

`core/importing/bruno.oxl` + `bruno_syntax.oxl` + `bruno_load.oxl`
+ tests + testdata. Port syntax.go (parseDocument/parsePairs/
opensMultiline/isText/outdent/list/sliceUTF16/values), bruno.go
(scope/convert/expander/grpcMessage/grpcProtos/scopeConstants/
postingVariables/environment/mergeRows/mergeQuery/requestFootprint/
warn/diagnostics), load.go (Load/readBounded/readDir/walk/
loadEnvironments/sortEntries).
Gate: unit tests green.

## Stage P6 — cli_import wiring + format detection

`tui/cli.oxl`: rewrite cli_import_args → upstream parseImportOptions
(flag gather + fs.Parse semantics hand-rolled: flags anywhere,
`--`, `-t/-o` value forms), readImports (source classification,
isPostmanEnvironment, parseCollection detection), importCommand
(output dir default `paths.DefaultCollectionDir()/DirectoryName`,
Abs, Write, warnings, result lines, exit codes). `tui/cli_test.oxl`
additions. Also `importDiagnostic` (strconv.Quote-minus-quotes) +
`curl.Quote` port (check upstream internal/curl Quote impl).
Gate: `oxl test ./tui`.

## Stage P7 — run fixes (S2)

`tui/cli.oxl` run section: runUsage verbatim; run_parse_args →
upstream messages + `-c` alone → target "."; run_env → root-only
dirs + settingsInEnvironmentFiles warnings; run_exec error paths →
report-with-error (text summary / --json error field) exit 1;
--json per-request error field on HTTP-error status; keep existing
ordering/fail-fast/scripts/captures-degrade.
Gate: `oxl test ./tui` + manual smoke vs fixtures.

## Stage P8 — remote fixes (S3)

`tui/cli.oxl` remote section: parseRemoteOptions port (strict
flags, per-command rules, cross-flag errors), command set minus
new/focus, verbatim remoteUsage, vendored SKILL.md (generate
`tui/remote_skill.oxl` const from upstream file — check
gen_assets.oxl pattern or plain const), list empty→stderr/`[]`,
instance degrade exit 1, `--help` exit 0.
Gate: `oxl test ./tui`.

## Stage P9 — themes/tools spot-check (S4)

Verify §8.1/§8.4 behaviors against corpus; fix only on failure.
Gate: existing tests + manual review.

## Stage P10 — full verify + review pipeline

`oxl build ./tui ./cli`, full test loop, code-review + verify runs,
then ship pipeline (commits, push, PR, gate IN file — see ship notes:
check IN id collisions on sibling branches first).

## Ordering rationale

P1→P2 foundation before engines (engines need dom/vars/write).
P3 postman first (simplest DOM consumer, validates jsondom+write).
P4 openapi (hardest DOM+schema). P5 bruno (self-contained text).
P6 wiring last so engines are testable headlessly. P7/P8 surgical.
P9 verify-only. TDD per stage: write ported upstream test cases
first where feasible (ADR-0048), then implement to green.

## Risks

- oxl DOM friction (json.Json linked-list obj, no str-keyed maps) —
  assoc lists + linear scans; watch perf on 32MiB docs (budgets
  bound work anyway).
- `own`/`ref`/`mut` discipline across recursive DOM ports.
- Volume: ~4-5k lines new oxl; commit per stage keeps reviewable.
- Sibling worktrees share machine: explicit paths only in git add.
