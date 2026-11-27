# WI-0015 spec — S11 TUI config, flags, and subcommands

Direction: ADR-0034 (`core/config` leaf + settings contract),
ADR-0035 (ANSI-8 theme slots), ADR-0036 (CLI surface split +
degrade map), ADR-0037 (history + env persistence). Contract:
corpus-posting.md §1 (CLI surface), §2 (config), §3 (`keymap:`),
§4.4/4.11/4.12, §5.1/5.3, §6.1, §8.1; upstream-verified constants
in `context/references/posting3-cli-config-semantics.md`.
**S11 = settings file + env precedence end-to-end, theme catalog +
pickers, queued UI degrades, argv surface + 5 subcommands.**
Captures, OAuth2, GraphQL/gRPC/WS sends, import engines, remote
sockets stay M4/post with explicit degrades (ADR-0006/0024).

## Files

New core leaf (ADR-0016 layout):
- `core/config/config.oxl` — `Settings` (40 keys), `defaults()`,
  `load(file, getenv)`, `validate()`, `keys_for()`, paths helpers.
- `core/config/config_test.oxl` — decode/merge/validate/paths
  cases over fixture files + env tables.

TUI (`package main`):
- `tui/cfg.oxl` — `apply_settings(App, own config.Settings)`,
  startup-warning plumbing, `scan_user_themes`, env memory
  load/save, disk history load/append, `rebind_table`.
- `tui/themes.oxl` — `Theme` + 37-entry builtin catalog (terma
  v0.27.0 names+hex verbatim) + `quantize(hex)->ansi id` +
  user-theme decode off `core/yaml` + picker row builders.
- `tui/cli.oxl` — `cli_dispatch(argv)->int` for `import|locate|
  remote|run|version` + top-level spec parse result; `run_*`
  helpers: arg parse, request selection, send loop, report emit.
- `tui/curlimp.oxl` — `import_curl(text)->[own collection.PRequest,
  []str warns, err]` (§7.7 subset).
- `tui/cfg_test.oxl`, `tui/themes_test.oxl`, `tui/cli_test.oxl`,
  `tui/curlimp_test.oxl`.
- `tui/types.oxl` — App additions (settings handle, theme fields,
  rebinds, picker state, env/history persistence fields,
  vars-edit state, curl-import modal, pending external command).
- `tui/app.oxl` — theme-slot fgs plumbed, rebind-aware global
  table, new modal kinds + dispatch arms, queued-degrade
  replacements (vars edit, folder delete, curl paste, `$`
  suggestions, f3/f4).
- `tui/render.oxl` — theme slots replace hardcoded fgs; picker +
  curl modal renders; sidebar gradient ramp; heading config
  (visible/show_host/show_version/hostname); URL preview gated by
  `url_bar.show_value_preview`.
- `tui/coll.oxl` — env dir list (CWD→coll→config), remembered-env
  recall, history hooks in `load_collection`/`install_resp`,
  `focus.on_request_open` in `open_into_draft`, `focus.on_response`
  in `install_resp`, folder delete arm in `confirm_yes`,
  curl-paste arm in URL-bar enter.
- `tui/main.oxl` — subcommand dispatch before session open;
  settings load + apply after `parse_argv`; f3/f4 external-command
  effect handling (session close → exec → reopen → render).
- Fixtures: `tests/tui-fixtures/config-app/` — config.yaml cases
  (full, bad-yaml, wrong-types, unknown-keys, enum fallbacks,
  keymap, env overrides) + `themes/*.yaml` user-theme fixtures
  (valid dark, valid light, missing-primary, bad-hex,
  same-name-override).

Fixtures must NOT contain secrets-shaped literals via file tools
(redaction hazard) — use plain ASCII names/values only.

## core/config — the settings contract (ADR-0034)

`struct Settings` — flat typed fields, one per corpus §2.2 key:

