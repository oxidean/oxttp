# ADR-0033 — S10 UX-semantics boundaries

- Status: accepted
- Date: 2026-11-26
- Work item: WI-0014 (S10)

## Context

Specification surfaced a set of product-semantic decisions that
aren't architectural enough for their own ADRs but are durable
choices the implementation and later stages must not silently
revisit: how file ops behave, what preview tabs mean, and where
S10's env/history persistence boundary sits.

## Decision

1. **File ops follow §4.9/§5.2 verbatim where bound**: `d` copies
   the request file beside the original as `<base> (copy)[ N]
   .posting.yaml` (first free name) and rewrites `name:` with the
   ` (copy)` suffix; `backspace`/`delete` removes the file after a
   single MConfirm and reloads the tree — an open tab for a
   deleted file stays open as unsaved. Folder dup/delete degrade.
2. **Save refuses silent clobber**: `save-confirm` requires a
   name, slugifies non-alnum → `-`, lets `File`/`Folder` override
   placement (mkdir_all), and asks before overwriting an existing
   file — a uniform rule straddling the corpus's save-directly UI
   and refuses-to-clobber remote.
3. **Preview tabs implement §8.6**: collection opens land in the
   current preview tab (replaced in place) or a new preview tab;
   any draft-mutating edit or `keep-tab` flips `preview=false`;
   multi-select opens all — first in the preview tab, the rest as
   normal tabs.
4. **S10 persistence boundary**: history is a memory-only
   100-entry ring (disk `<data>/history/` + sha256 naming land
   S11 with config/paths); active environment is session-only
   (`environments.json` + `use_host_environment` land S11);
   auth/options request panes are read-only renderings of the
   loaded file — in-UI editing degrades to S11.

## Consequences

- Every choice above is exercised by tests against fixture
  collections; none blocks S11's config/history/flag work, which
  layers on top rather than replacing.
- The save-confirm-overwrite rule and read-only panes are
  documented deviations in the spec's deviation table.
