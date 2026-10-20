#!/bin/sh
# Saves one Linear-hosted upload into an export folder's files/ directory, where `arc import linear` finds it.
# Signed upload links expire a few minutes after Linear issues them, so run this right after reading the issue.
#
#   scripts/fetch-linear-upload.sh import/linear "https://uploads.linear.app/...?signature=..."
set -eu
[ $# -eq 2 ] || { echo "usage: $0 <export-folder> <url>" >&2; exit 64; }
folder="$1"
url="$2"
stable="${url%%\?*}"
key="$(printf '%s' "$stable" | shasum -a 256 | cut -c1-16)"
name="$(python3 -c 'import sys, urllib.parse; print(urllib.parse.unquote(sys.argv[1].rsplit("/", 1)[1]))' "$stable")"
safe="$(printf '%s' "$name" | sed 's/[^A-Za-z0-9._() -]/_/g')"
mkdir -p "$folder/files/$key"
curl -fsSL --max-time 120 -o "$folder/files/$key/$safe" "$url"
echo "$folder/files/$key/$safe"
