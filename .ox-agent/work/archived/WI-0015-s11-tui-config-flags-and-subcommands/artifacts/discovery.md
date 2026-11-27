# WI-0015 discovery — S11 TUI config, flags, and subcommands

Scope (umbrella WI-0001 S11, deps S10): "all 40 `.posting.yaml` config
keys wired, theme/styling corpus, remaining modals and bindings live,
startup flags + 5 subcommands". Gate: config checklist 40/40;
subcommand corpus coverage; full transcript suite green.

Sources: `docs/corpus/corpus-posting.md` sections 1 (CLI surface), 2
(configuration, 40 keys), 3 (keymap rebind), 4.4/4.11/4.12 (URL bar
import, variables screen, dialogs), 5.1/5.3 (env search dirs, disk
history), 6.1 (environments.json, host env), 8.1 (themes). Verified
against the pinned upstream clone `/tmp/oxttp-corpus/posting-src`
(`cmd/posting/{main,run,import,remote}.go`, `internal/config`,
`internal/paths`, `internal/env`, `internal/history`,
`internal/themes`, `internal/remote/protocol.go`) and terma v0.27.0
`theme.go` (the 37-name builtin registry lives in terma, not posting).

## Corpus inventory — what S11 must cover

### Section 1 CLI surface (verified vs `cmd/posting/main.go`)

- Subcommands dispatched on `args[0]` before flag parsing:
  `import`, `locate`, `remote`, `run`, `version` (also `--version`,
  `-v`). Top level: Go-flag parse of `-c/--collection DIR`,
  `-e/--env NAME|FILE` (repeatable), `-h`; upstream errors
  `fs.NArg()>0` → `posting: unexpected argument %q` + usage → exit 2
  — upstream code rejects a bare positional collection even though
  corpus §1.1 documents `positional <collection>` (a real
  doc↔code disagreement). Resolution: follow the corpus/docs
  contract (S10 already accepts positional); record deviation.
- `-v/--version`/`version` prints `Posting <ver>` (upstream string;
  ours prints `Posting ` + shared version — keep the label, the
  program emulates posting).
- `locate config|collection|themes` prints a label line then the
  resolved path (`Config file:` / `Default collection directory:` /
  `Themes directory:`); wrong arg count or name → usage/`Unknown
  thing to locate: %q` → exit 2.
