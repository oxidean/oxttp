# WI-0005 discovery — S4 CLI flag surface

Scope (plan S4, deps S1): all 58 corpus flags declared in the option
table; `METHOD URL [REQUEST_ITEM…]` positionals; `--help`/usage shape;
every flag parses and validates (execution unwired). Gate: `--help`
covers all 58; parse conformance vs corpus table.

## Corpus surface (docs/corpus/corpus-xh.md §1–4, 7–8; source-verified
## against xh src/cli.rs + request_items.rs @ 8b21cc0)

### Flag inventory — 58 total (51 visible + 7 hidden)

- bool: `json/j form/f multipart offline check-status follow/F
  download/d continue/c ignore-netrc https native-tls ipv4/4 ipv6/6
  ignore-stdin/I curl curl-long debug all headers/h body/b meta/m
  stream/S help` — and `version/V` (clap auto version action).
- count: `verbose/v`, `quiet/q`, `compress/x` (all ArgAction::Count;
  compress conflicts multipart).
- string: `raw/RAW output/o/FILE session/FILE session-read-only/FILE
  auth/a/'USER[:PASS] | TOKEN' bearer/TOKEN(hidden) cert/FILE
  cert-key/FILE default-scheme/SCHEME(hidden) interface/NAME
  unix-socket/FILE timeout/SEC` (Timeout is a FromStr value parser —
  needs KSTR + app-side validation for corpus error texts).
- enum: `pretty/STYLE(all,colors,format,none)
  style/s/THEME(auto,solarized,monokai,fruity)
  auth-type/A(basic,bearer,digest)
  ssl/VERSION(auto,tls1,tls1.1,tls1.2,tls1.3 alias ssl2.3→auto)
  http-version/VERSION(1.0,1.1,2,2-prior-knowledge,3-prior-knowledge
  alias 1→1.0)
  generate/KIND(complete-bash,complete-elvish,complete-fish,
  complete-nushell,complete-powershell,complete-zsh,man,man-markdown —
  conflicts positional)
  unstable-m-sig-alg/ALG(hmac-sha256,ed25519,ecdsa-p256-sha256,
  ecdsa-p384-sha384,rsa-v1_5-sha256,rsa-pss-sha512; hidden)`.
- int (usize): `max-redirects/NUM` (KUINT — no clap default; 10 applies
  only at use time when follow).
- repeat+validated (KSTR repeat, app-side value checks):
  `proxy/PROTOCOL:URL`, `resolve/HOST:ADDRESS`,
  `format-options/FORMAT_OPTIONS`, `unstable-m-sig-comp/COMPONENTS`
  (hidden).
- more KSTR: `print/p/FORMAT`, `history-print/P/FORMAT`,
  `response-charset/ENCODING`, `response-mime/MIME_TYPE`,
  `unstable-m-sig-id/KEY_ID` (hidden), `unstable-m-sig-key/KEY`
  (hidden).
- hidden = 7: bearer, native-tls (build lacks both TLS backends),
  default-scheme, unstable-m-sig-{id,key,alg,comp}.
- `--no-<long>` synthesized for every option incl. help/version
  (engine `nono` default; corpus §4.8 — overrides_with last-wins).

### Relations (clap-declared → engine attrs)

- `multipart` conflicts `raw`,`compress`; overrides `json`,`form`.
- `json` overrides `form`,`multipart`; `form` overrides `json`,`multipart`.
- `session-read-only` conflicts `session`.
- `continue` requires `download` + `output`.
- `generate` conflicts `raw_method_or_url` (our `murl` slot).
- m-sig: id↔key mutual `requires`; alg requires key. All hidden —
  parse anyway (upstream: hard error only in run()).

### Positional + post-parse flow (try_parse_from order — VERIFIED)

Two positional slots only: `raw_method_or_url` (required,
`<[METHOD] URL>`) and `raw_rest_args: Vec<String>` (variadic,
`[REQUEST_ITEM]...`). There is NO separate URL slot — after method
detection the first rest arg becomes the URL.

