# Changelog

All notable changes to this package are documented here.

## 0.1.0 — 2026-08-28

- Revived Racket-MUD as an immutable, message-driven engine with TCP and
  account adapters.
- Added a world-neutral mudlib, command handling, recipes, topology, and
  deterministic logical actions.
- Preserved historical behavior as parity tests while intentionally excluding
  Teraum, TAB, and qtOps world data.

## Compatibility

0.1.0 begins a new package API. It is not source-compatible with historical
Racket-MUD generations; see the migration note in `README.md`.
