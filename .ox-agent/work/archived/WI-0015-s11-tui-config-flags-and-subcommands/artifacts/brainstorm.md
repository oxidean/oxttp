# WI-0015 brainstorm — S11 config, flags, subcommands

Settled upstream: corpus §1/§2/§8.1 verified against posting-src
code (see discovery + context/references/posting3-cli-config-
semantics.md). Open questions resolved below; every choice cites
corpus or names an explicit degrade per ADR-0006/0024.

## Q1 — Where does config live?

### Option A — new leaf `core/config` (CHOSEN)

`core/config/config.oxl` + `config_test.oxl`: `Settings` struct
(all 40 keys), `defaults()`, `load(file, environ_probe)`, typed
decode off `core/yaml` DOM (ADR-0030's pinned consumer),
`POSTING_*` env merge, `validate()` warnings, `keys_for(action)`
rebind map, paths helpers (`config_dir/file`, `data_dir`,
`theme_dir`, `history_dir`, `env_memory`, `default_coll_dir`).

Pros: mirrors upstream internal/config+paths one-for-one; `run`
subcommand consumes Settings without dragging App state; unit-
testable with injected env/file. Cons: none real — leaf matches
ADR-0016 layout.

### Option B — tui-local config (REJECTED)

`run` needs ssl.* + validation semantics without a UI; a
tui-local loader duplicates or couples. Rejected.

## Q2 — argv parsing strategy

### Option A — shared/args for top-level; hand-rolled per
subcommand mirroring upstream (CHOSEN)

Mission pins shared/args for the flag surface. Top-level spec:
`-c/--collection` str, `-e/--env` repeat, `-h/--help`,
`-v/--version` + positional collection (corpus §1.1) → Spec
covers it. Subcommand handlers parse their own args exactly like
upstream: `run` hand-parses (flags may follow PATH, `--k=v`
allowed, one positional); `import` same shape; `remote` Go-flag
subset + `--instance`/`--json`/`--env`/`--none`/`--curl`/`--yaml`/
`--name`; `locate`/`version` trivial. `tui/cli.oxl` hosts
dispatch + subcommand impls; `tui/main.oxl` calls it before any
session open (subcommands must work on non-tty).

### Option B — shared/args for everything (REJECTED)

run.go/import.go deliberately allow flags after positionals —
upstream hand-rolls that loop; forcing args.Spec risks diverging
on `posting run dir --json` orderings.

## Q3 — Theme representation on an 8-color screen

### Option A — semantic slots → ANSI-8 quantized fg; bg default
(CHOSEN)

`Theme{name, is_light, slots: primary, secondary, accent, warning,
error, success, text}` where each slot is an ANSI-8 id computed by
nearest-RGB quantization of the hex. Builtin catalog = the 37
terma entries (hex table embedded, extracted from terma v0.27.0
theme.go — names+colors verbatim). Render replaces hardcoded fg
ids with slot lookups: method cell/accents→accent|primary, normal
text→text, warn/error/success toasts+status classes→their slots,
header→primary. bg cells stay `-1` (terminal default): painting a
quantized background across every cell changes contrast in ways
8 colors can't honor — explicit deviation. AttrDim continues to
carry "muted".

### Option B — extend AnsiScreen to truecolor (REJECTED)

Driver change + escape-sequence growth mid-stage; S11's bar is
the theme/styling *corpus* (names, files, picker, config keys),
not color fidelity. Deferred to M4 with a deviation note.

## Q4 — Theme/gradient picker mechanics

### Option A — MThemePicker modal, live-apply on move (CHOSEN)

Rows: `Yours` group (user themes), `Dark`, `Light` (builtin
order preserved), plus a `sidebar gradient…` variant listing
theme|off|<each theme>. Cursor move applies the theme
immediately when `command_palette.theme_preview` is set;
`enter` commits for the session; `escape` restores the
snapshot taken on open. Mirrors overlays.go semantics.
`load_builtin_themes=false`+≥1 user theme → only Yours shown
(corpus §8.1).

## Q5 — f3/f4 pager/editor handoff

### Option A — session close → `exec.Cmd.run()` → reopen (CHOSEN)

New effect `EExternal{cmd}`: dispatch stashes the command; the
main loop closes the session (restores term+alt-screen), runs
`sh -c "<pager> <tmpfile>"` (stdio inherited), reopens the
session, full render. `pager_json` overrides `pager` when the
body parses as JSON; `editor` for f4. Missing command → toast
mirroring degrade. POSTING_EDITOR/POSTING_PAGER/POSTING_PAGER_JSON
override config values; $EDITOR/$PAGER are the config defaults
(upstream Defaults()). Applies to request-body and response-body
panes per §8.4.

### Option B — keep degrade (REJECTED)

Now implementable; leaving it would strand two corpus bindings.

## Q6 — Disk history shape

### Option A — upstream envelope + our-shape entries (CHOSEN)

`{version:1, next_id, entries[]}` at
`<data>/history/<sha256hex(abs-coll)>.json`, `.lock` sidecar
created around rewrite (best-effort lock: create-if-absent,
deviation — no flock), MaxEntries=100, MaxBytes=50MiB
newest-fitting with oversized dropped. Entries carry our fields
(id,title,method,url,status,reason,elapsed_ms,size,req_yaml,
resp_text,hdr/ck/tr rows). Load on collection open; append on
install_resp when `history.enabled`. Foreign/undecodable entries
are dropped on rewrite — deviation (upstream retains them; our
json has no RawMessage). 0700/0600 perms unavailable (no chmod)
— deviation.

### Option B — upstream HistoryEntry JSON clone (REJECTED)

Would need model.Request/Response JSON field-fidelity for
interop we can't verify; envelope compat already gives the
user-facing contract (file location, caps, disabled mode).

## Q7 — use_host_environment

### Option A — accept + startup degrade warn (ONLY OPTION)

No `environ()` in std — host vars can't be enumerated. When the
resolved setting is true, emit one startup warning
`use_host_environment: host env enumeration unsupported in this
build` and continue without a host layer. File upstream issue on
oxidean/oxl for `os.environ()`.

## Q8 — Positional collection arg

### Option A — accept per corpus §1.1 (CHOSEN)

Upstream code rejects positionals (doc↔code disagreement);
corpus + S10 behavior accept. Keep `posting <dir>` working;
record deviation. Rejecting would break the documented contract
and S10 muscle memory.

## Q9 — remote subcommand degrade shape

### Option A — corpus-shaped degrade (CHOSEN)

`remote --help`/unknown → upstream usage text/exit codes.
`remote list` → print the empty report shape (text: header line
`PID  VERSION  COLLECTION  SOCKET` then "no running Posting"
note; --json: `[]`). All instance commands (`requests show open
send response env save`) → stderr `no running Posting found
(unix sockets unsupported in this build)` exit 1. `remote skill`
→ embedded SKILL.md verbatim to stdout exit 0 (needs no
instance). `remote send` non-zero on failure contract holds
degenerate-ly.

## Q10 — curl import scope (§4.4/§4.12/§7.7)

### Option A — §7.7 flag subset → draft fields (CHOSEN)

`import_curl(text) -> [PRequest-ish draft patch, warns]`: tokenize
by whitespace honoring `'…'`/`"…"` + `\` continuations; handle
`-X --request`, `-H --header`, `-d --data --data-raw --data-ascii
--data-binary (@file → file body path)`, `--json` (CT+json body),
`-F --form --form-string` (→ multipart block, locked-edit like
loaded files), `-u --user` (basic; `--digest`→digest),
`-b --cookie` (Cookie header), `-A --user-agent`, `-e --referer`,
`-k --insecure` (options.verify_ssl=false), `-L --location`
(follow_redirects=true), `-x --proxy` (options.proxy_url),
`-m --max-time` (options.timeout), `-G` (data→query params), `-I`
(HEAD), `--oauth2-bearer` (bearer auth); `-s -S -v -i -o -O -w`
ignored silently (upstream ignores `-s -v -o`). `$NAME` preserved
verbatim. Multiline `\` joins. Replaces draft except
name/description/file. URL-bar enter + palette dialog both route
here; palette "Import curl command…" opens a one-field modal
(MCurl) whose `ctrl+j` imports (§4.12).

### Option B — degrade stays (REJECTED)

Explicitly queued for S11 in two degrade sites.

## Q11 — Variables screen editing (§4.11)

### Option A — inline session-layer edit (CHOSEN)

Rows carry (name, value, layer) triples internally. `enter` on a
row → edit its value as a session override (highest layer);
`a` → prompt-style new NAME=VALUE session entry; `d` → remove the
session override for that name exposing the file value (only when
a session override exists — else the row's `d` is inert);
`ctrl+r` reveal already works. Render keeps `NAME = value
[layer]` rows; overrides rows re-render to `[session]`.

## Q12 — environments.json triggers

### Option A — recall at launch, remember on env_pick (CHOSEN)

Recall only when no `-e` at launch (main.go); remembered value
seeds `env_active` before `load_collection`. env_pick writes via
tmp+rename; `(none)` selection deletes the key. Deviation: our
memory stores `{name,dir}` form only (we never persist raw file
lists — env_pick selects names; file-path `-e` args aren't
remembered, matching "remembered env is a name" usage).

## Q13 — No-op/half-wired keys policy

Accept-and-note (never silent): `watch_*` (no fsnotify),
`remote_control.enabled` (enabled+no UDS → one startup message
mirroring upstream's listen-failure text; disabled → silent),
`spacing` (accepted, always standard), `animation`,
`use_xresources`, `watch_themes` (P2 no-ops),
`text_input.blinking_cursor` (false hides cursor; true = current
static cursor — no blink timer in the read loop, deviation),
`heading.hostname` (strip `[b]…[/]` markup → literal),
`curl_export_extra_args` (stored; export itself degrades),
`pager_json` (wired into f3 selection), `ssl.password` (tls
encrypted-key support TBD — problems report at send time per
corpus §2.2).

## Q14 — `run` captures degrade

Request with non-empty `captures` → per-request FAILED with
`captures unsupported in this build — lands M4` (upstream: all
captures must succeed or send is a failure — failing is the
honest mapping, never silently skip). Requests without captures
run fully.

## Open questions → none blocking

Positional-collection disagreement resolved by corpus fidelity
(Q8). `posting` vs `oxttp-tui` branding on `--version`: print
`Posting <ver>` — the binary emulates posting (corpus §1.1
contract); same call xh-side already prints xh strings.
