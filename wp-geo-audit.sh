#!/usr/bin/env bash
#
# wp-geo-audit.sh — Flag (and optionally delete) WordPress users
#                   whose sessions originate from blocked countries.
#
# Version: 1.0.0
# Homepage: https://github.com/headwalluk/wp-geo-audit
# Licence:  GPL-2.0-only (https://www.gnu.org/licenses/gpl-2.0.html)
#
set -euo pipefail
VERSION="1.0.0"

# ── Configuration ──────────────────────────────────────────────────────────────

GEOIP_DB="/var/lib/GeoIP/GeoLite2-Country.mmdb"
WP="/usr/local/bin/wp"
WP_OPTS=(--skip-plugins --skip-themes --skip-packages)

# Show help and exit early
[[ "${1:-}" == -h || "${1:-}" == --help ]] && SHOW_HELP=1

MODE="${2:-report}"

# ── Colours ────────────────────────────────────────────────────────────────────

RED=$'\033[0;31m'  YLW=$'\033[1;33m'  GRN=$'\033[0;32m'
DIM=$'\033[2m'     BLD=$'\033[1m'     RST=$'\033[0m'

# ── Helpers ────────────────────────────────────────────────────────────────────

die()   { printf '%s\n' "${RED}Error:${RST} $*" >&2; exit 1; }

usage() {
    cat <<EOF
${BLD}wp-geo-audit${RST} v${VERSION} — Flag/delete WordPress users by country

${BLD}Usage:${RST}  $0 <COUNTRIES> [report|delete]

${BLD}Arguments:${RST}
  COUNTRIES  ${BLD}(required)${RST}
              Comma-separated ISO 3166-1 alpha-2 country codes
              e.g. "RU, vn, CN, IQ" — whitespace and case are
              normalised automatically.

  report     List flagged users (default if omitted)
  delete     List and delete flagged users
             (administrators are always protected)

${BLD}Options:${RST}
  -h, --help  Show this help message

${BLD}Environment:${RST}
  WP_PATH=<dir>  Path to WordPress installation
                 (if not running from the WP root)

${BLD}Examples:${RST}
  $0 "RU, CN, IR, BY"
  $0 "RU, CN, IR" report
  $0 "KP, IR" delete
  WP_PATH=/var/www/html $0 "RU, CN"
EOF
    exit 0
}

# ── Parse country list (required) ─────────────────────────────────────────────

if [[ -z "${1:-}" && -z "${SHOW_HELP:-}" ]]; then
    die "Missing required COUNTRIES argument. Use -h for help."
fi

