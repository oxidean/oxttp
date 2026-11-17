# Posting — user-facing feature corpus

Source of truth: `https://github.com/darrenburns/posting`, shallow clone at
`/tmp/oxttp-corpus/posting-src`, HEAD `32c45669032342cf9b95d5758af47a0d93de0ad7`
("Release Posting 3.0.0-beta.1", tag `v3.0.0-beta.1`, 2026-10-15).

## 0. Canonical implementation

The repo contains **two** implementations:

- **Posting 3 (canonical)** — a single Go binary. Entry `cmd/posting/`, packages under
  `internal/` (`client, collection, config, curl, env, grpcurl, history, importing, model,
  paths, remote, themes, ui`), `go.work`, `.goreleaser.yaml`. README: "Posting 3 is in beta.
  It's a single binary written in Go". UI framework is Terma (`github.com/darrenburns/terma`).
- **Posting 2 (legacy)** — Python/Textual under `src/` + `pyproject.toml`. README: "Posting 2
  was built with Textual." Posting 3 reads the same collections, `config.yaml` and `.env`
  files. Posting-3-only features (OAuth, multipart/file bodies, captures, generated values,
  gRPC, WebSocket) are documented as unreadable/unusable by Posting 2.

This corpus documents Posting 3 exhaustively; Posting 2 is noted only where docs/code
explicitly retain compatibility.

---

## 1. CLI surface (`cmd/posting/main.go`, `run.go`, `import.go`, `remote.go`)

`posting` is a single static binary. Usage: `posting [options] [<collection>]` plus
subcommands `locate`, `import`, `remote`, `run`, `version`.

### 1.1 Top-level flags
| Flag | Notes |
|---|---|
| `-c, --collection DIR` | Open this collection directory (equivalent to positional arg). |
| `-e, --env NAME|FILE` | Repeatable; named env(s) or env file(s) to load at startup. |
| `-v, --version`, `--version` | Print version and exit. |
| `-h, --help` | Usage. |
| positional `<collection>` | Collection directory to open; default is `<data>/default` |
| subcommand `version` | Same as `--version`. |

Relevant env vars at launch: `POSTING_CONFIG_FILE`, `POSTING_*` config overrides,
`HTTP_PROXY`/`HTTPS_PROXY`/`NO_PROXY`, `$EDITOR`, `$PAGER`, `POSTING_INSTANCE` (remote target).

### 1.2 `posting locate <config|collection|themes>`
Prints resolved paths: config file, active collection, themes directory.

### 1.3 `posting import [options] <source> [env files...]`
- `-t, --type openapi|postman|bruno` — force format (default: auto-detect; `.bru` and
  `bruno.json` mark Bruno, Postman env files detectable).
- `-o, --output DIR` — where to write the new collection.
- Sources: OpenAPI file, Postman collection JSON + optional `*.postman_environment.json`
  files, single `.bru` file or Bruno collection directory.
- Postman environment files may be passed alone to emit env files only.

### 1.4 `posting run [options] <file|dir> [--env X ...]`
Headless runner. Flags: `-c/--collection`, `-e/--env` (repeatable), `--fail-fast`, `--json`,
`-h/--help`. Ordering = directory listing (docs recommend `01-`, `02-` prefixes). A single file
must end `.posting.yaml`. Captures feed later requests in the same run; cookies/captures are
discarded at the end. `--json` emits one document `{results, passed, failed, skipped}`;
result objects carry `request`, `file`, `response` (same shape as `remote send --json`).
Exit codes (`cmd/posting/run.go`, docs/guide/running.md):
- `0` — every request got a response and all captures succeeded;
- `1` — at least one request failed (HTTP status, timeout, failed capture); redirects are not
  failures; a GraphQL/gRPC "error" status still passes unless a declared capture fails;
- `2` — usage/startup error (bad flag, missing file, unreadable collection/env).
SSE keeps the raw body + `streamError`; a headless WebSocket sends its saved nonempty message
then waits for the timeout.

### 1.5 `posting remote <command>` (`cmd/posting/remote.go`, `internal/remote/protocol.go`)
Drives a running Posting over a Unix socket (when `remote_control.enabled`). Commands:
`list`, `requests`, `show`, `open`, `send`, `response`, `env`, `save`, `skill`.
- Target instance: `--instance PATH`, else `$POSTING_INSTANCE`, else the only running instance.
- `list` — running instances; `requests` — saved requests (file, name, kind, url/method);
  `env` — environments with `files`, `name`, `variables`, `active`; `show` — open tab as YAML;
  `open`/`send` — open/send a request by `--curl CMD`, `--yaml FILE|-`, a request ref
  (file path), or the current tab; `response` — last exchange; `save` — save current tab
  (`--name`, `--file`); `skill` — print the agent skill (works with no instance).
