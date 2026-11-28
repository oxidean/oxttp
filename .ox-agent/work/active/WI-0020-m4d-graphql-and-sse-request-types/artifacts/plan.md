# WI-0020 plan — M4d GraphQL + SSE

Direction: spec.md S1–S9 + ADR-0044/0045. TDD order — tests land
with or before each unit's code.

## Stage A — core/env + core/collection (leaf, no deps)

1. `core/env/env.oxl`: `substitute_braced(text, set) -> [str, err]`
   — share the scanner with `substitute` via a `braced_only` flag;
   `${NAME}`+`${$gen}`+`$$`→`$` only; unresolved passthrough.
2. `core/env/env_test.oxl` (or existing test file): braced cases.
3. `core/collection/collection.oxl`:
   a. `PGraphQL.variables: own json.Json` → `str`; `gql_dec` uses
      `scal`; encode uses `yput_str` (omitempty on empty); drop
      `jnode` if orphaned.
   b. `gql_document(query, variables, operation_name) -> str` —
      json.tojson(jstr()) quoting, jparse-compaction-or-verbatim
      variables, omission rules.
   c. `plan_req`: `kind=="graphql"` proceeds (grpc/ws keep degrade);
      method=POST; body=Raw json doc; substitution query→braced,
      variables→all, gated by subbody; Accept appended when absent;
      r.method/r.body ignored for the kind.
4. `core/collection/*_test.oxl`: update variables cases to scalar +
   map-rejection; plan_req graphql matrix (document bytes exact,
   substitution matrix, Accept rules, POST force, params/headers/
   auth still apply, grpc/ws degrade intact).

## Stage B — core/model + core/http SSE

5. `core/model/model.oxl`: `StreamEvent` struct; `Resp.events:
   own []StreamEvent`, `Resp.stream_error: str`.
6. `core/http/sse.oxl` (new): `parse_sse(body: []byte, at_ms_fn)
   -> [own []model.StreamEvent, str]` — port of upstream parseSSE +
   seed/terminal events; caps 1MiB/event, 10k events; BOM/CRLF/
   comments/id-persist/empty-data-drop/content-type detect.
   `sse_time_str(ms) -> str` local HH:MM:SS.mmm formatter (civil
   algorithm; put in model or http — choose model for TUI reuse).
7. `core/http/h1.oxl`: TmoReader/TmoTlsReader `deadline: int`→
   `shared`; roundtrip builds cell, passes to finish_roundtrip;
   SSE detect post-head → sset(dl,0); raw-read cap 64MiB for SSE;
   post-decode truncate+stream_error; call parse_sse → Resp fields.
   `h2_exchange`: detect event-stream, parse events post-body
   (deadline kept — D6); share via helper `sse_finish(resp,
   body_decoded)`.
8. `core/http/*_test.oxl`: SSE fixture matrix (fields, comments,
   multi-line, CRLF, BOM, caps, stream_error, seed/terminal,
   content-encoding, deadline lift past timeout_ms, non-SSE
   regression, HEAD no-events).

## Stage C — TUI GraphQL editors + send

9. `tui/types.oxl`: App+RDraft `gql_query/gql_vars: TextView`,
   `gql_op: LineEdit`, `resp_events`, `msg_detail`, `msg_following`.
10. `tui/app.oxl`: req_tabs(KGraphql) reorder → [Query, Variables,
    Headers, Path, Params, Auth, Info, Options]; snapshot/restore
    copies; bindings for new tabs (tv keys on Query/Variables,
    KV on Headers/Params/Path); resp tab-0 message bindings
    (up/down/enter/f/escape) when events; jump stays positional.
11. `tui/coll.oxl`: draft_to_request graphql branch (fresh
    PGraphQL from widgets; body skipped); draft load fills gql_*
    from preq.graphql; install_resp events capture + warning
    class 3 (kind from pending_preq) + title suffix; history keeps
    text only (D3).
12. `tui/render.oxl`: req pane Query/Variables renderers; resp
    tab label Events/Messages swap; message rows render + detail
    view; resp_class 3 → yellow.
13. `tui/*_test.oxl`: draft round-trip, plan→send fake transport
    asserting Req method/body/headers, install_resp warning +
    events rows, label swap, detail enter/escape.

## Stage D — CLI run + parity

14. `tui/cli.oxl`: resp_json adds streamError + events (at unix ms,
    body base64 per upstream []byte JSON); run outcome treats
    warning class like error per upstream run.go (verify upstream
    during impl).
15. `.ox-agent/context/specs/parity-matrix.md`: §7.2/§7.5 → done
    + ADR-0044 footnote.
16. Full suite: `oxl test` per leaf dir + cli/tui golden.

## Gates

- Each stage ends green on its package tests before next starts.
- Stage D ends with full `oxl test ./cli ./tui ./core/...` sweep
  (repo test_command) + build of both binaries.