```
theme str          sidebar_gradient str   theme_directory str
load_user_themes   load_builtin_themes    layout str   spacing str
nerd_fonts int (-1 unset | 0 | 1)
use_host_environment watch_env_files watch_collection_files
watch_themes use_xresources animation str
history_enabled response_prettify_json response_show_size_and_time
heading_visible heading_show_host heading_show_version
heading_hostname str
url_bar_show_value_preview url_bar_hide_secrets_in_value_preview
collection_browser_position str collection_browser_show_on_startup
command_palette_theme_preview text_input_blinking_cursor
focus_on_startup focus_on_response focus_on_request_open str
editor pager pager_json curl_export_extra_args str
keymap []model.KV            // action-id -> "k1,k2" ordered
remote_control_enabled
ssl_ca_bundle ssl_certificate_path ssl_key_file ssl_password str
```

`defaults()` = config.go Defaults() verbatim (theme galaxy,
gradient theme, dir `<data>/themes`, loads true, layout vertical,
watches true, animation "none", history/response/heading/url_bar/
collection_browser/command_palette/text_input trues, position
left, pager $PAGER, editor $EDITOR, spacing standard, remote true,
nerd_fonts -1, focus url/""/"", strings empty, keymap empty).

`load(file: str, getenv: fn(str)->str) -> [Settings, []str]`:

1. `settings = defaults()`; `file==""` → resolve via
   `config_file()` ($POSTING_CONFIG_FILE→fullpath else
   `config_dir()+"/config.yaml"`).
2. `os.exists(file)` → `yaml.parse(os.readfile_(file))`;
   parse err OR decode type err (a known key's value has the
   wrong YAML shape) → `settings = defaults()` +
   `Couldn't read <file>: <err>`; unreadable non-ENOENT → same
   warn, defaults kept. Unknown keys ignored silently
   (yaml.Unmarshal is non-strict upstream — mirror).
   Known-key coercion table per field kind:
   bool ← `true/false` scalars (yaml bool spellings
   true/false/yes/no/on/off/1/0 — decode normalizes, matching
   yaml.v3's bool token set True/true/False/false only? NO —
   upstream yaml.v3 accepts yes/no/on/off for bools too; our
   tobool already handles that set — reuse), str ← scalar,
   keymap ← map of scalar→scalar.
   Nested sections decode their own maps; a section that isn't a
   map = type error (whole file ignored).
3. POSTING_* env merge — for each name returned by a caller-
   provided environ-pairs list (probe fn yields "NAME=value";
   prod passes os-environ? std lacks environ() → prod code scans
   the KNOWN key names: build the 40 `POSTING_<KEY>` +
   `POSTING_<SECTION>__<KEY>` names and getenv each — equivalent
   surface since unknown POSTING_* names are ignored upstream
   anyway): value=="" skip; key lowercase, `config_file` skip;
   `__` splits section__leaf; bool-typed leaf accepts
   1/yes/on/true 0/no/off/false else value verbatim; unknown leaf
   ignored; a KNOWN leaf whose value fails its type → ALL env
   overrides dropped + `Ignoring POSTING_ environment settings:
   <err>` (upstream semantics verbatim).
   `keymap` can't be env-set (map type → any POSTING_KEYMAP
   value = decode error → nukes all env overrides; matches
   upstream yaml-decode behavior).
4. `validate()` — resets + warns `Unknown <name> %q; using %q`:
   layout ∈{vertical,horizontal}; spacing ∈{standard,compact};
   collection_browser.position ∈{left,right};
   focus.on_startup ∈{"",url,method,collection}→"url";
   focus.on_response ∈{"",body,tabs}→"";
   focus.on_request_open ∈{"",headers,body,query,info,url,method,
   path}→"".
5. Theme/gradient name validation happens in `apply_settings`
   (needs the theme catalog — upstream does it at app level too).

`keys_for(s, action, defaults []str) -> []str` — look up action
in keymap; absent/blank → defaults; else split on `,`, lower +
trim each, drop empties (upstream KeysFor).