- `--json` for machine output; `--env NAME|FILE...`/`--none` for env switching.
- `remote send` exits non-zero when the exchange failed/was cancelled; `open`/`send`/`save`/
  `env` errors (e.g. ambiguous env name, path outside collection) are returned as text.
- Outcomes: `done`, `failed`, `cancelled`, `sending`, `none` (`protocol.go:136-142`).
- `remote` protocol JSON for a response: `status`, `headers`, `trailers`, `body`/`bodyBase64`,
  `contentType`, `size`, `elapsedMs`, timestamps, `streamError`, tab + environment.
- `posting remote skill` emits `skills/using-posting/SKILL.md` (agent skill; docs/guide/agents.md
  gives install paths for Claude Code / Codex / Pi / Amp and the `POSTING_INSTANCE` workaround).

### 1.6 Exit/quit behavior in the TUI
`ctrl+c` quits (fixed); `ctrl+z` suspends (undo inside text fields); `ctrl+shift+s` writes a
text screenshot to CWD; `escape` cancels an in-flight request / stops a gRPC call / closes a
dialog.

---

## 2. Configuration (`internal/config/config.go`, `internal/paths/paths.go`,
`docs/guide/configuration.md`)

### 2.1 Locations and precedence
Config file: `$POSTING_CONFIG_FILE`, else `$XDG_CONFIG_HOME/posting/config.yaml`
(default `~/.config/posting/config.yaml`). Precedence: defaults < config file <
`POSTING_*` env vars (nested keys joined by `__`, e.g. `POSTING_HEADING__SHOW_HOST`;
booleans accept `true/false, 1/0, yes/no, on/off`). Unknown values for layout/spacing/
sidebar position/focus target/theme fall back to default with a startup notification;
invalid YAML or wrong types → whole file ignored with a notification. `POSTING_*` keys found
inside request env files produce a warning (Posting 2 read settings from them).

Paths (paths.go): data dir `$XDG_DATA_HOME/posting` (default `~/.local/share/posting`) holding
`default/` (default collection), `themes/`, `history/`, `environments.json` (remembered env);
sockets under `$XDG_RUNTIME_DIR/posting` else `/tmp/posting-<uid>`.

### 2.2 Settings (40 leaf keys; 37 effective — `watch_themes`, `use_xresources`, `animation`
are accepted Posting-2 no-ops)

| Key | Default | Effect |
|---|---|---|
| `theme` | `galaxy` | Active theme name (builtin or user). |
| `sidebar_gradient` | `theme` | `theme`\|`off`\|theme name; sidebar gradient from accent colours. |
| `theme_directory` | `<data>/themes` | User theme directory. |
| `load_user_themes` | `true` | Load user themes. |
| `load_builtin_themes` | `true` | `false`+≥1 user theme → picker shows only yours. |
| `layout` | `vertical` | `vertical` (response under request) / `horizontal` (side by side). |
| `spacing` | `standard` | Accepted; currently no effect (`standard` always). |
| `nerd_fonts` | auto-detect | `*bool`; auto true in Nerd-Font terminals (e.g. Ghostty). |
| `use_host_environment` | `false` | Expose shell env vars as request variables. |
| `watch_env_files` | `true` | Reload active env when its files change. |
| `watch_collection_files` | `true` | Reload collection on disk changes. |
| `watch_themes` | — | Posting-2 no-op (themes load at startup). |
| `use_xresources` | `false` | Posting-2 no-op. |
| `animation` | — | Posting-2 no-op. |
| `history.enabled` | `true` | Persist history to disk; `false` = memory only. |
| `response.prettify_json` | `true` | Indent JSON in body view. |
| `response.show_size_and_time` | `true` | Show response size + elapsed in title. |
| `heading.visible` | `true` | Top header row (env + host). |
| `heading.show_host` | `true` | Show `user@host`. |
| `heading.show_version` | `true` | Logo/version bottom-left. |
| `heading.hostname` | unset | Custom header text; `[b]…[/]` markup allowed. |
| `url_bar.show_value_preview` | `true` | Line under URL bar: variable values + resolved URL. |
| `url_bar.hide_secrets_in_value_preview` | `true` | Mask secret-looking variable values in preview. |
| `collection_browser.position` | `left` | `left`/`right`. |
| `collection_browser.show_on_startup` | `true` | Sidebar visible at launch. |
| `command_palette.theme_preview` | `true` | Live preview in theme/gradient pickers. |
| `text_input.blinking_cursor` | `true` | Pulsing cursor in all inputs. |
| `focus.on_startup` | `url` | `url`/`method`/`collection`. |
| `focus.on_response` | unset | `body`/`tabs` on response arrival. |
| `focus.on_request_open` | unset | `url`/`method`/`headers`/`body`/`path`/`query`/`info`. |
| `editor` | `$EDITOR` | Editor command for `f4` (or `POSTING_EDITOR`). |
| `pager` | `$PAGER` | Pager for `f3` (or `POSTING_PAGER`). |
| `pager_json` | unset | Separate JSON pager (or `POSTING_PAGER_JSON`). |
| `curl_export_extra_args` | empty | Inserted right after `curl` in exports. |
| `keymap` | empty | `action-id: key[,key]` overrides (see §3). |
| `remote_control.enabled` | `true` | Accept `posting remote` connections. |
| `ssl.ca_bundle` | unset | Extra PEM CAs (file, not dir). |
| `ssl.certificate_path` | unset | Client certificate PEM. |
| `ssl.key_file` | unset | Client key PEM (else read from certificate_path). |
| `ssl.password` | unset | Password for PKCS#8 / `Proc-Type: 4,ENCRYPTED` keys. |

