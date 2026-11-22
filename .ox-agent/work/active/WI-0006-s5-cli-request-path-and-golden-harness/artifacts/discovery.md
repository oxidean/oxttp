# WI-0006 discovery — S5 CLI request path and golden harness

Scope (plan S5, deps S2/S3/S4): wire the S4 `Intent` through the S2
domain model into the S3 h1 transport, shape output per xh
semantics, and land the differential golden harness vs real xh.
Gate (plan): basic GET/POST/header/param rows diff-clean vs real xh.

Source-verified this stage against a fetched upstream tree
(xh @ 8b21cc07, matches corpus pin): `src/main.rs` run() L98–790,
`src/request_items.rs` L190–520, `src/printer.rs`, `src/formatting/
headers.rs`, `src/session.rs`, `src/auth.rs`, `src/netrc.rs`,
`src/download.rs`, `src/error_reporting.rs`, `src/utils.rs`, plus
live probes of the real `xh 0.26.3` musl binary against a local
server (this machine fetched the release tarball — CI cannot rely
on xh being installed; see harness note).

## Request construction (upstream main.rs run() order — VERIFIED)

1. `args.request_items.headers()` → (HeaderMap, headers_to_unset):
   items apply in order — HttpHeader/HttpHeaderFromFile `append`
   (duplicates kept: `A:1 A:2` → two lines); HttpHeaderFromFile
   trims the file contents; HttpHeaderToUnset `remove`s + records
   the name in the unset set. A later HttpHeader for the same name
   cancels the unset. `Cookie:` item value is sent verbatim
   (leading space after `:` preserved — `Cookie:  a=b` observed).
2. `url_with_query(url, query_items)` — UrlParam/UrlParamFromFile
   appended via `query_pairs_mut().append_pair` = form-urlencoded
   (space→`+`, `+`→`%2B`, `%`→`%25` observed `r==a%20b`→`r=a%2520b`).
   Only when non-empty (else no `?` added).
