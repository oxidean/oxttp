# ADR-0046 — TUI proxy env capture: named-var pairs + pure `proxy_pick`

- Status: accepted
- Date: 2026-11-27
- Work item: WI-0017 (M4a)

## Context

ADR-0044 put proxy wiring inside `collection.plan_req`, which reads the
process env. `std/os` exposes `getenv(name)` only — no environ
iteration — and tests cannot set env vars. The CLI solves the same
problem with `cli/main.oxl os_envpairs`: read a fixed name list via
`os.getenv` into `"NAME=value"` pairs, then run pure functions over
the pairs (`env_lookup`, sem's proxy capture) — fully testable.

## Decision

1. `core/collection` gains `collect_proxy_env() -> []str` — emits
   `"NAME=value"` pairs for the fixed list (`REQUEST_METHOD`,
   `HTTPS_PROXY`, `https_proxy`, `HTTP_PROXY`, `http_proxy`,
   `ALL_PROXY`, `all_proxy`, `NO_PROXY`, `no_proxy`) via `os.getenv`,
   omitting empty values (unset and empty are indistinguishable —
   repo convention, same as `os_envpairs`).
2. `proxy_pick(proxy_url, pairs)` is a pure function returning the
   three `model.Req` proxy fields (struct return — oxl multi-return
   wants `err` last). All selection logic (explicit `all:` wrap,
   scheme/lowercase name matching, httpoxy guard, NO_PROXY precedence,
   empty-value skipping) lives here and is unit-tested with synthetic
   pairs — no env mutation needed.
3. `plan_req` calls `proxy_pick(proxy, collect_proxy_env())` and
   assigns the fields; the getenv seam is one line and untested by
   design (same coverage class as cli's `os_envpairs`).

## Consequences

- Proxy semantics are pinned by pure unit tests in
  `core/collection`; only the name list itself is untested glue.
- If posting later needs additional proxy env names, they join the
  fixed list in `collect_proxy_env` — pairs format stays stable.
- Consistent with the CLI's envpairs architecture (decision 0015:
  deferral routing and env wiring) — same pattern, second consumer.
