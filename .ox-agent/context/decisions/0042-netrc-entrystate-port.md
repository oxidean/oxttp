# ADR-0042 — netrc: port upstream EntryState machine; IDNA bound documented

- Status: accepted
- Date: 2026-11-26
- Work item: WI-0016 (brainstorming)

## Context

Our netrc reader is a line-tokenizer that strips `#`→EOL and
string-compares hosts. Upstream `netrc.rs` is a line-word state
machine whose semantics differ in five observable ways: `default`
collects a fallback entry suppressed by ANY `machine` match —
including an incomplete one (INCOMPLETE_AND_DEFAULT); an unknown word
terminates the open entry; `#` starts a comment only at word position
(a `#…` token in value position is a literal — login `#!@$` survives);
`macdef` finishes the entry and skips to the next blank line; host
matching goes through `url::Host` (IDNA so `É.com`==`xn--9ca.com`, and
IPv4 int forms like `16843009`==`1.1.1.1`). Decode is UTF-16-BOM-aware
+ lossy UTF-8. `login.or(account)` matches ours already.

## Decision

Port the machine (~150 lines oxl): per-line word scanner preserving
`#`-by-position, EntryState {Wrong,Correct,Default}, finish_entry on
unknown word/`machine`/`default`/`macdef`, `suppress_default` on any
host match, `login.or(account)`. File precedence `$NETRC` →
`~/.netrc` → `~/_netrc` (already correct); decode UTF-16 BOM +
lossy-8 (cheap — port). Host normalization bounded to casefold +
trailing-dot strip + IPv4-int expansion — **IDNA/punycode has no std
codec**; non-ASCII host equivalence is a documented deviation.

## Alternatives considered

- Patch the current tokenizer — rejected: five interacting semantics
  on the wrong tokenization model; the state machine is the cheaper
  faithful path.

## Consequences

- netrc corpus rows (INCOMPLETE_AND_DEFAULT, OCTOTHORPE_IN_VALUE,
  ENTRY_AFTER_DEFAULT, macdef) become pinnable in unit tests off the
  upstream `netrc.rs::tests` vector list; IDNA bound in spec
  deviations.
