# ADR-0044 — TUI proxy surface: `plan_req` owns `proxy_url` + env capture

- Status: accepted
- Date: 2026-11-27
- Work item: WI-0017 (M4a)

## Context

Corpus posting §7.1: "Proxy: `proxy_url` else env
`HTTP(S)_PROXY`/`NO_PROXY`." Until now `collection.plan_req` detected a
non-empty `options.proxy_url` and emitted the warn "proxy unsupported
in this build — sending direct", dropping it (S10 partial, parity
matrix §7.1). WI-0013 gave the transport the full machinery
(`Req.proxies`/`proxy_env`/`no_proxy` → `pick_proxy` + CONNECT) and the
CLI wires it in `sem.oxl`; the TUI never populated the fields.

`pick_proxy` (core/http/h1.oxl) splits each `proxies` entry on the
FIRST colon as `PROTO:URL` — a bare `http://host:port` would misparses
(proto `http`, remainder `//host:port`). posting's `proxy_url` is a
single scheme-full URL with no protocol tag and §5.2 scopes it to all
requests.

## Decision

1. `plan_req` is the single wiring point for both the interactive send
   (`coll.oxl send_plan`) and headless `run` (`cli.oxl`) — it already
   imports `std/os` and builds the whole `model.Req`.
2. `proxy_url` non-empty → `req.proxies = ["all:" + trim(proxy_url)]`
   and env capture is skipped entirely (corpus "else"; mirrors xh
   `--proxy` disabling ALL/HTTP/HTTPS_PROXY, corpus-xh §4.5).
   Surrounding whitespace is trimmed; interior text is verbatim.
3. `proxy_url` empty → per-send env capture via `os.getenv`:
   `HTTPS_PROXY`/`https_proxy`, `HTTP_PROXY`/`http_proxy`,
   `ALL_PROXY`/`all_proxy` → `req.proxy_env` as `NAME=value` (non-empty
   values only; pick_proxy already treats explicit-empty as unset and
   falls through to `all_proxy`), `NO_PROXY`/`no_proxy` →
   `req.no_proxy`. Per-send reads match Go's per-request
   `ProxyFromEnvironment`.
4. httpoxy guard: `REQUEST_METHOD` set ⇒ skip the `HTTP_PROXY` entries
   (both cases) — same rule cli/sem.oxl applies, keeping the two
   binaries' env semantics aligned.
5. Invalid proxy URLs are not pre-validated in plan_req; the transport
   reports `http: invalid proxy URL` / scheme degrades at send time —
   corpus puts client/proxy problems at send time.

## Consequences

- The "proxy unsupported" warn branch is deleted; `plan_req` warns
  nothing for proxy anymore.
- `options.proxy_url` survives draft edits already
  (`draft_to_request` carries `options` verbatim).
- gRPC requests can't carry `proxy_url` per §5.2 — decode rules
  unchanged; if a file smuggles one, plan applies it only to HTTP-kind
  sends (verify at spec; kind gating is a plan_req concern).
- Env proxy now affects EVERY TUI send in proxy-equipped environments —
  intended corpus behavior, but a behavior change vs S10's always-
  direct sends; called out in the spec's behavior-delta section.
