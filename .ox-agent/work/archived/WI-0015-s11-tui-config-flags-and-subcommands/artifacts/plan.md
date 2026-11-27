# WI-0015 plan — S11 config, flags, subcommands

Direction: spec.md + ADR-0034..0038. TDD order — tests land with
or before each unit's code (pipeline enforces).

## Stage A — core/config (leaf)

1. `core/config/config.oxl`: Settings struct (40 fields), paths
   helpers, `defaults()`, `load(file, getenv, environ)->[Settings,
   warns]`, `validate()`, `keys_for()`. Decode off core/yaml.
   `environ` arg = []str "NAME=value" pairs (prod: the 40 known
   POSTING_* names probed via getenv — helper `posting_env_pairs
   (getenv)` builds them).
2. `core/config/config_test.oxl` FIRST: defaults spot-checks;
   file cases (full map incl. nested sections + keymap,
   bad-yaml → defaults+warn, wrong-typed key → defaults+warn,
   unknown key tolerated, missing file silent); env cases (`__`
   nesting, bool spellings ×8, bad value nukes all, empty skip,
   POSTING_CONFIG_FILE skip); validate warnings ×6; keys_for
   (absent→defaults, blank→defaults, comma list, lower+trim);
   paths (XDG abs-only fallbacks, POSTING_CONFIG_FILE→abs).

## Stage B — themes

3. `tui/themes.oxl`: Theme struct (8 ANSI slots), `quantize(hex)`,
   37-entry builtin table, `theme_alias`, `parse_user_theme`,
   `scan_user_themes`, picker row builders.
4. `tui/themes_test.oxl`: quantize exact primaries + edges;
   catalog count/order/split; user parse valid/missing-primary/
   bad-hex/dark-false-base; scan sort + same-name override +
   problem strings.

## Stage C — cli surface

5. `tui/cli.oxl`: `cli_dispatch`, run arg parse + selection +
   send loop (fake-transport seam like exec_send_t), report emit
   (text + --json via json builders), locate/version/import/
   remote handlers, embedded SKILL.md const.
6. `tui/cli_test.oxl`: arg-parse matrix → exit codes; locate
   outputs; run selection rules (malformed abort, scripts, sort);
   run loop via fake transport (counts, fail-fast, captures
   degrade, json shape fields); remote degrade map; skill emits
   non-empty SKILL.md with frontmatter.

## Stage D — app wiring

7. `tui/cfg.oxl`: `apply_settings`, `posting_env_pairs`, rebind
   table builder (action→[]KeyPat via parse_key), env memory
   recall/remember, disk history load/append (sha256 path,
   lock sidecar, JSON envelope), `resolve_tools` (editor/pager/
   pager_json + POSTING_* env overrides).
8. `tui/cfg_test.oxl`: field mapping asserts; rebind replace +
   bad spec warn; env memory round-trip (tmp+rename via tmpdir);
   history write→load round-trip + caps + enabled=false;
   focus.on_response/on_request_open moves.
9. `tui/types.oxl`/`app.oxl`: App fields (settings-owned: theme,
   gradient, nerd_fonts, blink, heading/url_bar/focus opts,
   hist_disk, ssl fields, tool cmds, rebinds map, pickers state,
   vars-edit state, ext_cmd, env_active_file flag); modal kinds
   MTheme/MGradient/MCurl/MSaveResp/MVarsEdit? (reuse one edit
   modal shape); dispatch arms; queued-degrade replacements:
   vars enter/a/d → session layer ops; folder delete → confirm +
   remove_all; URL `$` → suggestions list; URL enter curl →
   import_curl apply; f3/f4 → ext_cmd effect; palette rows
   updated (Theme…→MTheme, Sidebar gradient…→MGradient, Import
   curl…→MCurl, Save response→MSaveResp).
   `global_bindings()` consults rebinds first.
10. `tui/coll.oxl`: env dirs [CWD,coll,cfgdir]; remembered env
    at launch; history hooks; focus moves; curl arm; folder arm.
    `begin_send_preq` applies ssl.* into plan (cert reads eager,
    errors → warns); `install_resp` honor prettify/size+time/
    focus.on_response/disk history.
11. `tui/render.oxl`: slot fgs via a.theme; heading config; URL
    preview gate; pickers + curl/save/vars-edit modals render;
    gradient ramp on sidebar; nerd icon slots.
12. `tui/main.oxl`: subcommand dispatch first; then top-level
    Spec parse (help/version exit paths preserved); settings
    load → apply → startup toasts; ext_cmd effect in loop.

## Stage E — verify

13. Build all dirs; per-dir oxl test loop; tmux smoke (TUI
    starts with fixture config, pickers, toasts); `git diff`
    scan for `***`; corpus checklist 40/40 in spec verified
    against code; parity-matrix rows updated (§1, §2 → done/
    partial notes); changelog/PR body.

## Commit order

A(core/config+tests) → B(themes+tests) → C(cli+tests) →
D(app wiring+tests) → E(fixtures+docs+matrix). Commit subjects
`feat(tui): …` / `feat(core): …` per commit-check.