Paths (paths.go verbatim): `config_home()` ($XDG_CONFIG_HOME
abs-only else ~/.config), `data_home()` ($XDG_DATA_HOME abs-only
else ~/.local/share), `config_dir/file`, `data_dir`,
`theme_dir`, `history_dir`, `env_memory`, `default_coll_dir`,
`socket_dir` (XDG_RUNTIME_DIR else /tmp/posting-<uid> — uid
unavailable → `posting-$USER` fallback, degrade note; unused
since remote degrades).

## Themes (ADR-0035)

`struct Theme { name str, is_light bool, primary int, secondary
int, accent int, warning int, error int, success int, text int }`
— slots are ANSI-8 ids from `quantize(hex)`: parse
`#rgb|#rrggbb|#rrggbbaa` (alpha ignored → deviation note), map to
the nearest of the 8 standard xterm colors by squared RGB
distance (palette: 0 #000000, 1 #CD0000, 2 #00CD00, 3 #CDCD00,
4 #0000EE, 5 #CD00CD, 6 #00CDCD, 7 #E5E5E5).

`builtin_themes() -> []Theme` — all 37 terma entries, names+hex
verbatim (28 dark then 9 light, registry order — extracted table
in themes.oxl). `text` slot comes from each entry's Text hex;
entries whose upstream Text is `AutoText()` get the white/black
endpoint the formula produces (precomputed constants — recorded
in the table comments).

`theme_alias(name) -> str` — verbatim: ""/posting/textual-dark
→galaxy; catppuccin-{mocha,macchiato,frappe}→catppuccin;
textual-light→catppuccin-latte.

`parse_user_theme(text) -> [UserTheme, err]` — DOM decode:
required `name` + `primary`; each present colour must match
`#hex{3|6|8}` else `<field> colour "<v>" isn't a hex colour like
#1e88e5`; `dark` optional bool (unset→dark); 9 optional colours
(secondary, accent, background, surface, panel, warning, error,
success, text, foreground).

`scan_user_themes(dir) -> [[]Theme, []str problems]` —
`os.ls(dir)` missing-dir → empty; `*.yaml|*.yml` only, skip dirs;
each file: parse → err pushes `Couldn't load theme <file>:
<err>` (upstream problem text shape), else build Theme on the
base (dark→galaxy, light→catppuccin-latte) with set fields
overriding, `foreground`+`text` both →text; sort by name.
Same-name user theme replaces the builtin row when both exist.

Picker rows (`theme_rows(app)`): `Yours` section header + user
names, `Dark`/`Light` headers + builtin names in registry order
(load_builtin_themes=false + ≥1 user theme → only Yours).
`gradient_rows(app)`: `theme`, `off`, then every theme name.
Modal kinds `MTheme`/`MGradient` reuse ListCur nav + filter;
cursor-move live-applies when `command_palette.theme_preview`,
`enter` commits session state (`a.theme`/`a.gradient`),
`escape` restores the snapshot taken at open.

`sidebar_gradient` application: "off" → flat; "theme"/name →
vertical AttrDim→normal ramp on sidebar title/separator rows
using that theme's accent (deviation — approximates the accent
gradient in 8 colors).

`nerd_fonts` resolution (`use_nerd_fonts(settings, getenv)`):
set → value; else true when TERM_PROGRAM≈ghostty | TERM=
xterm-ghostty | GHOSTTY_RESOURCES_DIR nonempty. Icon slots:
folder ▸/request •|nf glyphs — nerd true → `▸`/glyphs, false →
current ASCII (deviation-lite: two icon slots only).

## CLI surface (ADR-0036)

`cli_dispatch(argv []str, getenv, stdout, stderr) -> int` —
`argv[0]` in {import, locate, remote, run, version, --version,
-v} → handler else `nil`-sentinel meaning "not a subcommand".
`main()`: `code := cli_dispatch(...)`; code >= 0 → `os.quit`.

Top-level (when not a subcommand): `shared/args` Spec
`-c/--collection DIR`, `-e/--env NAME|FILE` (repeat),
`-h/--help` (print usage → 0), `-v/--version`, positional
`<collection>`; unknown flag → stderr + usage → `os.quit(2)`.
Parse result feeds coll_dir + env_active/session-vars exactly as
S10's parse_argv did (file-path `-e` loads into session layer;
missing file → error toast upstream errors hard — match: missing
env file at startup = startup toast, S10 behavior kept).

