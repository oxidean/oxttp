# WI-0020 ship readiness — M4d GraphQL and SSE

## Verdict

Ready to ship after PR review/CI gates clear. Verification passed across the
repo suite in the clean-copy harness, both binaries build, and CLI/TUI smokes
pass.

## Shipping surface

- GraphQL collection requests lower to POSTed JSON documents with upstream
  query/variables/operationName behavior and environment substitution.
- GraphQL responses surface upstream-style warning classification when a 2xx
  body carries top-level `errors`.
- Server-sent events are parsed into response event streams with upstream
  field semantics, event/log caps, seed/terminal events, content decoding, and
  interruption reporting.
- The TUI gains GraphQL query/variables/operation editors and an
  Events/Messages response surface.
- `posting run` JSON output includes stream events and stream errors.

## Rollout evidence

- ox-agent implementation run `run_1795819586965_4598c5`: pass.
- ox-agent code review run `run_1795850693090_136f99`: pass_with_notes; no
  blocking defects.
- ox-agent verification run `run_1795850943311_65185b`: pass; evidence in
  `artifacts/verification.md`.
- CI must be green on the final head before merge.

## Rollback

Revert the squash-merge commit for the WI-0020 PR. The change is additive to
collection/http/model/TUI surfaces and introduces no external migration or
persistent service state.

## Outstanding gate

Human merge approval is required before `shipping → shipped`.
