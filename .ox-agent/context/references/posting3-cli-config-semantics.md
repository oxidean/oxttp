# Posting 3 verified CLI/config semantics (S11 reference)

Verified against `/tmp/oxttp-corpus/posting-src` HEAD 32c4566
(v3.0.0-beta.1) + terma v0.27.0. Source of truth remains
docs/corpus/corpus-posting.md; this file records code-level
constants the corpus summarizes.

## argv dispatch (cmd/posting/main.go)

- `args[0]` ∈ {import, locate, remote, run, version, --version,
  -v} → subcommand before flag parse.
- Top flags: `-c/--collection`, `-e/--env` (repeat), `-h`;
  positional arg → `posting: unexpected argument %q` + usage,
  exit 2 (corpus §1.1 documents positional — disagreement).
- `version`/`--version`/`-v` → `Posting <ver>` stdout, 0.
- `locate`: exactly 1 arg; config→"Config file:", collection→
  "Default collection directory:", themes→"Themes directory:"
  label + path; else `Unknown thing to locate: %q` → 2.
- `run` exit 0 pass / 1 fail-or-error / 2 usage. `PASSED|FAILED
  <rel>: <detail>` + `%d passed, %d failed, %d skipped`.
  `--json`: `{results[{file,name,outcome,error?,response?}],
  passed,failed,skipped,error?}` 2sp indent; response =
  remote.Response `{method,url,status,reason?,statusCode?,proto?,
  headers[],trailers?,contentType?,streamError?,body|bodyBase64,
  size,elapsedMs,receivedAt}`.
- `import` usage errors → 2; read/write errors → 1; prints
  `Imported N <format> request(s) into "<dir>"` or
  `Imported N environment(s) into "<dir>"`.
- `remote skill` prints skills/using-posting/SKILL.md with no
  instance needed.

## config.Load (internal/config/config.go)

- defaults < file < POSTING_* env. File unmarshal error (bad YAML
  or wrong-typed value; unknown keys OK) → whole file ignored +
  `Couldn't read <file>: <err>`.
- Env: POSTING_* (case-insensitive prefix), `__` splits nesting,
  empty values + `config_file` skipped; bool fields accept
  1/yes/on/true 0/no/off/false; ANY decode error → all env
  overrides dropped + `Ignoring POSTING_ environment settings:`.
- validate() warns `Unknown <k> %q; using %q` for layout,
  spacing, collection_browser.position, focus.on_startup,
  focus.on_response, focus.on_request_open (allowed sets in
  discovery.md).
- Defaults: theme galaxy; sidebar_gradient theme; theme_directory
  <data>/themes; load_user_themes true; load_builtin_themes true;
  layout vertical; watch_env_files/watch_collection_files/
  watch_themes true; animation "none"; history.enabled true;
  response.prettify_json/show_size_and_time true; heading
  visible/show_host/show_version true, hostname ""; url_bar
  show_value_preview/hide_secrets_in_value_preview true;
  collection_browser left/show_on_startup true;
  command_palette.theme_preview true; text_input.blinking_cursor
  true; pager $PAGER; editor $EDITOR; keymap {}; spacing standard;
  remote_control.enabled true; ssl.* unset; focus.* url/""/"";
  nerd_fonts nil (auto: Ghostty via TERM_PROGRAM/TERM=
  xterm-ghostty/GHOSTTY_RESOURCES_DIR); use_host_environment
  false; use_xresources false.
- themeAlias: ""/posting/textual-dark→galaxy; catppuccin-mocha/
  macchiato/frappe→catppuccin; textual-light→catppuccin-latte.
  Unknown → `Unknown theme %q; using galaxy`.
  sidebar_gradient: theme|off|<theme> else `Unknown sidebar
  gradient %q; following app theme`.
- KeysFor: `keymap` entry replaces defaults; commas split,
  lowercase+trim each key.
- Settings in env files warn: `<file> sets <names>, but settings
  aren't read from environment files. Set them in config.yaml or
  your shell instead.`

## paths (internal/paths/paths.go)

- ConfigFile: $POSTING_CONFIG_FILE→abs else <cfg>/posting/
  config.yaml. ConfigHome=$XDG_CONFIG_HOME(abs-only)|~/.config.
  DataHome=$XDG_DATA_HOME(abs-only)|~/.local/share. DataDir=
  <data>/posting: default/, themes/, history/,
  environments.json. SocketDir=$XDG_RUNTIME_DIR/posting|
  /tmp/posting-<uid>.

## themes (internal/themes + ui/themes.go + terma theme.go)

- 37 builtins = terma registry (28 dark, 9 light). User theme YAML:
  name+primary required; #rgb|#rrggbb|#rrggbbaa; optional dark,
  secondary, accent, background, surface, panel, warning, error,
  success, text, foreground; dark=nil→true. Map: panel→Surface2,
  foreground&text→Text; base = galaxy (dark) / catppuccin-latte
  (light). Same-name overrides builtin. Sorted by name. Bad file →
  `Couldn't load theme <file>: <err>`.
- Picker groups: Yours first, then Dark, then Light (terma
  DarkThemeNames/LightThemeNames order).
- Full builtin hex table extracted to tui/themes.oxl (S11).

## env memory (internal/env/memory.go)

- environments.json `{<abs-coll>: {name,dir} | {files[]}}`.
  Recall named → Stack(dir,name); file-set → all must exist.
  Remember on env switch; empty → delete. Write: MarshalIndent
  2sp + '\n' to <file>.tmp then rename.

## history (internal/history/history.go)

- Path <data>/history/<sha256hex(abs-coll)>.json; sidecar .lock.
  `{version:1,next_id,entries[]}` entries raw JSON w/ id field.
  MaxEntries=100, MaxBytes=50MiB newest-fitting, oversized
  entries dropped; unknown kinds stay.

## env files (main.go environmentFiles)

- No -e given → env.Stack(CWD, "posting") = posting.env +
  posting.local.env if present (P2 fallback).
- -e arg existing file → appended verbatim (repeat re-applies).
- Else env.Named(dirs, name) over [CWD, coll, cfgdir] —
  finds <name>.env/.local.env stack in FIRST dir containing it;
  unknown name → `environment %s is neither a file nor an
  environment in %s`. Base stack of the found dir shares layers.
- Remembered env recalled only when no -e at launch.
