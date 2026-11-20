#!/usr/bin/env bash
# deploy/env-import.sh: write .env.azure (the app's API keys, never committed).
#
# Rep-Tell has no current host to copy settings from (no Render/Vercel), so:
#
#   bash deploy/env-import.sh                 # asks for each key (typing is hidden)
#   bash deploy/env-import.sh path/to/.env    # copies them from a .env file
#                                             # (e.g. the developer's local one,
#                                             # uploaded to Cloud Shell)
#
# Every name is written with this project's suffix: GEMINI_API_KEY becomes
# GEMINI_API_KEY_rep_tell (see deploy/AZURE.md, "Settings"). Values are never
# printed. An existing .env.azure is backed up to .env.azure.bak first; when
# asking, Enter keeps the value it already has.
#
# Left out (and listed): PORT (Azure always uses 8080), DB_* (the app never
# uses a database; only backend/backend/test_db.py does), website build
# settings (VITE_*: the website is built by GitHub from deploy/azure-deploy.conf),
# placeholders such as "your_gemini_api_key", empty and multi-line values.
set -euo pipefail
. "$(cd "$(dirname "$0")" && pwd)/lib.sh"

load_conf
OUT="$REPO_DIR/.env.azure"
SRC="${1:-}"

# Settings the code reads, in the order they are asked for, with where to get them.
KNOWN_KEYS="GEMINI_API_KEY YOUTUBE_API_KEY NEWS_API_KEY REDDIT_CLIENT_ID REDDIT_CLIENT_SECRET BLUESKY_HANDLE BLUESKY_APP_PASSWORD"
where() {
  case "$1" in
    GEMINI_API_KEY) echo "Google AI Studio -> Get API key (https://aistudio.google.com/apikey). Recommended: without it new mentions get only keyword sentiment." ;;
    YOUTUBE_API_KEY) echo "Google Cloud console -> APIs & Services -> Credentials -> API key, with 'YouTube Data API v3' enabled. Recommended: without it no YouTube videos are collected." ;;
    NEWS_API_KEY) echo "https://newsapi.org/account. Optional: news still comes from Google News RSS." ;;
    REDDIT_CLIENT_ID|REDDIT_CLIENT_SECRET) echo "https://www.reddit.com/prefs/apps -> create a 'script' app. Optional (both or neither): Reddit is read without it, less reliably." ;;
    BLUESKY_HANDLE|BLUESKY_APP_PASSWORD) echo "bsky.app -> Settings -> Privacy and security -> App passwords (handle like name.bsky.social). Optional (both or neither)." ;;
  esac
}
is_known() { case " $KNOWN_KEYS " in *" $1 "*) return 0 ;; esac; return 1; }

NAMES=(); VALUES=(); LEFT_OUT=()
set_value() { # set_value KEY VALUE (last one wins)
  local i=0
  while [ "$i" -lt "${#NAMES[@]}" ]; do
    if [ "${NAMES[$i]}" = "$1" ]; then VALUES[$i]="$2"; return 0; fi
    i=$((i + 1))
  done
  NAMES+=("$1"); VALUES+=("$2")
}
get_value() {
  local i=0
  while [ "$i" -lt "${#NAMES[@]}" ]; do
    [ "${NAMES[$i]}" = "$1" ] && { printf '%s' "${VALUES[$i]}"; return 0; }
    i=$((i + 1))
  done
  return 0
}
unset_value() {
  local i=0 n=() v=()
  while [ "$i" -lt "${#NAMES[@]}" ]; do
    [ "${NAMES[$i]}" = "$1" ] || { n+=("${NAMES[$i]}"); v+=("${VALUES[$i]}"); }
    i=$((i + 1))
  done
  NAMES=(${n[@]+"${n[@]}"}); VALUES=(${v[@]+"${v[@]}"})
}

