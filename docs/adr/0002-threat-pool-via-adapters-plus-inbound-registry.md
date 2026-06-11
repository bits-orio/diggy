# Threat pool fed by bundled adapters plus an inbound declarative registry

Difficulty escalation rolls spawns from a single threat registry with two doors. (1) Bundled adapters — one file per known third-party mod (e.g. `integrations/mother.lua`) that detects the mod via `script.active_mods` and registers threat specs on its behalf, for mods that will never know Diggy exists. (2) A `diggy-v1` remote function `register_threat(spec)` so future mods can opt in themselves, mirroring MTS's `register_milestone` pattern.

Specs are declarative (entity names, depth gate, weight, pack size) because Factorio remote calls cannot pass functions. For behavior specs can't express, Diggy raises an `on_threat_spawned` custom event so the registering mod can post-process its units.

Considered alternatives: adapters-only (every integration needs a Diggy release; no self-service) and registry-only (Mother-style script-less mods could never be supported).
