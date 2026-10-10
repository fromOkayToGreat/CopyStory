# Changelog

## 0.3.0 — Unreleased

- Public MIT-licensed source repository, contributor guidance, private security
  reporting, pinned dependency notices, CI, and reproducible packaging checks.
- Sparkle update integration with manual checks and opt-in automatic checks
  and downloads. Require signed feeds and archives, verify before extraction,
  and reject older/equal numeric builds and unexpected asset locations.
- Drain accepted storage changes before ordinary quit or updater relaunch.
  Preserve capture/clear ordering and existing data/preferences.
- Developer ID/notarization release gates, package/signature checks, and
  signed release metadata. Public app binaries await those gates and acceptance.

## 0.2.0 — Local release

- App exclusions, optional expiry that preserves pins, stricter paste-target
  matching, canceled-copy protection, and hardened runtime packaging.

## 0.1.1 — Local release

- Prevent pending captures from recreating cleared history; preserve ordered
  save/clear behavior and suppress stale refresh results.

## 0.1.0 — Local release

- Native local text/image history, search, pins, retention limits, hotkey,
  direct paste with manual-copy fallback, and launch at login.
