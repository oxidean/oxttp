# WI-0019 spec — M4c import / run / remote subcommands, themes, tools

Direction locked by `artifacts/brainstorm.md` + ADR-0064/0065/0066/0067.
Corpus: `docs/corpus/corpus-posting.md` §1 (CLI surface) + §8
(themes/import/remote/tools). Upstream source of truth re-verified
first-hand at `darrenburns/posting` @ `32c4566` (clone
`/tmp/posting-src-full`); every behavior below cites that tree.

## Scope

### S1 — `posting import` real engines (the bulk)

New package `core/importing` (ADR-0064). `tui/cli_import_args`
rewritten to upstream `parseImportOptions`/`readImports`/
`importCommand` semantics (`cmd/posting/import.go`):

- Flag grammar: `-t/--type`, `-o/--output` (both `--x v`, `--x=v`,
  `-x v`, `-x=v` spellings), flags may follow positionals, `--`
  terminates flags; unknown flag → exit 2
  `posting import: <err>`; `-h/--help` → usage exit 0.
- Type validation: only `openapi|postman|bruno` (lowercased) else
  `unknown import type %q (choose openapi, postman, or bruno)` → 2.
- Sources: ≤1 collection source + N Postman env exports; second
  collection → `expected one collection, but %s and %s are both
  collections; other arguments must be Postman environment exports`
  → 1; env-only without `-o` → `importing only environments requires
  --output DIR, the collection to add them to` → 2; zero importable
  requests → `source contains no importable HTTP requests` (+
  warnings) → 1.
- Format detection (no `-t`): `.bru` ext → bruno; dir → bruno
  (`<format> import requires a file` if `-t` non-bruno); JSON doc
  keys `openapi`|`swagger`→openapi, `info`+`item`→postman; else YAML
  doc same keys; else `cannot detect import format; use --type
  openapi, postman, or bruno` → 1. JSON validity checked first
  (YAML-invalid-JSON chars tolerated via YAML fallback, upstream
  verbatim).
- Postman env detection: `values` array present AND `item` absent →
  env file; name defaults to filename minus `.json`/`.postman_
  environment`; `globals` scope → error.
- 32 MiB source cap → `source exceeds the 32 MiB import limit`.

#### S1a — shared result/write/layers (`result.oxl`, `write.oxl`, `layers.oxl`)

- `Result{Name, Requests[]{req,file}, Variables[]{name,value,source},
  Environments[]{name,variables[]}, Warnings[], DeferredVariables}`.
- `BracedOnly` port verbatim (GraphQL `${…}`-only unescaping).
- `DirectoryName`/`safePart`/`safePath`/`numberedName`/
  `environmentFile`/`dotenvValue`/`environmentDataMode` verbatim —
  incl. reserved device names, 120-rune cap, `.local`→`-local`,
  `posting`→`-environment`, `$$`→`$` in single-quote path,
  `${`→`${:-$}{` double-quote escape, TemplateHeader when deferred.
- `Write(result, dir)`: marshal each request via `collection.
  encode`+`yaml.emit`, verify via `yaml.parse`+`collection.decode`
  round-trip BEFORE writing anything (upstream ParseRequest check);
  never overwrite — `-2`, `-3`… suffixes (case-insensitive used-set);
  base `posting.env` only when `Variables` nonempty (else
  `existingBase` reads dir's posting.env via `env.parse_dotenv` +
  Templates-skipped warning); env files via `layers()` (topo order,
  cycle warnings `…reference each other in a cycle; they are written
  in source order`, base-var repeat into envs that redefine deps);
  deferred mode writes TemplateHeader + skips layering;
  `source contains no importable requests, variables or environments`
  when empty; incomplete-write cleanup removes created files
  reverse-order; `Written{Files, Environments[{Name,File,Base}],
  Warnings}`.
