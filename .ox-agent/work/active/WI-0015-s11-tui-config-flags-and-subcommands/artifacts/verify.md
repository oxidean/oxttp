# WI-0015 verify — S11 TUI config, flags, and subcommands

Date: 2026-11-26. Verifier: verification-stage run (manual adapter).

## Test command (config.yaml `project.test_command`)

`for d in $(git ls-files '*.oxl' | xargs -n1 dirname | sort -u); do oxl test $d || exit 1; done`

| dir | rc | pass | fail |
|-----|----|------|------|
| cli | 0 | 190 | 0 |
| core/collection | 0 | 54 | 0 |
| core/config | 0 | 35 | 0 |
| core/env | 0 | 16 | 0 |
| core/http | 0 | 64 | 0 |
| core/item | 0 | 9 | 0 |
| core/model | 0 | 3 | 0 |
| core/session | 0 | 6 | 0 |
| core/term | 0 | 28 | 0 |
| core/yaml | 0 | 18 | 0 |
| shared/args | 0 | 15 | 0 |
| shared/version | 0 | 0 | 0 (no tests) |
| tui | 0 | 280 | 0 |

**718 test lines, 0 failures.** `oxl build ./cli`, `oxl build ./tui`,
`oxl build ./core` clean.

## Acceptance criteria (spec.md)

- `oxl build ./core ./tui ./cli ./shared` clean on pin — yes.
- Per-dir `oxl test` green — yes, table above.
- core/config: defaults spot-checks, file decode (full/bad-yaml/
  wrong-type/unknown-key/empty), env merge (`__` nesting, bool
  spellings, bad-value nuke-all, config_file skip, empty skip),
  validate warnings ×6 enum keys, keys_for replace, paths (XDG
  abs-only, POSTING_CONFIG_FILE) — config_test (35).
- tui/themes: quantize bounds, builtin count 37 + dark/light split,
  user parse cases, scan sort + same-name override + problem text —
  themes_test (10 fns).
- tui/cli: locate outputs+exit codes, run parse errors→2, run
  file/dir selection (malformed abort, scripts reject, sort), run
  send via fake transport (counts, captures degrade, --json shape),
  remote list/skill/other degrade, import degrade codes —
  cli_test (6 fns).
- tui/cfg: apply_settings field mapping (focus/layout/sidebar/
  heading/preview/remote-message), rebind replace + bad-spec warn,
  env-memory recall/remember round-trip, disk history write+load
  round-trip + enabled=false memory-only, variables edit/add/revert,
  folder delete, curl import subsets (data/json/form/auth/flags/
  errors) — cfg_test (13 fns, added this stage at 3860a57 — the
  file the plan's step 8 calls for had not been written when this
  stage ran; gap found and closed here).
- keymap: rebind end-to-end (custom key dispatches action, defaults
  gone) — cfg_test `test_rebind_end_to_end_dispatch` (f9 dispatch
  toggles; replaced ctrl+h inert).
- Transcript-style: startup with bad config → warn toasts +
  defaults (`test_apply_settings_warns_and_defaults`); theme picker
  enter/escape (`test_theme_picker_enter_escape`); env switch
  persists environments.json (`test_env_memory_roundtrip`).
- `git diff` byte-check — zero `***` literals in tree (swept).
- Manual: `posting version` → `Posting 0.1.0-dev`; `posting locate
  config|collection|themes` → correct XDG paths (bad arg → exit 2);
  `posting run` on a scratch collection → FAILED line + exit 1 on
  refused connect, `--json` emits the report shape, fixture dir
  with malformed.posting.yaml aborts the run before any send.
  TUI smoke in tmux: deferred — no tmux in this environment
  (same class of manual deferral WI-0014 recorded for live-network
  smoke).

## Review findings (severity-ranked, cited in run output)

- minor — tui/cli.oxl:91 — `posting remote` usage advertises
  `[--instance NAME]` but the parser never handles the flag; its
  value is consumed as the command name. Harmless while remote
  degrades; fix when sockets land.
- minor — tui/cli.oxl:186 — bool flags `--fail-fast`/`--json`
  silently accept a `=value` suffix (`--json=false` still enables);
  upstream flag parsing honors the value.
- info — tui/cli.oxl:539 — `is_utf8` approximates validity by NUL
  check only; binary bodies without NUL get JSON-escaped rather
  than bodyBase64'd. Documented approximation in code comment.
- info — tui/cfg.oxl:553 — history `.lock` sidecar is create/remove
  advisory only (no flock) — deviation already documented in the
  cfg.oxl header comment.
- info — tui/cfg.oxl:530 — `hist_write`/`remember_save` leave a
  `.tmp` file behind when `writefile_` fails (rename skipped) —
  harmless residue, next successful write replaces it.

## Deferred / noted

- TUI smoke in tmux — deferred (no tmux available; manual item).
- Upstream parity notes: `posting run` counts 3xx-class responses
  as PASSED (status_class error is ==2/≥400); remote/unix-socket
  and imports degrade with corpus messages until their milestones.
