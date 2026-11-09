#!/bin/bash
# Roundtrip the barctl scripts without the shell: glassy set/get on a temp
# config, autohide clamp on a temp shell.json, layout parse, plugin status.
set -euo pipefail
here=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

echo '{}' > "$tmp/glassy.json"
export OMARCHY_GLASSY_CONFIG="$tmp/glassy.json"

"$here/scripts/barctl-glassy" set opacity 0.42
"$here/scripts/barctl-glassy" set blur true
"$here/scripts/barctl-glassy" set width 80%
"$here/scripts/barctl-glassy" set shadow_tint 0.5
v=$("$here/scripts/barctl-glassy" get | grep '^opacity=') && [[ $v == opacity=0.42 ]]
grep -q '^blur=true$' <("$here/scripts/barctl-glassy" get)
grep -q '^width=80%$' <("$here/scripts/barctl-glassy" get)
"$here/scripts/barctl-glassy" set opacity abc && exit 1 || echo "invalid rejected"

cp "$HOME/.config/omarchy/shell.json" "$tmp/shell.json"
export OMARCHY_SHELL_JSON="$tmp/shell.json"
"$here/scripts/barctl-autohide" set 640
[[ $("$here/scripts/barctl-autohide" get) == 640 ]]
"$here/scripts/barctl-autohide" set 9999
[[ $("$here/scripts/barctl-autohide" get) == 5000 ]]

"$here/scripts/barctl-layout" list | grep -q '|'
export OMARCHY_BAR_CONTROL_STATE="$tmp/state"
[[ -z $("$here/scripts/barctl-layout" take) ]]
"$here/scripts/barctl-layout" color omarchy.clock '#89b4fa'
"$here/scripts/barctl-layout" list | grep -q '|omarchy.clock|#89b4fa$'
"$here/scripts/barctl-layout" color omarchy.clock -
"$here/scripts/barctl-layout" list | grep -q '|omarchy.clock|$'
"$here/scripts/barctl-layout" take >/dev/null
"$here/scripts/barctl-layout" keep layout
out=$("$here/scripts/barctl-layout" take)
[[ $(sed -n 1p <<<"$out") == layout ]]
[[ $(sed -n 2p <<<"$out") =~ ^[0-9]+$ ]]
[[ -z $("$here/scripts/barctl-layout" take) ]] && echo "reopen state ok"
"$here/scripts/barctl-plugins" status | grep -E '^(glassy|autohide) '

echo ALL OK
