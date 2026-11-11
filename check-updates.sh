#!/bin/bash
# Count pending updates for the devi.arch-updates bar widget, and list them.
#
# Output, line 1 (unchanged from 1.6.x, so an old widget still works):
#   "<total> <repo> <aur> <mise> <plugins> <themes>"
# Following lines, one per pending item, tab-separated (printf \t, never a
# literal tab in this file, so the format survives editors and git):
#   repo<TAB><name><TAB><old-version><TAB><new-version>
#   aur<TAB><name><TAB><old-version><TAB><new-version>
#   mise<TAB><name><TAB><current><TAB><latest>
#   plugin<TAB><name><TAB><commits-behind>
#   theme<TAB><name><TAB><commits-behind>
# Package/version fields never contain tabs or newlines, so the widget can
# split on them safely. No line is emitted for a category with zero items.
#
# Check-only: nothing here installs anything. Installs go through omarchy update
# (system, AUR, mise) and, separately, omarchy plugin update / theme git pull
# for shell plugins and themes.

repo=0
aur=0
mise=0
plugins=0
themes=0
details=""

# Append one detail line. $1 is a printf format (with \t escapes), the rest
# are the fields, so no literal tabs are needed anywhere in this script.
add_detail() {
  local fmt="$1"; shift
  details+=$(printf "$fmt" "$@")$'\n'
}

# Repo (pacman-contrib). checkupdates prints "name old-version -> new-version"
# per line; keep the raw output instead of only counting it.
repo_out=""
if command -v checkupdates >/dev/null 2>&1; then
  repo_out=$(checkupdates 2>/dev/null)
