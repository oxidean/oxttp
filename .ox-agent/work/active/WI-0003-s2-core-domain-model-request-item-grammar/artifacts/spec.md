# WI-0003 spec - S2: core domain model + request-item grammar

Upstream: plan.md S2, WI-0001 spec, ADRs 0002/0003/0005/0010/0012.
Corpus: `docs/corpus/corpus-xh.md` §2-4 + §4.4, `docs/corpus/corpus-posting.md`
§5.2 + §3-4; source-verified algorithm in
`context/references/xh-request-item-grammar.md`.

## Scope

IN: domain types + request-item grammar + session/collection/term/transport
type surface in `core/`; grammar unit matrix.
OUT: any IO (no file/socket/terminal), request-item→body assembly (S6),
nested-JSON key paths (S6), method/URL positional handling (S4/S5),
h1 transport implementation (S3 - port only), posting.yaml load/save (S10).

## Packages (ADR-0012)

### `core/model` - transport-agnostic domain

- `struct Header { name: str, value: str }`; headers are an ordered
  `[]Header` (repeated names legal, insertion order = wire order).
- `struct KV { name: str, value: str, enabled: bool }` - shared
  name/value/enabled row (posting headers/params/parts).
- `enum Body { Empty, Raw{ctype, text}, Form{fields: []KV},
  Multipart{parts: []Part}, FileBody{path, ctype, filename} }` - covers
  xh Body kinds (Json bodies ride Raw with JSON ctype until S6 adds the
  nested-json assembler; a `Json{j: own Json}` variant is provided now).
- `struct Part { name, value, file, filename, content_type: str,
  enabled: bool, is_file: bool }` (posting multipart part shape).
- `struct Req { method, url: str, headers: []Header, body: Body }` +
  `timeout_ms: int` (0 = none), `follow: bool`, `max_redirects: int`.
- `struct Resp { status: int, reason: str, headers: []Header,
  body: []byte, elapsed_ms: float, remote: str, trace: own Trace }`.
- `struct Trace { connect_ms, tls_ms, send_headers_ms, send_body_ms,
  recv_headers_ms, recv_body_ms, closed_ms: float }` (posting §4.14).
- `fn status_class(status: int) -> int` - <300 success(0), <400
  redirect(1), else error(2) per posting §4.15 + xh check-status.

### `core/item` - REQUEST_ITEM grammar (the gate)

- `enum Item { HttpHeader{key,value}, HttpHeaderFromFile{key,value},
  HttpHeaderToUnset{key}, UrlParam{key,value}, UrlParamFromFile{key,value},
  DataField{key,raw_key,value}, DataFieldFromFile{key,raw_key,value},
  JsonField{raw_key, raw_value, value: own Json},
  JsonFieldFromFile{raw_key,value},
  FormFile{key,file_name,file_type,file_name_header} }` - 10 variants,
  12 syntax forms (mirrors request_items.rs; file_type/file_name_header
  are `own str`, nil = absent).
- `fn parse(item: str) -> [Item, err]` - exact algorithm:
  SEPS = `==@ =@ :=@ :@ == := = @ :`, left-to-right scan, longest match
  per position, `\` consumes next char unconditionally; key/value
  unescaped over `=@:;\`; `:=` JSON-validates eagerly
  (`Invalid value for '[REQUEST_ITEM]...': "<item>" <err>` on failure);
  `key;` post-scan fallback (NOT unescaped) → HttpHeader(key,"");
  no match → err `Invalid value for '[REQUEST_ITEM]...': "<item>"`.
- `fn unescape(s: str, special: str) -> str` - exported; nested-JSON
  stage passes `"=@:;[]\\"`.
- `fn parse_part_params(s: str) -> PartParams` - right-scan on
  `;type=`/`;filename=`, each consumed once, leftovers stay in value.

### `core/http` - transport port

- `interface Transport { send(req: ref model.Req) -> [model.Resp, err] }`
- h1 lands in S3 inside this package; port is all S2 provides.

### `core/session` - xh session model

- `struct Session { meta_about, meta_xh: str, auth: own SessAuth,
  cookies: []SessCookie, headers: []Header }`
- `struct SessAuth { type, raw_auth: str }`
- `struct SessCookie { name, value, expires, path, domain: str,
  secure: bool }`
- `fn session_path(name, host: str, port: int) -> str` - pure naming:
  `<host>[_<port>]/<name>.json`; rejects host `.`/`..`/empty.

### `core/collection` - .posting.yaml schema verbatim (types only)

17 top-level keys per corpus §5.2: `name, description, kind, method,
url, headers: []KV, params: []KV, path_params: []KV, body: own PBody,
graphql: own PGraphQL, grpc: own PGrpc, websocket: own PWebsocket,
auth: own PAuth, scripts: own PScripts, options: own POptions,
captures: []KV, variable_scope: own PVarScope`.
- `PBody`: `content, file, content_type: str, form_data: []KV,
  multipart: []Part` (+ `has_` markers so >1 body kind = parse error
  later; corpus: exactly one).
- `PGraphQL{query, variables: own Json, operation_name}`;
  `PGrpc{method, message, authority, proto: own PProto}`;
  `PProto{files: []str, import_paths: []str}`;
  `PWebsocket{message: str, binary: bool}`;
  `PAuth{type, basic_user, basic_pass, digest_user, digest_pass,
  bearer_token, oauth2: own POAuth2}`;
  `POAuth2{grant_type, authorization_url, token_url, client_id,
  client_secret, scope, redirect_uri, client_auth}`;
  `PScripts{setup, on_request, on_response}`;
  `POptions{follow_redirects, verify_ssl, attach_cookies,
  substitute_body_variables: bool, proxy_url: str, timeout_s: float}`;
  `PVarScope{variables: []KV}`.
- Defaults are NOT baked into zero structs - parse stage applies
  corpus defaults (method GET, follow_redirects true, timeout 5, ...).

### `core/term` - Screen/Key port

- `enum Key { Rune{ch}, Named{code}, Mouse{event} }` - `code` per the
  corpus named-key set (enter tab space backspace delete insert escape
  up down left right home end pgup pgdown f1..f12) as `Named_*`
  constants; `Mouse{kind, x, y}` covers SGR click/scroll per corpus §4.
- `struct KeyEvent { key: Key, mods: int }` - modifier bitset
  CTRL/ALT/SHIFT/META/SUPER consts.
- `interface Screen { size() -> [int,int], set_cell(x,y:int, ch:str,
  fg,bg,attr:int), present() -> err, cursor(x,y:int, show:bool) }` -
  cell-buffer port; stty-ANSI driver (S8) + headless test driver
  implement it.

## Acceptance criteria

1. `oxl build` green on every new package dir; `oxl test` per-dir green.
2. Grammar unit matrix covers, at minimum: all 12 syntax forms; SEPS
   longest-match orderings (`==@` vs `=@` vs `:` at same position);
   escaped separators (`foo\==bar`, `weird\:key=v`); backslash-before-
   normal (`f\o\o=\ba\r`); trailing `\`; empty-key `@file`; `key;`
   (incl. `foo\;` quirk + unescaped key); `a=b;` NOT a header;
   `key:` unset vs `key:value`; `:=` valid+invalid JSON; part-params
   right-scan incl. `;type=a;type=b` leftover; no-sep error shape.
3. Posting schema types cover all 17 corpus keys; session model covers
   corpus §4.4 fields; no IO anywhere in `core/`.
4. Every corpus deviation or gap is written down in findings - none
   silent.
