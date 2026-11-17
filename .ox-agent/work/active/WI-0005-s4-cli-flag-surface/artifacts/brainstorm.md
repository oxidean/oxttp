# WI-0005 brainstorm — S4 CLI flag surface shape

Settled upstream: full 58-row table lands here (decision 0011) on the
S1 engine (0004/0012/0013); parse everything, degrade explicitly
(0006). Corpus §1–4 + source-verified flow in
`context/references/xh-cli-parse-flow.md`. This brainstorm picks the
cli-internal architecture and how corpus value parsers beyond the
engine's kinds get their exact messages.

## Option A — table + cli-side semantic pass (CHOSEN)

`cli/` (package main) holds: `spec.oxl` — the 58-row option table +
2 positional slots (`murl` required, `rest` variadic) built through
`shared/args` builders in upstream struct order; `run.oxl` —
post-parse semantic pass replaying `try_parse_from`: help literal →
method/URL extraction → item parse via `core/item` → bin_name →
process_relations → per-option value validation → construct_url; a
parsed-intent struct the S5 request path consumes. Validation helpers
are pure fns so `cli_test.oxl` drives them in-package (`oxl test
./cli` verified to run package-main tests on pin v0.15.0).

Pros: engine untouched (S1 shipped, TUI will reuse); every corpus
value-parser message reachable verbatim; post-parse order mirrors
upstream exactly; tests live beside the table they cover. Cons: a
handful of options must be declared KSTR (not their natural engine
kind) so cli owns their messages — mitigated by pinning each in spec.

## Option B — extend shared/args with custom validators (REJECTED)

Add a validator-hook kind or per-kind variants (KTIMEOUT, KPRINT…).
Puts xh's messages inside the shared engine (leaks app specifics into
a shared component TUI also drives), forces an S2-shipped package to
grow mid-flight, and still can't run validation at clap's argv
position. Rejected — engine stays kind-generic per decision 0004.

## Option C — cli library subpackage for testability (REJECTED)

`cli/oxcli/` lib + thin main. Probed: `oxl test ./cli` already runs
`fn test_*` in `package main` dirs on v0.15.0, so the subpackage buys
nothing and splits the surface across two packages. Rejected.

## Sub-decisions

1. **Value-parser coverage**: timeout, print, history-print,
   format-options, proxy, resolve, m-sig-comp normalization, verify
   normalization — all KSTR (repeat where upstream repeats) + cli
   post-parse checks emitting corpus messages verbatim. `--timeout`
   deliberately NOT KFLOAT: engine's "not a valid number" diverges
   from xh's "Connection timeout is not a valid number".
   `--max-redirects` stays KUINT (engine message already matches
   clap's `invalid digit found in string`). `--response-charset`:
   implement normalization + WHATWG label table (bounded, mechanical
   — spec pins the set) so invalid labels error corpus-faithfully.
2. **Positional model**: two slots (`murl` required + `rest`
   variadic) — upstream has no middle URL slot; `Missing <URL>` is a
   cli-side clap-shaped error (exit 2), as is the raw+body conflict
   and `Invalid <URL>: <e>`.
3. **Deferral layer**: after a fully valid parse, run paths degrade
   per 0006: any m-sig option → `This binary was built without
   message signature support. Enable the 'http-message-signatures'
   feature.`; http-version=3-prior-knowledge → `This binary was built
   without support for HTTP/3. Enable the 'http3' feature.`;
   constructed https:// URL → TLS-not-available variant; everything
   else → `request execution is unsupported in this build` —
   all `{bin}: error:` shape, exit 1. `--generate` gets its own
   deferral line (generation machinery is S-later scope).
4. **Env wiring**: parse-level — XH_CONFIG_DIR (config dir),
   XH_HTTPIE_COMPAT_MODE (compat; empty-set indistinguishable →
   deviation), REQUESTS_CA_BUNDLE→CURL_CA_BUNDLE (engine env on
   verify), NO_COLOR/TERM (guess_pretty — TTY branch falls back since
   no isatty, deviation), *_PROXY/NO_PROXY (captured; `--proxy`
   disables). Execution-side reads deferred: NETRC, RUST_LOG,
   RUST_BACKTRACE, SOURCE_DATE_EPOCH — recorded in the parsed-intent
   docs + spec coverage list.
5. **default_options**: implement now — corpus §1, ~40 lines: config
   dir (XH_CONFIG_DIR > macOS-legacy-if-exists > ~/.config/xh),
   config.json `{"default_options":[...]}` via std/encoding/json,
   prepend between argv0/argv, xh-shaped warnings on read/parse
   failure.
6. **Parse-order fidelity**: post-parse value checks run in table
   declaration order (upstream: argv position). Divergence only when
   two invalid values race — spec'd deviation, differential stage can
   tighten.

## Open questions for spec

- Exact short-help row order/indent (declaration order = upstream
  struct order; engine renders the column alignment).
- Whether `--generate` deferral exits 1 like other deferred surfaces
  (yes — honest failure) and its message text.
- `xhs`/`https` bin-name handling for the oxttp binary (implement
  verbatim: https in {https,xhs,xhttps} → https=true; {http,https} →
  compat).
