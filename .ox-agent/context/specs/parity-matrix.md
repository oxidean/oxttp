# Corpus parity matrix (living)

Definition: IN-0006 option A. Status values: `done` | `next` |
`post` | `oxl-blocked` (cite issue).

Updated: 2026-11-22 · pin oxl 0.23.2

## xh (`docs/corpus/corpus-xh.md`)

| Section | Status | Notes |
|---|---|---|
| §1 Invocation / bin names / config.json | `next` | Parse done (S4); config default_options S7 |
| §2 METHOD/URL positionals | `done` | S5 construct_url → H1 (+ https) |
| §3 REQUEST_ITEM grammar | `done` | WI-0003 |
| §4.1 Body modes json/form/multipart/raw/stdin | `done` | WI-0006 S5 |
| §4.2 Print/pretty/style/meta/verbose | `next` | meta/print done; pretty≠none degrades; style/isatty S7 |
| §4.3 Download/output | `next` | `-d`/`-o` done; `--continue` degrades until Range |
| §4.4 Sessions | `done` | jar-lite + load/save (ADR-0023) |
| §4.5 Auth basic/bearer/digest | `done` | digest §D3 retry landed |
| §4.5 `https://` / `--https` / `--verify=yes\|pem` | `done` | ADR-0026; PEM path + system roots |
| §4.5 `--verify=no` | `done` | AcceptAll Verifier (IN-0005=B) |
| §4.5 `--cert` / `--cert-key` | `oxl-blocked` | [#221](https://github.com/oxidean/oxl/issues/221) |
| §4.5 `--ssl` <1.3 / `--native-tls` | `oxl-blocked` | [#224](https://github.com/oxidean/oxl/issues/224) |
| §4.5 HTTPS + `--proxy` CONNECT | `oxl-blocked` | [#222](https://github.com/oxidean/oxl/issues/222) |
| §4.6 `--http-version` 1.0/1.1 | `done` | H1 emits 1.0/1.1 |
| §4.6 `--http-version` 2* | `oxl-blocked` | [#218](https://github.com/oxidean/oxl/issues/218) |
| §4.6 `--http-version` 3* | `oxl-blocked` | [#219](https://github.com/oxidean/oxl/issues/219) |
| §4.7 offline/curl/generate/check-status | `next`/`post` | check-status done; curl degrade; generate `post` |
| §5 `--curl` map | `next` | still degraded |
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
| §7.1 client certs | `oxl-blocked` | [#221](https://github.com/oxidean/oxl/issues/221) |
| §7.2 GraphQL | `post` | M4 |
| §7.3 gRPC | `oxl-blocked` | [#223](https://github.com/oxidean/oxl/issues/223) (needs [#218](https://github.com/oxidean/oxl/issues/218)) |
| §7.4 WebSocket | `oxl-blocked` | [#220](https://github.com/oxidean/oxl/issues/220) |
| §7.5 SSE | `post` | M4 |
| §7.6 OAuth2 | `post` | M4 |
| §8 Themes / import / remote / tools | `post` | M4 |
| S8 terminal driver | `next` | `std/os/term`+`signal` (not stty) |
