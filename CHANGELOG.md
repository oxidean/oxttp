# Changelog

All notable changes to oxttp are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project
adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- Workspace scaffold: `shared/`, `core/`, `cli/`, `tui/` modules on the
  pinned oxl toolchain
- `shared/args`: table-driven clap-shaped option parser (WI-0002)
- `core`: domain model and xh request-item grammar (WI-0003)
- `core/http`: HTTP/1.1 transport on `std/net` sockets (WI-0004)
- `cli`: complete 58-flag xh argv surface with parse-time semantics
  (WI-0005)

### Changed

- Toolchain pin `.oxl-version` **0.15.0 → 0.23.2** (unlocks `std/net/tls`,
  `std/os/term`, `std/os/signal`). Compat: `[T, err]` multi-returns,
  `Screen.Size`, `os.writefile_` byte-count success.
