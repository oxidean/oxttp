# oxl toolchain notes (pin v0.15.0) - findings from WI-0003 discovery

Verified empirically against the pinned toolchain + std source
(~/wsl-projects/oxidean-org/language/std, read-only).

## oxl test quirks

- Multiple package dirs in one invocation run ONLY the first dir's test
  binary: `oxl test ./a ./b` runs ./a tests (plus dependency dirs'
  tests), ./b tests never run. The project test_command
  (`oxl test $(git ls-files '*.oxl' | xargs -n1 dirname | sort -u)`)
  therefore silently tests only the alphabetically-first package dir -
  CI must loop per dir until upstream fixes arg handling.
- `oxl test ./<dir>` runs `fn test_*` in that dir AND in dirs its module
  transitively requires - a tests package importing the unit under test
  still executes the library's own `fn test_*`.
- `fn test_*` can sit in `*_test.oxl` beside library sources in the
  same `package` - no separate tests package needed.
- `./...` glob arg is not reliable in v0.15.0 - prefer explicit dirs.

## Type-system constraints shaping the domain model

- No `Option[T]`; `own str`/`own int` fields work (`new("s")`/`new(42)`
  box them, `== nil` checks) but dereference is awkward (`.*` is
  struct-only, `len(ownstr)` rejected). Optional scalars: use
  `{v, ok}`-style small structs or `has_` bools - the std convention.
- `own T` fields for optional sub-objects work cleanly; `new(T)`
  zero-inits, `== nil` reliable.
- `std/collections.Map` is int-payload only - str->str maps (Posting
  `captures`, `variable_scope`) need ordered KV lists.
- enums support positional + named + unit payloads; `e.kind()` gives
  the tag, `e as E.V` extracts payload, `match` is exhaustive-checked.
- interfaces exist: `interface W { write(...) }`, methods on value/
  `mut`/`own` receivers; used for the transport port + Screen.
- `std/encoding/json` provides a Json tree (`jobj/jarr/jstr/jint/...`,
  `tojson`, `jparse`) - usable for `:=` JsonField value validation now
  and .posting.yaml `graphql.variables` later.
- No `std/yaml` - .posting.yaml is types-only this stage per plan.
- strings: `len`, `substr(s,a,b)`, `byteat(s,i)`, `find(s,sub)` are
  builtin; `std/strings` adds startswith/endswith/contains/trim/split/
  join/upper. No `rfind` in std/strings - the part-params right-scan
  needs a local helper.
- Errors are `[v, err]` tuples; `errors.msg(e)` reads text; raising a
  parse error = returning a non-nil `err`.
