#!/usr/bin/env bash
# Copy the shared references/ files each skill uses into <skill>/references/ and point its links there.
# Installers (npx skills add) copy only a skill's own folder, so ../references/ never ships.
# Edit the top-level references/ only; rerun this script; CI fails if the copies drift.
set -euo pipefail
cd "$(dirname "$0")/.."

ref_names() {
  grep -ohE '(\.\./)?references/[a-z0-9-]+\.md' "$@" 2>/dev/null | sed -E 's#.*references/##' || true
}

for skill_md in */SKILL.md; do
  dir=${skill_md%/SKILL.md}
  [ "$dir" = references ] && continue

  docs=$(find "$dir" -maxdepth 1 -type f -name '*.md')
  # shellcheck disable=SC2086
  needed=$(ref_names $docs | sort -u)

  # References link to each other by bare filename, so pull those in too.
  while :; do
    more=$needed
    for n in $needed; do
      for m in $(grep -ohE '[a-z0-9-]+\.md' "references/$n" | sort -u); do
        [ -f "references/$m" ] && more=$(printf '%s\n%s\n' "$more" "$m")
      done
    done
    more=$(printf '%s\n' "$more" | sed '/^$/d' | sort -u)
    [ "$more" = "$needed" ] && break
    needed=$more
  done

  rm -rf "$dir/references"
  [ -z "$needed" ] && continue
  mkdir -p "$dir/references"
  for n in $needed; do
    [ -f "references/$n" ] || { echo "$dir links references/$n, which does not exist" >&2; exit 1; }
    cp "references/$n" "$dir/references/$n"
  done
  # shellcheck disable=SC2086
  perl -pi -e 's#\.\./references/#references/#g' $docs
done
