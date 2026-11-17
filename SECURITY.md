# Security policy

oxttp is an HTTP client toolchain: a command-line HTTP client and a
terminal UI, written in oxl. Reports are taken seriously.

## Supported versions

Security fixes land on `main` and the latest release tag. Older tags are
not patched, so please upgrade before reporting a bug against an old
version.

## Reporting a vulnerability

Do not file public issues, pull requests, or discussions for
vulnerabilities.

Use [GitHub private vulnerability reporting](https://github.com/oxidean/oxttp/security/advisories/new)
on `oxidean/oxttp`.

A good report includes:

- the release tag or commit you tested
- your OS and the oxl toolchain version (`oxl version`)
- steps to reproduce and the impact you see — ideally a minimal command
  line or config that triggers it
- whether the issue needs a specific server, proxy, or environment to
  trigger

Please give us reasonable time to investigate and release a fix before
disclosing publicly. We will acknowledge reports as soon as we can; this
is an early-stage project, so there is no formal SLA.

## Scope

In scope: the oxttp binaries and the code they ship — the CLI surface,
the TUI, the HTTP transport and wire handling, session/collection file
handling, config and env processing, and the argument parser. Issues
that cross a trust boundary — credential leakage through redirects or
logs, response-parser memory safety, terminal-escape injection from
server-controlled bytes, unsafe file writes from `--download`/`--output`
or session paths — are squarely in scope.

Out of scope:

- bugs in the oxl toolchain itself (report those to `oxidean/oxl`)
- weaknesses of a specific deployment or host (open ports, unpatched
  system libraries)
- servers you don't control behaving maliciously toward other clients
- issues in third-party dependencies without a demonstrated exploit path
  through oxttp
- denial-of-service via resource exhaustion that applies to any HTTP
  client given a pathological peer

When in doubt, report privately anyway and let us triage.
