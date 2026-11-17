# WI-0005 spec — S4 CLI flag surface

Upstream: WI-0001 plan S4 + spec; ADRs 0004, 0006, 0011, 0012, 0013,
0014. Corpus: `docs/corpus/corpus-xh.md` §1–4, 7, 8 — every behavior
below cites it; source-verified flow in
`context/references/xh-cli-parse-flow.md` (cli.rs/request_items.rs @
8b21cc0).

## Intent

`cli/` (module `github.com/oxidean/oxttp/cli`, `package main`) wires
the COMPLETE xh argv surface: the 58-row option table on
`shared/args`, both positional slots, all cli-side semantics of
upstream `try_parse_from` (method/URL, items via `core/item`,
bin-name detection, process_relations, corpus value parsers,
construct_url), parse-level env wiring, and xh-shaped
diagnostics/exit codes. Request execution is deferred (S5+): a fully
valid parse ends in the degradation contract's explicit error.

Non-goals: any socket/file-request IO, request/response printing,
`--curl`/`--offline`/`--generate` outputs (parse + degrade only),
sessions IO, netrc reading.

## Files

- `cli/spec.oxl` — `fn spec(prog: str) -> own args.Spec`: the table
  below in listed order + `pos` slots + nothing else.
- `cli/sem.oxl` — pure semantic pass: `Intent` struct, method/URL,
  relations, value validators, `construct_url`, `guess_pretty`, and
  `fn resolve(m: own args.Matches, envpairs: []str) -> own Out`.
- `cli/cfg.oxl` — env lookups over `envpairs` (`NAME=value` list):
  `config_dir`, `default_options` (parse + warning text), proxy-env
  capture, compat detection, `bin_name(argv0)`.
- `cli/main.oxl` — `main()`: os glue only — argv0/bin name, env pair
  list, config prepend, `args.parse`, dispatch on Out, writes to
  stdout/stderr, `os.quit(code)`.
- `cli/spec_test.oxl`, `cli/sem_test.oxl`, `cli/cfg_test.oxl` — the
  gate matrix (package main tests; `oxl test ./cli` verified).

`Out` is the semantic result: `{ code: int, stdout: str, stderr: str,
intent: own Intent }` — code 0 = print stdout; 2 = print stderr
(clap-shaped diag); 1 = print stderr (app error); a code-1 variant
with `intent` filled signals "would execute" — S4 always ends in a
deferral so v0.1 never returns it, but the field is the S5 seam.

## The table (58 options — corpus §4, upstream struct order)

`flag`=KFLAG `count`=KCOUNT `str`=KSTR `uint`=KUINT `enum`=KENUM;
attrs: **H**idden, **R**epeat, **E**nv, plus named relations.
`--no-*` synthesized for every row (engine default). Order below is
declaration order AND upstream struct order.

1. `json` `-j` flag — overrides `form,multipart`. Help: "(default)
   Serialize data items from the command line as a JSON object."
2. `form` `-f` flag — overrides `json,multipart`. "Serialize data
   items from the command line as form fields."
3. `multipart` flag — overrides `json,form`; conflicts
   `raw,compress`. "Like --form, but force a multipart/form-data
   request even without files."
4. `raw` str `RAW`. "Pass raw request data without extra processing."
5. `pretty` enum `STYLE` vals `all,colors,format,none`. "Controls
   output processing."
6. `format-options` str `FORMAT_OPTIONS` **R**. "Set output
   formatting options."
7. `style` `-s` enum `THEME` vals `auto,solarized,monokai,fruity`.
   "Output coloring style."
8. `response-charset` str `ENCODING`. "Override the response
   encoding for terminal display purposes."
9. `response-mime` str `MIME_TYPE`. "Override the response mime type
   for coloring and formatting for the terminal."
10. `print` `-p` str `FORMAT`. "String specifying what the output
    should contain"
11. `headers` `-h` flag. "Print only the response headers. Shortcut
    for --print=h."
12. `body` `-b` flag. "Print only the response body. Shortcut for
    --print=b."