BAD_COUNTRIES=()
if [[ -n "${1:-}" && -z "${SHOW_HELP:-}" ]]; then
    # Trim whitespace, uppercase, split on commas, reject invalid entries
    IFS=',' read -ra _raw <<< "$1"
    for _code in "${_raw[@]}"; do
        _code=$(echo "$_code" | tr -d '[:space:]' | tr '[:lower:]' '[:upper:]')
        [[ "$_code" =~ ^[A-Z]{2}$ ]] || die "Invalid country code: '$_code'"
        BAD_COUNTRIES+=("$_code")
    done
    (( ${#BAD_COUNTRIES[@]} )) || die "Country list is empty"
fi

# Optional: point at a remote WP install  (e.g. WP_PATH=/var/www/html)
[[ -n "${WP_PATH:-}" ]] && WP_OPTS+=(--path="$WP_PATH")

# ── Preflight ──────────────────────────────────────────────────────────────────

[[ -n "${SHOW_HELP:-}" ]] && usage
[[ "$MODE" == report || "$MODE" == delete ]] || die "Unknown mode: '$MODE'. Use -h for help."

command -v mmdblookup &>/dev/null \
    || die "mmdblookup not found — apt install libmaxminddb-tools"

[[ -x "$WP" ]]        || die "WP-CLI not found at $WP"
[[ -f "$GEOIP_DB" ]]  || die "GeoIP database not found at $GEOIP_DB"

"$WP" "${WP_OPTS[@]}" core is-installed 2>/dev/null \
    || die "No WordPress installation detected (run from the WP root or set WP_PATH)"

if [[ "$MODE" == delete ]]; then
    printf '%s\n' "${RED}${BLD}WARNING:${RST} delete mode will permanently remove flagged accounts."
    printf 'Press Enter to continue or Ctrl-C to abort… '
    read -r
fi

# ── GeoIP lookup with cache ───────────────────────────────────────────────────

declare -A GEO_CACHE=()

geo_country() {
    local ip="$1"
    if [[ -n "${GEO_CACHE[$ip]+x}" ]]; then
        echo "${GEO_CACHE[$ip]}"; return
    fi
    local cc
    cc=$(mmdblookup --file "$GEOIP_DB" --ip "$ip" country iso_code 2>/dev/null \
         | sed -n 's/.*"\([A-Z][A-Z]\)".*/\1/p') || true
    GEO_CACHE[$ip]="${cc:-??}"
    echo "${GEO_CACHE[$ip]}"
}

is_bad() {
    local cc="$1" bad
    for bad in "${BAD_COUNTRIES[@]}"; do
        [[ "$cc" == "$bad" ]] && return 0
    done
    return 1
}

is_private() {
    local ip="$1"
    [[ "$ip" =~ ^10\. ]]                                && return 0
    [[ "$ip" =~ ^172\.(1[6-9]|2[0-9]|3[01])\. ]]       && return 0
    [[ "$ip" =~ ^192\.168\. ]]                           && return 0
    [[ "$ip" =~ ^127\. ]]                                && return 0
    [[ "$ip" =~ ^0\. ]]                                  && return 0
    [[ "$ip" == "::1" || "$ip" =~ ^fe80: ]]              && return 0
    [[ "$ip" =~ ^f[cd] ]]                                && return 0
    return 1
}

# ── Resolve table prefix ──────────────────────────────────────────────────────

TABLE_PREFIX=$("$WP" "${WP_OPTS[@]}" config get table_prefix 2>/dev/null) \
    || TABLE_PREFIX="wp_"

# ── Banner ─────────────────────────────────────────────────────────────────────

printf '\n%s\n' "──────────────────────────────────────────────────────────"
printf '  %bMode:%b       %s\n'       "$BLD" "$RST" "${MODE^^}"
printf '  %bCountries:%b  %s\n'       "$BLD" "$RST" "${BAD_COUNTRIES[*]}"
printf '  %bGeoIP DB:%b   %s\n'       "$BLD" "$RST" "$GEOIP_DB"
printf '  %bTable pfx:%b  %s\n'       "$BLD" "$RST" "$TABLE_PREFIX"
printf '%s\n\n' "──────────────────────────────────────────────────────────"

# ── Main scan ──────────────────────────────────────────────────────────────────

declare -A SEEN=()
flagged=0
deleted=0
skipped=0

SQL="SELECT um.user_id, u.user_email, um.meta_value
     FROM ${TABLE_PREFIX}usermeta um
     JOIN ${TABLE_PREFIX}users u ON um.user_id = u.ID
     WHERE um.meta_key = 'session_tokens'"

while IFS=$'\t' read -r user_id email serialized; do
    # Skip the column-header row
    [[ "$user_id" =~ ^[0-9]+$ ]] || continue

    # Extract every IP from the serialized PHP session blob.
    # Format: "ip";s:<len>:"<addr>"  — works for both IPv4 and IPv6.
    mapfile -t ips < <(grep -oP '"ip";s:\d+:"\K[^"]+' <<< "$serialized" 2>/dev/null || true)
    (( ${#ips[@]} )) || continue

    for ip in "${ips[@]}"; do
        is_private "$ip" && continue

        cc=$(geo_country "$ip")
        is_bad "$cc" || continue

        # Only act on each user once
        [[ -n "${SEEN[$user_id]+x}" ]] && continue
        SEEN[$user_id]=1
        (( ++flagged ))

        printf '%b%-7s%b  ID=%-6s  %-40s  IP=%-39s  CC=%s\n' \
            "$RED" "FLAGGED" "$RST" "$user_id" "$email" "$ip" "$cc"

        if [[ "$MODE" == delete ]]; then
            # Protect user ID 1 and administrators
            roles=$("$WP" "${WP_OPTS[@]}" user get "$user_id" --field=roles 2>/dev/null || echo "")
            if [[ "$user_id" -eq 1 || "$roles" == *administrator* ]]; then
                (( ++skipped ))
                printf '%b%-7s%b  User %s is an administrator — not deleted\n' \
                    "$YLW" "SKIPPED" "$RST" "$user_id"
            elif "$WP" "${WP_OPTS[@]}" user delete "$user_id" --reassign=1 --yes 2>/dev/null; then
                (( ++deleted ))
                printf '%b%-7s%b  User %s removed (content → user 1)\n' \
                    "$YLW" "DELETED" "$RST" "$user_id"
            else
                printf '%b%-7s%b  Could not delete user %s\n' \
                    "$RED" "ERROR" "$RST" "$user_id"
            fi
        fi
    done

done < <("$WP" "${WP_OPTS[@]}" db query "$SQL" 2>/dev/null)

# ── Summary ────────────────────────────────────────────────────────────────────

printf '\n%s\n' "──────────────────────────────────────────────────────────"
printf '  %bFlagged:%b %d user(s)\n' "$BLD" "$RST" "$flagged"
if [[ "$MODE" == delete ]]; then
    printf '  %bDeleted:%b %d user(s)\n' "$BLD" "$RST" "$deleted"
    (( skipped > 0 )) && printf '  %bSkipped:%b %d admin(s)\n' "$BLD" "$RST" "$skipped"
fi
printf '%s\n' "──────────────────────────────────────────────────────────"
