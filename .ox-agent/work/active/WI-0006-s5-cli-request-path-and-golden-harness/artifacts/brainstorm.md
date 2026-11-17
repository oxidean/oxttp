# WI-0006 brainstorm — request path + golden harness shape

Settled upstream: `Intent` is the seam (S4 spec), `core/model` is the
domain vocabulary, `core/http.H1` is the transport, degrade
explicitly (0006), differential vs real xh (0007). Discovery pinned
the upstream run() order — this brainstorm picks the execution
architecture, history-hops mechanism, scope cuts, and the harness
design.

## Option A — cli-side exec pass on a pure core (CHOSEN)

New files in `cli/` (package main):
- `req.oxl` — Intent → `model.Req`: items → headers/params/body
  (json/form/multipart/file/raw + stdin body), replace_headers
  semantics, auth (arg/session/netrc), session merge, compress.
- `print.oxl` — the printer: request/response head render (titlecase
  names, reason phrases), verbatim body handling, meta line,
  separator rule, binary suppressor, latin1 value annotation,
  download/-o destinations, progress lines.
- `sess.oxl` — session file IO (load/persist + cookie jar-lite +
  HTTPie migrate) and `netrc.oxl` — the ~/.netrc parser.
- `exec.oxl` — `fn execute(i: ref Intent, env: []str, stdin: []byte,
  stdin_tty: int) -> own Run`: orchestrates build → optional
  offline-print → transport → per-print-set output assembly.
  Returns `Run{code, stdout: []byte, stderr: []byte}`; file writes
  (-o/-d/session) go through real os IO inside execute (callers in
  tests point them at temp dirs — same seam xh itself uses).
- `main.oxl` — after `resolve()`: when `o.exec` set, detect stdin
  TTY via the `/dev/stdin` fullpath heuristic, read stdin when
  redirected, call execute(), write streams, `os.quit(code)`.

Pros: keep `resolve()` pure (S4 tests untouched); every upstream
behavior reachable in `oxl test` via `execute()` — including the
golden harness which CANNOT spawn a process (no os.exec in std);
file IO isolated to three call sites. Cons: `execute` is a big fn —
mitigated by splitting into `req.oxl`/`print.oxl` pure helpers with
their own unit tests.

## Option B — core/request package for item→Req assembly (REJECTED)

Move item→body/headers into `core/request`. The mapping needs cli
types (Intent, env pairs, session/auth/netrc state) — pushing them
into core couples the domain package to CLI specifics (S1/S2
boundaries stay clean; decision 0016 keeps cli semantics in cli).
Rejected — core stays transport-agnostic; assembly lives in cli.

## Option C — harness drives the built binary (REJECTED)

std has no os.exec/process spawn, so an `oxl test` harness cannot
run the compiled oxttp. The honest seam is `execute()` — argv→Intent
parsing is S4's shipped gate; Intent→streams/exit is S5's. The
generator script still runs real `xh` + real `oxttp` binaries at
author time so fixtures capture true end-to-end xh bytes; the oxl
replay then diffs `execute()` output against them (same argv/stdin/
env). Rejected as the test mechanism; kept as the generation path.

## Sub-decisions

1. **History hops for --all**: extend `model.Resp` with
   `hops: own []Hop` where `Hop{req_head: own ReqHead, status,
   reason, headers, body, elapsed_ms, remote}` (`ReqHead{method,
   uri, headers}`). H1.send fills it during its redirect loop;
   Transport signature unchanged; --all prints hops per
   --history-print then the final resp per --print. Alternative
   (cli re-follows redirects) duplicates the h1 loop — rejected.
2. **Digest auth**: implement. md5 is in std; the flow is
   request→401+WWW-Authenticate→digest Authorization retry (one
   extra hop inside cli exec, not the transport — upstream does the
   same via middleware). Falls back to explicit degrade only if
   blocked mid-implementation; spec pins which qop variants are
   covered (auth only — auth-int/MD5-sess rare).
3. **Cookie jar**: jar-lite — name-keyed map attached to the
   request, updated by Set-Cookie on every hop, emitted as
   `Cookie:` on subsequent hops + display; no path/domain/expiry
   matching this stage (session cookies carry path/domain fields
   but jar match is host-only). Deviation recorded vs RFC 6265 —
   upstream jar is reqwest's; matching it fully is S7+.