13. `meta` `-m` flag. "Print only the response metadata. Shortcut
    for --print=m."
14. `verbose` `-v` count. "Print the whole request as well as the
    response."
15. `debug` flag. "Print full error stack traces and debug log
    messages."
16. `all` flag. "Show any intermediary requests/responses while
    following redirects with --follow."
17. `history-print` `-P` str `FORMAT`. "The same as --print but
    applies only to intermediary requests/responses."
18. `quiet` `-q` count. "Do not print to stdout or stderr."
19. `stream` `-S` flag. "Always stream the response body."
20. `compress` `-x` count. "Content compressed (encoded) with
    Deflate algorithm."
21. `output` `-o` str `FILE`. "Save output to FILE instead of
    stdout."
22. `download` `-d` flag. "Download the body to a file instead of
    printing it."
23. `continue` `-c` flag — requires `download,output`. "Resume an
    interrupted download. Requires --download and --output."
24. `session` str `FILE`. "Create, or reuse and update a session."
25. `session-read-only` str `FILE` — conflicts `session`. "Create or
    read a session without updating it from the request/response
    exchange."
26. `auth-type` `-A` enum vals `basic,bearer,digest`. "Specify the
    auth mechanism."
27. `auth` `-a` str `USER[:PASS] | TOKEN`. "Authenticate as USER
    with PASS (-A basic|digest) or with TOKEN (-A bearer)."
28. `bearer` str `TOKEN` **H**. "Authenticate with a bearer token."
29. `ignore-netrc` flag. "Do not use credentials from .netrc"
30. `unstable-m-sig-id` str `KEY_ID` **H** — requires
    `unstable-m-sig-key`. "Message signature key identifier (RFC
    9421)."
31. `unstable-m-sig-key` str `KEY` **H** — requires
    `unstable-m-sig-id`. "Message signature key material (RFC
    9421)."
32. `unstable-m-sig-alg` enum `ALG` **H** vals
    `hmac-sha256,ed25519,ecdsa-p256-sha256,ecdsa-p384-sha384,
    rsa-v1_5-sha256,rsa-pss-sha512` — requires `unstable-m-sig-key`.
    "Message signature algorithm (RFC 9421)."
33. `unstable-m-sig-comp` str `COMPONENTS` **H** **R**.
    "Comma-separated list of message signature components (RFC
    9421)."
34. `offline` flag. "Construct HTTP requests without sending them
    anywhere."
35. `check-status` flag. "(default) Exit with an error status code
    if the server replies with an error."
36. `follow` `-F` flag. "Do follow redirects."
37. `max-redirects` uint `NUM`. "Number of redirects to follow.
    Only respected if --follow is used."
38. `timeout` str `SEC` (NOT KFLOAT — corpus messages). "Connection
    timeout of the request."
39. `proxy` str `PROTOCOL:URL` **R**. "Use a proxy for a protocol.
    For example: --proxy https:http://proxy.host:8080."
40. `verify` str `VERIFY` **E** `REQUESTS_CA_BUNDLE,CURL_CA_BUNDLE`.
    "If \"no\", skip SSL verification. If a file path, use it as a
    CA bundle."
41. `cert` str `FILE`. "Use a client side certificate for SSL."
42. `cert-key` str `FILE`. "A private key file to use with --cert."
43. `ssl` enum `VERSION` vals `auto,tls1,tls1.1,tls1.2,tls1.3`
    alias `ssl2.3`→`auto`. "Force a particular TLS version."
44. `native-tls` flag **H**. "Use the system TLS library instead of
    rustls (if enabled at compile time)."
45. `default-scheme` str `SCHEME` **H**. "The default scheme to use
    if not specified in the URL."
46. `https` flag. "Make HTTPS requests if not specified in the URL."
47. `http-version` enum `VERSION` vals
    `1.0,1.1,2,2-prior-knowledge,3-prior-knowledge` alias `1`→`1.0`.
    "HTTP version to use"
48. `resolve` str `HOST:ADDRESS` **R**. "Override DNS resolution for
    specific domain to a custom IP."
