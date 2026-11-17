# .ox-agent — project state managed by ox-agent

This directory is the project-local AI-SDLC runtime for `ox-agent`. Work items,
skills, contracts, and the event journal live here.

- `framework.yaml`, `config.yaml`, `policy.yaml` — the project's contract files; these are yours to edit.
- `skills/`, `schemas/`, `workflows/`, `pipelines/`, `lifecycle/`, `integrations/` —
  materialized assets tracked by `assets.lock`; do not edit in place. Add
  extension skills as new directories under `skills/`.
- `work/` — the project's spec trail. Every work item keeps its `spec.md`,
  `plan.md`, and artifacts under `work/active/`, and `archived/` holds
  the permanent record of what shipped. Commit it — the history is documentation.
- `context/` — project standards, decisions, and promoted specifications
  (`specs/`). What lives here indexes into future work-item packets.
- `state/`, `discussions/` — the append-only journal (`events.ndjson`)
  and durable threads; committed with everything above.
- `runtime/` — generated packets and runs; gitignored.

`ox-agent doctor` validates this setup. `ox-agent integrate` wires it into
agent harnesses (a managed `AGENTS.md` block plus `/.agents/skills` and
`/.claude/skills` links) so the materialized skills are discoverable during
agentic work — without it, nothing outside this directory advertises the toolkit.
