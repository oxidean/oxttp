# ADR-0037 — disk history + environments.json persistence

- Status: accepted
- Date: 2026-11-26
- Work item: WI-0015 (S11)

## Context

§5.3 pins per-collection disk history; §6.1 pins remembered
environments in `<data>/environments.json`. S10 keeps both
session-only (ADR-0033 boundary). std/crypto/sha256 +
encoding/hex make upstream naming exact; no chmod/flock/O_EXCL
in std forces documented degrades.

## Decision

1. History file = `<data>/history/<sha256hex(abs-coll-path)>.json`,
   `.lock` sidecar created-if-absent around each rewrite and
   removed after (advisory only — no flock; deviation).
   `{version:1, next_id, entries[]}` envelope verbatim; entries
   carry OUR JSON shape (id + title/method/url/status/reason/
   elapsed_ms/size/req_yaml/resp_text/resp row sets) since oxl
   json has no RawMessage — foreign-shape entries are dropped on
   rewrite (deviation vs upstream's retain-raw rule).
   MaxEntries=100; MaxBytes=50MiB newest-fitting, oversized
   dropped. `history.enabled=false` → memory ring only, no disk
   writes. Load merges at collection open (oldest→newest).
   0700/0600 perms unavailable — deviation.
2. `environments.json` mirrors memory.go: map keyed by abs
   collection dir; `{name,dir}` remember-form (our env_pick only
   selects names — file-list form never written, deviation-lite).
   Recall at launch only when no `-e` given; remembered name
   seeds `env_active` before `load_collection`; recall
   forgets entries whose env no longer scans. `(none)` pick
   deletes the key. Write via `<file>.tmp` then `os.rename`
   (mirrors upstream atomicity).
3. `use_host_environment` — no `environ()` in std → accepted,
   one startup warning when true; upstream issue filed on
   oxidean/oxl for environ enumeration.

## Consequences

- History/env persistence are user-visible corpus behaviors now;
  deviations are the mechanical bits (perms, flock, raw-entry
  retention), all documented in the spec's table.