3. stdin: `use_stdin = !(ignore_stdin || stdin.is_terminal() ||
   test_pretend_term())`. When used: non-empty items →
   `Request body (from stdin) and request data (key=value) cannot
   be mixed. Pass --ignore-stdin to ignore standard input.`;
   multipart → `Cannot build a multipart request body from stdin`;
   --raw → `Request body from stdin and --raw cannot be mixed. Pass
   --ignore-stdin to ignore standard input.` Else `Body::Raw(
   read_to_end)` — **EMPTY stdin still counts as a Raw body**:
   `xh GET x </dev/null` sends `Content-Type: application/json`,
   `Accept: application/json, */*;q=0.5`, `Content-Length: 0`.
   oxl has no isatty (oxl#125) — probe verified `os.fullpath(
   "/dev/stdin")` resolves `/dev/pts/N` on a TTY, `/dev/null` or a
   real path otherwise, `""` on a pipe → heuristic substitute.
4. method = explicit or `body.pick_method()` (empty→GET else POST;
   `is_empty`: Json null, Form [], never Multipart/File/Raw — Raw("")
   still counts empty? — verified: `</dev/null` + explicit GET only;
   Body::Raw is_empty→false BUT pick_method applies to Body::Raw ""
   — upstream marks Raw non-empty → POST. WAIT, verified: `xh GET x
   </dev/null` sends method GET (explicit). `echo '' | xh x` → POST.
   Raw("") body → POST (is_empty only Json-null/Form-empty).
5. Builder headers in this exact order (observed on wire):
   `Accept-Encoding: gzip, deflate, br, zstd` (deviation: ours
   `gzip, deflate` — ADR 0017) · `User-Agent: xh/0.26.3` (ours:
   `oxttp/<ver>`) · `Connection: keep-alive` — ONLY when
   http-version ∈ {none,1.0,1.1} (ours `Connection: close` — ADR
   0019); http10/11 also force `reqwest::Version` — 1.0 emits
   `HTTP/1.0` request line. Then body-kind headers:
   - Json non-null: `Accept: application/json, */*;q=0.5` + CT json
     (`.json()` inserts CT after Accept — observed order).
   - Json null + explicit `--json` flag: same two headers, NO body
     (is_null → no `.json()` call; explicit --json adds CT too).
   - Json null + --json NOT explicit: NOTHING (bare GET → only
     client `Accept: */*`). `args.json` = flag-passed, not body_type.
   - Form: `.form()` → CT `application/x-www-form-urlencoded` only
     (no Accept — client `*/*` survives).
   - Multipart: `.multipart()` → CT `multipart/form-data;
       boundary=<random>` (reqwest boundary = random alphanumeric).
   - Raw: `--form`→CT urlencoded else Accept-json + CT-json; body
     verbatim bytes.
   - File (`@file` whole body): `;type=` > mime_guess > CT json;
     body file bytes. `;filename=` → warning `Ignoring ;filename=
     tag for single-file body. Consider --multipart.`
6. `--continue` resume: if headers contain Range → warning
   `--continue can't be used with a 'Range:' header. --continue
   will be disabled.` else `-o` file exists → `Range: bytes=<size>-`
   appended after body headers.
7. auth (session first, then `-a`/`--bearer`, then netrc):
   `Authorization: Basic base64(user:pass)` /
   `Bearer <token>` / digest untouched (challenge middleware).
   `-a u:p` splits FIRST colon (colons in pass OK); `-a u:` →
   password None (no prompt); `-a u` (no colon) → rpassword prompt
   `http: password for u@<host>: ` via /dev/tty.
8. `.headers(item_map)` — reqwest `replace_headers`: existing keys
   get values REPLACED at the key's original slot (user
   `Accept:text/x` occupies the default's position, no dup line);
   new names append at the end of builder headers.
9. `headers_to_unset` applied last — removes even fixed headers
   (`user-agent:` removes UA entirely).
10. Send-time synthesized (display + wire agree): client default
    `Accept: */*` appended iff accept absent; `Content-Length` iff
    body; `Host[:port]` LAST (port only when explicit in URL).
    Observed order ends `... Content-Length, Host`.
11. `--download` → `Accept-Encoding: identity` replaces the AE
    header (insert → same slot).
12. `-x/--compress`: body deflate; skipped w/ warning when a
    `Content-Encoding:` header present; skipped when output >=
    input unless `-xx`. Conflicts multipart (parse-level already).
13. Cookie jar (reqwest, always on): session cookies + `Cookie:`
    header (removed from header map into jar, session mode only);
    jar carries Set-Cookie across redirect hops.

## Body kinds from items (request_items.rs body_*)

- json (default): `key=v`→string field; `key=@f`→string from file
  contents; `key:=j`→Json literal (validated at parse); `key:=@f`→
  Json parsed from file. Fields insert via nested_json paths (S6 —
  this stage treats keys as flat root fields; nested `[a][b]` path
  support is S6 scope per plan — flag it in spec).
- form: `key=v`/`key=@f` → urlencoded `k=v&`; `:=` items → error
  `JSON values are not supported in Form fields`. `key@file` →
  auto-promotes to multipart.
- multipart: DataField text parts + FormFile file parts
  (`;type=`→part Content-Type, `;filename=`→Content-Disposition
  filename, else file basename); `:=` → `JSON values are not
  supported in multipart fields`.
- json+`key@file` → error `Can't use file fields in JSON mode
  (perhaps you meant --form?)`; bare `@file` → Body::File (CT:
  `;type=` > mime_guess > application/json); 2+ bare `@file` →
  `Can't read request from multiple files`; data items + bare
  `@file` → `Request body (from a file) and request data
  (key=value) cannot be mixed.`

## Response handling (run() tail + printer.rs — VERIFIED)

- print sets resolved in S4 (print_new/order: verbose>0→HhBb(+m
  if>1); quiet→∅; offline→HB; headers→h; **body||!is_terminal→b —
  checked BEFORE meta**, so `-m` alone prints body when piped;
  meta→m; else hb). Explicit `--print`/`-P` win.
- Request head print: `METHOD path[?query] HTTP/1.x\n` + headers +
  `\n`. Accept `*/*` or_inserted for display; jar cookies inserted;
  CL synthesized iff body known; `Host[:port]` appended last.
- Response head: `HTTP/x.y CODE reason\n` + headers + `\n`.
  reason = wire phrase when non-standard, else canonical, else
  `<unknown status code>` (utils::reason_phrase — canonical table
  needed).
- Header NAMES print Title-Cased for HTTP/1.x versions (hyper rule:
  upper first + after `-`). Applies to BOTH request and response
  display — `x-weird: v` → `X-Weird: v`.
