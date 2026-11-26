# WI-0011 ship — oxl 0.26.0 pin

Release note line: "Toolchain pin: oxl 0.23.2 → 0.26.0 (h2/h2c, mTLS,
TLS 1.2, CONNECT, WebSocket, gRPC now consumable; no source changes)."

Rollout: merge PR → main pin flips → CI self-installs 0.26.0.
Rollback: revert the pin line (single-line revert, no migration).
Evidence: artifacts/verification.md — full suite green on 0.26.0.
Gate: human merge approval (durable input request).