Client-cert/password problems are reported at send time. TLS failures hint `grpc://`/`grpcs://`.

---

## 3. Global actions & keymap (`internal/ui/actions.go`, `docs/guide/keymap.md`)

18 rebindable action IDs (entry *replaces* defaults; comma-separated multi-keys; `jump` uses
only the first key). Key format: `ctrl/alt/shift/meta/super+key`; named keys `enter tab space
backspace delete insert escape up down left right home end pgup pgdown f1..f12`; case-insensitive.

| ID | Default(s) | Effect |
|---|---|---|
| `send-request` | `ctrl+j`, `alt+enter` | Send request / send message into open gRPC stream or WS. |
| `stream` | `alt+j` | Open or end gRPC stream / disconnect WebSocket. |
| `jump` | `ctrl+o` | Enter jump mode. |
| `commands` | `ctrl+p` | Command palette. |
| `save-request` | `ctrl+s` | Save request to collection. |
| `new-request` | `ctrl+n` | New request tab. |
| `close-tab` | `alt+w` | Close tab. |
| `keep-tab` | *(none)* | Pin preview tab. |
| `next-tab` | `alt+right` | Next tab. |
| `previous-tab` | `alt+left` | Previous tab. |
| `search-tabs` | `alt+down` | Search open tabs. |
| `search-requests` | `ctrl+g` | Search collection requests. |
| `focus-url` | `ctrl+l` | Focus URL bar. |
| `focus-method` | `ctrl+t` | Method menu. |
| `toggle-collection` | `ctrl+h` | Sidebar show/hide. |
| `expand-section` | `alt+z` | Maximize focused panel (quirk: `alt+z` still works inside Request/Response; a new key only expands Request). |
| `variables` | `ctrl+shift+v` | Variables screen. |
| `help` | `f1` | Keyboard shortcuts screen. |

Fixed global keys (not rebindable): `escape` (cancel/stop/close), `ctrl+c` (quit),
`ctrl+z` (suspend; undo in text fields), `ctrl+shift+s` (text screenshot to CWD).
Focused widgets take precedence over globals (e.g. `ctrl+r` toggles a KV row).

---

## 4. Screens, panels and widgets (`internal/ui/*.go`, `docs/guide/navigation.md`,
`keymap.md`, `help_system.md`, `command_palette.md`)

### 4.1 Main layout
Header row (`heading.*`): app name/version, active environment, `user@host` (or
`heading.hostname`). URL bar (method selector + URL input + value preview line). Sidebar
(collection browser) left/right. **Request** panel with seven tabs — **Headers, Body, Path,
Query, Auth, Info, Options** (GraphQL replaces Body with Params; gRPC shows Metadata + Message
+ Proto + Info + Options; WebSocket shows Message). **Response** panel with tabs Body,
Headers, Cookies (or Trailers for gRPC), Trace, and Messages for streams. Footer shows
context keys. `layout` vertical/horizontal; `expand-section` maximizes a panel.

### 4.2 Jump mode (`ui/app.go` jump handling, navigation.md)
`ctrl+o` shows one-letter targets; `escape` exits. Letters: `q w e r t y u` = request tabs
(per-kind: gRPC `q`→Metadata; GraphQL has no Body, `r`→Params); response letters include `a`
= response body; `4` = history. (Docs navigation.md lists the full mapping on screen.)

### 4.3 Method selector
`enter`/`space` open menu; letters `g p u a d h o` → GET/POST/PUT/PATCH/DELETE/HEAD/OPTIONS,
`q` → GraphQL, `r` → gRPC, `w` → WebSocket (menu and selector alike).

