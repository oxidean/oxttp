# WI-0014 plan — S10 TUI collections + envs + send path

Spec: `artifacts/spec.md` (grammar, semantics, degradation table,
deviations, acceptance criteria). Architecture: ADR-0030/0031/0032
(+0033 UX boundaries). TDD: red tests first per stage; `oxl test`
runs per leaf dir (`oxl build` honors only the first dir arg —
loop `core/yaml`, `core/env`, `core/collection`, `tui`, then
`cli` regression).

## S10.1 — `core/yaml` DOM subset (new leaf)

Red: `core/yaml/yaml_test.oxl` —
- block map nesting, `key:` empty, `- ` seq of scalars and of
  inline-map items (continuation lines merge), plain/'…'/"…"
  scalars (escapes \n \t \" \\), `|`/`>` block scalars incl.
  indent+chomp, comments, mixed seq-in-map-in-seq.
- errors: tabs in indent, anchors `&`/`*`, tags `!`, flow `[/{`,
  `---` doc marker — each errors with a line number.
- emit: map/seq/scalar kinds, plain-safe vs quoted fallback,
  multiline → `|`, key order preserved; `parse(emit(n))` round-
  trips on fixture-shaped nodes.
Green: `yaml.oxl` DOM (`YNode`/`YPair`), recursive-descent
`parse`, `emit`.
Gate: `oxl test core/yaml` green.

## S10.2 — `core/env` dotenv + substitution (new leaf)

Red: `core/env/env_test.oxl` —
- parse_dotenv: `NAME=v`, `export `, `'`/`"` quotes, `#` comments,
  bare `NAME`, `${OTHER}` refs (same-file then prior layer),
  `POSTING_*` → warns.
- EnvSet: layer precedence (posting.env < posting.local.env <
  name.env < name.local.env < session), ordered vars.
- substitute: `$NAME`/`${NAME}`/`$$`; unresolved → err in_url,
  passthrough elsewhere; `${$uuid}`/`${$timestamp}`/
  `${$timestampMs}`/`${$isoTimestamp}`/`${$randomInt}` shapes;
  >10000 refs / >16 MiB errors.
- scan_envs/build_set on fixture dir incl. missing-file skip.
Green: `env.oxl` per spec.
Gate: `oxl test core/env` green.

## S10.3 — `core/collection` decode/encode/scan/plan_req

Red: `core/collection/load_test.oxl` + committed fixtures under
`tests/tui-fixtures/` —
- decode: all 17 keys; method validate+uppercase+default-GET;
  body exactly-one (>1 → err; part w/o exactly-one-of-value|file
  → err); strict keys inside graphql/grpc/websocket; enabled
  default true; options defaults applied + set_mask tracks
  explicit sets; kind validation; auth blocks; captures/
  variable_scope/scripts decode.
- encode: omitempty (defaults omitted incl. implicit options),
  corpus key order, string-vs-bool scalar safety;
  marshal→parse→decode round-trip on fixtures.
- scan: fixture tree — nested folder, skips dot-dir/`node_modules`,
  folders-first-alpha sort, malformed file → node w/ err not abort.
- plan_req: scheme-less→http://; `:name` fill; enabled-only
  params/headers; body variants (content/form_data/multipart/
  file); auth basic/bearer → Authorization (explicit row wins);
  digest/oauth2/kind → degrade errs; follow/max_redirects/
  timeout_ms/verify="no"; attach_cookies jar header vs explicit
  Cookie; proxy_url → warn; substitute in url/headers/auth/body
  (gate flag); UA synth.
Green: decode/encode/scan/load_file/save_file/plan_req in
`collection.oxl` (+ `set_mask` field on POptions).
Gate: `oxl test core/collection` green; `oxl test core/yaml`,
`core/env` still green.

## S10.4 — TUI state + glue (`tui/`)

Red: `tui/coll_test.oxl` + `tui/send_test.oxl` —
- types: TreeNode gains `path`/`kind`/`err`; RDraft gains
  auth/options display fields + `path`; App gains `env_active`,
  `env`, `jar`, `history`, `pending`, `coll_dir`.
- open_into_draft fills draft fields from PRequest; malformed
  node → toast; preview-tab reuse + flip-on-edit; multi-open.
- tree ops: dup writes `(copy)` file + renamed `name:`; delete
  confirm→remove→reload (folder degrades); save marshal at
  slug path w/ folder mkdir + overwrite confirm; tab title/path.
- env: build_set at load; MEnvSwitch pick → env_active + rebuild;
  `(none)` clears; variables screen flattened rows + masking +
  reveal; URL preview substitution + mask + unresolved marker.
- send: send-request builds plan→ESend (plan err → toast; warns
  → info toasts); exec_send installs resp (body incl. JSON
  re-indent, headers, cookies, trace, size·elapsed title),
  jar update, history append; error installs error text.
- history: cap 100 drop-oldest; MHistory rows newest-first;
  enter opens as-sent preview tab; backspace removes.
Green: `tui/coll.oxl` + wiring in `app.oxl`/`types.oxl`/
`render.oxl` (sidebar rows w/ req names, env name row, response
tabs, auth/options read-only panes, response title meta) +
`main.oxl` (argv coll/env, `ESend` → painted "Sending…" frame →
`exec_send`). Replace S10 degrade branches; keep still-deferred
toasts per spec table.
Gate: `oxl test tui` + `oxl build ./tui` green; `cli` untouched —
run `oxl test cli` to prove no regression.

## S10.5 — Integration smoke + docs + matrix

- Build both binaries; run `oxl test` loop over every leaf dir.
- Manual tty smoke (documented in verify): launch against
  `tests/tui-fixtures/small-app` — browse tree, open request,
  switch env, send GET to a local `python3 -m http.server` (or
  httpbin when reachable), view body/headers/cookies/trace tabs,
  save a request, dup/delete it.
- Update `parity-matrix.md`: §5 → `done`, §6 → `done`/`partial`
  (env files+switching+substitution done; captures M4,
  environments.json S11), §7.1 → `done` (HTTPS included via
  verify field — note TLS works through existing H1 path).
- Findings list upstream candidates: real YAML port, fsnotify,
  async/cancel-able transport, clipboard, RFC6265 scoping.
- Commits: `feat(core): …`, `feat(tui): …` conventional slices
  per stage; no AI attribution; hook-gated subjects <100 chars.

## Risk notes

- oxl `[v,e]=f()` shadows in blocks; `mkslice(Qualified.Type)`
  broken — build `[]own YNode`/`[]YPair` via `push` on locally
  declared slices; own-returned nodes need `new(x)` boxing where
  fields take `own`.
- `os.readfile_` conflates missing/empty — `exists`-gate all
  reads; `ls` returns sorted names but we re-sort folders-first.
- Blocking send: `exec_send` runs on the UI thread — the painted
  "Sending…" frame is the only affordance; spec'd.
- `time.unix()` is seconds — isoTimestamp formatter needs
  civil-from-days; keep it small + unit-tested.
- JSON re-indent: `json.jparse` may reorder object keys? If so,
  spec deviation → check jget order-preservation first; fall
  back to verbatim body when parse fails or reorders.
- Fixture collection must avoid absolute paths — file bodies
  resolve vs `coll_dir` param, not CWD.
