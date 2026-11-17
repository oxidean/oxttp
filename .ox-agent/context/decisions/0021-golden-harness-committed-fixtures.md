# 0021 — golden harness: committed xh fixtures + normalized replay

Status: accepted (2026-11-17, WI-0006 specification)

`xh` is not installable in CI, so the differential harness replays
committed fixtures instead of a live binary:

- `tests/golden/` holds a case table (argv, stdin, env, scripted
  server script), expected captures `fixtures/<case>.{stdout,
  stderr,exit}`, and a `golden` package (`golden.oxl` runner +
  `golden_test.oxl`) that drives `execute()` per case against a
  local scripted server (the core/http `Fx` pattern).
- `scripts/golden-gen.sh` regenerates fixtures at author time by
  running REAL `xh 0.26.3` (release tarball) and the built `oxttp`
  against an equivalent local server. `OXTPP_XH=<path>` turns the
  oxl test into a live-diff mode when a binary is around.
- A normalizer maps both sides before diffing: prog name
  (`xh`/`oxttp` -> `<PROG>`), UA version, the `br, zstd`
  Accept-Encoding tail and `keep-alive`/`close` (ADRs 0017/0019),
  volatile values (elapsed, remote addr, Date/Server, multipart
  boundary). Anything still divergent must be a declared deviation
  or a bug — normalization never hides a corpus difference.

Consequence: CI green requires no network and no xh; author-time
regeneration needs only the release tarball.