fi
if [ -n "$repo_out" ]; then
  repo=$(printf '%s\n' "$repo_out" | wc -l)
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    # shellcheck disable=SC2086: intentional word-splitting on the 4 fields
    set -- $line
    name=${1##*/}
    [ -n "$name" ] && [ -n "$2" ] && [ -n "$4" ] || continue
    add_detail 'repo\t%s\t%s\t%s' "$name" "$2" "$4"
  done <<EOF
$repo_out
EOF
fi

# AUR (yay, falls back to paru). -Qua prints the same
# "name old-version -> new-version" shape, sometimes with an "aur/" prefix
# on the name, which is stripped above.
aur_out=""
if command -v yay >/dev/null 2>&1; then
  aur_out=$(yay -Qua 2>/dev/null)
elif command -v paru >/dev/null 2>&1; then
  aur_out=$(paru -Qua 2>/dev/null)
fi
if [ -n "$aur_out" ]; then
  aur=$(printf '%s\n' "$aur_out" | wc -l)
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    # shellcheck disable=SC2086: intentional word-splitting on the 4 fields
    set -- $line
    name=${1##*/}
    [ -n "$name" ] && [ -n "$2" ] && [ -n "$4" ] || continue
    add_detail 'aur\t%s\t%s\t%s' "$name" "$2" "$4"
  done <<EOF
$aur_out
EOF
fi

# Mise dev tools. MISE_MINIMUM_RELEASE_AGE=0 so the count matches what an
# update installs (same as omarchy update does). Prefers --json + jq; falls
# back to counting plain output lines after the header when jq is missing.
if command -v mise >/dev/null 2>&1; then
  if command -v jq >/dev/null 2>&1; then
    mise_out=$(MISE_MINIMUM_RELEASE_AGE=0 timeout 120 mise outdated --json 2>/dev/null | jq -r 'to_entries[] | select(.value.current != .value.latest and .value.latest != "") | ["mise", .key, (.value.current // ""), (.value.latest // "")] | @tsv' 2>/dev/null)
    if [ -n "$mise_out" ]; then
      mise=$(printf '%s\n' "$mise_out" | wc -l)
      details+="$mise_out"$'\n'
    fi
  else
    mise_out=$(MISE_MINIMUM_RELEASE_AGE=0 timeout 120 mise outdated 2>/dev/null | awk 'NR>1 && NF>=3 {print "mise\t" $1 "\t" $2 "\t" $3}')
    if [ -n "$mise_out" ]; then
      mise=$(printf '%s\n' "$mise_out" | wc -l)
      details+="$mise_out"$'\n'
    fi
  fi
fi

# Shell plugins: git checkouts in ~/.config/omarchy/plugins with a remote.
# A plugin counts when its tracked branch is behind after a fetch (same
# approach as techspawn.updates). Fetches run in parallel so a full plugin
# list stays fast. Plain folders, symlinks, and checkouts without a remote
# are not counted. Each behind plugin writes one detail line
# ("plugin<TAB><name><TAB><commits-behind>") to the temp dir, so the
# count is the file count and the names survive.
plugins_dir="$HOME/.config/omarchy/plugins"
if [ -d "$plugins_dir" ]; then
  plug_tmp=$(mktemp -d)
  for d in "$plugins_dir"/*/; do
    d=${d%/}
    [ -f "$d/manifest.json" ] || continue
    [ -L "$d" ] && continue
    [ -d "$d/.git" ] || continue
    (
      branch=$(git -C "$d" symbolic-ref -q --short HEAD 2>/dev/null)
      remote=""; ref=""
      if [ -n "$branch" ]; then
        remote=$(git -C "$d" config --get "branch.$branch.remote" 2>/dev/null)
        merge=$(git -C "$d" config --get "branch.$branch.merge" 2>/dev/null)
        if [ -n "$remote" ] && [ "$remote" != "." ] && [ -n "$merge" ]; then
          ref="$merge"
        fi
      fi
      if [ -z "$ref" ]; then
        git -C "$d" remote get-url origin >/dev/null 2>&1 || exit 0
        remote="origin"; ref="HEAD"
      fi
      if timeout 30 git -C "$d" fetch --quiet --no-tags "$remote" "$ref" 2>/dev/null; then
        target=$(git -C "$d" rev-parse -q --verify 'FETCH_HEAD^{commit}' 2>/dev/null)
        if [ -n "$target" ]; then
          behind=$(git -C "$d" rev-list --count "HEAD..$target" 2>/dev/null || echo 0)
          behind=$(echo "$behind" | tr -d ' ')
          if [ -n "$behind" ] && [ "$behind" -gt 0 ] 2>/dev/null; then
            printf 'plugin\t%s\t%s\n' "$(basename "$d")" "$behind" > "$plug_tmp/$(basename "$d")"
          fi
        fi
      fi
    ) &
  done
  wait
  plugins=$(find "$plug_tmp" -type f 2>/dev/null | wc -l)
  for f in "$plug_tmp"/*; do
    [ -f "$f" ] || continue
    details+=$(cat "$f")$'\n'
  done
  rm -rf "$plug_tmp"
fi

# Git themes (from omarchy-theme-extras). A theme counts when its upstream
# branch is behind after a fetch.
if command -v omarchy-theme-extras >/dev/null 2>&1; then
  while IFS= read -r t; do
    [ -n "$t" ] || continue
    [ -d "$t/.git" ] || continue
    if timeout 30 git -C "$t" fetch --quiet 2>/dev/null; then
      behind=$(git -C "$t" rev-list --count 'HEAD..@{upstream}' 2>/dev/null || echo 0)
      behind=$(echo "$behind" | tr -d ' ')
      if [ -n "$behind" ] && [ "$behind" -gt 0 ] 2>/dev/null; then
        themes=$((themes + 1))
        add_detail 'theme\t%s\t%s' "$(basename "$t")" "$behind"
      fi
    fi
  done < <(omarchy-theme-extras 2>/dev/null)
fi

# Normalize to plain numbers (wc -l output can carry spaces).
repo=$(echo "$repo" | tr -d ' ')
aur=$(echo "$aur" | tr -d ' ')
mise=$(echo "$mise" | tr -d ' ')
plugins=$(echo "$plugins" | tr -d ' ')
themes=$(echo "$themes" | tr -d ' ')

# Guard against empty/non-numeric values (e.g. a failed query).
for v in repo aur mise plugins themes; do
  eval "val=\$$v"
  case "$val" in
    ''|*[!0-9]*) eval "$v=0" ;;
  esac
done

echo "$((repo + aur + mise + plugins + themes)) $repo $aur $mise $plugins $themes"
printf '%s' "$details"
