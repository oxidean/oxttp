# WI-0016 plan — M3 deep HTTP polish

Spec: `artifacts/spec.md`. ADRs: 0039/0040/0041/0042/0043. All stages
run on this branch in order; each gate = `oxl build ./cli` + affected
dirs `oxl test` green, commit per stage.

| Stage | Work | Depends | Gate |
|---|---|---|---|
| **P1 gen-assets** | `scripts/gen-assets.sh` (new): fetch pinned upstream files — `completions/{_xh,xh.bash,xh.elv,xh.fish,xh.nu,_xh.ps1}`, `doc/xh.1`, `doc/xh.1.md`, `assets/themes/{ansi,solarized,monokai,fruity}.tmTheme` @8b21cc0 → emit `cli/gen_assets.oxl` (string literals + provenance header) and `cli/gen_styles.oxl` (per-theme resolved `{element → SGR}` table — offline scope-stack matcher applying theme rules doc-order, convert_color port). Run + commit generated files. | — | script idempotent; `oxl build ./cli` clean |
| **P2 format pipeline** | `cli/fmt.oxl` (new): `FmtOpts` resolve (spec S2), ContentType substring map, bounded charset decode {utf-8,utf-16le/be,w1252+latin1/ascii} + BOM sniff. `cli/sem.oxl`: delete `--format-options` defer. `cli/exec.oxl`: body_render split — response-body decision tree (non-tty raw-binary vs tty suppressor, is_text table, stream/event-stream, print_body_text dispatch, valid_json via jparse, indent-param JSON pretty default 4, bounded XML re-indent); heads get `headers_sort` + h1-only titlecase + latin1/` (UTF-8: )` annotation; `--pretty=format` etc. reach fmt paths. | — | cli dirs green; fixtures regenerated at indent-4/sorted-heads; sem_test flipped |
| **P3 colors** | fmt.oxl: palette lookup into `gen_styles` table + SGR emit helpers; head-element coloring (method/path/ver/status/reason/hname/colon/hval/error) per headers_fmt order incl. plain-reset + end-reset; bounded body lexers (json/xml/html/css/js token classes); `--style` table select (auto→ansi); `--pretty=colors` honored; color warn-degrades removed. | P1, P2 | unit pins: SGR per element×theme (ansi method `\x1b[32m`, path `\x1b[4;36m`, header_value uncolored); cli dirs green |
| **P4 curl emit** | exec: `curl_quote` (os_display maybe_quote unix port); `curl_emit` rewrite to spec-S1 fixed order (warnings→flags→URL→item-headers→auth→payload); `curl_ignored` verbatim 15-flag list + silent 3; item-header derivation incl. unsets/FromFile/empty; payload emitters (data-urlencode name-enc, -F forms, compact-JSON -d, --data-binary); resolve/interface/unix/ipv4/ipv6 emit; ssl map incl. tls1/1.1 + auto-none; multipart-JSON hard error; keep DevD1/D2. | — | all 23 upstream vectors + re-derived curl-* cases green; cli dirs green |
| **P5 generate** | sem: delete `--generate` defer. exec: emit per kind — completions w/ bin-name substitution (spec S5 list), man `.TH` date (SOURCE_DATE_EPOCH ?: today) + version sub, man-markdown version sub; stdout + exit 0. | P1 | generate-* golden cases green (date normalized); cli dirs green |
| **P6 netrc + env tail** | netrc reader → EntryState port (spec S6: word-scanner, #-position, macdef blank-skip, suppress_default, login.or(account), casefold/dot-strip/IPv4-int host match, UTF-16-BOM+lossy decode). `envnames()` += `XH_TEST_DIGEST_AUTH_CNONCE`. | — | upstream netrc.rs vector tests ported green; cnonce env reaches digest path end-to-end |
| **P7 harness + matrix + docs** | `g_load` `env:` merge into envpairs; env-var cases (NO_PROXY pin, NO_COLOR/TERM pretty-guess); `docs/corpus/parity-matrix.md` row flips per spec; corpus deviation notes DevD1–D11 where rows cite them. | P2–P6 | env-driven golden case green; matrix diff matches spec |
| **P8 full verify** | per-dir `oxl test` loop; `oxl build ./cli` + `./tui`; `git status` clean. | P7 | whole-tree green |

## Order rationale

- P1 first: both P3 (style table) and P5 (completion/man bytes)
  consume generated artifacts; single script run, no behavior change.
- P2 before P3: the dispatch/pipeline sites are what colorization
  wraps; landing format defaults first keeps color diff reviewable.
- P4 independent of P2/P3 (curl path never formats) — placed after
  so fixture regeneration happens once per area, not interleaved.
- P6 last substantive stage: self-contained algorithm port + one-line
  envnames fix — isolated risk.
- P7 after behavior: matrix rows and env fixtures pin final texts.

## Open plumbing calls (resolve in-stage, spec findings carried)

- `execute()` likely needs an `out_tty` param (TTY-gated suppressor/
  colors) — add alongside existing stdin_tty; xrun/golden runners
  choose per case.
- `FmtOpts` resolution site: exec-side (`plan()` populates a small
  struct on `p`) — sem stays a pure resolver.
- netrc home: stays where it is (cli-side reader) unless it lives in
  core already — locate at stage start; no package move.

## Risks

- **P3 scope-match fidelity**: offline extraction must mirror syntect
  prefix-match + doc-order override — mitigated by the pinned element
  list (finite stacks) + unit pins vs manually verified values.
- **P4 fixture churn**: every curl-* fixture changes; keep D7
  clearing inside new order per spec DevD2 (review F-pin origin).
- **P2 golden noise**: indent 2→4 + sorted heads touch many fixtures —
  regenerate wholesale, eyeball diff once, mark provenance.
- **P5 substitution safety**: bin-name sub is string surgery on
  vendored files — pin the substitution list, cover with
  substituted-output fixtures.
- **Commit granularity**: per-stage commits (8) — matches gate table
  and keeps revert units small.