# read_env_file FILE STRIP_SUFFIX: KEY=value lines (comments, blanks, "export ",
# quotes and \r handled). With STRIP_SUFFIX=1 only KEY_<project> names are taken.
read_env_file() {
  local file="$1" strip="$2" line name val first last inml=0 q=""
  while IFS= read -r line || [ -n "$line" ]; do
    line="${line%$'\r'}"
    if [ "$inml" = 1 ]; then
      case "$line" in *"$q") inml=0 ;; esac
      continue
    fi
    line="${line#"${line%%[![:space:]]*}"}"
    [ -z "$line" ] && continue
    case "$line" in \#*) continue ;; esac
    case "$line" in export[[:space:]]*) line="${line#export}"; line="${line#"${line%%[![:space:]]*}"}" ;; esac
    case "$line" in *=*) ;; *) continue ;; esac
    name="${line%%=*}"; name="${name%"${name##*[![:space:]]}"}"
    val="${line#*=}"
    val="${val#"${val%%[![:space:]]*}"}"; val="${val%"${val##*[![:space:]]}"}"
    printf '%s' "$name" | grep -Eq '^[A-Za-z_][A-Za-z0-9_]*$' || continue
    first="${val:0:1}"
    if { [ "$first" = '"' ] || [ "$first" = "'" ]; }; then
      if [ "${#val}" -ge 2 ] && [ "${val:${#val}-1:1}" = "$first" ]; then
        val="${val:1:${#val}-2}"
      else
        inml=1; q="$first"; LEFT_OUT+=("$name (multi-line value)"); continue
      fi
    fi
    if [ "$strip" = 1 ]; then
      case "$name" in *_"$PROJECT") name="${name%_"$PROJECT"}" ;; *) continue ;; esac
    fi
    set_value "$name" "$val"
  done < "$file"
}

# ---------------------------------------------------------------------------
say "Project $APP: writing .env.azure (names end in _$PROJECT)"
if [ -e "$OUT" ] && git -C "$REPO_DIR" ls-files --error-unmatch .env.azure >/dev/null 2>&1; then
  die "git tracks .env.azure. It holds secrets: run 'git rm --cached .env.azure' and commit that first."
fi

if [ -n "$SRC" ]; then
  [ -f "$SRC" ] || die "can't read '$SRC'"
  info "copying settings from $SRC"
  read_env_file "$SRC" 0
  # Someone may hand over a file that already uses the suffixed names.
  i=0; n=("${NAMES[@]+"${NAMES[@]}"}"); v=("${VALUES[@]+"${VALUES[@]}"}"); NAMES=(); VALUES=()
  while [ "$i" -lt "${#n[@]}" ]; do
    k="${n[$i]}"; case "$k" in *_"$PROJECT") k="${k%_"$PROJECT"}" ;; esac
    set_value "$k" "${v[$i]}"; i=$((i + 1))
  done
else
  [ -f "$OUT" ] && read_env_file "$OUT" 1
  [ -t 0 ] || die "no .env file given and this isn't an interactive terminal. Run: bash deploy/env-import.sh path/to/.env"
  say "Enter each key (typing is hidden). Enter alone keeps the current value, or skips it; '-' removes it."
  for k in $KNOWN_KEYS; do
    cur="$(get_value "$k")"
    printf '\n  %s\n    where: %s\n' "$k" "$(where "$k")"
    if [ -n "$cur" ]; then printf '    %s (set; Enter keeps it): ' "$k"; else printf '    %s: ' "$k"; fi
    val=""
    IFS= read -rs val || true
    printf '\n'
    val="${val%$'\r'}"
    case "$val" in
      "") ;;
      -) unset_value "$k" ;;
      *) set_value "$k" "$val" ;;
    esac
  done
fi

