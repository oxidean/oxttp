# ox-agent workflow (oxttp)

All planning, brainstorming, specification, implementation staging, and
shipping for this repo runs through `ox-agent`. Do not hand-edit work-item
lifecycle state or invent work-item directories outside the CLI.

## Required loop

1. `ox-agent start "<title>"` — creates the work item and journals it.
2. `ox-agent run <wi> [--pipeline plan|…]` — compiles a packet and
   dispatches the stage skill (manual adapter writes under `runtime/runs/`).
3. Execute the skill against the packet; write artifacts under the
   packet's `artifacts_dir`; write schema-valid JSON to the packet's
   `output.path`.
4. `ox-agent run collect <run-id>` — validates, journals, applies
   `next_action`.
5. Human answers via `ox-agent input respond` when a skill uses
   `await_input` or a gate fires — never rely on a synchronous chat prompt.

## Do not

- Create `work/active/WI-*` directories or `index.json` by hand.
- Advance stages by editing `current_stage` / `state` in place.
- Ask durable policy questions only in chat — file `await_input` or
  `ox-agent input request` so the answer lands in the next packet.

## Checks

- `ox-agent doctor` healthy before starting work.
- `ox-agent status` / `events` / `input pending` for resumable state.