4. **Sessions**: full load/persist per session.rs — headers list
   (minus cookie/content-*/if-*), auth {type,raw_auth}, cookies
   list→jar-lite, HTTPie map-migration, `<config>/sessions/
   <host>[_port]/<name>.json` naming, persist-after-response
   (incl. on 3xx/4xx/5xx failures — upstream persists on any
   response; NOT on transport error).
5. **netrc**: implement — parser is ~120 lines, corpus-pinned
   ($NETRC > ~/.netrc > ~/_netrc; machine/default/login/password/
   account/#comment/macdef-skip; host match incl. `default`;
   suppress-default-after-machine).
6. **--compress**: implement — zlib deflate exists in std; rule:
   skip+warn on Content-Encoding header; skip when out>=in unless
   -xx; sets `Content-Encoding: deflate`.
7. **--curl/--generate**: keep degrading (S7 — big tables, no
   request-path dependency).
8. **--download/-o/--continue**: implement — dest = -o file
   (truncate|append-resume) else stdout; headers+progress to
   stderr (`Downloading <b> to "<dest>"`/`Done. <b> in %.5fs
   (<r>/s)`); Range resume; 416 → already-complete exit 0;
   incomplete-body error.
9. **verify/cert/cert-key/ssl/native-tls**: parse-inert for http://
   (upstream: TLS-only knobs, unused on cleartext — no degrade
   needed, spec notes why). --http-version: 1.0/1.1 → h1 request
   line version + `Connection: keep-alive` (hmm — our transport
   sends `close`; upstream sends `keep-alive` header; wire version
   `HTTP/1.0` honored); `2|2-prior-knowledge` → explicit degrade
   (h2 unsupported); `3-prior-knowledge` keeps its corpus-pinned
   error.
10. **--resolve/--interface/--ipv4/--ipv6/--unix-socket/--proxy/
    proxy-env**: degrade explicitly per 0006 (connection-layer;
    corpus message per flag family, spec pins texts).
11. **stdin**: `/dev/stdin` fullpath heuristic — `/dev/pts/*`,
    `/dev/tty`, `/dev/console` → TTY → skip read; else read
    (pipe→"" path → not a TTY → read). Deviation documented:
    upstream is_terminal(); heuristic is POSIX-shaped.
12. **Pretty/style/format-options/response-charset/response-mime/
    --stream/--debug/--ignore-stdin(honored)/--ignore-netrc/
    --history-print**: parse-level honored or display-inert this
    build (no TTY → pretty=none, formats/colors unreachable);
    spec lists each flag's disposition — inert is only acceptable
    where upstream output is byte-identical for non-TTY too.
13. **Golden harness layout**: `tests/golden/` — `golden.oxl`
    (runner lib: fixture server adapted from core/http's Fx,
    case loader, normalizer+comparator), `golden_test.oxl`
    (drives `execute()` per committed case), `cases/*.yaml`-ish
    case files (simple kv format — name/argv/stdin/env/script/
    files), `fixtures/<case>.{stdout,stderr,exit}` committed
    author-time captures from REAL xh 0.26.3 (+ the scripted
    server request echoes). `scripts/golden-gen.sh` regenerates
    via real xh + real oxttp binaries; `OXTPP_XH=<path>`
    env enables live-diff mode in the test.
14. **Normalization**: comparator maps both sides through a
    normalizer: `xh`→`<PROG>`, `oxttp`→`<PROG>` (prog name);
    `xh/0.26.3`/`oxttp/*`→`<UA>`; `gzip, deflate, br, zstd`→
    `<AE>`; `keep-alive`/`close`→`<CONN>` (AE+Conn are ADR'd
    deviations); elapsed/remote/date/multipart-boundary →
    placeholders. Anything still divergent → declared deviation in
    spec or a bug — never silently normalized away.

## Open questions for spec

- Exact degrade message texts per deferred flag family (spec pins
  one corpus-shaped line each).
- Session-header merge position (session headers extend BEFORE
  item headers — verify position semantics in spec tests).
- Whether `Run.files` is real IO or captured — CHOSEN real IO into
  caller paths; tests use tmp dirs (golden cases assert on file
  contents/exit/streams anyway).
- `--history-print` intermediate meta — does `m` in hist set print
  per-hop meta? (Upstream: yes, inside the with_printer loop —
  pin in spec.)