1. clap tokenize + value validation (exit-2 errors).
2. `--generate` → return early (positional skipped by conflict).
3. `raw_method_or_url == "help"` → print LONG help, exit 0.
4. `parse_method`: first positional all-ASCII-alpha & non-empty →
   method (uppercased); then rest[0] = URL else
   `error: Missing <URL>` (MissingRequiredArgument, exit 2).
5. Each remaining rest arg → `RequestItem::from_str` →
   `Invalid value for '[REQUEST_ITEM]...': "<raw>"` (+ serde err for
   `:=`) — clap InvalidValue, exit 2.
6. bin_name = argv0 basename minus `.ext`: `https|xhs|xhttps` →
   https=true; `http|https` or `XH_HTTPIE_COMPAT_MODE` set →
   httpie_compat_mode=true.
7. `process_relations`: verbose>0→all; curl_long→curl; https→
   default_scheme="https"; bearer→auth_type=bearer+auth=bearer;
   check_status/stream tri-states via no-* flags; download→
   follow+check_status=Some(true); body_type=json|form|multipart;
   `--raw` + non-empty body (body items or multipart) → ValueValidation
   error "Request body (from --raw) and request data (key=value)
   cannot be mixed."; session_read_only→session (read-only flag).
8. `construct_url` → ValueValidation `Invalid <URL>: <err>` exit 2:
   default scheme "http://" (or --default-scheme/https);
   `://rest`→default_scheme+rest; `:`→"localhost"+rest;
   no `[a-zA-Z0-9]://.+` match → prepend default scheme.
9. check_status effective default = `!httpie_compat_mode`.

### Parse-time value parsers beyond engine kinds (exit-2 messages pinned)

- `--timeout`: NaN/garbage → `Connection timeout is not a valid
  number`; negative → `... is negative`; >=u64::MAX secs or inf →
  `... is too big`. Clap wraps as `invalid value '<v>' for '--timeout
  <SEC>': <msg>`. → KSTR + app validation.
- `--print`/`--history-print`: chars H B h b m; bad char →
  `'<ch>' is not a valid value`.
- `--format-options`: lowercase split ','; each `key:value` — missing
  ':' → `Format options consist of a key and a value, separated by a
  ":".`; keys json.indent/json.format/xml.indent/xml.format/
  headers.sort; `json.sort_keys` → `Unsupported option 'json.sort_keys'`;
  other → `Unknown option '<k>'`; bad num/bool →
  `Invalid value '<v>' in '<arg>'`. Repeat merges later-wins.
- `--proxy`: `PROTOCOL:URL` split on first ':'; missing → `The value
  passed to --proxy should be formatted as <PROTOCOL>:<PROXY_URL>`;
  protocol∉{http,https,all} → `Unknown protocol to set a proxy for:
  <p>`; URL must be absolute (reqwest Url) else `Invalid proxy URL
  '<u>' for protocol '<p>': <err>`.
- `--resolve`: exactly 2 colons → `Value should be formatted as
  <HOST>:<ADDRESS> (not <HOST>:<PORT>:<ADDRESS>)`; no colon → `Value
  should be formatted as <HOST>:<ADDRESS>`; bad IP → `Invalid address
  '<a>'` (IPv6 may be `[::1]` or bare).
- `--unstable-m-sig-comp`: infallible normalizer — split ',', trim,
  lowercase up to first ';', keep `;params`.
- `--verify`: infallible — `no|false`→No, `yes|true`→Yes (lowercased),
  else CA-bundle path. Never errors.
- `--response-charset`: liberal normalization (lowercase, strip
  non-alnum except _-:; u8/utf→UTF-8, u16→UTF-16LE, -/_ /digit-split
  variants) then WHATWG label lookup; unknown → `<label> is not a
  supported encoding, please refer to https://encoding.spec.whatwg.org/
  #names-and-labels for supported encodings`.

### Env vars (14 documented)

- Wired at S4 parse level: `XH_CONFIG_DIR` (config.json
  default_options + session/config root), `XH_HTTPIE_COMPAT_MODE`
  (compat mode; any value incl. empty counts — os.getenv CANNOT
  distinguish empty-set → deviation), `REQUESTS_CA_BUNDLE` then
  `CURL_CA_BUNDLE` (--verify env fallback, engine env attr),
  `NO_COLOR`/`TERM` (guess_pretty inputs), `ALL_PROXY`/`HTTP_PROXY`/
  `HTTPS_PROXY`/`NO_PROXY` (captured; `--proxy` disables all four).
