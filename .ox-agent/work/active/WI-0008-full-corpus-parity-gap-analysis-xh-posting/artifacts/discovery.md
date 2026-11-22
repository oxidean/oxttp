# WI-0008 discovery — full corpus parity gap inventory

Corpora: `docs/corpus/corpus-xh.md` (xh 0.26.3 @ 8b21cc0),
`docs/corpus/corpus-posting.md` (Posting 3.0.0-beta.1 @ 32c4566).
Pin today: oxl **0.15.0** (latest **0.23.2** unlocks TLS/term/signal —
see WI-0007). Umbrella plan: WI-0001 S1–S11.

Status legend: **done** | **in-flight** | **planned (v0.1)** |
**unlocked (needs oxl ≥0.23 + WI)** | **blocked upstream** |
**post-v0.1 / not yet sliced**.

---

## A. Shared foundation (already shipped)

| Surface | Corpus | Status | Evidence |
|---|---|---|---|
| Table-driven args engine | xh §4 clap shape | **done** | WI-0002 → `shared/args` |
| Domain model + REQUEST_ITEM grammar (9 seps, 12 variants, escape, `;type=`/`;filename=`) | xh §3 | **done** | WI-0003 → `core/item`, `core/model` |
| Session / collection / Screen·Key types | posting §5, xh §4.4 | **done** (types) | WI-0003; IO later |
| H1 transport on `std/net` (headers, redirects, gzip/deflate, timeouts) | xh exec | **done** | WI-0004 → `core/http` |
| 58-flag CLI table + parse-time semantics + deferral routing | xh §1–4, §7–8 | **done** (parse) | WI-0005 → `cli/spec`, `cli/sem` |

---

## B. oxttp CLI (`xh` corpus) — remaining work

### B1. Planned v0.1 stages (WI-0001)

| Stage | Corpus coverage | Status | Notes |
|---|---|---|---|
| **S5** request path + golden harness | §2 URL/method, §8 exits, output shape | **in-flight** WI-0006 @ intake | Replaces `request execution is unsupported` deferral |
| **S6** body & content kinds | §3 items, §4.1 json/form/multipart/raw/stdin, nested JSON | **planned** | Depends S5 |
| **S7** remaining flags + degradation | §4.2–4.7, §5 curl map, §6–9, env | **planned** | Auth, session, download, pretty/style, check-status, env; TLS items rewrite after bump |

### B2. HTTPS / TLS (corpus §4.5) — was v0.1 deferred

| Item | Status after oxl 0.23.2 | Gap |
|---|---|---|
| `https://` URLs | **unlocked** | H1 still rejects non-http (`cli/sem` + `h1.check_url`) |
| `--https` / `xhs`/`https` bin name default scheme | **unlocked** | Parse already sets intent; needs live path |
| `--verify=yes` (default) | **unlocked** | Wire `tls.Config` + system/env roots |
| `--verify=<pem>` | **unlocked** | `x509.Roots.load_pem`; map vs `REQUESTS_CA_BUNDLE`/`CURL_CA_BUNDLE`/`OXL_SSL_CERT_*` |
| `--verify=no` / `-k` | **policy** | oxl has no `insecure_skip_verify` — accept-all Verifier vs keep unsupported (IN-0005) |
| `--cert` / `--cert-key` (mTLS) | **blocked upstream** | oxl TLS parks client certs |
| `--ssl` < tls1.3 / `--native-tls` | **blocked upstream** | Client-only TLS 1.3; no native-tls dual backend |
| HTTPS through `--proxy` / CONNECT | **blocked upstream** | Parked in oxl `docs/tls.md` |
| SOCKS proxies | **post-v0.1** | Need socket/proxy stack beyond current H1 |

### B3. HTTP versions & extras (corpus §4.6–4.7, §10)

| Item | Status | Gap |
|---|---|---|
| `--http-version` 1.0 / 1.1 | **planned** S7 / H1 tweak | Connection: keep-alive vs ADR-0019 close deviation |
| `--http-version` 2 / 2-prior-knowledge | **blocked upstream** | No h2 in oxl std |
| `--http-version` 3-prior-knowledge | **blocked upstream** | Already feature-gated deferral; needs QUIC |
| `--unix-socket` | **post-v0.1** | Unix dial path |
| `--interface` | **post-v0.1** / platform | SO_BINDTODEVICE / name→IP |
| `--ipv4` / `--ipv6` | **planned** S7 | Resolver filter on H1 dial |
| `--compress` (deflate request) | **planned** S6/S7 | Response decode exists; request compress TBD |
| `--generate` completions/man | **post-v0.1** | Currently hard-deferred |
| `--unstable-m-sig-*` | **blocked / feature** | Needs crypto signing surface + product decision |
| Cookie jar / sessions on disk | **planned** S7 | Types exist; persistence + Cookie header |
| `--download` / resume | **planned** S7 | |
| `--curl` / `--curl-long` | **planned** S7 | Translation map §5 |
| Pretty/style/format-options/charset | **planned** S7 | TTY detection → use `std/os/term.isatty` after bump |
| Config `default_options` JSON | **planned** S7 | Partial parse-time hooks exist |