### 4.4 URL bar
`enter` send (or import if content is a curl command); `down` → request tabs; `ctrl+y` copy
URL; `ctrl+shift+z` redo (since `ctrl+y` copies); typing `$` triggers variable suggestions;
URL segment autocomplete from collection URLs (`url_completion.go`) — prefix tree by path
segment, host case-insensitive, suppresses in query/fragment and inside curl commands;
`MaxVisible` 8, fuzzy filter; file-path completion inside file-path fields (≤512 dir entries).

### 4.5 Request tabs (generic tab strip; also sidebar + response tabs)
`left/h`,`right/l` switch; `down/j/enter` into content; `up/k` back out.

### 4.6 KV tables — Headers, Query, form (`ui/kv_editor.go`)
Type in last empty row → new row; `up/down` move (`up` from first row exits to tabs/body
selector); `ctrl+r` toggle enabled; `ctrl+x` delete; header-name suggestions while typing;
checkbox/`✕` clickables. Path table: names from `:name` URL placeholders, only values
editable. Disabled rows persist but aren't sent.

### 4.7 Body editor (`ui/smart_input.go`, `multipart.go`)
Raw body: syntax-highlighted textarea (JSON/Text/XML/HTML content-type selector); smart
bracket/quote pairing, auto-indent (2 spaces or tabs), dedent closing bracket on empty line.
`f3` pager, `f4` editor. Multipart: part list + inspector; `insert`/`+ Add part`, `ctrl+r`
toggle, `ctrl+x` delete, `alt+up/down` reorder; inspector fields: type (Text/File tabs),
name, value/path, filename override, content type, enabled; `f5` re-stats file path;
`enter`/`escape` for narrow-pane full-width inspector.

### 4.8 Text inputs/areas (Terma)
`ctrl+left/alt+b`, `ctrl+right/alt+f` word move; `home/end`, `ctrl+e`; shift+move select;
`ctrl+a` select all; `ctrl+z/ctrl+y` undo/redo (`ctrl+shift+z` in URL bar);
`ctrl+w`/`alt+backspace` delete word; `ctrl+u/ctrl+k` delete to line start/end;
`ctrl+d`/`delete` delete char right; suggestion lists `up/down enter escape`.
gRPC Method field: `ctrl+r` re-list server methods.

### 4.9 Collection browser (`ui/collection.go`, docs/guide/collections.md)
Tree of folders/requests; open request in **bold**, other open requests dotted, preview tab
italic; `enter` open/expand (multi-select opens all), `up/k down/j` move,
`shift+up/k shift+down/j` extend selection, `left/h right/l` collapse/expand or parent/child,
`home/g end/G` first/last, `shift+home/shift+end` extend, `space` toggle folder, `/` search,
`escape` clear selection then search, `d` duplicate request (or all selected),
`backspace`/`delete` delete (confirm once). New folders/`(copy)` naming rules in §5.

### 4.10 History panel (`ui/history.go`, `internal/history/history.go`)
`enter` open entry into preview tab (request as sent + its response); `up/k down/j`,
`shift+up/down` select, `home/g end/G`, `shift+home/end` extend, `pgup/ctrl+u pgdown/ctrl+d`,
`escape` clear, `backspace` delete selected. Jump-mode `4`.

### 4.11 Variables screen (`ui/variables.go`, docs/guide/environments.md)
Table of effective variables w/ source labels (`file`/`session`/host env). `enter` edit
session value, `a` add session variable, `d` revert a session override to file value,
`/` filter, `ctrl+r` reveal/mask secrets, `escape` close.

### 4.12 Dialogs/overlays (`ui/overlays.go`)
Command palette; help overlay (`f1`); Save Request dialog (Name required; File name; Folder;
Description); Save Response dialog (filename; `O_EXCL` 0600 — never overwrites); confirmation
dialog; curl import dialog (`ctrl+j` to import); environment file switcher; toasts
(info/success/error); theme & sidebar-gradient pickers with live preview + `escape` restore.

### 4.13 Command palette contents
`ctrl+p`; `up/down` (or `ctrl+p/ctrl+n`) move, `enter` run/submenu, `escape` back/close,
`backspace` on empty query = back. Commands include: New/Open/Duplicate/Delete request(s),
tab ops (close/pin/search), search requests, environment switch, open variables, reload
collection, OAuth sign-in, gRPC stream open/end, WebSocket disconnect, Import curl
command… / Import curl from clipboard / Export as curl / Export as grpcurl / Export as YAML,
View toggles (collection, layout), Theme…, Sidebar gradient…, History, Help, Open docs,
response copy commands, Quit.

