# 0011 — Full flag table before execution depth

Status: accepted (2026-11-17, WI-0001 specification)

`cli` declares the complete 58-flag corpus option table (kinds,
defaults, env fallbacks, conflicts, `--no-*` pairs) up front — the
table-driven `shared/args` parser makes the surface a declaration, not
58 features. Execution depth lands incrementally behind the complete
surface; unsupported behaviors degrade explicitly per decision 0006.