`version`/`--version`/`-v` → `println("Posting " + ver)` exit 0
(corpus §1.1 contract — emulate posting's string).

`locate` — exactly 1 arg else usage→2; `config`→"Config file:\n"
+config_file(); `collection`→"Default collection directory:\n"
+default_coll_dir(); `themes`→"Themes directory:\n"+theme_dir();
else `Unknown thing to locate: %q`→2.

`run` — verbatim run.go semantics:
- args: `-c/--collection`, `-e/--env` repeat, `--fail-fast`,
  `--json`, `-h/--help`; `--k=v` form ok; flags after PATH ok;
  `--` ends flags; >1 positional or missing-value →
  `posting run: <err>` + `Run posting run --help for usage.` → 2;
  `-h` → upstream usage text → 0.
- selection: target join collection when relative → fullpath;
  not-exist → 1 `posting run: <err>`; dir → `collection.scan`
  nodes with `err!=""` → abort-all `posting run: <err>` (upstream
  aborts on ANY malformed file); file must end `.posting.yaml`;
  decode errors abort; empty list → `no request files found in
  %s` → 1; per req: empty url or non-empty scripts → error → 1
  (upstream wording: `Posting 3 doesn't run Python scripts;
  remove or replace its scripts before running headlessly`).
  Sort by collection-relative path lexical.
- config: `config.load` warnings non-empty → `posting run:
  <warns joined>` → 1 (fatal unattended).
- env: `-e` names resolve `<name>.env`+`<name>.local.env` in
  root; file paths resolve CWD; no -e → `posting.env`+
  `posting.local.env` in root; missing named env → upstream
  error text → 1. `use_host_environment` → warn to stderr (no
  environ()). ssl.* → plan options (ca_bundle → verify path;
  cert/key files read eagerly — error → 1; password → sent-time
  warn degrade).
- send: `plan_req` over built EnvSet (+ jar always-empty —
  cookies discarded per corpus; wait — "Cookies and response
  captures carry forward during this run only" — carry a run-
  scoped jar exactly like the TUI does per App). H1 send per
  request in order; transport err → failed; resp status_class
  error(2) → failed with `STATUS LINE` detail; declared
  `captures` non-empty → FAILED `captures unsupported in this
  build — lands M4`; `failed` + `--fail-fast` → skip rest
  (count into skipped). PASS line `PASSED <rel>: <status>
  <reason> (<ms> ms)`; FAIL `FAILED <rel>: <err>`.
- summary `%d passed, %d failed, %d skipped\n`; `--json` →
  `{results[],passed,failed,skipped,error?}` 2sp indent —
  results[{file,name,outcome,error?,response?}] with response =
  remote.Response fields (method,url,status,reason?,statusCode?,
  proto?,headers[{name,value}],contentType?,body|bodyBase64
  (utf8-valid→body else base64),size,elapsedMs,receivedAt unix
  ms? — upstream sends RFC3339 time; ours: unix seconds float —
  deviation note or RFC3339 format via time fns if available).
- exit: any failed or run-level error → 1; else 0.

`import` — parse `-t/--type openapi|postman|bruno`,
`-o/--output DIR`, sources (flags-after-positional ok per
upstream splitter); usage errors → `posting import: <err>` → 2;
then `posting import: <fmt> import lands M4 in this build` → 1.
(Postman env-file-only imports degrade the same way — engine is
M4 wholesale.)

`remote` — `--help`→usage text→0; `list` → text header
`PID\tVERSION\tCOLLECTION\tCWD\tSOCKET` + `no running Posting`
line / `--json` → `[]` → 0; `skill` → embedded SKILL.md verbatim
→ 0; other commands → `no running Posting found (unix sockets
unsupported in this build)` → 1; unknown command → usage → 2.
`--instance`/`POSTING_INSTANCE` parsed-and-ignored (degrade
note).

## App wiring (tui/cfg.oxl + edits)

`apply_settings(a, s, warns)` — after collection/env init:
- layout vertical|horizontal → a.layout; spacing ignored
  (validated anyway); collection_browser.position → sidebar_pos;
  show_on_startup → sidebar_on.
- focus.on_startup → a.focus (url→FUrl, method→FMethod,
  collection→FSidebar); focus.on_response stored → install_resp
  moves focus (body→FRespPane+resp_tab Body, tabs→FRespTabs);
  focus.on_request_open stored → open_into_draft moves focus to
  the named request pane/tab (url/method/headers/body/path/
  query/info map onto FUrl/FMethod/FReqPane+req_tab index).
- history.enabled → a.hist_disk flag + load at collection open.
- response.prettify_json → install_resp's json_pretty gate;
  response.show_size_and_time → title suffix gate.
- heading.visible → header row hidden (url bar moves up);
  show_host/show_version/hostname → header text composition
  (`[b]…[/]` markup stripped → literal).
- url_bar.show_value_preview → preview line hidden when false;
  hide_secrets_in_value_preview → mask gate in url_preview.
- command_palette.theme_preview → picker live-apply gate.
- text_input.blinking_cursor → false hides cursor rendering
  (cursor() show=false at render; true = static cursor —
  deviation: no blink pulse).
- editor/pager/pager_json → resolved command strings
  (POSTING_EDITOR/POSTING_PAGER/POSTING_PAGER_JSON env override
  config values; editor/pager config defaults already carry
  $EDITOR/$PAGER).
- curl_export_extra_args → stored for export surface (export
  still degrades — stored not dead).
- remote_control.enabled → true+no-UDS startup toast `posting
  remote won't work: unix sockets unsupported in this build`.
- ssl.* → app-level fields consumed by `begin_send_preq`:
  ca_bundle → `req.verify = <path>` (when request verify_ssl
  true); certificate_path → read PEM text → `req.cert_pem`
  (read err → plan warn `ssl.certificate_path: <err>` — send
  still proceeds? upstream reports at send time → we degrade as
  plan-stage warn + send without cert, documented); key_file →
  `req.key_pem`; ssl.password → warn `ssl.password unsupported —
  encrypted keys land with mTLS M4` when cert+password both set
  (oxl tls has no encrypted-key support — verify at implement;
  corpus says problems surface at send time).
- use_host_environment=true → one warn toast (no environ()).
- watch_env_files/watch_collection_files → accepted, silent
  no-op (deviation; "Reload collection" stays manual).
- animation/use_xresources/watch_themes/spacing → parsed only.
- keymap → `a.rebinds` (action→[]KeyPat); `global_bindings()`
  consults it: action with rebind entry → emit binds ONLY for
  the custom specs (entry replaces defaults); unknown action id
  or bad key spec → startup warn `keymap: <action> <err>` and
  the entry is skipped (defaults apply). Fixed-globals are NOT
  rebindable (corpus §3).
- theme → `theme_alias` → catalog/user lookup → apply;
  unknown → `Unknown theme %q; using galaxy` warn; same check
  for sidebar_gradient (`theme|off|<name>` post-alias else
  `Unknown sidebar gradient %q; following app theme`).

`load_collection` gains: env scan dirs = [CWD, coll_dir,
config_dir] for `-e` name resolution (env.scan_envs gets a dirs
list or an added config-dir probe — mirror main.go envDirs);
remembered env recall (when no -e at launch):
`env_memory()` json → entry for abs coll_dir → set env_active
before building EnvSet; env_pick remembers `{name, dir:coll_dir}`
via tmp+rename (or deletes on none); POSTING_* env-file warnings
use core/env's existing warns (upstream wording differs —
deviation-lite, ours already names the file+var).

