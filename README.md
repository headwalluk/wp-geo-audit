# wp-geo-audit

![Version](https://img.shields.io/badge/version-1.0.0-blue)
![Shell](https://img.shields.io/badge/shell-bash%204%2B-green)
![License](https://img.shields.io/badge/licence-MIT-yellow)
![WP-CLI](https://img.shields.io/badge/WP--CLI-required-orange)
![MaxMind](https://img.shields.io/badge/MaxMind-GeoLite2-purple)

Flag and optionally delete WordPress user accounts whose sessions originate from blocked countries, using MaxMind GeoIP data.

## How It Works

1. Queries the WordPress `usermeta` table for all active session tokens
2. Extracts IP addresses from the serialised PHP session blobs (IPv4 and IPv6)
3. Looks up each IP against the MaxMind GeoLite2-Country database
4. Reports any user whose session IP resolves to a country in the blocked list
5. In `delete` mode, removes flagged accounts (administrators are always protected)

## Requirements

- **Bash 4+**
- **WP-CLI** (`/usr/local/bin/wp`)
- **libmaxminddb-tools** — provides the `mmdblookup` command
  ```bash
  sudo apt install libmaxminddb-tools
  ```
- **MaxMind GeoLite2-Country database** at `/var/lib/GeoIP/GeoLite2-Country.mmdb`
  (typically installed via `geoipupdate`)
- **GNU grep** with `-P` (Perl-compatible regex) support

## Installation

```bash
git clone <repo-url>
chmod +x wp-geo-audit.sh
```

No other installation steps are needed — it's a single self-contained script.

## Usage

```
./wp-geo-audit.sh <COUNTRIES> [report|delete]
```

Run from the root of a WordPress installation, or set `WP_PATH` to point at one.

### Arguments

| Argument    | Description |
|-------------|-------------|
| `COUNTRIES` | **(required)** Comma-separated ISO 3166-1 alpha-2 country codes. Whitespace and case are normalised automatically. |
| `report`    | List flagged users (default if omitted) |
| `delete`    | List and delete flagged users |

### Options

| Option       | Description |
|--------------|-------------|
| `-h, --help` | Show help message |

### Environment Variables

| Variable  | Description |
|-----------|-------------|
| `WP_PATH` | Path to WordPress installation (if not running from the WP root) |

### Examples

```bash
# Report — country list is always required
./wp-geo-audit.sh "RU, CN, IR, BY"

# Whitespace and case don't matter
./wp-geo-audit.sh "RU, vn, CN, IQ" report

# Delete flagged users (with confirmation prompt)
./wp-geo-audit.sh "KP, IR" delete

# Target a WordPress install in a different directory
WP_PATH=/var/www/html ./wp-geo-audit.sh "RU, CN"
```

## Safety

- **Administrators are always protected** — user ID 1 and any user with the `administrator` role will be flagged but never deleted.
- **Delete mode requires confirmation** — you must press Enter before any accounts are removed.
- **Deleted users' content is reassigned** to user ID 1.
- **Private and reserved IPs** (RFC 1918, loopback, link-local, ULA) are silently skipped.
- Always run in `report` mode first to review which users would be affected.

## Configuration

The following defaults can be changed at the top of `wp-geo-audit.sh`:

| Variable   | Default                                        | Description |
|------------|------------------------------------------------|-------------|
| `GEOIP_DB` | `/var/lib/GeoIP/GeoLite2-Country.mmdb`         | Path to MaxMind database |
| `WP`       | `/usr/local/bin/wp`                             | Path to WP-CLI binary |
| `WP_OPTS`  | `--skip-plugins --skip-themes --skip-packages`  | Default WP-CLI flags |

The WordPress table prefix is auto-detected via `wp config get table_prefix`.

## Licence

MIT