### 4.14 Response widgets
- **Body text view** (`response_text.go`): `k j h l`, `w/b` word, `0 ^ $`, `g/G`, `%` match
  bracket, `pgup/ctrl+b pgdn`, `ctrl+u/ctrl+d` half-page, `ctrl+f`/`/` search w/ `n/N`,
  `shift+hjklwb` visual-select, `v` visual mode, `V`/`f6` select line, `f7` select all,
  `y/c` copy selection-or-all, `f3`/`f4` pager/editor. `ctrl+a` = line start (differs from P2).
- **JSON tree** (`response_json.go`): `ctrl+f`/`/` JSONPath filter, `escape` clear filter,
  `y/c` copy value, `Y` copy JSONPath of node, `e` expand all, `E` collapse all.
- **Headers/Cookies/Trailers tables** (`response_table_copy.go`): `up/k down/j`, `home/g end/G`;
  `y`/`c` copy value, `n` copy name, `b` copy both (`Name: value`; cookie `name=value`);
  headers/trailers add `shift+up/down` multi-row + `ctrl+a` select-all → `y/c` copies full lines.
- **Messages log** (SSE/WS/gRPC `response_messages.go`): sent/received/info/error rows w/
  timestamps; `f` toggle follow-latest; `enter` inspect; `escape` back; binary shown base64;
  WS `FrameType` text/binary; SSE `event:`/`id:` metadata.
- **Image preview** (`response_image.go`): PNG/JPEG/GIF(first frame)/static WebP; sniffed by
  content-type or magic bytes; limits 32 MiB, 16 MP, 16384px/side; `f2` image↔text; `s` save.
- **Save response** (`response_save.go`): default name from URL path else `response`; common
  image extensions appended; writes original bytes `O_EXCL` 0600.
- **Trace tab**: per-stage timings — connect, tls handshake, send headers, send body,
  receive headers, receive body, response closed (`model/response.go` TraceStage).

### 4.15 Response panel semantics (`internal/model/response.go`, docs/guide/responses.md)
StatusClass: <300 success, <400 redirect, else error; Warning = transport-OK but app-level
errors (e.g. GraphQL 200 + `errors`). gRPC status by name (`OK`, `NOT_FOUND`…), only OK =
success colour; Headers tab = response metadata; Trailers carry `grpc-status`/`grpc-message`.
`StatusOf`/`FormatBytes` ("1.23 KB"), `FormatDuration` ("45.67 ms"/"1.20 s"). 64 MB body
cap — SSE/WS/gRPC streams truncate with `CANCELLED` + "response truncated at 64.00 MB".

---

## 5. Collections & request files (`internal/collection/`, `internal/model/`,
`docs/guide/collections.md`, `requests.md`)

### 5.1 Discovery
A collection is a directory tree of `*.posting.yaml` files. Root = positional arg /
`--collection`, else `<data>/default` (auto-created 0755; `cmd/posting/main.go:152-158`).
Env files are searched in CWD, then the collection dir, then the config dir
(`main.go:166-169`). Skips dot-directories,
`__pycache__`, `node_modules` (`collection/dir.go`). Malformed files appear as placeholders
named by file + parse error rather than aborting the load. Watcher reloads on fs changes
(`watch_collection_files`). Sidebar sorting: folders first, then requests, alphabetical.
Folder ops: rename/move/delete on disk; new folders via save dialog `Folder` field.

### 5.2 Request file schema (`.posting.yaml`; `collection/format.go` + `kinds.go`)
17 top-level keys (all optional except effectively `url`+name-ish; only non-defaults are
written — `omitempty` throughout):