`install_resp` gains: when `history.enabled` && hist_disk →
append entry + rewrite file (lock sidecar best-effort); history
modal reads a.history either way (disk load feeds it at open).
`focus.on_response` honored here.

`tree_delete` folder arm → confirm "Delete <dir>/ and its
contents?" → `os.remove_all` + reload (corpus §5.1 folder ops).

Variables screen (§4.11): rows become {name, value, layer,
session_idx}; `enter` → inline LineEdit seeded with row value →
commit sets session override (upsert into a.session_vars +
rebuild EnvSet); `a` → add-mode LineEdit "NAME=VALUE" → session
push; `d` → remove session override for name (when one exists —
rebuild + note revert); `ctrl+r` reveal + `/` filter unchanged.

`$` var suggestions (§4.4): typing `$` in URL bar opens a small
suggestion list of env var names (from a.env layers +
session_vars); `up/down/enter/escape` nav — enter inserts name;
list filters by prefix after `$`. Replaces the degrade toast.

URL-bar enter curl import: `is_curl_text` → `import_curl` →
apply to draft (all fields except name/description/file —
upstream curl import replaces the request); warns toast;
palette "Import curl command…" → `MCurl` modal: one LineEdit,
`ctrl+j`/enter imports, escape closes.

Save response (§4.12): palette "Save response" → MSaveResp
modal (filename field; default from URL path basename else
`response`); confirm → exists → toast error `exists — never
overwrites` (O_EXCL approximated); write resp body bytes.
Palette degrade strings updated.

