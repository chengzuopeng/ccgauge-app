# Changelog

All notable changes to ccgauge-bar will be documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [1.0.0] — 2026-05-24

First public release.

### Added

- macOS menubar app that reads local Claude Code and OpenAI Codex CLI
  JSONL session logs and surfaces token usage, cost, and cache savings.
  Single-click the menubar gauge to open a 580×720 pt popover.
- **Two pages**:
  - **Overview** — per-provider cards (Claude / Codex with turn counts
    and active minutes), KPI grid (token total / est. cost / I/O tokens
    / cache hit ratio), trend chart with 1D/7D/30D ranges and three
    metrics (tokens / cost / turns), Top 5 projects and models with
    sort toggle.
  - **Usage** — turn-grouped table with 1D/7D/30D/All ranges, debounced
    search, pagination (50/page), expandable rows showing 8-cell detail
    strip + full prompt, per-row token-breakdown popover, CSV export.
- **Settings** — General, Data, About tabs. Bilingual UI (English /
  简体中文), light / dark auto.
- **Privacy by design** — reads only local JSONL; zero network calls;
  no telemetry; no crash reporting; nothing persisted in-process
  beyond a derived file-metadata cache.
- **Data layer** — `ScanEngine` actor with on-disk index cache
  (~50ms warm starts), FSEvents recursive watcher with 250ms debounce,
  5-tier derived-data caches in `PopoverViewModel` keyed by
  `(scanKey, source, range)` for snappy filter switching.
- **Packaging** — universal binary (Apple Silicon + Intel), hardened
  runtime, drag-to-install DMG via `make dmg`.
- **Test suite** — 25 unit tests covering pricing resolution, range
  bucketing, and formatters.

### Known limitations

- Ad-hoc signed (no Apple Developer ID). First launch on macOS requires
  one-time Gatekeeper bypass (see README "下载安装").
- Currency conversion stays USD-equivalent — non-USD codes swap the
  symbol only (no live FX rates).
- Plan field on Provider Card is a placeholder; JSONL has no
  subscription metadata.

[Unreleased]: https://github.com/chengzuopeng/ccgauge-app/compare/v1.0.0...HEAD
[1.0.0]: https://github.com/chengzuopeng/ccgauge-app/releases/tag/v1.0.0