49. `interface` str `NAME`. "Bind to a network interface or local
    IP address."
50. `ipv4` `-4` flag. "Resolve hostname to ipv4 addresses only."
51. `ipv6` `-6` flag. "Resolve hostname to ipv6 addresses only."
52. `unix-socket` str `FILE`. "Connect using a Unix domain socket."
53. `ignore-stdin` `-I` flag. "Do not attempt to read stdin."
54. `curl` flag. "Print a translation to a curl command."
55. `curl-long` flag. "Use the long versions of curl's flags."
56. `generate` enum `KIND` vals `complete-bash,complete-elvish,
    complete-fish,complete-nushell,complete-powershell,complete-zsh,
    man,man-markdown` — conflicts `murl`. "Generate shell
    completions or man pages."
57. `help` flag — action AHELP_SHORT. "Print help."
58. `version` `-V` flag — action AVERSION. "Print version."

Hidden total = 7 (nos. 28, 30–33, 44, 45) → 51 visible rows.

Positionals (upstream's exact two):
- `murl` metavar `<[METHOD] URL>` required, help "The request URL,
  preceded by an optional HTTP method."
- `rest` metavar `[REQUEST_ITEM]...` variadic, help "Optional
  key-value pairs to be included in the request."

`newspec(prog, version.get(), about)` — prog = bin_name (see below);
about = "oxttp is a friendly and fast tool for sending HTTP
requests." Spec `extra` stays EMPTY — main renders the per-mode
trailer itself (engine appends `extra` to both help modes; upstream
uses different after_help/after_long_help text):
- short (`--help`): `Each option can be reset with a --no-OPTION
  argument.` + blank + `Run "<prog> help" for more complete
  documentation.`
- long (`help` literal): `Each option can be reset with a --no-
  OPTION argument.`

## Semantics (cli-side, mirrors try_parse_from order — corpus §1–2)

`bin_name(argv0)`: basename (strip through last `/` or `\`), then
strip extension at FIRST `.` (upstream `split('.').next()` —
`xhs.exe`→`xhs`); empty → `oxttp`. `https|xhs|xhttps` → https=true;
`http|https` OR `XH_HTTPIE_COMPAT_MODE` present → compat=true.

`resolve(m, envpairs)` order (upstream: value parsers run during
tokenize, requires/conflicts at match end, then the positional
semantic pass):
1. `m.act` handled by caller first (help_short/version) — resolve
   only sees act=="".
2. Value checks, TABLE order, each recorded occurrence (dead
   occurrences validate too — upstream validates at token time;
   iterate `m.svals` per option, first failure wins; see messages
   below): timeout → print → history-print → format-options →
   proxy → resolve → response-charset → m-sig-comp (infallible
   normalize) → verify (infallible canon: `no|false`→`no`,
   `yes|true`→`yes` lowercased, else path).
3. If `generate` present → deferral `{prog}: error: --generate is
   unsupported in this build` (code 1; upstream returns before
   positional checks).
4. `pos0 == "help"` → Out{code:0, sout: long help + long trailer}.
5. Method: pos0 non-empty AND all bytes ASCII alpha → method =
   upper(pos0), URL = pos1 else Missing-URL error; else URL = pos0,
   items = pos[1..]. Missing URL → exit-2 diag
   `error: Missing <URL>` + usage + footer.
6. Each item arg → `item.parse`; on err → exit-2 diag
   `error: <err.msg>` + usage + footer.
7. Apply bin_name https/compat (env read from envpairs).
8. Relations (upstream process_relations): verbose>0 → all=1;
   curl_long → curl=1; https → default_scheme="https"; bearer →
   auth_type=bearer + auth=bearer-val; check_status/stream =
   engine `state()` tri; download → follow=1 + check_status=1;
   body_type = multipart if present else form else json (default);
   `--raw` present && (body_type==multipart || any item is
   DataField/DataFieldFromFile/JsonField/JsonFieldFromFile/FormFile)
   → exit-2 diag `Request body (from --raw) and request data
   (key=value) cannot be mixed.`; session_read_only → session +
   session_ro=1.
9. `construct_url` → `Invalid <URL>: <e>` exit-2 diag on failure.
10. Deferral routing (all `{prog}: error: <msg>`, code 1):
    a. any m-sig option present → `{prog}: error: This binary was
       built without message signature support. Enable the
       `http-message-signatures` feature.`
    b. http-version == `3-prior-knowledge` → `{prog}: error: This
       binary was built without support for HTTP/3. Enable the
       `http3` feature.`
    c. constructed URL scheme != `http` → `{prog}: error: <scheme>
       URLs are unsupported in this build (only http:// is
       supported)`
    d. else → `{prog}: error: request execution is unsupported in
       this build`

Effective check_status = state==1 → on; ==-1 → off; ==0 →
!compat (corpus: `unwrap_or(!httpie_compat_mode)`; download forces
on). Effective method = explicit method else `POST` when body
non-empty (multipart counts non-empty) else `GET`. Effective
max-redirects = value else 10 when follow. Resolved print set
(Print::new, is_terminal=false — no isatty, deviation): verbose>0 →
H,B,h,B(,m if >1); quiet>0 → none; offline → H,B; headers → h;
body || !tty → b; meta → m; else h,b. `--print`/`--history-print`
explicit values win over the computed set (upstream: explicit print
disables verbose-implied default; history-print defaults to print).

`guess_pretty(is_tty, envpairs)` (buffer.rs::guess_pretty): non-tty
→ `none` unconditionally; tty → NO_COLOR set-nonempty OR
TERM=="dumb" → `format`, TERM set-other → `all`, TERM unset →
`format`. v0.1 calls it with is_tty=0 (no isatty — oxl#125), so it
always yields `none` today; the parameter keeps the tty arm for S5.

## Value-parser checks (exit-2, `invalid value` wrapper)

Each emits `error: invalid value '<v>' for '--<name> <<META>>':
<detail>` + usage + footer — same shape as engine `check()` output
so diagnostics are indistinguishable.

- `timeout <SEC>`: value parses as f64 (else `Connection timeout is
  not a valid number`); NaN same; negative → `Connection timeout
  is negative`; >= 18446744073709551615.0 (u64::MAX secs) or inf →
  `Connection timeout is too big`.
- `print <FORMAT>` / `history-print <FORMAT>`: every char ∈
  {H,B,h,b,m}; first bad char c → `'<c>' is not a valid value`.
- `format-options <FORMAT_OPTIONS>`: lowercase the string, split
  on `,`; each element needs `:` — else `Format options consist of
  a key and a value, separated by a ":".`; key ∈ json.indent,
  json.format, xml.indent, xml.format, headers.sort;
  `json.sort_keys` → `Unsupported option 'json.sort_keys'`; other
  key → `Unknown option '<key>'`; indent values parse as u64,
  format/sort as strict `true|false` — else
  `Invalid value '<v>' in '<elem>'`.
- `proxy <PROTOCOL:URL>` (each occurrence): split on FIRST `:`;
  no `:` → `The value passed to --proxy should be formatted as
  <PROTOCOL>:<PROXY_URL>`; lowercased protocol ∉ {http,https,all} →
  `Unknown protocol to set a proxy for: <proto>`; remainder must
  contain `://` (absolute URL approximation) → else `Invalid proxy
  URL '<u>' for protocol '<p>': relative URL without a base`.
- `resolve <HOST:ADDRESS>` (each occurrence): exactly 2 `:` →
  `Value should be formatted as <HOST>:<ADDRESS> (not
  <HOST>:<PORT>:<ADDRESS>)`; no `:` → `Value should be formatted as
  <HOST>:<ADDRESS>`; address: `[...]` → inner IPv6 check, else
  IPv4/IPv6 literal check → fail → `Invalid address '<addr>'`.
- `response-charset <ENCODING>`: normalize = lowercase + drop chars
  not in [a-z0-9_\-:]; `u8`|`utf` → UTF-8 ok; `u16` → UTF-16LE ok;
  else try normalized, minus `-`/`_`, `_`→`-`, `-`→`_`, and
  digit-split (`gb2312`→`gb-2312`) forms against the WHATWG label
  set (data table `enc_labels` in spec.oxl — the full
  encodings.json label list); none match → `<normalized> is not a
  supported encoding, please refer to
  https://encoding.spec.whatwg.org/#names-and-labels for supported
  encodings`.
- `unstable-m-sig-comp <COMPONENTS>` (each occurrence): split `,`,
  trim each, lowercase up to first `;`, keep `;params` — stores
  normalized value, never fails.
- `verify <VERIFY>`: lowercase `no|false`→`no`; `yes|true`→`yes`;
  else CA-bundle path — never fails.

## Env vars (corpus §7 — all 14 covered)

Parse-level (this stage reads): `XH_CONFIG_DIR` (config_dir),
`XH_HTTPIE_COMPAT_MODE` (compat), `REQUESTS_CA_BUNDLE`,
`CURL_CA_BUNDLE` (verify env via engine), `NO_COLOR`, `TERM`
(guess_pretty), `ALL_PROXY`, `HTTP_PROXY`, `HTTPS_PROXY`,
`NO_PROXY` (captured into Intent when no `--proxy`). Execution-side
(documented, read at S5+): `NETRC`, `RUST_LOG`, `RUST_BACKTRACE`,
`SOURCE_DATE_EPOCH`.

`config_dir(envpairs)`: `XH_CONFIG_DIR` set → it; else
`$HOME/.config/xh` (HOME unset → `$HOME` literal empty → skip
config); macOS legacy branch needs OS detection — deferred
(documented; we run Linux/WSL).

`default_options`: read `<config_dir>/config.json`; absent →
none; unreadable → warn `\n<prog>: warning: Unable to read config
file: <e>\n`; jparse fails OR `default_options` missing/not-array/
non-string member → `\n<prog>: warning: Unable to parse config
file: <e>\n`; else prepend tokens between argv0 and argv.

## Diagnostics contract (exit codes — corpus §8)

- Engine/clap-shaped: `error: <msg>` [+ tip line] + `\n\n` +
  `Usage: <prog> [OPTIONS] <[METHOD] URL> [REQUEST_ITEM]...` +
  `\n\nFor more information, try '--help'.\n` → stderr, exit 2.
- `--help` → short help + short trailer → stdout, exit 0.
- `help` positional → long help + long trailer → stdout, exit 0.
- `-V/--version` → `oxttp 0.1.0-dev\n-native-tls -rustls -http3
  -http-message-signatures -network-interface` → stdout, exit 0
  (upstream appends the ±feature string; ours is honest about the
  v0.1 build).
- Deferrals/warnings: `{prog}: error: <msg>` exit 1;
  `{prog}: warning: <msg>` to stderr (config warnings carry their
  corpus newlines).

## Test matrix (the S4 gate)

`cli/spec_test.oxl` — table conformance:
- exactly 58 option rows; per-name presence loop over the corpus
  name list; 51 visible / 7 hidden (hidden parses, absent from help).
- usage_line exact string; help(0) contains every visible long +
  short form and all metavars; help(1) contains possible-values,
  aliases, env suffixes; `bearer`/m-sig/`default-scheme`/
  `native-tls` absent.
- every flag parses: per-option argv sweep asserting ok/present
  incl. every short, every enum value + alias, repeats,
  `--x=v`/`--x v`/`short=v`/`shortv` forms.
- negation per kind (incl. `--no-help`, `--no-version`,
  `--no-proxy` list clear, tri-states); radio trio cycles;
  counts (-vv/-qq/-xx); conflicts (4 pairs); requires (continue,
  m-sig id↔key, alg→key); env fallback order + argv-beats-env +
  negated-blocks-env; `--` separator; missing-value message;
  unknown-arg + tip; `--generate` positional conflict;
  missing required positional.
- `--version`/`--help` actions + `-V`.

`cli/sem_test.oxl` — semantic pass:
- method/URL: alpha → upper method + rest[0] URL; `localhost` →
  Missing <URL>; non-alpha → URL; `help` → long help; generate
  short-circuits.
- items: each corpus form parses; `badword` → Invalid value diag;
  `k:=`+bad json → invalid.
- relations: verbose→all, -vv→meta, curl-long→curl, bearer→
  auth_type+auth, https→default_scheme, download→follow+check,
  tri-states, raw+body conflict (raw+data, raw+multipart-no-items,
  raw+header-only ok), session-ro→session.
- value checks: timeout {-1, abc, NaN, 1e30}; print `x`;
  format-options {missing-colon, unknown, json.sort_keys, bad
  bool, bad int, merge}; proxy {no-colon, bad proto, no-scheme
  URL, good}; resolve {2-colon, no-colon, bad IP, good v4/v6
  bare+bracketed}; charset {utf8, latin1, bogus}; m-sig-comp
  normalization; verify {no,YES,path}.
- construct_url: `:` `:3000` `:/p` `://x` `example.org`
  `http://x` `https://x` + --default-scheme/--https/bin-name-https
  interactions; empty-host failure.
- deferral routing: generic request, generate, m-sig pair,
  http-version=3-prior-knowledge, https URL — each pins message +
  code 1.
- effective getters: check_status ×{flag,-no-,compat}, method
  pick (json-item→POST, headers-only→GET, multipart→POST),
  max-redirects default-under-follow, print set precedence.
- env: compat var (non-empty), proxy capture + --proxy-disables,
  guess_pretty matrix.

`cli/cfg_test.oxl` — bin_name cases (xhs.exe→xhs→https; http→
compat; oxttp default); config_dir precedence; default_options
{absent, unreadable→warn, bad json→warn, non-array→warn, valid→
prepend, prepend order before real argv}.

Main-level smoke (verified by hand before ship — `oxl build ./cli`
then run): `--help`, `help`, `-V`, missing positional, unknown
flag, `--generate=man`, a plain request → deferral error exit 1.

## Corpus coverage (this stage)

§1 invocation model: override-self, --no-*, help literal, bin-name
detection, default_options — FULL. §2 positionals + method +
construct_url — FULL. §3 items — consumed from core/item (S2 gate).
§4 all 58 flags incl. kinds/defaults/env/conflicts/requires/
overrides/hidden/aliases/repeats — FULL. §4.8 --no-* — FULL.
§7 env vars — all 14 (6 parse-level + 4 proxy-capture + 4
documented-deferred). §8 exit codes 0/1/2 + error/warning shapes —
FULL for the parse surface (3–6 land with execution).

## Deviations (recorded, corpus-checked)

- Post-loop value checks run in table order (clap validates at argv
  position); two racing invalid values may resolve differently.
  Engine `requires`/`conflicts`/`required-positional` checks also
  precede cli value checks (upstream: value errors during tokenize).
- `XH_HTTPIE_COMPAT_MODE=""` (set-empty) undetectable via os.getenv
  — treated unset.
- `--no-verify` blocks the CA-bundle env fallback; upstream applies
  env whenever verify resolves unset (includes post-negation).
- isatty absent (oxl#125): guess_pretty TTY branch unreachable →
  non-tty answer `none`/`format` per env; Print::new is_terminal
  fixed false.
- `:=` JSON errors carry `Invalid value for '[REQUEST_ITEM]...':
  "<raw>"` without upstream's appended serde detail (S2 shipped
  shape).
- `--response-charset` label table is the static WHATWG set, not
  encoding_rs's runtime map — equivalent set, frozen.
- Long help omits upstream's full REQUEST_ITEM doc block and
  per-flag long_help paragraphs (engine renders one help string per
  arg); short help matches.
- `--proxy` URL validity approximated by `://` presence; upstream's
  reqwest Url check is stricter.
- `--version` prints our version + build-feature string rather
  than xh's `0.26.3`/`XH_FEATURES`.
