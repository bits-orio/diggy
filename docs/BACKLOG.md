# Backlog — deferred decisions and future work

Decisions deliberately left open during the 2026-06-10 design session. Each entry notes what was decided so far and what remains. Glossary terms are in [CONTEXT.md](../CONTEXT.md); settled architecture is in [docs/adr/](./adr/).

## Deferred to "after core works"

### Special biters from other mods (threat pool details)
The plumbing is settled (ADR 0002: adapters + `diggy-v1` `register_threat(spec)` + `on_threat_spawned` event). Deferred:
- The threat spec schema (entity names vs. name patterns, depth gate, weight, pack size, evolution scaling). Placement rule is settled: threats materialize at the dug tile (dig spawn) — `scripts/dig_spawner.lua` is the seed this registry grows from.
- Mother adapter specifics: which tiers map to which depths; resolve existing prototypes at runtime (`Schall-category-N-mother-spitter`, names vary with SchallEndgameEvolution installed).
- Which other mods get bundled adapters (candidates: Rampant-style factions, Armoured Biters — survey when core is done).
- Spawn cadence: per-dig roll vs. depth-crossing trigger vs. timed waves.

### Progression twists (selected for v1, low priority, all game-start options)
- Mining-productivity → robot-cargo research replacement (fiddly runtime surgery; port of `mining_productivity.lua`).
- Landfill research lock, belts-n-bullets style tech disabling (easy data-stage wins, gated by startup settings).
- Decide which are startup settings (data-stage tech changes) vs. runtime-global.

### Milestone thresholds
Categories settled (depth reached, tiles dug, treasures found). Exact thresholds, `announce_first` flags, and verb/noun phrasing TBD. Keep thresholds dense enough that milestones double as the cross-team scoreboard (this is what justified cutting the team tab).

## Deferred to v1.x

### WDM-inspired features not in cavern v1 (decided 2026-06-10)
Cavern carving + empty/nest/hoard/sanctuary rooms shipped (ADR 0006). Deferred:
- Light & atmosphere pass: `rendering.draw_light` cones in special rooms, varied cavern dirt tiles, ceiling-drop particles, wind ambience.
- Ruins and hell-rooms (boss/swarm-burst rooms at extreme depth) — need prefab and boss design, plus a determinism story for swarm cadence.
- Gas-leak hazards and periodic swarm events.
- WDM's driller machine (auto-dig toward a target) — interesting late-game automation candidate.

### Team stats tab (MTS)
Cut from v1 as redundant with MTS milestone/production stats. Revisit only if hosts ask for live exact numbers (current depth, volume dug, collapse count). `register_team_tab` is the mechanism.

### Collapse alert tuning
Cross-team collapse alerts are in v1 behind a host setting. Deferred: rate limiting / minimum-severity threshold so a collapse-spammy team doesn't flood chat and Discord.

### Treasure design depth
v1 ships loot chests sealed in rock/pockets. Deferred: loot table design, rarity tiers by depth, whether treasure placement is data-stage (pocket content) or runtime-on-reveal — spike findings will inform this.

## Future / explicitly out of scope for v1

### Diggy as a planet
Diggy planet prototype + travel-to mode (Space Age). The nauvis-replacement architecture was chosen knowing this can be added later in the same mod (data-stage planet addition is save-safe). Re-grill the product question first: what does travel-to Diggy offer that's worth importing?

### Economy v2 (coins / market)
Cut from v1 (CONTEXT.md: _Avoid: coin, market_). If digging-for-currency ever returns, it needs a from-scratch design — RedMew's Retailer will not be ported.

### Aesthetic pass on undug world
The black-void look of the original is sacrificed by the pre-generated model (ADR 0001). Spike checks how bad rock-tops-instead-of-void looks; a custom dark "unexcavated" overlay/tile treatment is future polish if it bothers players.

### Cut scenario features (not planned)
Cutscene, blueprint_tools GUI, antigrief autojail, restart command, shelob, flaming_pumpjack, RedMew rank integration. Revisit only on demand.

## Standing constraints (don't re-litigate)
- Hostiles only ever appear via dig spawns. No pre-spawned nests (reversed 2026-06-10 after playtest); biter expansion off by default so digging stays the sole nest source.
- All dig-outcome randomness is seed-keyed (ADR 0005): identical worlds and identical dig outcomes across MTS teams. `math.random` in a dig path is a bug.
- MTS and ODB are optional dependencies; Diggy must be fully playable with neither.
- Diggy never grants starting gear (FasterStart / MTS starter items own that).
- Every difficulty knob is a host setting; presets scale them together.
- Requires a fresh map (nauvis chunks already generated can't be regenerated) — mid-save install must be detected and refused gracefully.
