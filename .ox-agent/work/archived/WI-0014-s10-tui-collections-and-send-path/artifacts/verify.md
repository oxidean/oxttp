# WI-0014 verify — S10 TUI collections + send path

Date: 2026-11-26. Verifier: verification-stage run (manual adapter).

## Test command (config.yaml `project.test_command`)

`for d in $(git ls-files '*.oxl' | xargs -n1 dirname | sort -u); do oxl test $d || exit 1; done`

| dir | rc | pass | fail |
|-----|----|------|------|
| cli | 0 | 156 | 0 |
| core/collection | 0 | 43 | 0 |
| core/env | 0 | 15 | 0 |
| core/http | 0 | 44 | 0 |
| core/item | 0 | 9 | 0 |
| core/model | 0 | 3 | 0 |
| core/session | 0 | 6 | 0 |
| core/term | 0 | 28 | 0 |
| core/yaml | 0 | 12 | 0 |
| shared/args | 0 | 15 | 0 |
| shared/version | 0 | 0 | 0 (no tests) |
| tui | 0 | 195 | 0 |

**526 tests, 0 failures.** `oxl build ./tui` and `oxl build ./cli` both
clean (cli untouched — regression-proof by its suite).

## Acceptance criteria (spec.md)

- `oxl build ./tui` + `./cli` clean — yes.
- `oxl test <dir>` green per leaf (loop, not multi-arg) — yes, table above.
- core/yaml: fixture corpus parses; marshal(decode(x)) stable; subset
  errors carry line numbers — covered by yaml_test (12) + collection
  fixture scan.
- core/env: dotenv edges, layer precedence, substitute rules incl.
  `$$`, unresolved-in-url vs passthrough, limits, generated values —
  covered by env_test (15) inside the tui dir run too.
- core/collection: decode schema blocks, exactly-one body, encode
  omitempty, plan_req options/auth/bodies/params/cookies, degrade
  errors — covered by load_test (43).
- tui: open-into-draft roundtrip, preview-tab reuse + pin-on-edit,
  multi-open, dup/delete/save on a /tmp scratch copy, tree filter,
  env-switch rebuild, variables masking + reveal, URL preview
  substitution/masking/unresolved, plan→ESend, exec_send install on a
  fabricated Resp (body/JSON re-indent/headers/cookies/trace/title
  meta/jar/history), send_failed, history cap/newest-first/open/
  delete — coll_test 14 + send_test 10.
- Golden: no socket tests — exec_send exercises a fake Transport
  (exec_send_t seam); real-network smoke is manual (below).
- Parity matrix §5/§6/§7.1 flipped — `.ox-agent/context/specs/
  parity-matrix.md`.

## Root-cause note (the stalled crash)

`len()` on a nil `own []Hop` traps: oxl auto-derefs the own handle for
len/index/view (docs/semantics/slices.md), so `len(resp.hops)` on a
nil handle is a nil-pointer deref — silent exit 1, no diagnostic.
`install_resp` now nil-checks and emits the hops row only when >0
(spec wording). Production path: `h1.send` left `hops`/`req_head`
unset on the redirect-without-Location early return — now populated
like the main return, which also covers `cli --all`'s `resp.hops[:]`.

## Manual tty smoke (headless — procedure, not executed)

This environment has no tty; the interactive pass is for a real
terminal:

1. `python3 -m http.server 8000 &` in a scratch dir with a file or two.
2. `oxl run ./tui tests/tui-fixtures/small-app` — sidebar shows
   `requests/` tree with req names from `name:` keys, `bad`/`malformed`
   row dimmed, env row `(none)` under the pane title.
3. Cursor `Get users` → `enter` — draft loads: url/method/headers/
   params/body; tab title "Get users"; italic preview. Type in the URL
   bar — tab pins. `enter` on `Create user` — new preview tab.
4. `ctrl+shift+v`? no — env modal: `e`/`env-switch` palette command or
   the bound key — pick `dev` → toast `environment: dev (N vars)`;
   variables screen shows `WHO = devlocal [dev.local.env]` masked
   secrets; `ctrl+r` reveals.
5. URL bar on `$BASE/users` (create-user draft) — preview row shows
   `http://example.test/users`; with no env shows `(unresolved $…)`.
6. `ctrl+j` — "Sending…" frame paints, then response installs: title
   `response · 200 OK · <size> · <ms>` colored green; Body shows JSON
   re-indented; Headers/Cookies/Trace tabs list rows; Trace shows the
   7 stage timings.
7. History (`4` via ctrl+o jump, or its binding) — newest-first rows;
   `enter` opens the as-sent tab; `backspace` removes.
8. `ctrl+s` save modal — name `Smoke Req`, folder field `smoke` →
   writes `smoke/smoke-req.posting.yaml`; `d` on the new row dups it
   as `smoke-req (copy)`; `backspace` + `y` deletes it.
9. `ctrl+g` types into the sidebar `/` filter — non-matching rows hide
   (ancestors stay); `enter` commits, `escape` clears.
10. `ctrl+c` quits; `oxttp-tui --help` prints the banner and exits.

## Rollback

Revert `feat(tui): S10 collections and send path` slices on this
branch; cli is untouched so the CLI surface is unaffected.

## Deviations carried (spec.md list)

Synchronous send (no escape-cancel), YAML subset (anchors/tags/flow/
multi-doc = malformed-file errors), `posting/<ver>` UA token, jar-lite
(no RFC6265 scoping), memory-only history cap-100, session-only env
persistence + coll-dir-only env search, save-overwrite confirm,
read-only auth/options panes, `--env` seeds session env, substitute
limits on bodies, no 64MB response cap, generated values included.