f3/f4 (§8.4): on response body pane (`resp_view` focus or body
tab) — `f3` → pager cmd (+`pager_json` when body is JSON),
`f4` → editor cmd; writes body to a temp file
(os.temp_dir()+name), sets `a.ext_cmd`; main loop sees pending
ext_cmd → `sess.close()` → `exec.cmd("sh", ["-c", cmd+" "+
file])` → `open_session()` → full render; missing cmd → toast
`f3/f4: no pager/editor configured`. Request-body pane f3/f4
same path on body text. Nonzero exit → toast.

`parse_argv` replacement: top-level Spec parse → same seeding
as today + `-h` prints usage exit 0, `-v` prints version exit 0;
unknown flags → usage → 2 (was toast; now exits — upstream
parity).

## 40-key checklist (gate artifact — all "wired" or "no-op
documented")

| # | key | wire |
|---|---|---|
|1|theme|catalog apply+pickers+alias+warn|
|2|sidebar_gradient|ramp/off/name+picker+warn|
|3|theme_directory|user scan root|
|4|load_user_themes|scan gate|
|5|load_builtin_themes|picker Yours-only rule|
|6|layout|a.layout|
|7|spacing|accepted, always standard|
|8|nerd_fonts|icon slots + ghostty auto|
|9|use_host_environment|warn degrade (no environ)|
|10|watch_env_files|accepted no-op (no fsnotify)|
|11|watch_collection_files|accepted no-op|
|12|watch_themes|accepted P2 no-op|
|13|use_xresources|accepted P2 no-op|
|14|animation|accepted P2 no-op|
|15|history.enabled|disk store gate|
|16|response.prettify_json|install_resp gate|
|17|response.show_size_and_time|title gate|
|18|heading.visible|header row|
|19|heading.show_host|header text|
|20|heading.show_version|header text|
|21|heading.hostname|custom text, markup stripped|
|22|url_bar.show_value_preview|preview row|
|23|url_bar.hide_secrets_in_value_preview|mask gate|
|24|collection_browser.position|sidebar_pos|
|25|collection_browser.show_on_startup|sidebar_on|
|26|command_palette.theme_preview|live preview gate|
|27|text_input.blinking_cursor|cursor show flag|
|28|focus.on_startup|a.focus|
|29|focus.on_response|install_resp focus|
|30|focus.on_request_open|open_into_draft focus|
|31|editor|f4 cmd + POSTING_EDITOR|
|32|pager|f3 cmd + POSTING_PAGER|
|33|pager_json|f3 json cmd + POSTING_PAGER_JSON|
|34|curl_export_extra_args|stored for export surface|
|35|keymap|rebind table replace|
|36|remote_control.enabled|startup message gate|
|37|ssl.ca_bundle|plan verify path|
|38|ssl.certificate_path|plan cert_pem read|
|39|ssl.key_file|plan key_pem read|
|40|ssl.password|send-time warn degrade|

