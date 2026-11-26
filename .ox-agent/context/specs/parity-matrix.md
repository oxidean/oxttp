# Corpus parity matrix (living)

Definition: IN-0006 option A. Status values: `done` | `next` |
`post` | `oxl-blocked` (cite issue).

Updated: 2026-11-25 · pin oxl 0.26.0

## xh (`docs/corpus/corpus-xh.md`)

| Section | Status | Notes |
|---|---|---|
| §1 Invocation / bin names / config.json | `done` | config.json default_options wired |
| §2 METHOD/URL positionals | `done` | S5 construct_url → H1 (+ https) |
| §3 REQUEST_ITEM grammar | `done` | WI-0003 |
| §4.1 Body modes json/form/multipart/raw/stdin | `done` | WI-0006 S5 |
| §4.2 Print/pretty/style/meta/verbose | `next` | pretty+isatty+JSON indent done; style/colors polish later |
| §4.3 Download/output | `done` | `-d`/`-o` + `--continue` Range/206/416 |
| §4.4 Sessions | `done` | jar-lite + load/save (ADR-0023) |
| §4.5 Auth basic/bearer/digest | `done` | digest §D3 retry landed |
| §4.5 `https://` / `--https` / `--verify=yes\|pem` | `done` | ADR-0026; PEM path + system roots |
| §4.5 `--verify=no` | `done` | AcceptAll Verifier (IN-0005=B) |
| §4.5 `--cert` / `--cert-key` | `next` | oxl 0.26.0 `tls.Config.client_cert` → WI-0013; cert is TLS 1.3-only — a negotiated 1.2 session sends empty certificate_list |
| §4.5 `--ssl tls1.2` / `--native-tls` | `next` | oxl 0.26.0 `Config.min_ver/max_ver` (V12) → WI-0013 |
| §4.5 `--ssl tls1` / `tls1.1` | `oxl-blocked` | oxl rejects <V12 (deprecated versions); degrade = warn + auto-fallback per corpus §4.5 |
| §4.5 HTTPS + `--proxy` CONNECT | `next` | oxl 0.26.0 `Request.proxy`/`connect_proxy` → WI-0013 |
| §4.6 `--http-version` 1.0/1.1 | `done` | H1 emits 1.0/1.1 |
| §4.6 `--http-version` 2* | `next` | oxl 0.26.0 `http_version` "2"/"2-prior-knowledge" → WI-0013 |
| §4.6 `--http-version` 3* | `oxl-blocked` | [#219](https://github.com/oxidean/oxl/issues/219) closed w/o consumable pkg — ADR-0029 |
| §4.7 offline/curl/generate/check-status | `next`/`post` | check-status+curl done; generate `post` |
| §5 `--curl` map | `next` | emit + Ignored warnings; map incomplete vs corpus |
| §6 Completions/man | `post` | |
| §7 Env vars | `next` | proxy/netrc/CA partial; finish S7 |
| §8 Exit codes / warnings | `done` | 0–6 paths covered in S5 |
| §10 Feature gates | `done`/`oxl-blocked` | Deferrals match ADR-0024 |

## Posting (`docs/corpus/corpus-posting.md`)

| Section | Status | Notes |
|---|---|---|
| §1 CLI flags / locate/version | `next` | S11 |
| §1 import / run / remote | `post` | M4 |
| §2 Config 40 keys | `next` | S11 |
| §3 Keymap ~114 | `next` | S9 (degrade unimplemented) |
| §4 Screens / panels | `next` | S9–S10 |
| §5 `.posting.yaml` collections | `next` | S10 (types in WI-0003) |
| §6 Environments / captures | `next`/`post` | Env S10/S11; captures M4 |
| §7.1 HTTP(+TLS) send | `next` | S10 + HTTPS WI |
| §7.1 client certs | `next` | oxl 0.26.0 `client_cert` → WI-0013 cli + M4 tui; TLS 1.3-only — negotiated 1.2 sends empty cert list |
| §7.2 GraphQL | `post` | M4 |
| §7.3 gRPC | `post` | oxl 0.26.0 `net/grpc` shipped → M4 |
| §7.4 WebSocket | `post` | oxl 0.26.0 `net/websocket` shipped → M4 |
| §7.5 SSE | `post` | M4 |
| §7.6 OAuth2 | `post` | M4 |
| §8 Themes / import / remote / tools | `post` | M4 |
| S8 terminal driver | `done` | ADR-0027 AnsiScreen Session |