- Output lines verbatim: `Imported N <fmt> request(s) into "<dir>".`
  / `Imported N environment(s) into "<dir>".` then `Environments:
  <file>[( base)], …` (first non-base selected) then
  `Open with: posting -c "<dir>" [--env "<sel>"]` (curl.Quote
  semantics — `"` + shell-escape; port upstream Quote: wrap in
  single quotes, `'`→`'\''`… verify upstream curl.Quote). Warnings →
  stderr `warning: <importDiagnostic(msg)>` where importDiagnostic =
  strconv.Quote-minus-quotes (escapes control chars).

#### S1b — OpenAPI (`openapi.oxl`)

- JSON path: `std/encoding/json` DOM; depth ≤100; duplicate keys
  rejected (`duplicate object key %q`); numbers via kind-2/6
  (ADR-0065). YAML path: `core/yaml` subset (ADR-0065 deviation);
  version regex `^3\.[01]\.[0-9]+$` else `unsupported OpenAPI
  version %q (supported: 3.0.x and 3.1.x; Swagger 2 is not
  supported)`.
- `paths` must be object; non-`/` path → error; `x-` skipped; TRACE
  → warn+skip; per method get/post/put/patch/delete/head/options/
  trace.
- `$ref`: internal `#/…` JSON-pointer resolution only, ≤64 chain,
  cycle detect, sibling keys → warn-and-ignore (`$ref` siblings have
  undefined overlap — upstream warns per key? verify: upstream
  `p.fail`? — port exactly: upstream warns "has sibling keys
  besides $ref; they are ignored" — CHECK source during impl),
  external `$ref`/`$id`/`$dynamicRef` → scan warnings (never
  fetched), `!!timestamp` n/a under yaml subset.
- servers: array required-if-present; >1 → warn first; `{var}` →
  `variables.<name>.default` required (string) else fail; `?#` in
  URL → fail; scheme http/https only; relative → `${BASE_URL}` +
  `BASE_URL` variable + warn; missing servers → same.
- parameters: merge path-item+op (op overrides by name+in);
  name+in required; dup name+in → fail; `allowReserved` → warn+
  omit; `content` exactly-one-media; example via
  example>examples[0](alphabetical+warn)>schema-sample; styles
  simple/form/deepObject/spaceDelimited/pipeDelimited per
  `parameterValues` matrix; header skips accept/content-type/
  authorization; path→PathParams (style simple only); cookie→
  Cookie header (form+scalar); query→Query rows (enabled =
  present||required); unsupported → upstream warn texts.
- requestBody: media pick json > form-urlencoded > first(+warn);
  multipart → warn+omit; no example → warn `request body has no
  usable example or default; body needs editing`; form fields via
  `formValues` (encoding style/explode/allowReserved/contentType
  matrix, object→application/json default); raw JSON pretty-printed
  when `len(encoded) <= remaining/202`; `SubstituteBodyVariables`
  off for bodies (`options.substitute_body_variables: false` in
  file — verify encode maps this); wildcard media warn.
- security: OR-of-requirements; empty requirement object →
  anonymous (warn if >1 alternative); scheme resolution via
  components.securitySchemes; supported = http basic|bearer|digest
  (authCount≤1) + apiKey header|query|cookie; picks FIRST fully
  supported alternative (+warn `selected security alternative %d
  of %d`); placeholders `${OPENAPI_<NAME>_<sha256[:4]>}` via
  addVariable; apiKey header named Authorization counts toward
  authCount; cookie → `p.cookie` (QueryEscape name=value into
  Cookie header); final warn `authentication credentials are empty
  placeholders; configure imported variables before sending`;
  none supported → warn `security requirements cannot be
  represented (OAuth/OpenID/mTLS or incompatible schemes);
  authentication needs manual configuration`.
- callbacks non-empty → warn; per-request File =
  `[first-tag/]name.posting.yaml` (name=summary|operationId|
  `METHOD path`); description fallback item.description; budget
  checks (`checkRequestBudget`, `requestBytes`,
  `maxMaterializedBytes` 32MiB, `outputBytes` accounting incl.
  Name) → `OpenAPI materialized request data exceeds 32 MiB`.
- schema `sample()`: example/default/const → examples[0] →
  enum[0] → object synth (properties minus readOnly, warn
  `generated a body/parameter scaffold…`) → array [sample] → else
  false; depth≤16, budget 10000, allOf/oneOf/anyOf/$dynamicRef/$id
  → warn `requires an explicit example; no value synthesized`.
- Result.Name = info.title|"OpenAPI"; Variables Source "OpenAPI".

#### S1c — Postman (`postman.oxl`)

- Envelope: info{name,schema}+item[] required; schema must contain
  `/v2.0.0/` or `/v2.1.0/` else `unsupported collection schema %q
  (expected v2.0 or v2.1)`; Result.Name=info.name; collection
  `variable`→defaults map + Variables (disabled skip, last-wins,
  identifier warn `variable %q cannot be represented as a Posting
  variable; references remain literal`); `event`/`protocolProfile_
  behavior` warns.
- Walk ≤128 depth; folder=item[] (request+item both → error;
  neither → error); leaf request string-shorthand or object;
  method uppercase ∈{GET POST PUT PATCH DELETE HEAD OPTIONS} else
  `HTTP method %q is not supported by Posting`; File =
  `dirs…/name.posting.yaml` (unsanitized — writer sanitizes);
  name empty → `Untitled %d` (1-based index).
- URL: string | object{raw,protocol,port,host[],path[],hash,
  query[],variable[],auth{user,password}}; components authoritative
  when present (host join ".", path join "/" w/ leading-slash trim
  for string form, auth user:pass@, protocol trim ://, port, hash);
  query pairs → convertPairs(encoded) + `query parameters without
  '=' are normalized to empty values` warn; raw-query fallback split
  on `&`/`=` outside `{{}}`; fragment preserved; path `:var`
  (incl. `:name.suffix`→PathParams entry named segment) from
  url.variable[] enabled only; URL empty → `request URL is empty`.
- Headers: array of {key,value,disabled} or "Key: value" string
  (CRLF normalized, bad line → error).
- Body: disabled skip; modes ""/raw (contentType text/plain +
  language map json/xml/html/javascript; enabled Content-Type
  header overrides), urlencoded→Form pairs, graphql→Payload
  GraphQL{Query:BracedOnly(transform),Variables:transform} +
  non-POST warn `GraphQL request uses %s; Posting sends GraphQL
  requests as POST`; other modes → warn `body mode %q is
  unsupported; body omitted (multipart/files require manual
  conversion)`.
- Auth inherit chain (item.auth overrides); basic/digest/bearer/
  apikey/noauth/other-warn; apikey: empty kv → none; `in` attr →
  queryTarget via Substitute on defaults; header match
  case-insensitive removal of existing same-name fields then
  append; query exact-match; variable-name warn; digest>2 attrs
  warn.
- Templates: `$$`-escape literal `$` FIRST, expand local `{{name}}`
  refs (≤1024 budget/≤64 depth/≤1MiB per expand, 32MiB total
  expansionBytes, cycle warn `cyclic variable %q remains
  unresolved`, limit warns verbatim), then `{{ident}}`→`${ident}`,
  non-identifier → warn `variable reference %q is unsupported
  (dynamic, vault, or non-identifier name); left literal`;
  scopedAliases materializes collection defaults transitively
  referencing overridden locals (≤64 passes, sorted keys);
  cutOutsideReference/splitOutsideReference; escapeEncodedDollars
  (`%24`→`$$`) before decodeQuery; PathUnescape on path-param
  values.
- proxy/certificate present → warns; query fields scanned for
  encoded-var warn (`encoded query variable %q may need a decoded
  value…`); `model.Normalize` port (kind-field reset — GraphQL
  payload clears method/body/query/pathparams/headers? per
  upstream Fields — verify kind.go Fields per kind during impl).
- ParseEnvironment: values[] required; `_postman_variable_scope:
  globals` → error; enabled flag; same variables() path; warnings
  prefixed `environment "<name>"` when named.

#### S1d — Bruno (`bruno.oxl` + syntax/load)

- `parseDocument`: ≤16MiB, UTF-8 required, BOM strip, CRLF→LF;
  blocks `name{…}`/`name[…]`/`color: v`; text blocks
  (body*/docs/tests/example/script:*) end at column-0 `}`; `'''`
  multiline open/close tracking (opensMultiline rules incl.
  annotation `@x(` form and `~` prefix); list blocks `[…]`; ≤10000
  blocks; errors `line %d: expected a Bruno block opening|invalid
  block name|unexpected text after block|unclosed %s block`.
- `parsePairs`: `~` disable, quoted keys (\" escape), `:` split,
  `'''…'''` multiline values w/ sliceUTF16(4) per line +
  `@contentType(` tail, `[` empty-list value, annotation lines
  skipped (multiline-aware), ≤10000 rows.
- `document`: text(name) last-wins + outdent(2-space); has(name);
  pairs(name) concat all matching blocks; list(name) comma/newline
  split minus `~`.
- Single `.bru` → Parse(emptyScope): meta pairs, type http|graphql|
  grpc (other → warn `skipped unsupported Bruno request type %s`),
  method block (get/post/put/delete/patch/head/options/connect/
  trace OR `http{method:…}`/`grpc`), multiple method blocks →
  error, missing → `missing HTTP method block`, empty url →
  `HTTP request URL is empty`, method ∉ Posting set (grpc exempt)
  → warn `skipped HTTP method %s unsupported by Posting request
  files`; name default `Imported request`; File =
  `<basename>.posting.yaml`.
- convert(): vars merge (parent.vars + enabled vars:pre-request
  minus `@` prefix); deferred mode → variable_scope for
  identifier names (expansion.expand each) + expansion.vars =
  scopeConstants ∪ unrepresentable; headers mergeRows(parent,
  headers+metadata, fold-case) — disabled child doesn't disable
  enabled parent; query: legacy `query` + `params:query`, URL `?`
  split (QueryUnescape, invalid → error), fragment preserved,
  explicit-name suppression, mergeQuery(parent, child) — enabled
  child names drop same-named parent rows; params:path → PathParams;
  auth: `auth{mode}` + `auth:<mode>` pairs, `inherit`→parent
  (warn if none), basic/digest/bearer/apikey(placement
  header|queryparams→grpc warn|other warn)/none/other warn;
  body: `body:json|text|xml|sparql`→Raw+ctype map, missing block →
  `missing %s block`; form-urlencoded→Form pairs; graphql→Payload
  {Query, Variables} texts; grpc→grpcMessage (client/bidi/
  unknown-multi → `[…]` array join, else first + warn) +
  grpcProtos (protoPath warn-not-copied, ImportName search-path
  logic); other → warn `unsupported body mode %s; body was not
  imported`; legacy `body` block warn; settings pairs
  followRedirects(bool else `invalid followRedirects`)/timeout ms→s
  (0..86400000 else `invalid timeout`, `inherit`→warn Posting
  default)/other warn; diagnostics() warns for
  body:multipart-form|body:file|script:*|tests|assert|
  vars:post-response|example|app + non-text `@`-annotation lines;
  unsupported-block warn list verbatim.
- expander: `$$`-escape `$` first; `{{name}}` (whitespace-trimmed)
  → vars lookup → recursive expand (stack ≤32, count ≤10000,
  `expanded Bruno value exceeds 16 MiB` / `aggregate … exceeds
  16 MiB` errors); `process.env.` strip; identifier → `${name}`;
  else warn `unsupported variable reference %s retained`; cyclic →
  warn `cyclic variable reference %s retained`; jsonBody mode:
  in-string tracking w/ `\` escapes, replacement JSON-escaped
  (quoted[1:len-1]) + warn `unresolved JSON body variables require
  JSON-escaped values in Posting` when replacement contains
  `${`/`{{`; GraphQL Query → BracedOnly, Variables → expandMode
  json=true; gRPC Message expandMode json=true; digest+grpc warn.
- Load(dir): Lstat no-symlink; bruno.json required (`read
  bruno.json: %w`), name/type/ignore/protobuf.importPaths(enabled,
  nonempty path); walk ≤64 depth; collection.bru at root (scope,
  collection=true)/folder.bru per dir; environments/ dir at root →
  `vars`/`vars:secret`(+color) env files, others warn `skipped %s;
  Bruno environments are .bru files`; hidden/node_modules skip;
  symlinks warn `skipped symlink %s`; .bru → convert; per-request
  warnings prefixed `<rel>: `; deferred=true root scope;
  materialization budget: convert twice (deferred + materialScope)
  → `materialized Bruno collection exceeds 128 MiB`; file/dir
  counts 10000/20000/128MiB total.
- environment(): vars pairs enabled+identifier (else warns),
  vars:secret list warns (`secret variable %s has no value on disk;
  set it in %s.local.env` / plural), unsupported blocks warn.
- applyScope(): headers/query/vars:pre-request merge; collection
  vars → shared identifier rows → s.collection + result.Variables
  via postingVariables(expansion); auth mode parse; diagnostics +
  unsupported-block warns; scope.vars resets to parent.vars copy
  (folder vars materialize, collection vars defer).

### S2 — `posting run` fidelity fixes (ADR-0067)

- `-c/--collection DIR` without PATH → target `.` (whole collection);
  PATH relative joins -c root; without -c root = target dir or file
  parent (exists+isdir check → `collection %s is not a directory`).
- Env: no `-e` → root's posting.env+posting.local.env only; `-e` →
  `env_file_list`-equivalent with dirs=[root] (named envs root-only,
  file specs CWD-probed); ANY spec suppresses implicit base.
- `settingsInEnvironmentFiles`: per loaded env file, POSTING_*-prefixed
  names → stderr `posting run: <base> sets <names>, but settings
  aren't read from environment files. Set them in config.yaml or
  your shell instead.`
- `runUsage` verbatim (30-line upstream block).
- Parse errors → `posting run: <specific>` + `Run posting run --help
  for usage.` exit 2 (messages: `unknown option %s`, `%s needs a
  value`, `--%s takes no value`, `--%s needs a nonempty value`,
  `expected one request file or directory`, `give a request file,
  directory, or --collection DIR`, `request path must not be empty`).
- Load/run errors → stderr `posting run: <err>` AND report still
  printed: text `0 passed, 0 failed, 0 skipped` or `--json` full doc
  `{"results":[],"passed":0,"failed":0,"skipped":0,"error":"…"}`;
  exit 1.
- Per-request JSON: HTTP-error-status results carry `error`
  (`"<code> <text>"`) AND `response`; transport errors carry `error`
  only; upstream field order file,name,outcome,error,response.
- Keep: lexical rel-path ordering, fail-fast skip counting, scripts/
  empty-url abort texts, captures→FAILED degrade (WI-0018), config
  warnings fatal, use_host_environment stderr warning.

### S3 — `posting remote` surface fidelity (ADR-0066)

- `parseRemoteOptions` port: flags `--json --none --name --curl
  --yaml --instance` (+`-h/--help`), `--x=v`/`--x v`, `--` end;
  unknown option → `posting remote: unknown option %s` + usage hint
  exit 2; per-command positional rules verbatim (`open|send` ≤1 ref
  + exactly-one-of ref/curl/yaml; `env` positionals + none-conflict;
  `save` ≤1 file; `list|requests|show|response|skill` none);
  cross-flag errors (`--curl and --yaml are for open and send`,
  `--none is for env`, `--name is for save`, `give only one of
  REQUEST, --curl and --yaml`, `%s needs a nonempty value`).
- Command set EXACTLY `list requests show open send response env
  save skill` — **remove `new`/`focus`** (unknown command → 2).
- `skill` → vendored `skills/using-posting/SKILL.md` 131 lines
  verbatim (generated const asset per ADR-0041; `remote skill`
  works with no instance, exit 0).
- `remote --help`/`-h` → full `remoteUsage` text stdout exit 0.
- `list`: no instances → stderr `No Posting is running.` exit 0;
  `--json` → `[]\n`; else unreachable-without-UDS.
- Instance commands → degrade exit 1. Message: keep
  `no running Posting found (unix sockets unsupported in this
  build)` — recorded deviation from upstream's `no running Posting
  found: start Posting in another terminal first` (honest about
  capability; spec-noted).
- `--instance`/`$POSTING_INSTANCE`/`--curl`/`--yaml`/`--name`/
  positional env args/file args: parsed and validated per grammar;
  values consumed but transport-less (upstream would read files —
  `--yaml -` reads stdin; we degrade before IO, matching the
  instance-bound failure point — verify ordering: upstream reads
  yaml file BEFORE dialing? remoteRequest runs after Choose; with
  zero instances Choose fails first → degrade before file reads.
  Keep that order).
- `remote` protocol types ported as dead structs? — NO (ADR-0066
  note: only if trivial; skip to keep diff focused).

### S4 — themes/tools verification

- Spot-check §8.1: builtin order, P2 alias map, user-theme
  name+primary required, `#rgb|#rrggbb|#rrggbbaa` validation,
  omitted→inherit galaxy/builtin-light, same-name override, sorted
  files, bad-file→startup notification+skip, picker Yours-first,
  live preview + enter-applies/escape-restores, sidebar_gradient.
- §8.4: f3 pager (pager_json for JSON bodies)/f4 editor, $EDITOR/
  $PAGER + POSTING_* env, shell exec — verify tests exist.
- §8.5: scripts preserved not executed — run already rejects.
- Fix only if a check fails; otherwise no code change.

## Acceptance criteria

1. `oxl build ./tui` and `oxl test ./tui` green; `oxl test
   ./core/importing` (new pkg) green; `oxl test ./core/model`
   green; full `oxl test ./cli && oxl test ./tui && oxl test
   ./core/session` green.
2. `posting import --help` → usage on stdout with exit 0; bad type,
   env-only-no-output, and unknown flag → exit 2 with upstream-shaped
   stderr.
3. Postman fixture collection+env → writes `<dir>/posting.env`,
   `<name>.env`, request files; stdout `Imported N postman
   request(s) into "…"` + `Environments:` + `Open with:` lines;
   warnings on stderr `warning: …`.
4. OpenAPI JSON fixture (paths/params/body/security) → requests +
   `${OPENAPI_*}` placeholder vars in posting.env; YAML fixture
   within subset parses.
5. Bruno dir fixture (bruno.json+collection.bru+folder.bru+
   request.bru+environments/x.bru) → deferred variable_scope,
   collection vars in posting.env, named env file, grpc/graphql
   kinds where applicable.
6. Never-overwrite: pre-existing `name.posting.yaml` → `name-2.
   posting.yaml`; existing posting.env + env-only import → base
   vars land in numbered file + warning.
7. `posting run -c DIR` (no PATH) runs whole collection; env files
   resolve root-only; POSTING_* env file → stderr warning;
   load error → report-with-error + exit 1; bad flag → exit 2
   with specific message; --json error field present.
8. `posting remote` rejects `new`/`focus` (exit 2), strict flag
   errors exit 2, `skill` prints 131-line SKILL.md, `list` empty →
   stderr message exit 0, `--help` full usage.
9. Deviations recorded: this spec + ADR-0065 (yaml subset, number
   lexemes, fs confinement) + ADR-0066 (UDS degrade message) +
   ADR-0067 (env scoping is upstream-faithful, not a deviation).

## Out of scope

- UDS transport itself (oxl lacks AF_UNIX — upstream issue to file).
- Captures implementation (WI-0018), GraphQL/SSE/gRPC/WS request
  kinds in run (WI-0020/0021), OAuth (WI-0022), TLS/proxy (WI-0017).
- `remote` protocol client structs (dead code — skipped per ADR-0066).
