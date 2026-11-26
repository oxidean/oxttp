#!/usr/bin/env bash
# Regenerate cli/gen_assets.oxl + cli/gen_styles.oxl from pinned upstream
# xh artifacts (ADR-0041 vendored generate assets, ADR-0043 extracted
# .tmTheme palettes). Requires python3 + network. Run from repo root.
set -euo pipefail
cd "$(dirname "$0")/.."
python3 - "$@" <<'PYEOF'
import io, os, plistlib, sys, urllib.request

XH_REF = os.environ.get("OXTPP_XH_REF", "8b21cc07a6deeff0ca50ba2a4bfa8d34daffd94f")
BASE = "https://raw.githubusercontent.com/ducaale/xh/" + XH_REF + "/"

COMPLETIONS = {  # kind -> upstream path
    "zsh": "completions/_xh",
    "bash": "completions/xh.bash",
    "elvish": "completions/xh.elv",
    "fish": "completions/xh.fish",
    "nushell": "completions/xh.nu",
    "powershell": "completions/_xh.ps1",
}
DOCS = {"man": "doc/xh.1", "man-markdown": "doc/xh.1.md"}
THEMES = ["ansi", "solarized", "monokai", "fruity"]

def fetch(path):
    url = BASE + path
    with urllib.request.urlopen(url) as r:
        if r.status != 200:
            sys.exit(f"gen-assets: {url} -> HTTP {r.status}")
        return r.read()

def oxl_lit(data: bytes) -> str:
    """Escape bytes into a double-quoted oxl literal (ASCII-only output)."""
    out = []
    for b in data:
        c = chr(b)
        if c == "\\": out.append("\\\\")
        elif c == '"': out.append('\\"')
        elif c == "\n": out.append("\\n")
        elif c == "\t": out.append("\\t")
        elif c == "\r": out.append("\\r")
        elif 0x20 <= b < 0x7F: out.append(c)
        else: out.append("\\x%02x" % b)
    return '"' + "".join(out) + '"'

def emit_chunks(f, exprs, per=8):
    """Emit `return e1 + e2 + ...` chunked to keep lines reasonable."""
    for i in range(0, len(exprs), per):
        grp = exprs[i:i+per]
        f.write("        s = s + " + " + ".join(grp) + "\n")

# ---------- theme palette extraction (ADR-0043) ----------

# element -> scope stack (upstream palette!{} list + body token classes)
ELEMENTS = [
    ("http_keyword",   ["keyword.other.http"]),
    ("http_separator", ["punctuation.separator.http"]),
    ("http_version",   ["constant.numeric.http"]),
    ("method",         ["keyword.control.http"]),
    ("path",           ["const.language.http"]),
    ("status_code",    ["constant.numeric.http"]),
    ("status_reason",  ["keyword.reason.http"]),
    ("header_name",    ["source.http", "http.requestheaders", "support.variable.http"]),
    ("header_colon",   ["source.http", "http.requestheaders", "punctuation.separator.http"]),
    ("header_value",   ["source.http", "http.requestheaders", "string.other.http"]),
    ("error",          ["error"]),
    ("json_key",       ["keyword.other.name.jsonkv"]),
    ("json_string",    ["string.quoted"]),
    ("json_number",    ["constant.numeric"]),
    ("json_constant",  ["constant.language"]),
    ("markup_tag",     ["entity.name.tag"]),
    ("markup_attr",    ["entity.other.attribute-name"]),
    ("comment",        ["comment"]),
]

def atom_prefix_match(sel_atom, stack_atom):
    return stack_atom == sel_atom or stack_atom.startswith(sel_atom + ".")

def selector_matches(sel_atoms, stack):
    """TextMate descendant match: atoms match an ordered subsequence of
    stack, last atom must match the innermost stack element."""
    if not stack:
        return 0, 0
    # walk stack right-to-left for the last atom, then upward for the rest
    pos = len(stack) - 1
    depth_sum = 0
    for atom in reversed(sel_atoms):
        found = False
        while pos >= 0:
            if atom_prefix_match(atom, stack[pos]):
                depth_sum += atom.count(".") + 1
                pos -= 1
                found = True
                break
            pos -= 1
        if not found:
            return None
        # last selector atom must match the innermost stack element
        if atom is sel_atoms[-1] and pos == len(stack) - 2:
            pass
    if not atom_prefix_match(sel_atoms[-1], stack[-1]):
        return None
    return len(sel_atoms), depth_sum