| Key | Type | Notes |
|---|---|---|
| `name` | str | Display name. |
| `description` | str | Info tab. |
| `kind` | str | `graphql`\|`grpc`\|`websocket`; omitted = HTTP. |
| `method` | str | GET/POST/PUT/PATCH/DELETE/HEAD/OPTIONS (uppercased, validated; `validMethod`); omitted = GET. |
| `url` | str | URL without query string (query → `params`). |
| `headers` | `[{name,value,enabled}]` | `enabled:false` = saved-not-sent. |
| `params` | `[{name,value,enabled}]` | Query params. |
| `path_params` | `[{name,value}]` | Values for `:name` placeholders; always enabled. |
| `body` | obj | Exactly one of `content`(raw), `form_data`(KV list), `multipart`(`[{name, value|file, filename, content_type, enabled}]`), `file`(path); `content_type` for raw/file. >1 = parse error; part w/o exactly one of value|file = error. Form default CT `application/x-www-form-urlencoded`; raw CT falls back to `Content-Type` header. |
| `graphql` | obj | `query`, `variables`, `operation_name`. Strict decode — unknown key = error. |
| `grpc` | obj | `method`, `message`, `authority`, `proto{files[], import_paths[]}`. Strict decode. |
| `websocket` | obj | `message`, `binary` (bool; base64 send). Strict decode. |
| `auth` | obj | `type`: `basic|digest|bearer_token|oauth2`; blocks `basic{username,password}`, `digest{username,password}`, `bearer_token{token}`, `oauth2{grant_type, authorization_url, token_url, client_id, client_secret, scope, redirect_uri, client_auth}` (`model` OAuth2). |
| `scripts` | obj | `setup`, `on_request`, `on_response` — Posting 2 scripts; retained, never executed. |
| `options` | obj | `follow_redirects` (def true, max 10 redirects), `verify_ssl` (true), `attach_cookies` (true), `substitute_body_variables` (true), `proxy_url`, `timeout` (seconds, default 5). |
| `captures` | map | `VAR: jsonpath` — see §6. |
| `variable_scope` | obj | `{variables: {NAME: template}}` — request/folder-scoped variable templates; layer above env files, below session values (`model/scoped_variables.go:10-22`). P3-only. |

gRPC requests can't have `method`/`body`/`params`/`path_params` nor `follow_redirects`/
`attach_cookies`/`proxy_url`. Marshal writes only non-defaults; `multipart`, `file`, OAuth,
captures, generated values = Posting-3-only. `MarshalRequest` uses plain/!!binary-safe YAML
scalars. Duplicate = copy beside original + `(copy)` in name. Delete keeps open tab as unsaved.

### 5.3 History (`internal/history/history.go`, docs collections.md)
Per-collection JSON store at `<data>/history/<sha256-of-collection-path>.json` (+`.lock`
sidecar, 0700/0600 perms); `{version, next_id, entries[]}` of {request-as-sent + response};
`MaxEntries=100`, `MaxBytes=50MiB` (keeps newest fitting; oversized entries dropped; unknown
request kinds retained as raw JSON). `history.enabled=false` → memory only.

---

## 6. Environments & variables (`internal/env/`, `internal/model/substitute.go`,
`docs/guide/environments.md`)

### 6.1 Files & layering
dotenv files in the collection dir (or CWD for `--env` file paths). Layer order:
`posting.env` → `posting.local.env` → `<name>.env` → `<name>.local.env` → session values.
Missing files skipped. `.local.env` intended for secrets (gitignored). `--env dev` loads
`dev.env`+`dev.local.env` on top of both base files; multiple `--env` compose. Active env
remembered in `<data>/environments.json`. `posting remote env`/`--env`/`--none` can switch at
runtime. `use_host_environment` exposes shell env as variables. `watch_env_files` reloads on
change. `POSTING_*` keys in env files → warning.

### 6.2 Substitution
`$NAME` and `${NAME}`; `$$` = literal `$`. Unresolved: error if in URL address/path or OAuth
fields; passed through literally elsewhere (incl. query string). Expansion limits: >10000 refs or
>16 MiB aggregate = error (`model/scoped_variables.go:82-105`). `substitute_body_variables`
controls body (never file contents); URL/headers/auth always substitute.
Generated values: `${$uuid}`, `${$timestamp}` (s), `${$timestampMs}` (ms),
`${$isoTimestamp}` (RFC3339), `${$randomInt}`.
dotenv parsing supports `NAME=value`, quoting, `export `, comments, `KEY="${OTHER}"` refs.

### 6.3 Variables screen & secrets
See §4.11. Request-level `variable_scope.variables` templates layer above env, below
session. Secret-looking names
(masked in URL-bar preview when `hide_secrets_in_value_preview`; `ctrl+r` reveals on the
variables screen).

### 6.4 Response captures
`captures: {VAR: json.path}` — each capture must match **exactly one** value (shorthand paths
allowed); all must succeed or the send is a failure (run counts it); cancelled/replaced
requests never publish; gRPC stream captures from final retained body. Captured values become
session variables (highest layer).

---

## 7. Request features (`internal/client/`, `internal/model/`, docs/guide/requests.md)

### 7.1 HTTP
Methods: GET POST PUT PATCH DELETE HEAD OPTIONS. URL w/o scheme → `http://`. Sends
`User-Agent: posting/<ver>` unless set. Redirects ≤10 when `follow_redirects`; method rewrite
301/302/303→GET; cookies jarred per-app for `attach_cookies` (session-scoped, shared by tabs);
explicit Cookie headers preserved across digest retry. Digest: answer challenge; never
forward creds cross-origin/downgrade. Proxy: `proxy_url` else env `HTTP(S)_PROXY`/`NO_PROXY`.
Timeout counts connect+upload+redirects+body (default 5s); SSE lifts timeout post-headers
when watched. TLS: system roots + `ssl.ca_bundle`; client cert; per-request `verify_ssl`.
Uploads: file checks pre-connect, streamed w/ byte progress; redirect/digest re-send verifies
file identity/size/mtime or aborts. Multipart boundary auto-generated (explicit boundary or
non-multipart CT = error); file bodies cannot combine w/ other parts.

