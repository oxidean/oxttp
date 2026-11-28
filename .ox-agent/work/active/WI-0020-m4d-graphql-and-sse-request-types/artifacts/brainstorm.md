# WI-0020 brainstorm — M4d GraphQL + SSE

Divergent analysis over the five open questions from discovery;
convergent recommendation at the end. Prior art: WI-0013..WI-0019
established the pattern — corpus-faithful semantics with recorded
deviations where the single-threaded TUI/transport model forces them
(decision 0006 explicit degradation, corpus-fidelity standard).

## Q1 — SSE delivery: buffered-at-EOF vs live streaming

**Option A — buffered parse at EOF.** `Transport.send` keeps its
synchronous signature; h1 `finish_roundtrip` detects
`text/event-stream`, lifts the post-header deadline (shared deadline
cell or reader swap), reads the body under the 64 MB cap, then runs
the SSE parser over the decoded bytes into `Resp.events`. The TUI
Messages tab renders the complete event list; `f`/follow and `enter`
inspect work on the static list.

- Pros: no transport/UI restructuring; parser is pure and unit-
  testable; identical semantics for event capture, `id`, `streamError`,
  caps, raw body; fits the existing send-on-UI-thread model; CLI/run
  paths get events for free.
- Cons: "followed live" is not literally true — events appear only
  when the stream closes or hits a cap; an infinite stream hangs the
  send exactly like upstream *would* if unwatch... except upstream
  paints incrementally. Long-lived streams (SSE is designed for them)
  never complete → user sees nothing until escape/timeout — this is a
  real UX gap, not just cosmetic.

**Option B — spawned reader + channel into the UI.** Send returns
immediately after headers; a `spawn`ed task (or `spawnBlocking`)
incrementally reads the socket, parses events, and pushes them over a
`chan own model.StreamEvent` into the TUI paint loop, which appends
Messages rows and respects follow/unread.

- Pros: true live follow; escape can cancel the reader; matches
  upstream UX most closely.
- Cons: `Transport.send` is a synchronous interface method — cannot
  suspend, and the send path is invoked synchronously from the UI
  thread (`exec_send_t`). Making send async requires either a second
  interface (send_begin/send_poll) implemented by h1+h2, or running
  the whole send on a spawned task and channeling the final Resp —
  either way the response-pane install path, history write, capture
  evaluation, and `run --json` output all need an async completion
  path. oxl `chan own T` exists and gui uses it, so the mechanism is
  proven, but the blast radius is every send call site.

**Option C — hybrid: blocking incremental read with periodic
repaint.** Keep `send` synchronous but have it pump events into a
shared cell the UI polls between paint frames. Requires the send to
yield — impossible synchronously on one thread; equivalent to B with
extra steps.

**Disagreement preserved:** A is the cheap 80% (all corpus *data*
semantics: event capture, id, streamError, caps, raw body, Messages
tab, follow/inspect keys) but fails "followed live" for streams that
never close; B is corpus-faithful UX but touches the transport
interface contract every transport implements.

**Lean:** A for this WI, with the deviation recorded: "SSE events are
parsed at stream end (or cap); live incremental paint deferred —
upstream 'followed live' becomes 'complete on close'". If review/verify
finds the hang unacceptable, B becomes its own follow-up WI (M4e
grpc/websocket will need the same async machinery anyway — WS/gRPC
are interactive streams where buffering is impossible).

## Q2 — `PGraphQL.variables` representation

Upstream stores `variables` as a scalar string (`yamlString`) and
compacts/splices at document-build time. Our decode currently produces
a JSON node.

- **A — change to `str`:** decode scalar → str; encode back as scalar.
  Matches upstream exactly; TUI Variables tab edits raw text; strict
  decode still rejects maps. Cost: existing tests asserting node shape
  (`load_test.oxl` vars-json checks) need updating; YAML with a map
  `variables:` becomes a decode error — matches upstream strictness.
- **B — keep node, serialize at plan time:** less churn now, but the
  TUI editor would have to edit JSON-as-text anyway and round-trip
  node→text→node; upstream's verbatim-splice semantics (invalid JSON
  kept raw) are awkward through a node.

**Lean: A.** It is the upstream representation and simplifies both
editor and document builder.

## Q3 — Jump letters for GraphQL's 8 tabs

Upstream letters are per-tab fixed (`i` Query, `o` Variables, then
shared `q e r t y u`). Ours are positional `jump-0..6` → q w e r t y u.

- **A — positional for all kinds:** zero new machinery; GraphQL's 8th
  tab has no letter (or reuse `i`/`o` bound to fixed actions). Deviates
  from upstream letter map.
- **B — per-kind letter table:** bind actual keys (`i`,`o`,…) to
  `jump-tab-<name>` actions resolved per kind. More faithful; modest
  keymap/app changes.

**Lean: A with deviation note** — keymap already documents positional
letters; B can ride along if cheap during implementation.

## Q4 — Warning status class

Upstream `StatusClassWarning` sits between redirect and error. Our
`Resp.status_class` is 0/1/2 (success/redirect/error) rendered green/
yellow/red.

- **A — new class 3 (warning):** render yellow (same as redirect) +
  `· N error(s)` suffix in status title; CLI `--json` emits the class.
  Small, contained.
- **B — fold into error:** wrong — a GraphQL 200-with-errors is not a
  transport failure; upstream treats it as warning (yellow).

**Lean: A.**

## Q5 — CLI/headless event surface

Upstream `run --json` Response shape includes `streamError` and the UI
Messages data derives from the same events. Our CLI prints status +
body. Decision: emit `streamError` in JSON output when present; events
list optional in JSON (include `events` array — cheap since parsed).
Body tab still shows raw SSE text — corpus retains raw body.

## Convergent recommendation

A (buffered SSE) + A (variables as str) + A (positional jumps, dev
note) + A (warning class 3) + include events+streamError in CLI JSON.
One ADR to record the SSE buffering deviation and the variables-as-str
fix; the rest are mechanical.