- Header VALUES: ASCII print verbatim; else latin1 + ` (UTF-8: <t>)`
  annotation when also valid UTF-8 (terminal sanitize only).
- Request body print: verbatim (pretty=none→no JSON reformat) +
  `\n\n` (breathing room). NUL byte → BINARY_SUPPRESSOR even
  non-TTY.
- Response body print (non-TTY, pretty=none): VERBATIM bytes, no
  trailing newline. Color/format branches unreachable w/o TTY —
  pretty/style/format-options/response-charset/response-mime are
  display-inert this build (charset affects decode only when
  formatting; `--stream` auto-activates only for event-stream
  content type — also inert when piped).
- Separator `\n` between body and meta only when both printed.
- Meta: `Elapsed time: %.5fs\n` + `Remote address: <ip:port>\n` +
  `\n`. Elapsed = request+body durations.
- --all intermediates print per `--history-print` (default = print
  set) in hop order: per hop pair → prev resp (h, b+sep, m) then
  next req (H, B). **S3 transport doesn't expose hops → model.Resp
  needs a history field (or Hop list) — spec decision.**
- --offline: build request, print HB, exit 0 (CL synthesized from
  buffered body; file bodies → no CL).
- --download: AE→identity; dest = `-o` file (truncate, or append on
  resume) else stdout when piped (dest label `<stdout>`; filename
  from Content-Disposition>URL>index only when TTY — never here);
  response headers + progress go to STDERR: `Downloading <bytes>
  to "<dest>"` / `Downloading to "<dest>"`, then `Done. <bytes> in
  %.5fs (<rate>/s)`; quiet≥1 hides progress. Incomplete body →
  `Interrupted...` + `Incomplete download: size=..; downloaded=..`
  exit 1. `--continue`: Range sent; non-206 → resume dropped; 416 →
  `Download <o> is already complete` exit 0.
- -o FILE (no -d): whole print-set output → file; stderr unaffected.
- check-status effective (S4: explicit, else download, else
  !compat): 3xx && !follow → exit 3; 416+resume → complete msg;
  4xx → 4; 5xx → 5. Warning `HTTP <code> <reason>` on stderr when
  `failure && (is_output_redirected || !print.response_headers)` —
  is_redirect true = stdout piped (us), false for -o/-d.
- --quiet: `-q` warnings still print, `-qq` suppresses them;
  `<prog>: error:` lines are anyhow/eprintln — never suppressed.
- Session (session.rs): load → merge session headers FIRST (items
  headers then extend/override — session headers occupy earlier
  positions... verified below), auth from file, cookies → jar,
  `Cookie:` item header → removed into jar; `save_headers` persists
  merged request headers MINUS cookie/content-*/if-*; persist
  pretty-JSON `{__meta__:{about:"xh session file",xh:"0.26.3"},
  auth:{type,raw_auth},cookies:[{name,value,expires?,path,secure?,
  domain?}],headers:[{name,value}]}` 4-indent + trailing \n.
  Session name w/o path sep → `<config>/sessions/<host>[_port]/
  <name>.json` (path_from_url: "." ".." missing → `couldn't extract
  host from url`). HTTPie-format sessions migrate (headers/cookies
  maps→lists). Persist unless read_only AND file exists.
- netrc: `$NETRC` else `~/.netrc` then `~/_netrc`; entries
  `machine <h> login <l> password <p>`; `default` entry fallback
  (suppressed once a machine entry seen); `account` = login
  fallback; `#` comments, `macdef` skipped to blank line;
  incomplete entries ignored. Used only when no `-a`/`--bearer`/
  session auth, and not saved to session.
- Digest: `-A digest` sends request unauthenticated; on
  401+WWW-Authenticate → digest_auth middleware computes
  Authorization (MD5 in std). Complex — candidate for recorded
  degradation this stage.

## Exit codes (error_reporting.rs + run() — VERIFIED live)

0 ok · 1 app error (`<prog>: error: <msg>` — anyhow Debug adds
`\n\nCaused by:\n    <cause>` when context chained, e.g. session
load failures) · 2 clap diag AND request TIMEOUT (reqwest
is_timeout) · 3/4/5 check-status · 6 TooManyRedirects →
`Too many redirects (--max-redirects=N)` (observed). Transport
errors surface as `{prog}: error: <display>` — our h1 errs carry
`http: ` prefix; cli strips it for display (fixture diff).