### 7.2 GraphQL (`model/graphql.go`)
`kind: graphql`; POST of `{query, variables(obj), operationName}` JSON; `Accept:
application/json`. Params tab replaces Body. 200-with-`errors` → warning status. Vars in
`variables` JSON substitute (respect `substitute_body_variables`).

### 7.3 gRPC (`internal/client/grpc.go`, `internal/grpcurl/`)
Address table: `grpc://`/`http://` = plaintext; `grpcs://`/`https://` = TLS; loopback/any
hosts (localhost, 127.0.0.1, [::1], 0.0.0.0, [::]) = plaintext; other scheme-less = TLS;
`unix:///path` = plaintext UDS (relative→CWD). Default ports 443/80. Schema: server
reflection when Proto tab empty, else `proto.files` (`.proto` source compiled in-app;
`.protoset/.binpb/.pb` descriptor sets) + `proto.import_paths` (default = collection dir;
each file must be under one). `authority` sets `:authority`/TLS SNI check. Message: protojson
object (unary) or array (one msg per element for client/bidi streaming). Body shows replies
as JSON incl. default-valued fields; failure w/o messages = `{code,message,details}` w/
`google.rpc` details decoded, others typeURL+base64. `send-request` streams into an open
call; `stream` (`alt+j`) opens/ends; `escape` stops; no timeout once connected; unary/server-
stream open calls send first message then listen. Per-send new connection; reflection re-
fetched each send unless proto files. Response: status name, headers tab = metadata, trailers
tab w/ `grpc-status`/`grpc-message`, `DEADLINE_EXCEEDED`/`CANCELLED` keep arrived messages.
Not supported: gRPC-Web/Connect, compression, proxies, per-request client certs, proto path
completion, connection reuse, Postman/grpcurl import (Bruno gRPC import works).

### 7.4 WebSocket (`model/websocket.go`, client ws)
`kind: websocket`; `ws://`/`wss://`. `send-request` = connect then send draft as one message;
edit+send repeatedly incl. empty; `binary` = base64→binary frame. `stream`/`alt+j` or
Disconnect palette = disconnect; `escape` stops. Handshake honours headers/query/path,
Basic/Bearer/OAuth, cookies, proxy, TLS; `Sec-WebSocket-Protocol` header for subprotocols;
OAuth needs `wss://` except loopback. Auto-pong to pings. Timeout bounds connect + each
write only. No redirects/digest/per-message-compression/auto-reconnect; queued unsent
messages dropped.

### 7.5 SSE
`Accept: text/event-stream` responses stream into Messages tab; event/id captured; followed
live; `f` resume follow; `streamError` recorded; raw body retained.

