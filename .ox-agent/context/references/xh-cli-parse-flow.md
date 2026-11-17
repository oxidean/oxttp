# xh CLI parse flow — source-verified @ 8b21cc0 (src/cli.rs, src/request_items.rs)

Upstream `Cli::try_parse_from` pipeline order (all errors clap-shaped,
exit 2 unless noted):

1. `default_cli_args()`: `<config>/config.json` `{"default_options":
   [...]}` inserted between argv0 and argv. Missing file silent;
   unreadable → `\nxh: warning: Unable to read config file: <e>\n`;
   bad JSON/types → `\nxh: warning: Unable to parse config file: <e>\n`.
2. clap tokenize: `args_override_self` (later wins), `--no-<long>`
   auto-synthesized for every option (SetTrue + overrides_with, last
   occurrence wins), value parsers run at token position.
3. `generate.is_some()` → return early (positional skipped via
   declared conflict).
4. `raw_method_or_url == "help"` → LONG help, exit 0.
5. `parse_method`: positional 1 all-ASCII-alpha & non-empty → method
   uppercased; then rest[0] is URL, missing → `error: Missing <URL>`.
6. Each later rest arg → `RequestItem::from_str` → `Invalid value for
   '[REQUEST_ITEM]...': "<raw>"` (`:=` failures append the serde
   error: `... "<raw>" <err>`).
7. bin_name = argv0 basename minus `.ext`: `https|xhs|xhttps` →
   https=true; `http|https` or `XH_HTTPIE_COMPAT_MODE` set (empty
   counts) → httpie_compat_mode.
8. `process_relations`: verbose>0→all; curl_long→curl; https→
   default_scheme=https; bearer→auth_type=bearer & auth=bearer;
   check_status/stream tri-state (no-* flags); download→follow +
   check_status=Some(true); body_type from json/form/multipart;
   `--raw` + non-empty body → "Request body (from --raw) and request
   data (key=value) cannot be mixed."; session_read_only→session.
9. `construct_url` → `Invalid <URL>: <err>`: scheme "http://" default
   (`--default-scheme`/`--https` override; "://" suffix added if
   absent); `://x`→scheme+x; `:x`→scheme+"localhost"+x; no
   `[a-zA-Z0-9]://.+` → prepend scheme; else as-is.
10. Effective check_status = `check_status.unwrap_or(!compat)`;
    effective method = explicit or `pick_method` (GET iff body empty
    else POST — multipart counts non-empty; `is_body_empty` skips
    header/param items).

Value-parser messages (clap InvalidValue wrappers, exit 2):
- timeout: `Connection timeout is not a valid number|is negative|is
  too big` (f64, NaN rejected, >=u64::MAX secs/inf too big).
- print/history-print: `'<ch>' is not a valid value` (chars HBhbm).
- format-options: `Format options consist of a key and a value,
  separated by a ":".` / `Unsupported option '<k>'` (json.sort_keys) /
  `Unknown option '<k>'` / `Invalid value '<v>' in '<a>'`; lowercased,
  comma-split, merged last-wins.
- proxy: `The value passed to --proxy should be formatted as
  <PROTOCOL>:<PROXY_URL>` / `Unknown protocol to set a proxy for:
  <p>` / `Invalid proxy URL '<u>' for protocol '<p>': <e>` (protocols
  http|https|all; URL absolute).
- resolve: `Value should be formatted as <HOST>:<ADDRESS> (not
  <HOST>:<PORT>:<ADDRESS>)` (exactly 2 colons) / `... as
  <HOST>:<ADDRESS>` (no colon) / `Invalid address '<a>'` (IPv6
  `[::1]` or bare).
- unstable-m-sig-comp: infallible — trim, lowercase to first ';',
  keep params.
- verify: infallible — no|false→No, yes|true→Yes, else CA path.
- response-charset: normalize (lowercase, strip non-[alnum_\-:],
  u8/utf→UTF-8, u16→UTF-16LE, -/_ +digit-split variants) → WHATWG
  label; else `<label> is not a supported encoding, please refer to
  https://encoding.spec.whatwg.org/#names-and-labels ...`.
- max-redirects: usize → `invalid digit found in string`.

Help trailers: short help gets after_help `Each option can be reset
with a --no-OPTION argument.\n\nRun "xh help" for more complete
documentation.`; long help gets `Each option can be reset with a
--no-OPTION argument.` Usage: `xh [OPTIONS] <[METHOD] URL>
[REQUEST_ITEM]...` (positional slots: `raw_method_or_url` required +
`raw_rest_args` variadic only — URL lives inside rest args).

Deferred-surface app errors (exit 1, `xh: error: <msg>`): m-sig →
"This binary was built without message signature support. Enable the
'http-message-signatures' feature."; http-version=3-prior-knowledge →
"This binary was built without support for HTTP/3..."; https/TLS
surfaces → unsupported-in-this-build class (ADR 0006).
