#!/usr/bin/env bash
# Regenerate tests/golden/fixtures/<case>.{stdout,stderr,exit} with real xh.
# Requires: python3, $OXTPP_XH or `xh` on PATH. Run from repo root.
set -uo pipefail
cd "$(dirname "$0")/.."
XH="${OXTPP_XH:-$(command -v xh || true)}"
[ -n "$XH" ] || { echo "golden-gen: no xh (set OXTPP_XH)" >&2; exit 1; }
mkdir -p /tmp/oxttp-golden
for case in tests/golden/cases/*.case; do
    name="$(basename "$case" .case)"
    argv=""; stdin_unset=1; stdin=""
    declare -a envs=() scripts=()
    while IFS= read -r line; do
        case "$line" in
            '#'*|'') continue;;
            argv:*) argv="${line#argv: }";;
            stdin:*) stdin_unset=0; stdin="${line#stdin: }";;
            env:*) envs+=("${line#env: }");;
            script:*) IFS=';' read -ra parts <<< "${line#script: }"
                     for p in "${parts[@]}"; do p="${p# }"; p="${p% }"; [ -n "$p" ] && scripts+=("$p"); done;;
            files:*) :;;  # file pre-state only affects oxttp-side test env
        esac
    done < "$case"
    rm -rf "/tmp/oxttp-golden/$name"; mkdir -p "/tmp/oxttp-golden/$name"
    portf="/tmp/oxttp-golden/$name.port"; rm -f "$portf"
    python3 scripts/golden-server.py "$portf" "${scripts[@]}" &
    srv=$!
    for _ in $(seq 50); do [ -s "$portf" ] && break; sleep 0.05; done
    port="$(cat "$portf")"
    url="http://127.0.0.1:$port"
    run_argv="${argv//\{URL\}/$url}"
    (
        cd "/tmp/oxttp-golden/$name"
        env "${envs[@]}" -i PATH="$PATH" XH_CONFIG_DIR=/tmp/oxttp-golden/cfg TERM=xterm ${stdin_unset:+XH_NOSTDIN=1} -- \
            2>/dev/null || true
        if [ $stdin_unset -eq 1 ]; then
            env -i PATH="$PATH" "${envs[@]}" "$XH" $run_argv < /dev/null > stdout.raw 2> stderr.raw
        else
            env -i PATH="$PATH" "${envs[@]}" "$XH" $run_argv > stdout.raw 2> stderr.raw <<< "$stdin"
        fi
        echo -n $? > exit.raw
    )
    wait $srv 2>/dev/null
    mv "/tmp/oxttp-golden/$name/stdout.raw" "tests/golden/fixtures/$name.stdout"
    mv "/tmp/oxttp-golden/$name/stderr.raw" "tests/golden/fixtures/$name.stderr"
    mv "/tmp/oxttp-golden/$name/exit.raw" "tests/golden/fixtures/$name.exit"
    unset envs scripts
done
echo "golden-gen: fixtures regenerated"
