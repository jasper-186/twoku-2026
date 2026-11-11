#!/usr/bin/env bash
#
# Build the app package.
#
# Roku's packager takes whatever is in the package, so this lists the paths
# explicitly rather than zipping the repository. Zipping the repository would
# ship .git/, the development docs, any node_modules/ and any stale build
# output nested inside the package.
#
# Usage:
#   ./package.sh [output.zip]
#
# To install it on a development device:
#   curl --digest -u rokudev:<password> \
#        -F mysubmit=Install -F archive=@twoku.zip \
#        http://<device-ip>/plugin_install

set -euo pipefail

cd "$(dirname "$0")"

OUT="${1:-twoku.zip}"

# The env file configures which backend the app talks to. It is read from the
# root of the installed package (pkg:/env), so it has to ship.
#
# It is not committed - each deployment has its own. Start from env.example
# and edit BASE-URL to point the app at your own backend.
if [ ! -f env ]; then
    cp env.example env
    echo "note: no env file found, created one from env.example."
    echo "      Edit BASE-URL in it to point at your own backend."
    echo
fi

# Everything the app needs at runtime. Anything not listed here does not ship.
CONTENTS=(manifest source components images fonts env)

if [ ! -f manifest ]; then
    echo "error: no manifest in $(pwd)" >&2
    exit 1
fi

rm -f "$OUT"
zip -qr "$OUT" "${CONTENTS[@]}"

echo "Packaged $OUT"
echo
echo "Backend URL:"
echo "  $(grep -E '^BASE-URL=' env | head -1)"
echo
echo "Contents:"
unzip -Z1 "$OUT" | sed 's/^/  /'
