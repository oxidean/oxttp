# WI-0008 spec — full corpus parity program

## Intent

Define acceptance for **full corpus parity** with xh 0.26.3 and Posting
3.0.0-beta.1 under definition **A** (IN-0006): every corpus row is
either implemented to upstream behavior or an explicit, tracked
degradation with a reopen path (ADR-0006). Protocol long-tail stays
oxl-blocked until oxidean/oxl#218–#224 land.

## Decisions locked

- IN-0006 → A (honest oxl-capable parity; M5 blocked rows).
- IN-0005 → B (bump → S5/S6 → HTTPS; `--verify=no` via accept-all
  Verifier).
- Upstream issues filed: see `context/references/oxl-protocol-deps.md`.

## Deliverables of this WI (planning)

1. Living **parity matrix** at
   `context/specs/parity-matrix.md` (created by the plan stage /
   first follow-on commit) listing every major corpus section with
   status `done|next|oxl-blocked|post`.
2. Staged plan M0–M5 with concrete WI titles and gates.
3. No silent corpus omissions — blocked rows cite oxl issue numbers.

## Acceptance criteria

1. Matrix covers xh §§1–10 and Posting §§1–10 at section granularity
   (flag groups OK; not every keybinding line required in v1 of the
   matrix).
2. Every `oxl-blocked` row cites one of #218–#224 (or a successor).
3. M0–M2 WIs are openable without further product questions.
4. `ox-agent` journal shows discover → brainstorm → specify → plan
   collected for this WI.

## Out of scope for this WI

Implementation of S5+/HTTPS/TUI; bump chore may ship in the same
agent run but is a separate commit/WI concern.