### B4. Verification for CLI parity

- Differential golden harness vs real `xh` (ADR-0007) — **S5 introduces**; grow through S6/S7/HTTPS.
- Exit codes 0–6 — **S5/S7**.
- Warning catalog §8 — **S7**.

---

## C. oxttp-tui (`Posting` corpus) — remaining work

### C1. Planned v0.1 stages (WI-0001 Tranche 2)

| Stage | Corpus coverage | Status | Notes |
|---|---|---|---|
| **S8** terminal driver | §1.6, §4 input | **planned** | Prefer `std/os/term`+`signal` (supersede ADR-0005); not `stty` |
| **S9** app shell + ~114 keybindings | §3 keymap, §4 screens | **planned** | Unimplemented actions degrade explicitly |
| **S10** collections + send via core | §5 `.posting.yaml`, §7.1 HTTP | **planned** | Byte-compat fixtures |
| **S11** config (40 keys) + polish | §2 config, §1 flags/subcommands | **planned** | |

### C2. HTTP features inside TUI (depend on core)

| Item | Status | Gap |
|---|---|---|
| HTTP send/response render | **planned** S10 | Uses core Transport |
| HTTPS / SSL settings (`ssl.*`, verify_ssl, ca_bundle, client cert) | **unlocked** / **partial block** | Same as CLI TLS; client cert still upstream |
| Auth basic/bearer | **planned** | |
| Auth digest | **post-v0.1** | Challenge/response |
| OAuth2 + browser PKCE | **post-v0.1** | Needs browser/OS open + local redirect listener |
| Cookies / history | **planned** S10–S11 | |
| GraphQL | **post-v0.1** | UI + body shape; still HTTP transport |
| SSE | **post-v0.1** | Streaming read loop |
| Captures / generated values / scripts | **post-v0.1** | |
| Environments / `$VAR` substitution | **planned**–**post** | Core pieces in S10/S11 |

### C3. Non-HTTP protocols (corpus §7.3–7.4) — beyond current core

| Item | Status | Gap |
|---|---|---|
| gRPC / gRPCS | **blocked upstream** + large product | Needs HTTP/2 or dedicated gRPC stack; proto reflection |
| WebSocket / WSS | **blocked / large** | No WS in oxl std today |
| grpcurl export / Bruno gRPC import | **post** after gRPC | |

### C4. CLI subcommands & remote (corpus §1)

| Item | Status | Gap |
|---|---|---|
| `locate`, `version`, `--collection/--env` | **planned** S11 | |
| `import` OpenAPI/Postman/Bruno | **post-v0.1** | |
| `run` headless runner | **post-v0.1** | |
| `remote` Unix-socket control + agent skill | **post-v0.1** | Needs UDS server |

### C5. Themes, imports, external tools

| Item | Status |
|---|---|
| Themes (§8.1) | **planned** S11 / polish |
| curl import/export | **post-v0.1** (CLI has `--curl`; TUI interop later) |
| External editor/$PAGER | **post-v0.1** |
| Scripting | **post-v0.1** (docs note limited) |

---

## D. Cross-cutting toolchain / process

| Item | Status |
|---|---|
| Bump oxl → 0.23.2 | **WI-0008 chore** (named WI-0008 in WI-0007 plan — renumber: open as bump WI after this analysis) |
| Simplify CI multi-arg `oxl test` (#131 fixed) | with bump |
| ox-agent workflow for all stages | **standard added** (`ox-agent-workflow.md`); WI-0007 IN-0005 still pending |
| Windows/macOS terminal parity | **post** (Linux/WSL first per WI-0001) |
| Package publish / install channels | **out of scope** until later |

---

## E. Counts to close for "full corpus parity"

**xh:** 58 flags parse today; execution ~0 until S5; HTTPS subset unlockable; h2/h3/mTLS/CONNECT/msg-sig remain upstream-gated; generate/completions/man are product extras.

**Posting:** 13 CLI flags + 5 subcommands + ~114 bindings + 40 config keys + `.posting.yaml` schema — v0.1 targets HTTP TUI fidelity; gRPC/WS/OAuth/remote/import/run are the long tail for full upstream parity.

## F. References loaded

- Corpora under `docs/corpus/`
- WI-0001 plan/spec; ADRs 0001–0019; decision 0020 (post-oxl sequencing)
- WI-0007 discovery/brainstorm; `cli/sem.oxl` deferral table; `core/http/h1.oxl`
- oxl `docs/tls.md` @ v0.23.2; issues #125–#128, #131
