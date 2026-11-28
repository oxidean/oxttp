# ADR-0052 — JSONPath filter object iteration is document order

- Status: accepted
- Date: 2026-11-28
- Work item: WI-0018 (M4b response captures)

## Context

RFC 9535 filter selectors over objects may yield members in any
order; theory/jsonpath (Go) iterates `map[string]any` — randomized.
Our `JVal` DOM preserves document order, which is deterministic.

## Decision

Filter/wildcard/descendant selection over object members yields
**document order**. The match *set* is identical to upstream; only
the ordering of results differs, which is unobservable except when a
capture matches multiple values — and that case is an error either
way ("matched N values; expected exactly one"), where upstream's own
ordering is nondeterministic so no faithful order exists to copy.

## Consequences

- Deterministic tests; spec documents the deviation. No user-visible
  difference for valid captures (exactly-one-match ⇒ order irrelevant).
