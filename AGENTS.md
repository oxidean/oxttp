# oxttp

This file is the single source of truth for agent instructions in this repo.
`CLAUDE.md` is a symlink to this file. Edit only `AGENTS.md`.

## Conventions

- This repo follows the agentcanon convention: agent-facing skills
  resolve under `.agents/skills/` (a symlink to `.ox-agent/skills`;
  `.claude/skills` and `.devin/skills` point at it). Never place
  skill folders in `.claude/skills/` — extension skills are new
  directories under `.ox-agent/skills/`.
- Compatibility surface contracts live in `docs/corpus/` — one
  source-cited corpus per ported app (`corpus-xh.md`,
  `corpus-posting.md`). Implementations match the corpus; deviations
  are called out in specs, never silent.
- Planning flows through ox-agent work items: `ox-agent start <title>`
  opens one; the staged skills drive it from brainstorm through ship —
  see the Ox-Agent toolkit block below.
- Always commit with the repo's configured git identity (the local
  user's). Never use `-c user.name`/`-c user.email` overrides or an
  agent identity.
- No AI attribution on commits or PRs: no `Co-authored-by` /
  `Generated with` / `Made-with` trailers or bot signatures for any AI
  or tool, and no invisible markers.
- Commit subjects are `type(scope): subject` and PR titles the same —
  enforced by `scripts/commit-check.sh` (`.githooks/commit-msg`
  locally, CI `commit-lint` on every PR).
- The pinned oxl toolchain lives in `.oxl-version`; `oxl` on PATH
  resolves it. Bump the pin and CI together.

<!-- ox-agent:begin -->
## Ox-Agent toolkit

This repository is managed by `ox-agent` — a repository-local AI-SDLC
runtime. Project state, skills, and contracts live under `.ox-agent/`.

- `ox-agent doctor` validates the setup; `ox-agent start <title>` opens work items.
- Work items carry state in `index.json`; drive them with
  `ox-agent transition|archive|unblock|status`.
- Human input is durable, never synchronous. When you need an answer or a
  gated approval, file `ox-agent input request` and END THE TURN —
  chat prompts expire before humans see them. Poll with
  `ox-agent input pending` / `input wait --timeout <budget>`;
  answers arrive via `input respond <id> --by <name> --answer "..."`
  (approvals: `--approve|--reject`). Escalated runs and gate hits file
  these requests automatically; a skill asks a
  question with `next_action.type: await_input` — the run stays
  dispatchable and the answer lands in the next packet under `context.inputs`.
- Skills are contracts, not free-form prompts: `.ox-agent/skills/<name>/SKILL.md`
  plus input/output `schemas/`.
- Compile the bounded packet (`ox-agent context compile <wi> --skill <s>`)
  or dispatch via `ox-agent run <wi>`; results land in `runtime/runs/`
  and are schema-validated on collection.
- Materialized skills also resolve under `.agents/skills/` for harnesses
  that scan that path.

Do not edit `.ox-agent/skills`, `schemas`, `workflows`, `pipelines`,
`lifecycle`, or `integrations` in place — they are materialized assets
tracked by `assets.lock`. `kind: core` in a skill manifest means bundled
with the distribution and sync-owned (repaired on `init --repair --sync`);
`kind: extension` means added post-init and never reconciled. To customize a
core skill, fork it under a new directory name: set its manifest `name:` to
`ox-agent/<new-name>` — the qualified form bundled manifests and packets
carry — its SKILL.md frontmatter `name:` to the bare `<new-name>`
matching the directory, and `kind:` to `extension`, and update the
`skill` constants in `schemas/input.schema.json` and
`schemas/output.schema.json` to `ox-agent/<new-name>`, plus the
`skill:` field in
`evals/evals.yaml` — `eval --emit` packets and recorded results take
that qualified name, so a fork still naming the original evaluates under the original
skill. Packets and outputs validate against the schema constants, so a fork
still naming the original skill rejects its own results. Then enable the fork
under `skills.enabled` by its bare directory name and replace the original
directory name in the `skills.stage_skills` entries where it should run —
appending leaves the original selected first; finish the affected stage before
editing its mapping, since `stage_skills` is read at dispatch and a
mid-stage change re-dispatches the in-flight stage under the new skill. `stage_skills` only feeds
stage-driven runs: `ox-agent review`, `ship`, and `run <wi> --pipeline <name>`
read the `skill:` fields inside `pipelines/<name>.yaml` instead. To swap a
pipeline step's skill, copy the pipeline file into `.ox-agent/pipelines/` under
a new filename and set its internal `name:` to the filename stem — `--pipeline <name>` resolves
the file by name and progress tracks that internal name, so the two must
match — then edit its `skill:` references and invoke it via `ox-agent run <wi> --pipeline <name>`.
Update hard-coded asset paths
in the fork's instructions too: a copied SKILL.md that still points at the
core skill's scripts executes the core helper. An extension dir that reuses
a bundled skill's name can still be overwritten by `skills update --yes` —
pick a distinct name. If `assets.lock` is missing or corrupt, repair keeps
drifted files and reports them as conflicts instead of rewriting — review
conflicts before assuming sync ownership was restored.
<!-- ox-agent:end -->
