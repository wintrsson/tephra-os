#!/usr/bin/env bash
# Publishes the files of the current commit to the public repo (wintrsson/tephra-os) as ONE new commit on its main.
# The private repo's history never goes there (it has personal details); only a snapshot of the files does.
# The snapshot's UPDATE_BRANCH says "main", so public installs update from the public repo's main.
# Stops if a personal detail is found in the files.
# Usage: tools/publish-public.sh            (run from a clean checkout of the update branch, after a release)
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PUBLIC="${TEPHRA_PUBLIC:-https://github.com/wintrsson/tephra-os}"
cd "$ROOT"
git diff --quiet HEAD || { echo "publish: commit your changes first" >&2; exit 1; }
VER="$(cat shell/tephra-shell/VERSION)"

# Personal details that must never be published (a username, real names, Steam IDs other than the public base, emails).
if git grep -n -i -E 'noahd|\bnoah\b|nowah|gmail\.com|7656119[0-9]{10}' -- . ':!tools/publish-public.sh' \
    | grep -v '76561197960265728'; then
  echo "publish: personal details found above; remove them first" >&2
  exit 1
fi

W="$(mktemp -d)"
trap 'rm -rf "$W"' EXIT
git clone -q --depth 1 "$PUBLIC" "$W/pub"
# Replace the public files with this commit's (files deleted here are deleted there too).
git -C "$W/pub" rm -q -r --ignore-unmatch . >/dev/null
git archive HEAD | tar -x -C "$W/pub"
echo main > "$W/pub/shell/tephra-shell/UPDATE_BRANCH"
cd "$W/pub"
git add -A
if git diff --cached --quiet; then
  echo "publish: the public repo already has these files"
  exit 0
fi
export GIT_AUTHOR_DATE GIT_COMMITTER_DATE
GIT_AUTHOR_DATE="$(date -u +%Y-%m-%dT%H:%M:%S+0000)"
GIT_COMMITTER_DATE="$GIT_AUTHOR_DATE"
git -c user.name=wintrsson -c user.email=340798008+wintrsson@users.noreply.github.com commit -qm "Tephra $VER"
git push -q origin HEAD:main
echo "publish: Tephra $VER is on $PUBLIC"
