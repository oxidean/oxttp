# WI-0019 discovery — M4c import / run / remote subcommands, themes, tools

Pin: oxl **0.26.0** (`.oxl-version`). Corpus: `docs/corpus/corpus-posting.md`
§1 (CLI surface) + §8 (themes/import/remote/tools). Upstream re-verified
first-hand: fresh shallow clone of `darrenburns/posting` @ `32c4566`
(`v3.0.0-beta.1`, the corpus pin) at `/tmp/posting-src-full` — every claim
below cites `cmd/posting/*.go`, `internal/importing/**`,
`internal/remote/*`, `internal/themes/*`, `internal/model/*`,
`internal/env/dotenv.go`, `skills/using-posting/SKILL.md` at that commit.

## Current state (this worktree, branch feat/wi-0019-import-run-remote)

- `tui/main.oxl` dispatches subcommands before session open (ADR-0036);
  `tui/cli.oxl` implements `version`, `locate` (3 targets), `run`
  (headless runner over collection.scan+plan_req+H1, text+--json),
  `remote` (degraded), `import` (stub → exit 1 "lands M4").
- `tui/themes.oxl` already has the 37-builtin catalog (terma order+hex),
  user-theme YAML decode + dir scan, pickers, `sidebar_gradient`,
  `theme_preview` (S10/S11). §8.1 largely landed.
- `tui/cfg.oxl` already has f3 pager / f4 editor staging (§8.4 landed).
- `tui/curlimp.oxl` is §7.7 curl-command import (different surface).

## Gap analysis vs upstream (verified line-by-line)

### `posting import` — NOT IMPLEMENTED (the bulk of this WI)

Upstream `cmd/posting/import.go` (309 lines) + `internal/importing/`
(~4600 lines Go):

- CLI: `-t/--type openapi|postman|bruno` (repeatable flag spellings
  incl. `-t`/`--type`, `-o/--output`, flags may follow positionals,
  `--` ends flags). Detection: `.bru` ext → bruno; JSON doc with
  `openapi`|`swagger` key → openapi; `info`+`item` → postman; else
  YAML doc with same keys (flow-style tolerated); else error
  "cannot detect import format; use --type ...".
- Sources: ≤1 collection source (file or Bruno dir) + any number of
  Postman environment exports (`values` array, no `item` array →
  env). Env-only import requires `-o`.
- Postman env files: `postman.ParseEnvironment` — name defaults to
  filename stem; `_postman_variable_scope: globals` → error;
  `enabled:false` skipped; non-identifier names warned.
- 32 MiB per-source cap; Bruno collection ≤128 MiB / ≤10000 files /
  ≤20000 dir entries / ≤64 folder depth / ≤16 MiB per .bru.
- Output: `importing.Write(result, dir)` → per-request
  `<safe-path>.posting.yaml` (never overwrites — `-N` suffix),
  `posting.env` base + `<name>.env` per environment via
  `env.Templates`-compatible dotenv encoding (`dotenvValue` quoting
  rules), `layers()` topological variable ordering + cycle warnings +
  base-variable repeat into env files that redefine deps.
  `DeferredVariables` (Bruno dir loads) writes `TemplateHeader` and
  keeps `${NAME}` literals; Postman/OpenAPI materialize.
- Result line: `Imported N <format> request(s) into "<dir>".` or
  `Imported N environment(s) into "<dir>".` + `Environments: ...` +
  `Open with: posting -c <dir> [--env <name>]`.
  Warnings → stderr `warning: <msg>` (control chars escaped via
  strconv.Quote semantics — `importDiagnostic`).
- Exit codes: 0 ok; 1 read/convert/write errors + zero requests;
  2 usage/parse errors (`posting import: <err>`).

