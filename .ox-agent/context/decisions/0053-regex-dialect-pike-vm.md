# ADR-0053 — `match()`/`search()` run on std/regexp (Pike VM)

- Status: accepted
- Date: 2026-11-28
- Work item: WI-0018 (M4b response captures)

## Context

Upstream `match`/`search` JSONPath functions compile the pattern with
Go's `regexp` (RE2: linear-time, no backreferences/lookaround) and
rewrite `.` to `[^\n\r]` for RFC 9485 semantics. oxl 0.26.0 ships
`std/regexp` — a Thompson-NFA Pike VM, same linear-time class, ASCII
`\b`, `\A`/`\z` anchors, char classes, counted reps.

## Decision

Use `std/regexp` for both functions: `match` compiles
`\A(?:`+pattern+`)\z` then `matchstr`; `search` compiles the pattern then
`matchstr` (contains-match — Go `MatchString` semantics incl. empty
matches). Unescaped `.` outside char classes rewrites to `[^\n\r]`
before compile (text-level rewrite; equivalent to upstream's AST
rewrite for this grammar). Compile failure → function returns false
(upstream identical).

## Consequences

- Same expressiveness class as upstream (RE2 ≈ Pike-VM NFA: neither
  supports backreferences/lookaround). Patterns valid upstream are
  valid here except exotic RE2-only syntax if any — spec calls this
  out; `match`/`search` are filter-only conveniences, captures still
  work without them.