- Read-for-later (execution-side): `NETRC`, `RUST_LOG`,
  `RUST_BACKTRACE` (--debug forces 1), `SOURCE_DATE_EPOCH` (--generate
  man date). Test-only family `XH_TEST_MODE*` noted, harmless.
- default_options: `<config>/config.json` `{"default_options":[...]}`
  tokenized BETWEEN argv0 and argv. Missing file → silent; unreadable
  → `\n<bin>: warning: Unable to read config file: <e>\n`; bad JSON or
  wrong types → `\n<bin>: warning: Unable to parse config file: <e>\n`.

### Diagnostics / actions / trailers

- clap shape (exit 2): `error: <msg>` + optional tip + `Usage: <bin>
  [OPTIONS] <[METHOD] URL> [REQUEST_ITEM]...` + `For more information,
  try '--help'.` — engine `fail()` already emits this.
- `--help` → SHORT help exit 0; `help` literal → LONG help exit 0;
  `-V/--version` → `<bin> <ver>` (upstream appends feature string).
- after_help (short): `Each option can be reset with a --no-OPTION
  argument.\n\nRun "<bin> help" for more complete documentation.`
  after_long_help: `Each option can be reset with a --no-OPTION
  argument.` → two `help_extra` variants.
- Warnings/logger shape: `<bin>: warning: <msg>`; app errors
  `<bin>: error: <msg>` exit 1.

## oxl v0.15.0 constraints discovered (verified this stage)

- `oxl test ./cli` DOES run `fn test_*` in `package main` dirs —
  probed on pin v0.15.0; no library subpackage needed.
- `std/os`: `args(i)/nargs()/quit(code)/getenv(name)/stdout()/stderr()/
  stdin()/exists(path)/readfile_` all present; no isatty/termios
  (oxl#125) — `Buffer::guess_pretty` TTY branch can't be detected;
  NO_COLOR/TERM branches can.
- `std/encoding/json`: `jparse` tree (kind 4 obj / 5 arr / 3 str,
  `.child`/`.next` linked list, `jget` member lookup) — enough for
  config.json `{"default_options":[...]}`. jparse returns jnull on
  malformed input (== our "Unable to parse" branch).
- `std/os.getenv` returns "" for unset → `XH_HTTPIE_COMPAT_MODE=""`
  indistinguishable from unset (deviation; upstream counts empty).
- No `url` crate: `construct_url` shape-checks must be hand-rolled
  (scheme:// + non-empty authority + numeric-port sanity).
- Engine covers: tokenize, `--`, shorts/clusters, `=v`/`v` values,
  KFLAG..KENUM validation, --no-* last-wins, overrides/conflicts/
  requires/positional-req, env pass, actions, tips, usage/help —
  verified in WI-0002 tests. What engine lacks: per-app value parsers
  (timeout/print/proxy/resolve/format-options/m-sig-comp/charset),
  bin-name detection, help literal, post-clap relations → all live in
  cli per spec'd division (engine is app-agnostic, S1 decision 0004).

## Prior decisions cited (not re-litigated)

- 0004 shared/args engine, 0011 table-first (this WI), 0012 folded
  state, 0013 spec-pinned diagnostics, 0006 explicit degradation —
  valid parse ends in an xh-shaped "unsupported in this build" error
  (exit 1) until S5; m-sig/http3/https get their corpus-pinned
  variants where they exist.
- Ordering deviations to spec: post-loop value checks can't
  interleave with argv tokens like clap value parsers (engine has no
  callback) — table-declaration order used; and a value error vs a
  later `--bogus`/conflict resolves in clap's order upstream.

## Stage-level open questions (resolve at spec/plan)

- Exact `--help`/usage text content (row order = upstream struct
  order; help column alignment is engine-fixed).
- How far `--response-charset` label validation goes (full WHATWG
  table vs tagged partial).
- Uniform post-parse deferral message text + which surfaces get
  corpus-pinned variants (m-sig, http3, https scheme).