### 7.6 Auth
None / Basic / Digest (challenge-response, retry once, cookies re-attached) / Bearer
(`Authorization: Bearer *** / OAuth2 `grant_type`: `authorization_code` (PKCE via browser —
has own budget outside request timeout) or `client_credentials` (`client_secret`,
`client_auth`); token used only for original origin; palette "OAuth sign-in" command.

### 7.7 curl interop (`internal/curl/`, `internal/grpcurl/`)
Import: paste `curl` into URL bar (`enter`), palette dialog, or clipboard. Parses `-X -H -d
(--data*,--data-binary) --json -F/--form(-string) -u --digest -b -A -e -k -L -x -m -G -I
--oauth2-bearer` etc.; `-s -v -o` ignored. `-F` → multipart (`@path`, `;filename=`, `;type=`,
`--form-string` literal); `--data-binary @`/`--json @` → file body (paths vs collection root);
`$NAME` preserved as Posting var. Multiline `\` continuations OK. Replaces request except
name/description/file. Export: palette → clipboard + dialog, Values/Variables toggle, `y`
re-copy; uploads → `-F`/`--form-string` or `--data-binary @abs`; empty multipart → explicit
framing; `curl_export_extra_args`. gRPC requests export **as grpcurl** instead (`-plaintext`
/`-insecure`, `-unix`, `-authority`, `-cacert -cert -key` when TLS, `-H`, `-d`,
`-max-time`, `-import-path -proto -protoset` absolute; unresolved-var addresses kept;
scheme-less → TLS; arrays = concatenated JSON objects).

---

## 8. Responses, themes, imports, remote

### 8.1 Themes (`internal/themes/themes.go`, docs/guide/themes.md)
37 built-ins (default `galaxy`); Posting-2 names mapped (`posting`,`textual-dark`→`galaxy`;
unknown P2 names → fallback). User themes: `<data>/themes/*.yaml|.yml` (configurable),
Posting-2 YAML format; required `name` + `primary` (`#rgb|#rrggbb|#rrggbbaa`); optional
`dark`, `secondary, accent, background, surface, panel, warning, error, success, text,
foreground` (+ icons) — omitted colours inherit from `galaxy` (dark) / builtin light theme;
same-name overrides builtin; files sorted by name; bad file → startup notification + skip;
loaded at startup only. Picker lists **Yours** first; live preview (`command_palette.theme_
preview`), `enter` applies for session, `escape` restores. `sidebar_gradient` picker similar.

### 8.2 Import (`internal/importing/`, docs/guide/importing.md)
Writes a new collection dir (`-o`); env files → dotenv files; Bruno `collection.bru`/folder
vars + `protoPath`/import paths → request fields; collection vars → `posting.env`. Result
line: `Imported N <type> request(s) into "<dir>"`. Per-format support notes in
`docs/research/import-{openapi,postman,bruno}.md`. P2 `import --type postman` still works.

### 8.3 Remote/agent surface
`remote` commands execute on the UI goroutine (opens/sends are visible live); request refs
are collection-relative paths; `save` refuses to clobber existing files; env switch by name
(must be unique) or file list; `--none` clears. Skill at `skills/using-posting/SKILL.md`.

### 8.4 External tools (`docs/guide/external_tools.md`, `ui/external.go`)
`f3` pager / `f4` editor on request+response bodies; `pager_json` overrides `pager` for JSON;
commands run via shell in the terminal; suspend/resume handled by Terma.

### 8.5 Scripting (docs/guide/scripting.md)
`scripts{setup,on_request,on_response}` preserved in files but **not executed** in P3.
Alternatives table maps P2 script uses → session values, generated values, captures, layered
env files, host env refs.

### 8.6 Misc documented behaviors
Preview tabs: open-from-collection/history reuses italic preview tab until edited/pinned
(`keep-tab`). Mouse: click rows/tabs/checkboxes, scroll. Footer shows context keys; `f1`
full help; palette "Open docs" → documentation. Ctrl+h may be Backspace in some terminals —
rebind or use palette. Notifications/toasts for config/theme/env warnings.

---

## 9. Doc↔code disagreements & caveats

- `expand-section` (`alt+z`): docs admit partial rebind — `alt+z` keeps working inside
  Request/Response panels even when rebound, and custom keys only expand Request
  (keymap.md:86-87).
- `spacing: compact` accepted but always standard (docs + config.go:70 comment "no effect").
- Posting-2-only settings `watch_themes`, `use_xresources`, `animation` parsed but ignored
  (configuration.md "Settings not yet supported" ↔ config.go:45,48,60).
- keymap.md: `ctrl+shift+z` URL-bar redo needs kitty keyboard protocol; `ctrl+h` may collide
  with Backspace.
- Docs `requests.md` marks gRPC/WebSocket/multipart/file/OAuth/captures/generated values as
  P3-only — P2 silently can't preserve them.
- `posting remote save` writes via UI's save path (name slugify → `<slug>.posting.yaml` when
  no `--file`; `--file` must be collection-relative, `..`/`:`/abs rejected — `ui/remote.go`).

## 10. Counts (verified)

- **CLI flags**: 13 distinct options — `collection(-c)`, `env(-e)`, `version(-v/--version)`,
  `help(-h)`, `type(-t)`, `output(-o)`, `fail-fast`, `json`, `instance`, `none`, `name`,
  `curl`, `yaml`; subcommands: `locate`, `import`, `remote`, `run`, `version` (+9 remote
  subcommands).
- **Keybindings**: 18 rebindable global actions (19 default keys) + 4 fixed global keys +
  ~95 documented widget-level bindings (keymap.md tables + requests/responses/
  environments.md extras: multipart, JSON tree, message log, image, variables, history,
  collection, tabs, text editing).
- **Config options**: 40 accepted leaf keys (37 effective + 3 P2 no-ops), across 10 nested
  sections (`text_input, history, response, heading, url_bar, collection_browser,
  command_palette, ssl, focus, remote_control`).
- **Request-file fields**: 17 top-level keys; 50 nested/leaf keys (graphql 3; grpc 4 +
  proto 2; websocket 2; body 5; auth type+16 fields; kv row{name,value,enabled}; path_param
  {name,value}; scripts 3; options 6; captures map; variable_scope).
