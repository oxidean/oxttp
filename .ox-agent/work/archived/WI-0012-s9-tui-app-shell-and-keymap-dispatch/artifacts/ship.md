# WI-0012 ship readiness — S9 TUI app shell + keymap dispatch

## What ships

`oxttp-tui` now boots the Posting-compatible shell on the S8 term
driver: header / URL bar / collection sidebar / request & response
panes / footer, modal overlays (help, palette, variables, confirm,
save, tab-search, history, method menu, jump, env), and layered
keymap dispatch (modal > widget > global > fixed) covering the
corpus §3 ~114 bindings as 164 bound actions / 277 table rows.
Input decoder handles UTF-8, CSI/SS3/kitty-u, SGR mouse; degrade
paths toast instead of silently ignoring.

## Evidence

- verification verdict `pass` (run run_1795643690403_5fa4a1):
  project test_command over all 10 .oxl dirs green; 58 tui +
  24 term tests; `oxl build tui`/`cli` rc=0.
- code-review `pass_with_notes`: bounds/index/hit-rect fixes landed
  in 45db4bd; no blocking findings.
- ADR-0028 (flat App + layered keymap) recorded; parity matrix
  Posting §3 → done, §4 → partial.

## Rollout / rollback

Touches tui/ (new shell), core/term (decoder + open/close seqs),
parity matrix + work-item state. Rollback = revert the merge; the
cli/ and core/http surfaces are untouched. Non-tty fallback prints
the one-line banner, so CI/scripts never enter raw mode.

## Outstanding gate

shipping → shipped is human-approved (policy.yaml). Escalating;
fires on PR merge. Manual tty smoke recommended at merge time.
