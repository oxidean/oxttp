# ADR-0045 — Import DOM approximations: yaml subset, json lexemes, fs confinement

- Status: accepted
- Date: 2026-11-28
- Work item: WI-0019 (M4c)

## Context

Upstream importers consume untrusted documents with Go's `yaml.v3`
(full YAML 1.2) and `encoding/json` (`json.Number` preserves numeric
lexemes; struct unmarshal is last-key-wins), and `importing.Write`
confines output with `os.Root`. oxl 0.26.0 offers `core/yaml` (a
posting/config-pinned DOM subset: no anchors, aliases, tags, flow
collections, or multi-doc — all parse errors), `std/encoding/json`
(a `Json` DOM that types numbers as int/float and loses lexemes), and
plain `os.*` file calls with no `os.Root`.

## Decision

Deviations are accepted ONLY where routed through upstream's own
diagnostic shapes; everything else ports verbatim.

1. **OpenAPI YAML input** uses `core/yaml` — documents needing
   anchors/aliases/tags/flow/multi-doc fail with a yaml-shaped parse
   error where upstream succeeds. JSON input is unaffected (full
   `std/encoding/json` DOM). Recorded deviation; revisit if oxl grows
   a yaml package.
2. **Numbers**: `scalar()` formats `Json` kind-2 ints exactly and
   kind-6 floats with shortest round-trip formatting; Go
   `json.Number` lexeme preservation (e.g. `1e2` staying `1e2`) is
   approximated — `json.Marshal(float64)` equivalence is the target.
   Duplicate object keys resolve last-wins at DOM access.
3. **Filesystem confinement**: `safePath`/`safePart` port verbatim
   (control chars + `<>:"/\|?*` → `-`, 120-rune cap, reserved device
   names prefixed `_`, `untitled` fallback). The `-N` collision
   suffix loop checks `os.exists` before `os.writefile_`; the
   check-then-write race is accepted (single-user CLI import, same
   failure mode upstream's O_EXCL avoids only under adversarial
   concurrent writers). Incomplete-import cleanup deletes created
   files in reverse order on failure.
4. **Regexes**: upstream's four import regexes (postman/bruno
   `identifier`, `reference`/`template` `{{…}}`/`{…}`, OAS version
   `^3\.[01]\.[0-9]+$`, annotation line) are hand-rolled byte
   scanners — all are simple regular languages; std/regexp is used
   only if its API proves a drop-in during implementation.

## Consequences

- Spec acceptance criteria call out the YAML-subset and number-lexeme
  deviations explicitly; corpus-fidelity contract satisfied via
  recorded deviation, not silence.
- Bruno `.bru` parsing is pure text (no yaml/json dependency for the
  format itself) — unaffected.
- Postman/OpenAPI JSON inputs keep full fidelity modulo item 2.
