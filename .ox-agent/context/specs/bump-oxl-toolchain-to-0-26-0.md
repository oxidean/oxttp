# WI-0011 spec — pin oxl 0.26.0

## Scope
- `.oxl-version`: `0.23.2` → `0.26.0`. Single-line diff.
- Compat fixes ONLY if build/tests fail — verified unnecessary on this
  branch (clean build, full per-dir test loop green, golden harness
  green, --version/--help smoke xh-faithful).
- Update `context/specs/parity-matrix.md`: `Updated:` pin line; flip the
  rows 0.26.0 unblocks from `oxl-blocked` → `next` with the consuming WI
  cited (`--cert/--cert-key`, `--ssl`, `--native-tls`, CONNECT, h2 →
  WI-0013; ws/grpc → M4). `--http-version 3*` stays `oxl-blocked` — no
  consumable std surface despite oxl#219 closing.

## Non-goals
- No adoption of std `net/http` client (ADR-0003), no API migrations,
  no flag wiring (WI-0013), no TUI work (WI-0012 owns it).

## Acceptance criteria
1. `.oxl-version` = `0.26.0`; `oxl version` resolves it.
2. `oxl build ./cli`, `oxl build ./tui` clean.
3. Per-dir `oxl test` loop: every dir green on 0.26.0.
4. parity-matrix.md reflects the new unlock set + h3 caveat.
5. PR green: commit-lint + oxl-build (CI self-installs the pin).