# Decide what goes in.
KEEP_N=(); KEEP_V=()
i=0
while [ "$i" -lt "${#NAMES[@]}" ]; do
  k="${NAMES[$i]}"; val="${VALUES[$i]}"; i=$((i + 1))
  lc="$(printf '%s' "$val" | tr 'A-Z' 'a-z')"
  case "$k" in
    PORT) LEFT_OUT+=("$k (Azure always uses 8080)"); continue ;;
    DB_*|DATABASE_URL) LEFT_OUT+=("$k (the app never uses a database)"); continue ;;
    VITE_*|REACT_APP_*|NEXT_PUBLIC_*) LEFT_OUT+=("$k (website build setting: set in deploy/azure-deploy.conf)"); continue ;;
    RENDER_*|VERCEL_*|PYTHON_VERSION|NODE_VERSION|PYTHONPATH|PATH|HOME) LEFT_OUT+=("$k (host setting)"); continue ;;
    *ADMIN_PASSWORD*|*INITIAL_PASSWORD*) LEFT_OUT+=("$k (one-time admin password)"); continue ;;
  esac
  if [ -z "$val" ]; then LEFT_OUT+=("$k (empty)"); continue; fi
  case "$lc" in your_*|your-*|changeme|change_me|xxx*|"<"*">") LEFT_OUT+=("$k (placeholder value)"); continue ;; esac
  case "$val" in *$'\n'*) LEFT_OUT+=("$k (multi-line value)"); continue ;; esac
  is_known "$k" || info "note: $k is not read by the code today; kept anyway"
  KEEP_N+=("$k"); KEEP_V+=("$val")
done

# Write (mode 600 from the start; back up the old file).
if [ -f "$OUT" ]; then
  cp -p "$OUT" "$OUT.bak"; chmod 600 "$OUT.bak"
  info "old file kept as .env.azure.bak"
fi
umask 077
tmp="$OUT.tmp.$$"
{
  printf '# Rep-Tell settings for Azure (secret: never commit this file).\n'
  printf '# Every name ends in _%s; deploy/azure.sh stores KEY_%s as the app secret\n' "$PROJECT" "$PROJECT"
  printf '# <key>-%s and gives it to the code as KEY. Written by deploy/env-import.sh.\n' "$APP"
  i=0
  while [ "$i" -lt "${#KEEP_N[@]}" ]; do
    printf '%s_%s=%s\n' "${KEEP_N[$i]}" "$PROJECT" "${KEEP_V[$i]}"
    i=$((i + 1))
  done
} > "$tmp"
chmod 600 "$tmp"
mv "$tmp" "$OUT"

say "Wrote .env.azure (mode 600) with ${#KEEP_N[@]} setting(s):"
for k in ${KEEP_N[@]+"${KEEP_N[@]}"}; do info "  ${k}_$PROJECT"; done
if [ "${#LEFT_OUT[@]}" -gt 0 ]; then
  say "Left out:"
  for k in "${LEFT_OUT[@]}"; do info "  $k"; done
fi

has() { local k; for k in ${KEEP_N[@]+"${KEEP_N[@]}"}; do [ "$k" = "$1" ] && return 0; done; return 1; }
missing=0
for k in GEMINI_API_KEY YOUTUBE_API_KEY; do
  if ! has "$k"; then
    [ "$missing" = 1 ] || say "Recommended settings still missing (the app runs without them, doing less):"
    missing=1
    info "  ${k}_$PROJECT: $(where "$k")"
  fi
done
for pair in "REDDIT_CLIENT_ID REDDIT_CLIENT_SECRET" "BLUESKY_HANDLE BLUESKY_APP_PASSWORD"; do
  set -- $pair
  if has "$1" && ! has "$2"; then warn "${1}_$PROJECT is set but ${2}_$PROJECT isn't; they only work together"; fi
  if has "$2" && ! has "$1"; then warn "${2}_$PROJECT is set but ${1}_$PROJECT isn't; they only work together"; fi
done
info ""
info "Check names only (no values): cut -d= -f1 .env.azure"
info "Next: DRY_RUN=1 bash deploy/azure.sh"