Engines (all verified):
- **openapi** (`internal/importing/openapi/`): JSON (exact, dup-key
  rejecting, depth ≤100, json.Number lexemes) or YAML (yaml.v3 full
  grammar, timestamp→str, exactYAMLNumbers restore, 250k-node budget);
  OAS 3.0.x/3.1.x only (swagger → error); $ref resolution internal
  only (≤64 chain, cycle detect, sibling-key diagnostic, external
  refs warned not fetched); servers (first wins + warn, `{var}` →
  default or fail, relative → `${BASE_URL}` + warn, query/fragment
  fail); parameters (name+in required, dup in+name fail, override by
  name+in, style/explode/allowReserved/content serialization matrix,
  header accept/content-type/authorization skipped, path→PathParams,
  cookie→Cookie header, query→Query rows); requestBody media pick
  (json preferred, form-urlencoded, else first + warn; multipart
  warned-omitted); security (OR-of-AND requirements, http basic/
  digest/bearer + apiKey header/query/cookie → `${OPENAPI_*}`
  placeholder variables + sha256-suffixed names, else warn); callbacks
  warned; TRACE skipped w/ warn; schema sampling for examples
  (example/default/const/enum/examples[0], object/array synthesis,
  depth≤16, budget 10000, readOnly skip, allOf/oneOf/anyOf warn);
  32 MiB materialized budget; request File = `[tag/]name.posting.yaml`.
- **postman** (`internal/importing/postman/`): v2/v2.1 schema check;
  info.name → Result.Name; collection+folder `variable` (disabled
  skip, last-wins, identifier warn), `auth` inherit chain, `event`
  scripts warned, `protocolProfileBehavior` warned; item tree ≤128
  depth, folder = item[] w/o request, leaf needs request; request =
  string shorthand or object; method ∈ Posting methods else error;
  URL string|object (raw/host[]/path[]/port/protocol/auth/query[]/
  variable[]/hash; structured query authoritative; `{{var}}` path
  params incl. `:name.suffix` split; query pairs decoded after
  template transform); headers array-of-pairs or "Key: value" string;
  body modes raw(urlencoded? no—) raw/graphql/graphql-vars/
  urlencoded/others-warn; auth basic/digest/bearer/apikey(in
  header|queryparams)/noauth/other-warn; `{{var}}`→`${var}` template
  with `$$` escaping, local scope expansion (≤1024 budget, ≤64
  depth, ≤1MiB, 32MiB total), scopedAliases materialization,
  cutOutsideReference/splitOutsideReference, escapeEncodedDollars
  (%24→$$), decodeQuery, BracedOnly for graphql query;
  proxy/certificate warned; model.Normalize.
