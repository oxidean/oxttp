# WI-0011 brainstorm — 0.26.0 bump

Only question worth deciding: sequencing against in-flight S9 (oxttp-wt-s9
on pin 0.23.2) and WI-0013 (needs 0.26.0 APIs).

## Options

A. **Bump now, alone** (recommended) — land pin-only diff on its own PR
   ahead of WI-0013. S9's worktree stays on 0.23.2 until merge; it
   consumes only std/os/term+signal which are source-stable across the
   gap (verified: full test loop green on 0.26.0). Whichever PR lands
   second merges clean — `.oxl-version` isn't touched by S9.

B. Fold bump into WI-0013 — couples a global pin change to a feature
   branch; makes the flags PR the compat-bearer and delays S9's merge
   ordering behind it. Rejected: bump must be independently revertible.

C. Bump + opportunistic API adoption now (rewrite core/http onto std
   client) — rejected: our h1 transport is a deliberate port (ADR-0003);
   std client can't carry model.Trace timings or our redirect/trace
   semantics. Adoption decisions belong to future WIs, not a bump.

## Residual
- h3: no consumable surface (#219 closed without a package). Bump
  proceeds; `--http-version 3*` remains `oxl-blocked`; filing a comment
  on #219 asking whether a follow-up release exposes it is a Jesse-call
  — noted in parity matrix instead.
- If a hidden runtime regression surfaces post-merge, revert is the pin
  line itself (CI installs from it dynamically).
