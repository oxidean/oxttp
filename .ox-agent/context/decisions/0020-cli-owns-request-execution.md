# 0020 — cli owns request execution; execute() is the testable seam

Status: accepted (2026-11-17, WI-0006 specification)

S5 wires `Intent` -> `model.Req` -> `core/http.H1` -> xh-shaped
output inside `cli/` (package main): `req.oxl` (intent→request
assembly incl. items, auth, session merge), `print.oxl` (the
printer), `sess.oxl`/`netrc.oxl` (session file IO + netrc), and
`exec.oxl` exposing `execute(intent, envpairs, stdin_bytes,
stdin_tty) -> Run{code, stdout, stderr}`.

Rationale: `resolve()` stays pure (S4 contract); std has no
os.exec, so the golden harness cannot spawn the binary — execute()
is the deepest seam replayable inside `oxl test`. File IO (-o, -d,
session persist, file-item bodies) is real but path-injected:
tests aim them at temp dirs.

`model.Resp` gains `hops: own []Hop` — `{req_head, status, reason,
headers, body, elapsed_ms, remote}` per redirect hop — so
`--all`/`--history-print` works without duplicating h1's redirect
loop. `Transport.send`'s signature is unchanged; transports that
never redirect leave `hops` empty.

Digest auth's extra 401 retry runs inside execute() (cli), not the
transport — matching upstream's middleware split.

Consequence: `--all` interleaves history per upstream's
(prev_response, next_request) pair order; the spec pins the exact
emit order.
