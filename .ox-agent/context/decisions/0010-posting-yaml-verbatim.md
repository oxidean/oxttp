# 0010 — .posting.yaml cloned verbatim

Status: accepted (2026-11-17, WI-0001 specification)

`oxttp-tui` reads and writes the `.posting.yaml` collection schema
exactly as `corpus-posting.md` pins it — all 40 config keys, no
oxttp-native additions in v0.1. Collection files round-trip
byte-compatible with Posting 3; extensions wait for a later milestone
and would arrive namespaced, never inline.