- `run` (run.go, verified): options `-c/--collection`,
  `-e/--env` repeat, `--fail-fast`, `--json`, `-h`; `--k=v` and
  flag-after-PATH both accepted; one positional max. Parse errors →
  stderr + `Run posting run --help for usage.` → exit 2.
  `loadRunRequests`: dir → `collection.Dir.Load` (**problems abort
  before any send**); single file must end `.posting.yaml`; empty
  URL/scripts per-request abort; sort by rel file path lexical.
  Config warnings are fatal for unattended runs. Env stack =
  `posting(.local).env` in root, or `-e` files/names layered (names
  resolve `<name>.env`+`<name>.local.env` in root dir; missing →
  error). ssl.* config → TLS settings. Outcome per request:
  response status_class error/warning → `failed` (error text =
  `code + text`), else captures; capture failure → failed;
  `passed` → captures merge as session vars for later requests.
  Text line `PASSED|FAILED <rel-file>: <detail>`; summary
  `%d passed, %d failed, %d skipped`. `--json` →
  `{results:[{file,name,outcome,error?,response?}],passed,failed,
  skipped,error?}`, 2-space indent; response = remote.Response
  shape `{method,url,status,reason?,statusCode?,proto?,headers[],
  trailers?,contentType?,streamError?,body|bodyBase64,size,
  elapsedMs,receivedAt}` (bodyBase64 when body isn't valid UTF-8).
  Exit: failed>0 or run-level error → 1; else 0. "The UI's
  remembered environment is never used."
- `import` (import.go): `-t/--type openapi|postman|bruno` (else
  auto-detect), `-o/--output DIR`, sources positional (option values
  may follow positionals — hand-rolled splitter). Import engine
  (openapi/postman/bruno) is M4/post per parity matrix → S11 parses
  the surface and degrades explicitly with upstream-shaped errors.
- `remote` (remote.go): unix-socket protocol — `list`, `requests`,
  `show`, `open`, `send`, `response`, `env`, `save`, `skill`.
  oxl std has TCP only (no AF_UNIX) → client commands degrade
  "no running instance"; **`remote skill` needs no instance** →
  emit `skills/using-posting/SKILL.md` (131 lines upstream — embed
  verbatim; it teaches `posting` commands which our binary emulates).
- Env vars at launch: `POSTING_CONFIG_FILE`, `POSTING_*` overrides,
  `HTTP(S)_PROXY`/`NO_PROXY` (already honored via plan_req env
  capture), `$EDITOR`, `$PAGER`, `POSTING_INSTANCE`.

### Section 2 Configuration — all 40 leaf keys (verified vs config.go)

Paths (paths.go): config file `$POSTING_CONFIG_FILE` (→abs), else
`$XDG_CONFIG_HOME/posting/config.yaml` (XDG honored only when
absolute; else `~/.config`). Data dir `$XDG_DATA_HOME/posting` else
`~/.local/share/posting` holding `default/` `themes/` `history/`
`environments.json`. SocketDir `$XDG_RUNTIME_DIR/posting` else
`/tmp/posting-<uid>` (no getuid in std; remote degraded anyway).

Precedence: defaults < config file < `POSTING_*` env. File:
invalid YAML OR wrong types → whole file ignored +
`Couldn't read <file>: <err>` warning (yaml.Unmarshal is
non-strict: unknown keys OK, wrong-typed values error). Env:
`POSTING_<key>` / `POSTING_<section>__<key>` → YAML mapping merged
on top; empty values skipped; `config_file` skipped; bool fields
accept `1/yes/on/true` `0/no/off/false` (any other value errors →
`Ignoring POSTING_ environment settings: <err>` — **one bad env
value nukes ALL env overrides**, mirror that).

`validate()` resets unknown enumerated values with warnings:
`layout` ∈ vertical|horizontal; `spacing` ∈ standard|compact;
`collection_browser.position` ∈ left|right;
`focus.on_startup` ∈ ""|url|method|collection (default url);
`focus.on_response` ∈ ""|body|tabs (default "");
`focus.on_request_open` ∈ ""|headers|body|query|info|url|method|
path (default ""). Theme validated at app level:
`themeAlias` maps `""`/posting/`textual-dark`→galaxy,
catppuccin-{mocha,macchiato,frappe}→catppuccin,
`textual-light`→catppuccin-latte; unknown → `Unknown theme %q;
using galaxy`. `sidebar_gradient` ∈ theme|off|theme-name (after
alias) else `Unknown sidebar gradient %q; following app theme` →
"theme".

40 keys: theme, sidebar_gradient, theme_directory,
load_user_themes, load_builtin_themes, layout, spacing,
nerd_fonts(*bool auto), use_host_environment, watch_env_files,
watch_collection_files, watch_themes, use_xresources, animation,
history.enabled, response.prettify_json,
response.show_size_and_time, heading.visible, heading.show_host,
heading.show_version, heading.hostname, url_bar.show_value_preview,
url_bar.hide_secrets_in_value_preview, collection_browser.position,
collection_browser.show_on_startup, command_palette.theme_preview,
text_input.blinking_cursor, focus.on_startup, focus.on_response,
focus.on_request_open, editor, pager, pager_json,
curl_export_extra_args, keymap (map action-id→"k1,k2" replace),
remote_control.enabled, ssl.ca_bundle, ssl.certificate_path,
ssl.key_file, ssl.password. Three P2 no-ops (watch_themes,
use_xresources, animation) + spacing (accept-only).

Env vars under `POSTING_*` inside env files → warning per file
(already wired in core/env warns; main.go's
`settingsInEnvironmentFiles` is the launch-surface variant — apply
its wording at startup).

### Section 8.1 Themes — 37 builtins live in terma v0.27.0

28 dark + 9 light, full hex catalogs extracted (Primary/Secondary/
Accent/Background/Surface/Surface2/Warning/Error/Success/Text +
IsLight flag). Our AnsiScreen paints fg∈0..7 + attrs (no true
color). Mapping: each theme → quantized ANSI-8 fg ids per semantic
slot (primary/accent/warning/error/success/text/muted);
background/surface stay at terminal default bg (deviation —
painting bg on every cell changes the contrast story; fg-only
theme application documented). User themes: posting-2 YAML format,
`name`+`primary` required, `#rgb|#rrggbb|#rrggbbaa`, optional
dark+9 colors+icons; unset colors inherit galaxy
(dark)/catppuccin-latte (light); panel→Surface2; `foreground` and
`text` both →Text. Same-name user theme overrides builtin.
`theme_directory` default `<data>/themes`; `load_user_themes`
gates scanning; `load_builtin_themes`+≥1 user theme → picker shows
only yours. Files sorted by name; bad file → `Couldn't load theme
<file>: <err>` + skip; load at startup only.
Picker (overlays.go): "Theme…" command → grouped list **Yours** /
Dark / Light; live preview gated by `command_palette.theme_preview`;
`enter` applies for session, `escape` restores prior theme.
`sidebar_gradient` picker similar (theme|off|each theme); gradient
= accent ramp on sidebar — approximate with per-row fg/dim ramp
(deviation: 8-color palette can't do true gradients).

### Section 5.3 Disk history (history.go verified)

`<data>/history/<sha256-of-abs-collection-path>.json` (+`.lock`
sidecar); `{version:1,next_id,entries[]}` — entries RawMessage
with `id`; MaxEntries=100; MaxBytes=50MiB newest-fitting, oversized
dropped; unknown kinds retained. `history.enabled=false` → memory
only (today's ring). Our entries carry our own JSON shape
(title/method/url/status/reason/elapsed/size/req_yaml/resp rows) —
envelope + naming + caps stay corpus-exact; foreign-shape entries
aren't decodable by us (documented deviation: dropped on rewrite —
upstream-tolerated since entries are raw messages).
std has `crypto/sha256` + `encoding/hex` → naming is exact.
`os` has no chmod → 0700/0600 perms degrade; `.lock` = advisory
sidecar create/remove (no flock → deviation).

### Section 6.1 environments.json (memory.go verified)

`<data>/environments.json`: `{<abs-coll-dir>: {name?,dir?,files?}}`.
Recall: named env → rebuild `Stack(dir,name)`; else file list —
any missing file → forget. Remember on switch; no files → delete
key. MarshalIndent 2sp + newline, `*.tmp`→rename (os.rename).
Recall only when no `-e` given at launch (main.go).

### Remaining degrades queued for S11 (code survey)

- `tui/app.oxl:1049` curl-paste import in URL bar (`is_curl_text`
  → "lands S11"); palette "Import curl command…" (§4.12 dialog).
  Implement a curl→draft parser (§7.7 subset: `-X -H
  -d/--data*/--json -F --form(-string) -u --digest -b -A -e -k -L
  -x -m -G -I --oauth2-bearer`; `-s -v -o` ignored).
- `tui/app.oxl:2240-2244` variables screen `enter`/`a`/`d` →
  session variable edit/add/revert (§4.11).
- `tui/coll.oxl:659` folder delete → recursive remove with confirm
  (`os.remove_all` exists).
- `tui/app.oxl:1561` `$` variable suggestions in URL bar (§4.4).
- `tui/coll.oxl:63` argv degrade → full flag surface (mission pins
  shared/args for flags).
- `focus.on_response`/`focus.on_request_open` focus moves on
  response install / draft open.
- Env file search dirs: CWD → collection → config dir
  (S10 scanned collection only).
- `f3`/`f4` pager/editor — NOW implementable: `os/exec.Cmd.run()`
  inherits stdio; wrap with session close→run→reopen+full render.
  `pager_json` overrides `pager` for JSON bodies; `sh -c` shell.
  `editor`/`pager`/`pager_json` config + $EDITOR/$PAGER/
  POSTING_EDITOR/POSTING_PAGER/POSTING_PAGER_JSON env fallbacks.
- `heading.hostname` `[b]…[/]` markup → strip markup, literal
  render (deviation).
- `nerd_fonts` → icon vs ASCII fallbacks (folder/sidebar glyphs);
  auto-detect Ghostty (TERM_PROGRAM/TERM/GHOSTTY_RESOURCES_DIR).
- `text_input.blinking_cursor` → false hides the cursor cell; true
  keeps current static cursor (no frame timer in driver —
  deviation).
- `remote_control.enabled` — parsed; listener can't bind (no UDS)
  → startup message mirroring upstream's `posting remote won't
  work: <err>` when enabled; silent when disabled.
- `use_host_environment` — no `environ()` in std → degrade:
  accepted, one warning at startup (upstream issue candidate).
- `watch_*` — no fsnotify → accepted, no-op (spec note; palette
  "Reload collection" stays manual).
- `ssl.*` → wire into send plan: `ca_bundle`→Req.verify=path,
  `certificate_path`/`key_file`→cert_pem/key_pem reads at plan
  time; `ssl.password` — encrypted-key support check; corpus pins
  "problems reported at send time".
- `keymap` → apply rebinds at startup: parse `action: k1,k2`,
  replace that action's default bindings; unknown action id / bad
  key spec → startup warning.
- Save response dialog (§4.12: filename, O_EXCL 0600) — palette
  degrade is stale. Implement: default name from URL path else
  `response`, exists→error (never overwrite), write raw bytes
  (0600 unavailable → deviation; O_EXCL approximated by
  exists-check).
- Env vars `HTTP_PROXY`/`HTTPS_PROXY`/`NO_PROXY` — already honored
  through plan_req's env capture.

## oxl/std capability findings (verified)

- `std/crypto/sha256`, `std/encoding/hex`, `std/encoding/base64`,
  `std/encoding/json` (compact emit only) — history naming,
  bodyBase64, JSON reports all feasible.
- `std/os/exec` `Cmd.run()` inherits stdio → pager/editor handoff
  feasible (close session → run → reopen).
- NO: unix sockets (remote), fsnotify (watch_*), `environ()`
  (host env), chmod (0600/0700), O_EXCL flag (approximate via
  exists-check → deviation), clipboard API (copies stay degraded),
  SIGTSTP raise (ctrl+z stays degraded).
- `os.remove_all` exists → recursive folder delete implementable.
- YAML DOM in `core/yaml` is the config decode substrate
  (ADR-0030: "S11's config parser becomes a decode-only consumer").

## Constraints / risks

- Config loader must not break startup on bad file/env values —
  upstream warns + continues; TUI collects warnings as startup
  toasts (matches `messages` → notify pattern).
- `run` shares `plan_req`/H1 with TUI but must not write history
  or use remembered env — separate code path in `tui/main.oxl`
  (binary is `package main` — subcommands live in tui).
- Rebind config replaces whole default binding list per action
  (KeysFor); dispatch tables are rebuilt per event — apply via an
  App-held override map consulted by `global_bindings()`.
- Corpus fidelity: follow corpus where it documents behavior the
  code contradicts (positional collection); cite disagreements in
  spec deviations.