- **bruno** (`internal/importing/bruno/`): .bru text format —
  column-0 `}`/`]` block ends, `name{...}`/`name[...]` blocks, text
  blocks (body*/docs/tests/example/script:*), triple-quote `'''`
  multiline, `~` disable prefix, `@annotation` lines skipped,
  UTF-16 slice(4) outdent, ≤16MiB/≤10000 blocks/≤10000 rows;
  collection dir: bruno.json (name/type/ignore/protobuf.importPaths
  enabled), collection.bru/folder.bru scopes (headers/query merge,
  vars:pre-request collection→Variables identifier-only else
  materialized vars, auth mode+fields, diagnostics for unsupported
  blocks), environments/*.bru → named envs + vars:secret warnings,
  requests .bru → http/graphql/grpc kinds, DeferredVariables=true
  (variable_scope for identifier vars + scopeConstants materialize),
  128MiB materialized budget, symlink skip+warn, hidden/node_modules
  skip; single .bru file → Parse with emptyScope.
  Bruno `{{var}}` expander: `$$` escape first, `{{name}}`→`${name}`
  when identifier (process.env. prefix strip), recursion ≤32,
  count ≤10000, JSON-body mode tracks in-string + JSON-escapes
  replacement, warns on unresolved/cyclic.

Needed shared helpers NOT yet in repo (verified missing):
`model.FindVariables` (refs w/ Start/End, `$$` escape, `$NAME` +
`${NAME}` + `${$name}`), `model.Substitute`+`MapLookup`,
`model.PathParamNames`, `model.Normalize` (kind field reset —
GraphQL/gRPC payload field clearing), `model.Variable` (Name/Value/
Source), `model.KeyValue`→our `model.KV`, `env.Templates` equivalent
for existingBase, `collection` request parse-from-text for the
write-verify step, dotenvValue quoting.

### `posting run` — MOSTLY DONE, fidelity gaps found

Upstream `cmd/posting/run.go` (364 lines) vs our `cli_run`/`run_exec`:

- **-c without PATH**: upstream `opts.target="."` → runs whole
  collection. Ours requires a target → exit 2. GAP.
- **Env resolution**: upstream `env.Stack(root, BaseName)` default =
  collection ROOT's posting.env+posting.local.env ONLY (not CWD,
  not config dir). With `-e`: `environmentFiles(specs, [root])` —
  named envs resolve in root only; file args relative to CWD;
  base auto-included only via named-env stack. Ours searches
  CWD→coll→config dirs and defaults to dirs[0]=CWD base. GAP
  (deviation from corpus §6.1 layering for run).
- **settingsInEnvironmentFiles**: upstream warns per env file
  containing POSTING_* names → `posting run: <file> sets <names>,
  but settings aren't read from environment files...` on stderr.
  Missing. GAP.
- **Parse errors**: upstream prints `posting run: <specific err>` +
  `Run posting run --help for usage.` exit 2. Ours prints generic
  "bad arguments". GAP (message fidelity).
- **Usage text**: upstream runUsage is a fixed 30-line block — ours
  is a 6-line summary. GAP.
- **Load/runtime errors**: upstream `fail()` → stderr
  `posting run: <err>` AND still prints the report (text summary
  `0 passed, 0 failed, 0 skipped` or full --json doc with `error`
  field) exit 1. Ours prints only stderr, empty stdout, no json
  error field. GAP.
- **--json result**: upstream runResult{file,name,outcome,error?,
  response?} — HTTP-error responses carry BOTH `error`
  ("404 Not Found") and `response`. Ours emits response but no
  `error` on HTTP-status failures. GAP.
- Response shape = remote.NewResponse (protocol.go): method,url,
  status(str code),reason,statusCode,proto,headers,trailers,
  contentType,streamError,body|bodyBase64,size,elapsedMs,receivedAt.
  Ours approximates (no trailers/streamError — land with SSE/other
  WIs; fine).
- Ordering lexical by collection-rel path: DONE. fail-fast skip
  counting: DONE. scripts/nonempty-url abort: DONE (message matches).
  captures → per-request FAILED degrade: correct until WI-0018.
- Exit codes: 0 all pass / 1 run+request failure / 2 usage. Ours
  matches modulo the gaps above.

### `posting remote` — SURFACE-LEVEL, needs fidelity pass

Upstream `cmd/posting/remote.go` (526) + `internal/remote/`
(protocol.go/client.go/server.go) over UDS in paths.SocketDir:

- Commands: `list requests show open send response env save skill`
  — **NO `new`/`focus`** (ours accepts them → deviation; upstream
  `unknown command %q` → exit 2).
- Flag grammar: `--json --none --name V --curl V --yaml V
  --instance V --env?`(env takes positionals) `-h/--help`; `--x=v`
  and `--x v`; unknown option → exit 2; `--curl/--yaml` only for
  open|send and nonempty; `--none` only env; `--name` only save;
  open/send take ≤1 positional ref; env takes positionals;
  list/requests/show/response/skill take none; `--` ends flags.
  Ours parses loosely (any non-flag → cmd; ignores unknown flags).
  GAP.
- `skill`: prints `skills.UsingPosting` = vendored
  `skills/using-posting/SKILL.md` (131 lines) verbatim — ours prints
  a 9-line stub. GAP → vendor the file (ADR-0041 precedent).
- `list`: no instances → stderr `No Posting is running.` exit 0;
  --json → `[]`; else tabwriter `PID COLLECTION STARTED IN`.
  Ours prints a different table to stdout. GAP (minor).
- Instance commands with no instances: upstream Choose →
  `posting remote: no running Posting found: start Posting in
  another terminal first` exit 1. Ours: `no running Posting found
  (unix sockets unsupported in this build)` exit 1. Degrade reason
  differs — KEEP degrade (oxl std/net has NO AF_UNIX: verified —
  dial() is TCP host:port only, no unix socketlistens in 0.26.0
  stdlib) but align the surrounding parse/output fidelity; record
  the UDS gap as the standing deviation (ADR-0036 already covers;
  may file oxl issue for AF_UNIX support).
- `remote --help` prints full remoteUsage (52 lines) stdout exit 0.
  GAP.

### Themes (§8.1) and tools (§8.4/§8.5) — verify-only

- themes.oxl: 37 builtins + user themes + pickers + preview landed
  (S10/S11). Remaining check: "Yours first" picker order, P2 name
  mapping, bad-file→startup notification — spot-check during impl.
- cfg.oxl: f3/f4 pager/editor + pager_json + POSTING_* env landed.
- §8.5 scripting: preserved-not-executed — our run already rejects
  scripts-bearing requests (upstream run.go identical).
- §8.6 misc: keep-tab previews etc. — S10 scope, not this WI.

## Platform constraints (verified)

- oxl 0.26.0 `std/net`: TCP only — `dial(host,port)`, `listen(port)`.
  NO unix-domain sockets → `remote` instance commands can never
  succeed; degrade stands (candidate upstream issue: oxl AF_UNIX).
- `std/encoding/json`: DOM `Json{kind,key,s,i,f,b,child,next}` —
  kind 0 null/1 bool/2 int/3 str/4 obj/5 arr/6 float; `jparse`,
  `jget`, `tojson`, `jstr/jint/jfloat/jbool/jnull/jobj/jarr/jadd/
  jarrb` all package-visible. Number lexemes NOT preserved
  (int→i, float→f) — upstream json.Number fidelity is approximate.
- `core/yaml`: DOM subset — block maps/sequences, plain/single/
  double scalars, block scalars; NO anchors/aliases/tags/flow
  collections/multi-doc (parse error). OpenAPI YAML input limited to
  this subset → spec deviation (upstream yaml.v3 full grammar).
- os: `os.ls`, `os.exists`, `os.isdir`, `os.readfile_`,
  `os.writefile_`, `os.mkdir_all`, `os.fullpath`, `os.getenv`,
  `os.open` — enough for the writer (no os.Root; implement
  lexical-path safety in safePath/safePart + write-file-excl via
  os.open flags? check os.writefile_ semantics — may need
  exists-check loop for -N suffixing; acceptable: check-then-write
  race is benign for a CLI import).
- regexp: std has `regexp`? — check; upstream uses regexes for
  identifier/reference/template matching. std/regexp exists in
  toolchain listing; verify API surface during impl (may hand-roll
  the small matchers — identifier `^[A-Za-z_][A-Za-z0-9_]*$`,
  `\{\{...\}\}`, `\{[^{}]+\}`, `^3\.[01]\.[0-9]+$` — all simple).

## Test strategy

- `core/importing/*_test.oxl`: unit tests per engine mirroring
  upstream `*_test.go` cases (postman_test 253, openapi_test 316,
  bruno_test 384, environment_test, probe_test, write_test 331,
  result_test, layers via write_test) — port the meaningful subset:
  format detection, env-only import, warnings, dedup/overwrite
  suffixes, layering order, deferred variables, error paths.
- `tui/cli_test.oxl`: extend for import/run/remote arg parsing,
  exit codes, output shapes (Out contract already test-friendly).
- Fixture .bru/.json/.yaml files under testdata dirs.

## Risks

- Scale: ~4600 lines Go → est. 4000-5000 lines oxl. Single biggest
  WI to date; mitigate by file-per-upstream-file layout and TDD per
  engine (postman → openapi → bruno → writer → cli wiring).
- oxl quirks: multi-return ends in err; no maps with str keys
  (ordered KV lists — upstream uses map[string]… pervasively; port
  as sorted-key []Pair lists or linear-scan assoc lists); interface
  methods can't suspend; `substr` END index.
- json.Json DOM lacks number lexemes + duplicate-key last-wins
  semantics may differ (jadd appends; jget first-match — verify).
