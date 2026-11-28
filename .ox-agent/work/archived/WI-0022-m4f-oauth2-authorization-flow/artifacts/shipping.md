# WI-0022 shipping readiness

Release content: OAuth2 authorization-code PKCE and client-credentials support for HTTP Posting collections, including memory-only token reuse/refresh/forget, strict validation/sanitization, loopback browser callback flow, TUI editor/send integration, and noninteractive `posting run` behavior.

Verification evidence: independent review passed with notes; verification passed with notes; local `core/oauth` tests passed; CI has a dedicated `core/oauth` matrix leg. Documented degradations: memory-only token store, synchronous browser authorization without Escape cancellation, IPv6 loopback listener degradation.

Rollout: merge PR #27 after green CI and review completion. No migration or persistent token format is introduced. Rollback is revert of the squash merge; existing non-OAuth requests are unaffected.
