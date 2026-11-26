# WI-0011 plan — single stage

One stage (whole WI is one bounded change):

| Stage | Work | Gate |
|---|---|---|
| B1 | `.oxl-version`→0.26.0; rebuild cli+tui; per-dir test loop; update parity-matrix.md unlock rows + h3 note; commit `build: bump oxl toolchain to 0.26.0`; push; PR; green CI | per-dir `oxl test` green + CI |

Already executed on this branch pre-pipeline (verification-driven):
pin flipped, builds clean, all dirs green, binary smoke faithful. The
matrix update is the only remaining artifact work.
