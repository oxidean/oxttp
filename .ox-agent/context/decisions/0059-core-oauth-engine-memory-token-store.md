# ADR-0059 — `core/oauth` owns OAuth; oxl 0.26.0 tokens are session-memory only

- Status: accepted
- Date: 2026-11-28
- Work item: WI-0022 (M4f OAuth2 authorization flow)

## Context

Posting 3 keeps OAuth configuration in request YAML but generated access
and refresh tokens in the OS credential store, falling back to memory only
when that store fails (`internal/client/oauth.go` @ 32c4566). oxlp 0.26.0
has no keyring, Secret Service, Keychain, or Windows Credential Manager API.
`std/os/exec` cannot pass input on stdin, so helper tools such as
`secret-tool` cannot receive a token without exposing it through argv or the
environment. Upstream explicitly forbids plaintext-token-file fallback.

## Decision

1. Add `core/oauth` as the reusable OAuth engine: validation, cache keys,
   token acquisition, refresh rotation, browser/PKCE flow, Forget, memory
   entries, and sanitized errors live there rather than inside H1 or the TUI.
2. Define a narrow token-store port (`get/set/delete`) and ship only an
   in-memory implementation in this milestone. Tokens never persist across
   process restarts and never touch plaintext files.
3. Surface an explicit warning when a token is memory-only:
   `OAuth token is kept for this session only (OS credential store
   unsupported in this build).`
4. Preserve upstream cache-key semantics logically: collection root,
   resource origin, fully resolved OAuth configuration with defaults,
   `verify_ssl`, and `proxy_url` all partition token reuse. The exact Go
   JSON encoding need not be byte-compatible because oxttp cannot read the
   upstream OS vault anyway.

## Consequences

- Authorization-code users must sign in again after restarting the TUI;
  client-credentials grants re-acquire after restart. Refresh rotation and
  Forget are still fully testable inside a session/process.
- A future oxl OS-vault API can plug into the token-store port without
  changing validation, PKCE, refresh, UI, or transport behavior.
- No unsafe helper-command or plaintext-file shortcut is permitted.
