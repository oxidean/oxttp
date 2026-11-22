# Next steps after #8 + #9

Updated: 2026-11-22 (Europe/Berlin). Assumes #8 merged and #9 (bump + HTTPS) merging.

## Just landed

- Full S5 CLI request path + golden harness (WI-0006 / #8)
- oxl **0.23.2** pin, HTTPS on H1 (`tls.client_tmo`, `--verify`), plans WI-0007/8/9 (#9)

## Immediate (this week of work)

1. **Close/archive WI-0006 + WI-0009** once #9 is on `main` — mark shipping complete in ox-agent.
2. **S7 polish (new WI)** — remaining CLI fidelity that is not oxl-blocked:
   - `--continue` / Range resume for `-d`
   - `--pretty` / style / `std/os/term` isatty
   - `--curl` map (or keep degrade until mapped)
   - config.json `default_options`
   - env polish (CA bundle edge cases, netrc leftovers)
3. **Supersede ADR-0005 → S8 TUI driver** — `std/os/term` + `std/os/signal` (WI-0007 step 4), before Posting screens deepen.

## Next tranche (Posting)

4. **S9–S11** — keymap degrade table, screens/panels, `.posting.yaml` collections, env files (WI-0001 remaining; corpus-posting §§1–6).
5. **S10 send path** — reuse core/http HTTPS from CLI; Posting Trace tab timings already on `model.Trace`.

## Parked on upstream oxl

Track only; no local work until issues move:

| Gap | Issue |
|---|---|
| HTTP/2 | oxidean/oxl#218 |
| HTTP/3 | oxidean/oxl#219 |
| WebSocket | oxidean/oxl#220 |
| mTLS / client certs | oxidean/oxl#221 |
| HTTPS + HTTP proxy CONNECT | oxidean/oxl#222 |
| gRPC (needs h2) | oxidean/oxl#223 |
| TLS &lt; 1.3 / native-tls | oxidean/oxl#224 |

## Suggested ox-agent sequence

```
ox-agent start "S7 CLI polish: continue, pretty/term, curl, config.json"
ox-agent start "S8 TUI driver via std/os/term + signal (supersede ADR-0005)"
```

Then drive S9+ from WI-0001 plan once S8 unblocks the TUI.
