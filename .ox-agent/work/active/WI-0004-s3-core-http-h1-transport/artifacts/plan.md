# WI-0004 implementation plan - S3 core/http h1 transport

Spec: `artifacts/spec.md` (contracts, deviations, AC1-6).
Std surface: `context/references/std-net-transport-surface.md`.
ADRs: 0014 (accept-encoding scope), 0015 (wire encoding in
transport), 0016 (connection close).

## Stages

1. **wire.oxl failing-test matrix** (tdd skill)
   - `core/http/wire_test.oxl` written FIRST against spec'd helper
     signatures: lwr, hdr_get/hdr_has, render_body (all 6 Body
     variants incl. enabled=false KV/Part skips, file parts via
     tmp file, multipart boundary shape), read_head/parse_head
     (1.0/1.1, reason optional, LF-only, malformed, cap), unchunk
     (multi-chunk, ;ext, trailers append, bad size, truncated,
     missing CRLF), read_body exact-N, read_eof, decode_body
     (gzip/zlib/raw-flate/identity/br-err/empty).
   - Fixture gzip/zlib/flate bytes generated offline (python) and
     embedded as byte literals — std has no compressors.
   - Gate: tests compile; every case fails red on missing impl.

2. **wire.oxl implementation**
   - Pure helpers per spec contract. `render_body` uses
     `std/encoding/json` tojson, `std/net/url` queryescape,
     `std/os` readfile_.
   - Gate: `oxl test ./core/http` wire cases green.

3. **fixture server + live failing tests** (tdd skill cont.)
   - `core/http/fixture_test.oxl`: `fx_serve(handler)` —
     `net.listen(0)` + `spawnBlocking` accept loop; per-test
     scripted responses as raw byte strings; captures the raw
     request head+body for assertions; `fx_port`, `fx_url` helpers;
     second listener for cross-origin redirect tests.
   - `core/http/h1_test.oxl`: live matrix per AC4 — GET/HEAD/POST,
     custom headers, chunked, trailers, gzip/deflate, redirect
     (relative/absolute/cross-origin-strip/max/bad-Location/
     https-target/follow-false), 1xx skip, 204, truncated CL,
     timeout, port-satisfaction `let tr: Transport = H1{}` pin.
   - Gate: tests compile; live cases fail red (send() missing).

4. **h1.oxl implementation**
   - `struct H1{}` + `send` per spec §send contract (steps 1-7):
     url parse/guards, userinfo→Authorization, serialization order,
     dial+deadline wiring (dial vs dial_timeout, sndtimo, re-armed
     rcvtimo), `rt_sigpipe_ignore` once, 1xx-skip head read, body
     per framing precedence, decode_body, Resp fill (status/reason/
     headers+trailers/body/elapsed/remote/trace), redirect loop
     (method rewrite, header strips, resolve_reference,
     max-redirects + error shapes).
   - Gate: `oxl test ./core/http` fully green; `oxl build ./cli`,
     `oxl build ./tui` green.

5. **Wrap-up**
   - `oxl fmt` check on touched files; per-dir test loop per
     test_command; findings updated (upstream gaps verbatim);
     commits `feat(http): ...` conventional form, zero AI
     attribution; ship per the WI pipeline.

## Dependencies

- `core/http` → `core/model` (Req/Resp/Header/Body/KV/Part),
  `std/{net,io,bufio,bytes,errors,strconv,strings,os,time}`,
  `std/compress/{gzip,zlib,flate}`, `std/encoding/{json,base64}`,
  `std/net/url`. No shared/, no cli/tui imports — stays inside the
  core module.
- S2 (WI-0003) merged: model + port exist. S4 (WI-0005) is
  parallel — no cli changes needed here.

## Risks

- Multipart boundary: pick a fixed-format boundary
  (`oxttp-boundary-<n>` style constant per request — corpus only
  requires a valid boundary; tests assert shape not randomness).
- `deflate` ambiguity: zlib-then-flate fallback — test both.
- Redirect on 307/308 with FileBody: re-render body per hop (file
  re-read — acceptable v0.1).
- Fixture determinism: accept-loop races — use `listen(0)`,
  `l.port()`, readiness is implicit (dial blocks until accept).
  `set_rcvtimo` on fixture accept/read fds keeps stuck tests
  bounded.
- `spawnBlocking` task lifetime: fixture handlers must not outlive
  the test — conn close ends each handler.