## Golden harness design space (ADR 0007)

- xh 0.26.3 musl tarball fetched to /tmp this session — author-time
  fixture generation works HERE, but CI has no xh. Decide:
  committed fixtures (`.stdout/.stderr/.exit` per case, generated
  by `scripts/` runner against a local scripted server — the
  core/http `Fx` pattern) replayed by an `oxl test` harness vs
  `execute()`-level invocation of the SAME argv+stdin+env. Live-diff
  mode (`OXTPP_XH=/path/xh`) as a bonus.
- `oxl test` runs `fn test_*` inside package dirs; `oxl build` only
  emits binaries for package-main dirs and there is no os.exec in
  std → harness can't spawn the binary; it drives
  `resolve()+execute(intent, envpairs, stdin_bytes)` in-process —
  argv→Intent is already S4-gated, so the seam is honest.
- Normalization needed both sides: `xh`→`oxttp` prog name, UA
  `xh/0.26.3`→`oxttp/<ver>`, AE `br, zstd` tail, `Connection:
  keep-alive`→`close`, elapsed/remote/date values, multipart
  boundary, fixture `Server:`/`Date:` headers (ours controls).
- Volatile-free corpus surface to cover: methods/eff-POST,
  items→{headers dup/unset/empty/file, query merge+encoding, json
  body, form body, multipart, @file body, raw}, stdin
  mix/empty/pipe, --offline, --print combos/-v/-h/-b/-m/-q, pretty
  none output bytes, exit codes {0,1,2,3,4,5,6}, redirects
  {follow,--all,history-print,method rewrite,cross-origin strip},
  check-status warning, auth basic/bearer/netrc, session
  create/reuse/RO, -o, -d/-c, timeout (sleep fixture),
  header-value latin1/UTF-8 annotate (defer — terminal-only
  annotate; latin1 print IS non-tty → include), binary suppressor
  (request only), HEAD/204/no-CL-eof bodies, gzip/deflate decode.

## oxl v0.15.0 notes (verified this stage)

- `os.fullpath("/dev/stdin")` → `/dev/pts/N` (TTY) / `/dev/null` /
  real path / `""` (pipe) — stdin-is-tty heuristic works.
- `os.File.write` must be called on a bound variable
  (`f := os.stdout(); f.write(b)` — method calls need ref receiver
  on a place, not a temporary).
- md5/sha256/hmac exist in std/crypto (digest viable).
- No os.exec/process spawn — golden harness must call execute()
  in-process inside `oxl test` (package-main test dir or a library
  dir — golden runner is importable either way; keep harness in a
  leaf dir so the dir-loop runs it).
- str is a byte string; response bodies can ride in `str` — but
  assemble print output as `[]byte` for cleanliness.

## Prior decisions cited (not re-litigated)

- 0006 explicit degradation (digest/--curl/--generate/proxy-ish
  surfaces degrade loudly); 0007 differential verification (this
  WI lands the harness); 0014 cli owns post-clap semantics;
  0015 deferral routing (S5 replaces the code-1 tail for covered
  paths); 0016 core layout (session/netrc live where? — session
  model exists in core/session, file IO is cli's per S4 spec);
  0017 AE advertises decodable only; 0018 wire encoding in
  transport; 0019 single-shot Connection: close.

## Stage-level open questions (resolve at spec/plan)

- History hops for --all: extend model.Resp (field + Hop struct) vs
  cli-side reimplementation — spec decides (model extension keeps
  transport self-contained; interface stays `send`).
- Digest auth: implement (md5 exists) vs degrade — cost decision
  at plan; degrade is the S7 fallback per stage scope.
- Sessions: cookie jar across redirects (reqwest-faithful) vs
  minimal jar (name match, no path/domain/expires logic) —
  jar-lite + deviation note.
- stdin TTY heuristic (fullpath) vs ignore-stdin-only — heuristic
  verified; spec it as documented approximation.
- --compress: zlib exists; cheap — include or defer at plan.
- --curl translation: defer (large; S7) — keep degrading.
- Nested-JSON key paths: S6 owns; S5 treats `key` literally —
  deviation vs upstream only for `[`/`]` keys.