def resolve_style(theme, stack):
    """syntect-style resolution: matching rules apply in document order
    scored by (atom count, prefix depth); later/scored-higher wins."""
    rules = []
    for entry in theme["settings"]:
        scope = entry.get("scope")
        if not scope:
            continue
        for sel in scope.split(","):
            sel = sel.strip()
            atoms = sel.split()
            m = selector_matches(atoms, stack)
            if m:
                rules.append((m[0], m[1], entry["settings"]))
    if not rules:
        return {}
    rules.sort(key=lambda r: (r[0], r[1]))
    style = {}
    for _, _, st in rules:
        style.update(st)
    return style

def color_to_sgr_params(fg):
    """Port of upstream convert_color (formatting/mod.rs)."""
    if fg is None:
        return None
    v = int(fg.lstrip("#"), 16)
    r, g, b, a = (v >> 24) & 0xFF, (v >> 16) & 0xFF, (v >> 8) & 0xFF, v & 0xFF
    if a == 0:
        if r <= 0x06:
            return str(30 + r)
        if r == 0x07:
            return ""          # white -> uncolored (upstream quirk)
        return "38;5;" + str(r)
    return "38;2;%d;%d;%d" % (r, g, b)

def style_to_sgr(style, default_fg):
    params = []
    fs = style.get("fontStyle", "") or ""
    if "bold" in fs: params.append("1")
    if "underline" in fs: params.append("4")
    if "italic" in fs: params.append("3")
    fg = color_to_sgr_params(style.get("foreground", default_fg))
    if fg: params.append(fg)
    return ";".join(params)

# ---------- fetch ----------

assets = {}
for kind, path in {**COMPLETIONS, **DOCS}.items():
    sys.stderr.write(f"fetch {path}\n")
    assets[kind] = fetch(path)
themes = {}
for t in THEMES:
    sys.stderr.write(f"fetch assets/themes/{t}.tmTheme\n")
    themes[t] = plistlib.loads(fetch(f"assets/themes/{t}.tmTheme"))

# ---------- emit gen_assets.oxl ----------

hdr = ("package main\n\n// Code generated by scripts/gen-assets.sh -- DO NOT EDIT.\n"
       "// Source: ducaale/xh @ " + XH_REF + " (upstream-vendored, ADR-0041).\n\n")

with open("cli/gen_assets.oxl", "w") as f:
    f.write(hdr)
    f.write("/// gen_completion returns the vendored completion script for a\n")
    f.write("/// --generate <kind> shell name (clap_complete value names).\n")
    f.write("fn gen_completion(shell: str) -> str {\n")
    f.write("    let s: str = \"\"\n")
    for kind in ["bash", "elvish", "fish", "nushell", "powershell", "zsh"]:
        f.write(f"    if shell == \"{kind}\" {{\n")
        emit_chunks(f, [oxl_lit(assets[kind])])
        f.write("    }\n")
    f.write("    return s\n}\n\n")
    f.write("/// gen_doc returns the vendored roff man page or its markdown.\n")
    f.write("fn gen_doc(markdown: int) -> str {\n")
    f.write("    let s: str = \"\"\n")
    f.write("    if markdown == 0 {\n")
    emit_chunks(f, [oxl_lit(assets["man"])])
    f.write("    } else {\n")
    emit_chunks(f, [oxl_lit(assets["man-markdown"])])
    f.write("    }\n    return s\n}\n")

# ---------- emit gen_styles.oxl ----------

elem_names = [e for e, _ in ELEMENTS] + ["default"]
with open("cli/gen_styles.oxl", "w") as f:
    f.write(hdr)
    f.write("/// style_sgr returns the SGR parameter string (e.g. \"1;38;5;12\",\n")
    f.write("/// \"\" = uncolored) for a theme/element pair, resolved offline from\n")
    f.write("/// the vendored .tmTheme files (syntect prefix-match semantics +\n")
    f.write("/// upstream convert_color: index 0-6 -> SGR 30-36, 7 -> uncolored,\n")
    f.write("/// else 38;5;n; opaque colors -> 38;2;r;g;b).\n")
    f.write("fn style_sgr(theme: str, elem: str) -> str {\n")
    for t in THEMES:
        theme = themes[t]
        default_fg = theme["settings"][0]["settings"].get("foreground")
        f.write(f"    if theme == \"{t}\" {{\n")
        for name, stack in ELEMENTS:
            st = resolve_style(theme, stack)
            sgr = style_to_sgr(st, default_fg)
            f.write(f"        if elem == \"{name}\" {{ return \"{sgr}\" }}\n")
        dflt = color_to_sgr_params(default_fg) or ""
        f.write(f"        if elem == \"default\" {{ return \"{dflt}\" }}\n")
        f.write("        return \"\"\n    }\n")
    f.write("    return \"\"\n}\n")

sys.stderr.write("wrote cli/gen_assets.oxl + cli/gen_styles.oxl\n")
PYEOF
