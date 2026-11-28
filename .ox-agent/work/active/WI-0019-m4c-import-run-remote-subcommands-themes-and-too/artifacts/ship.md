# WI-0019 ship readiness — M4c import, run, remote, themes and tools

## Verdict

Ready to ship after PR review/CI gates clear. Verification passed on the branch:
400/400 TUI tests, the ported upstream Bruno/OpenAPI conformance suites, and
end-to-end `import`, `run`, and `remote` smoke coverage.

## Shipping surface

- `posting import` converts Postman, Bruno, and OpenAPI inputs into Posting
  collections through `core/importing`, preserving upstream conversion behavior
  and write collision semantics.
- `posting run` executes collection requests headlessly with collection-root
  environment scoping (ADR-0067) and integrates capture behavior from main.
- `posting remote` keeps the command surface while degrading Unix-domain remote
  control explicitly (ADR-0066).
- Theme/tool configuration and CLI wiring are included in the TUI command
  surface.
- `.github/workflows/ci.yml` now includes `core/importing` in the test matrix
  and carries compile-memory/non-tty smoke stabilization.

## Rollout evidence

- ox-agent verification run `run_1795846156669_a091be`: pass.
- ox-agent review run `run_1795846139363_6e6123`: pass, with informational
  upstream notes only.
- Ported upstream importer conformance tests run in `core/importing`.
- CI must be green on the final head before merge.

## Rollback

Revert the squash-merge commit for PR #25. The change is additive except for
CLI command wiring and CI test selection; no persistent migration or external
state is introduced.

## Outstanding gate

Human merge approval is required before `shipping → shipped`.
