# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Is

A single-file bash tool (`wp-geo-audit.sh`, v1.0.0) that scans WordPress user sessions for IP addresses originating from blocked countries using MaxMind GeoIP data, with an optional mode to delete those accounts.

## Running

```bash
./wp-geo-audit.sh "RU, CN, IR, BY"            # report (default mode)
./wp-geo-audit.sh "RU, vn, CN, IQ" report     # explicit report
./wp-geo-audit.sh "RU,CN,IR,BY" delete         # delete flagged users
WP_PATH=/var/www/html ./wp-geo-audit.sh "RU,CN"
./wp-geo-audit.sh --help
```

Must be run from a WordPress installation root (or with `WP_PATH` set).

## System Dependencies

- **bash 4+** (associative arrays, `mapfile`)
- **WP-CLI** at `/usr/local/bin/wp`
- **mmdblookup** from `libmaxminddb-tools`
- **MaxMind GeoLite2-Country.mmdb** at `/var/lib/GeoIP/GeoLite2-Country.mmdb`
- **GNU grep** with `-P` (Perl-compatible regex)

## Architecture

Everything lives in `wp-geo-audit.sh`. The flow is:

1. **Argument parsing** — `$1` is the required comma-separated country list (trimmed, uppercased, validated as 2-letter codes); `$2` is the optional mode (`report`/`delete`, defaults to `report`); `-h`/`--help` shows usage
2. **Preflight** — checks `mmdblookup`, WP-CLI, GeoIP DB, and WordPress installation
3. **Single SQL query** — JOINs `usermeta` + `users` to fetch user ID, email, and serialised session tokens in one pass
4. **IP extraction** — parses serialised PHP blobs with `grep -oP '"ip";s:\d+:"\K[^"]+'` (IPv4 and IPv6)
5. **GeoIP lookup** — `mmdblookup` with an associative-array cache (`GEO_CACHE`) to avoid redundant lookups
6. **Filtering** — skips private/reserved IPs; flags users whose session IP resolves to a country in `BAD_COUNTRIES`
7. **Deduplication** — `SEEN` associative array ensures each user is only flagged/acted on once
8. **Deletion** — in delete mode, checks roles first; user ID 1 and administrators are skipped; other flagged users are deleted with `--reassign=1`

## Key Configuration (top of script)

- `GEOIP_DB` — path to MaxMind `.mmdb` file
- `WP` — path to WP-CLI binary
- `WP_OPTS` — default WP-CLI flags (`--skip-plugins --skip-themes --skip-packages`)
- Table prefix is auto-detected via `wp config get table_prefix`

## Known Bash Pitfalls

- **Arithmetic with `set -e`**: Use `(( ++var ))` (pre-increment), never `(( var++ ))` (post-increment). Post-increment evaluates to the old value; when that's `0`, `(( 0 ))` returns exit status 1, which `set -e` treats as fatal.
- **`(( expr ))` in conditionals**: Safe when used as part of `&&` or `||` chains (e.g. `(( x > 0 )) && ...`) since bash exempts conditional contexts from `set -e`.

## Testing

No automated tests. Validate manually against a WordPress instance. Use `report` mode first to review output before running `delete`.
