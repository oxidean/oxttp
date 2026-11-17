# WI-0005 implementation plan — S4 CLI flag surface

Spec: `artifacts/spec.md` (the 58-row table, semantic order, messages,
matrix, deviations). Layout: ADR-0014 (cli owns post-clap semantics),
ADR-0015 (deferral routing, env levels). Grammar consumed from
`core/item` (WI-0003); engine from `shared/args` (WI-0002).

## Stages

1. **Test-first matrix** (tdd skill)
   - `cli/spec_test.oxl` — table conformance: 58 rows by name, 51
     visible / 7 hidden, usage line literal, help short/long content,
     per-flag parse sweep (all shorts, enum vals+aliases, repeats,
     `=v`/`v`/attached forms), negations incl. tri-states +
     `--no-help`/`--no-version`, radio trio, counts, 4 conflict
     pairs, requires (continue + m-sig), env fallback order,
     `--` separator, missing-value/unknown-arg/required-positional
     diagnostics, help/version actions.
   - `cli/sem_test.oxl` — semantic pass: method/URL extraction,
     `help` literal, Missing <URL>, item parse errors, all
     process_relations arms, raw+body conflict, every value-parser
     message (timeout/print/format-options/proxy/resolve/charset/
     m-sig-comp/verify), construct_url matrix, deferral routing,
     effective getters (check_status/method/max-redirects/print),
     env behaviors.
   - `cli/cfg_test.oxl` — bin_name cases, config_dir precedence,
     default_options matrix (absent/unreadable/bad-json/non-array/
     valid/prepend-order).
   - Gate: tests compile; assertions fail red on the scaffold main
     (no spec/sem/cfg yet).

2. **Table + helpers in `cli/spec.oxl`**
   - `fn spec(prog: str) -> own args.Spec` — 58 builder calls in
     upstream struct order + 2 positional slots; const data
     `enc_labels` (WHATWG label csv).
   - Gate: `cli/spec_test.oxl` green.

3. **Semantic pass in `cli/sem.oxl`**
   - `Intent` (parsed-intent struct — the S5 seam) + `Out{code,
     stdout, stderr, intent}`; `fn resolve(m, envpairs) -> own Out`
     in spec order 1–10; value validators; `construct_url`;
     `guess_pretty`; effective getters.
   - Gate: `cli/sem_test.oxl` green.

4. **Env/config in `cli/cfg.oxl`**
   - `bin_name`, env `lookup` over pair lists, `config_dir`,
     `default_options` (pure parse → tokens|warning) +
     `config_args` IO wrapper shape.
   - Gate: `cli/cfg_test.oxl` green.

5. **`cli/main.oxl` — os glue**
   - argv0 → bin_name → envpairs (declared names + the parse-level
     set) → default_options prepend → `args.parse` → act/diag/
     resolve dispatch → stdout/stderr + `os.quit(code)`.
   - Gate: `oxl build ./cli`; smoke run: `--help`, `help`, `-V`,
     missing positional, unknown flag, `--generate=man`, plain
     request → deferral (exit 1); diagnostics exit 2.

6. **Verify + wrap-up**
   - `for d in $(git ls-files '*.oxl' | xargs -n1 dirname | sort -u);
     do oxl test $d || exit 1; done` green; `oxl build ./cli`
     `./tui` clean; `oxl fmt` touched files (stdout-only tool —
     diff by hand); corpus coverage re-checked vs spec list.
   - Commit `feat(cli): corpus flag surface — 58 options, positional
     items, xh-shaped diagnostics` (+ earlier stage commits),
     push branch, PR.

## Dependencies

- `spec.oxl` → `shared/args` builders only.
- `sem.oxl` → `shared/args` (Matches getters, usage_line) +
  `core/item` (parse, Item enum) + std {strings, strconv, errors}.
- `cfg.oxl` → std {os, strings, encoding/json, errors}.
- `main.oxl` → all three + `shared/version`.

## Risks

- `package main` multi-file compile quirks — probed green already
  (test fn discovery verified); fall back to a `cli/xhspec`
  subpackage if a file-level issue appears.
- `own` move semantics on the Intent/Out graph — same patterns S1
  used (copy-out/write-back for slice fields, `new(push(x[:],e))`).
- WHATWG label table is data, not code — low risk, but keep the csv
  complete (all encodings.json labels).
