# Upstream oxl protocol dependencies (filed 2026-11-22)

From oxttp WI-0008 full-corpus parity (IN-0006 = keep M5 blocked until
oxl lands these). Accidental probe `#217` should be closed as not
planned (this agent lacks `issues:write` on oxidean/oxl — close
manually if still open).

| Issue | Surface | oxttp consumer |
|---|---|---|
| [oxidean/oxl#218](https://github.com/oxidean/oxl/issues/218) | HTTP/2 client (ALPN h2 + prior-knowledge) | xh `--http-version=2*`; Posting gRPC |
| [oxidean/oxl#219](https://github.com/oxidean/oxl/issues/219) | HTTP/3 over QUIC | xh `--http-version=3-prior-knowledge` |
| [oxidean/oxl#220](https://github.com/oxidean/oxl/issues/220) | WebSocket client (ws/wss) | Posting WS request kind |
| [oxidean/oxl#221](https://github.com/oxidean/oxl/issues/221) | TLS client certificates (mTLS) | xh `--cert`/`--cert-key`; Posting ssl client cert |
| [oxidean/oxl#222](https://github.com/oxidean/oxl/issues/222) | HTTPS via HTTP proxy CONNECT | xh `--proxy` + https; Posting proxy_url |
| [oxidean/oxl#223](https://github.com/oxidean/oxl/issues/223) | gRPC client (depends on #218) | Posting gRPC/gRPCS |
| [oxidean/oxl#224](https://github.com/oxidean/oxl/issues/224) | TLS 1.2 fallback | xh `--ssl=tls1.2` / legacy endpoints |

Already shipped upstream (no longer blockers): #125 termios, #126
signals, #127 richer http, #128 TLS/HTTPS (`std/net/tls` + x509).
