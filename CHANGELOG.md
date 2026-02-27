# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.0] - 2026-02-27

### Added

- Scan WordPress user sessions and flag accounts whose IPs geo-locate to blocked countries.
- Required comma-separated country list argument (auto-trimmed, uppercased, validated).
- `report` mode (default) — list flagged users with ID, email, IP, and country code.
- `delete` mode — remove flagged users with interactive confirmation prompt.
- Administrator protection — user ID 1 and users with the `administrator` role are never deleted.
- Deleted users' content is reassigned to user ID 1.
- GeoIP lookup caching to avoid redundant `mmdblookup` calls.
- Private/reserved IP filtering (RFC 1918, loopback, link-local, ULA).
- IPv4 and IPv6 support.
- Per-user deduplication — each user is only flagged/acted on once regardless of session count.
- Auto-detection of WordPress table prefix.
- `WP_PATH` environment variable for targeting remote WordPress installs.
- `-h` / `--help` flag.
