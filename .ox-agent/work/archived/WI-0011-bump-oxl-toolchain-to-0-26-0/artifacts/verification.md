# WI-0011 verification

- AC1 `.oxl-version`=0.26.0: yes — `oxl version` resolves v0.26.0.
- AC2 builds: `oxl build ./cli`, `oxl build ./tui` clean.
- AC3 tests: per-dir loop all green on 0.26.0 — cli (incl. 13 golden
  cases + exec/digest live fixtures), core/{collection,http,item,model,
  session,term}, shared/args. Same suite CI runs.
- AC4 matrix: 8 rows flipped to `next`/`post` citing real 0.26.0
  symbols; h3 honestly stays `oxl-blocked` (ADR-0029).
- AC5 CI: install step reads the pin dynamically — green expected on PR.
- Rollback: revert the single line; no state or API migration involved.