## Deviations recorded (explicit)

1. Positional collection accepted (corpus §1.1) — upstream code
   rejects it; doc↔code disagreement resolved for the docs.
2. Theme colors quantize to ANSI-8 fg; no bg painting, no
   truecolor — deviation.
3. Sidebar gradient = dim-ramp approximation, not real gradient.
4. History entries carry our JSON shape; foreign entries dropped
   on rewrite (no RawMessage); `.lock` is create/remove advisory
   (no flock); 0700/0600 perms unavailable (no chmod).
5. environments.json writes `{name,dir}` form only; recall
   forgots apply on missing env names.
6. `use_host_environment` warns unsupported (no environ() in
   std) — upstream issue to file.
7. `watch_*` accepted but inert (no fsnotify).
8. `remote` instance commands all fail `no running Posting`
   (no AF_UNIX); `skill` works.
9. `import` degrades post-parse (engine M4).
10. Cursor is static — `blinking_cursor=false` hides it, `true`
    can't pulse (no frame timer between blocking reads).
11. `heading.hostname` `[b]…[/]` markup stripped, not styled.
12. Save-response O_EXCL approximated by exists-check; 0600
    unavailable.
13. `ssl.password` unsupported (encrypted-key decode absent) —
    reported at plan/send time per corpus §2.2's own rule.
14. `run --json` receivedAt emitted as unix-ms number if RFC3339
    formatting unavailable; bodyBase64 only when body invalid
    UTF-8 (upstream-exact).
15. Nerd-font icons limited to sidebar glyphs.
16. Unknown keymap action-ids warn (upstream silently ignores) —
    friendlier, noted.
17. `POSTING_*` env-file warn wording differs from upstream's
    settingsInEnvironmentFiles text (ours names file+var).
18. `posting run` startup errors (missing target, missing env,
    unreadable/malformed collection, fatal config warns) exit 1 —
    corpus §1.4 documents 2 for usage/startup errors. Spec pinned 1
    (run-level error → 1); review-flagged, kept for now.
19. `posting remote` emits a text `no running Posting found` stub —
    `--instance`/`POSTING_INSTANCE` parsed-and-ignored, `list
    --json` → `[]`, unknown commands → usage/2 (review fixes).

## Acceptance criteria

- `oxl build ./core ./tui ./cli ./shared` clean on pin.
- Per-dir `oxl test` green; new tests:
  - core/config: defaults table (spot-check ≥10 keys), file
    decode (full/bad-yaml/wrong-type/unknown-key/empty), env
    merge (`__` nesting, bool spellings, bad-value nuke-all,
    config_file skip, empty skip), validate warnings ×6 enum
    keys, keys_for replace, paths (XDG abs-only, POSTING_CONFIG_
    FILE).
  - tui/themes: quantize bounds (pure primaries map exact),
    builtin count 37 + dark/light split, user parse (valid/miss-
    ing-primary/bad-hex/dark-false base), scan sort+same-name
    override+problem text.
  - tui/cli: locate outputs+exit codes, run arg-parse errors→2,
    run file/dir selection (malformed abort, scripts reject,
    sort order), run send via fake transport (pass/fail/skip
    counts, captures degrade, --json shape), remote
    list/skill/other degrade, import degrade codes.
  - tui/cfg: apply_settings field mapping (focus/layout/
    sidebar/heading/preview/remote-message), rebind replace +
    bad-spec warn, env-memory recall/remember round-trip, disk
    history write+load round-trip + enabled=false memory-only,
    variables edit/add/revert, folder delete, curl import
    subsets (data/json/form/auth/flags/errors).
  - keymap: rebind end-to-end (custom key dispatches action,
    defaults gone).
- Transcript-style tests exercise: startup with bad config →
  warn toasts + defaults; theme picker enter/escape; env switch
  persists environments.json.
- `git diff` byte-check — no `***` literals baked into files.
- Manual: `posting version|locate`, `posting run` on fixtures,
  TUI smoke in tmux (config theme applied, pickers, warnings).
