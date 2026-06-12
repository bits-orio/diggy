# Diggy

A standalone Factorio mod recreating RedMew's Diggy scenario: the world is solid rock, and the factory grows by digging it out — with cave-ins punishing unsupported ceilings. First-class optional integration with Multi Team Support (MTS).

## Language

### World

**Diggy world**:
The nauvis surface as redefined by this mod — out-of-map void everywhere, built into caves at runtime as the frontier wall is dug. Only revealed space exists.
_Avoid_: diggy surface, cave surface

**Void**:
Engine-native `out-of-map` beyond the frontier wall: black, impassable, holding nothing. Digging converts void into world.
_Avoid_: unexplored, fog

**Frontier wall**:
The single layer of minable cover entities (rocks, tree patches) standing between revealed space and the void. Digging a wall entity opens its floor and advances the wall into adjacent void.
_Avoid_: rock cover (ADR-0001-era term), walls

**Tree cover**:
Tiny noise-picked patches of dense trees in the frontier wall. Same rules as rock (bot-proof, counts as a dig) but quicker to mine — and flammable.
_Avoid_: forest

**Dig**:
The death of a frontier-wall entity — by hand-mining or by damage (explosives, fire, vehicles, gunfire) — opening its floor, rolling for veins, treasure, and dig spawns, and advancing the wall. Construction robots cannot deconstruct the wall; explosives and fire are the automation paths for mass digging.
_Avoid_: excavate, void removal (the scenario-era term)

**Ore vein**:
Ore that materializes at the dug tile, computed from noise seeded by the map seed — deterministic, but not existing as entities until dug. Veins never pre-generate (except the starter patch).
_Avoid_: ore patch, scattered resources (scenario-era term)

**Starter patch**:
A light-density seed-keyed ore mix scattered inside the spawn carve-out when it is built, enough to hand-mine basic defenses before the first dig.

**Spawn carve-out**:
The small pre-revealed safe area at the map origin where a team starts, ringed by rock cover.
_Avoid_: starting zone (the scenario-era term)

**Water pool**:
A noise-defined water blob that materializes (bounded flood-fill) when digging first touches it. Pools are benign — hostiles never pre-exist (see Dig spawn).
_Avoid_: pocket (ADR-0001-era term), lake

**Treasure**:
Loot containers sealed inside the rock cover or pockets, found by digging. There is no coin currency and no market in this mod.
_Avoid_: coin, market (scenario-era concepts, deliberately cut)

### Structural mechanics

**Support**:
An entity that counteracts stress on nearby ceiling (walls, refined flooring, remaining rock).
_Avoid_: support beam entity

**Stress**:
The structural load on a ceiling cell, computed live from current geometry (open floor nearby minus support contributions) whenever the world changes — never stored as truth (ADR 0008). Identical geometry always reads identically.
_Avoid_: stress map, ledger (ADR-0008 removed the accumulated form)

**World mirror**:
The chunk-local, never-saved copy of the world facts stress reads (tile codes + support records), maintained by assignment at the mutation choke points and rebuilt from the engine on demand (ADR 0009). `/diggy-mirror-check` proves it exact.

**Stress cache**:
The incrementally-maintained cell values layered on the mirror (ADR 0009). Candidates come from the cache; any marker or collapse decision is verified against a fresh computation first, and a rolling audit re-derives cells continuously. Wiped on player join and Support Struts research.

**Collapse**:
The cave-in that re-seals an area with rock cover when stress exceeds the threshold. Entities in the area are crushed into buried crushed remains; the terrain and ore beneath persist.
_Avoid_: cave-in (in code; fine in prose)

**Homestead lattice**:
The stone-wall pillar grid (spacing adapts to the wall-support setting; player-owned and minable) pre-placed across the spawn carve-out, so the starting cave is held up by the same honest geometry players build with later.

**Crushed remains**:
A non-colliding corpse entity left where a building was crushed by a collapse, holding its inventories — buried and lootable after re-digging. Opt-in (host setting, off by default): normally crushed buildings and their contents are simply destroyed.
_Avoid_: spilled items, wreck

### Difficulty

**Depth**:
Straight-line distance from the spawn carve-out. The canonical progression axis: depth gates which threats can appear and scales ore richness.
_Avoid_: distance (too generic)

**Threat**:
A spawnable hostile defined by a declarative spec (entity names, depth gate, weight, pack size). Threats come from Diggy's built-ins, bundled adapters, or external mods.

**Threat tier**:
A depth-gated band of the threat pool. Digging past a tier's depth unlocks its threats for spawn rolls.

**Dig spawn**:
Hostiles materializing as the consequence of a dig roll — together with cavern room contents, the only way enemies ever enter the world. Common rolls produce units; rare rolls produce a nest or worm in the revealed space. Vanilla biter expansion is off by default so digging stays the sole enemy source.
_Avoid_: pre-spawned nests, alien spawner (scenario-era term)

**Cavern**:
A space that carves open from a dig: a seed-keyed roll can breach a snaking tunnel, sometimes ending in a room. Carved tiles materialize veins and chart, but per-tile spawn/treasure rolls are skipped — the room's contents are the sole source of its danger and loot.
_Avoid_: cave (ambiguous with the whole world)

**Room**:
The space at the end of a cavern tunnel, with a depth-gated personality: empty cave, nest room (spawners and worms), hoard room (chest cluster), or rare sanctuary (grass, water, fish — a safe moment).

**Arming**:
A room's ceiling faces judgment the moment nothing guards it: nest rooms arm when their last worm dies; unguarded rooms arm at breach. Arming sweeps the room for cells over threshold in the live geometry; failing areas give a 15-second on-screen countdown, then shed roughly half their mass (a sparse collapse) — pillars placed during the countdown are honored. Sanctuaries never arm. While worms live, no collapse can trigger in their room — the only way in is to fight.

**Difficulty preset**:
A named bundle (e.g. Casual / Classic / Brutal) that scales the threat, evolution, and collapse knobs together. Every knob remains individually overridable by the host. Diggy never grants starting gear — that belongs to FasterStart or MTS starter items.

**Seed-keyed**:
Derived deterministically from (map seed, tile, stream id) — the only permitted source of randomness for dig outcomes, so MTS teams face identical worlds. `math.random` in a dig path is a bug.
_Avoid_: random (for dig outcomes)

### Integration

**MTS**:
Multi Team Support — an optional dependency. When present, each team plays its own identically-seeded Diggy world on its per-team nauvis variant.

**Adapter**:
A bundled per-mod integration file that detects a third-party mod and registers its content (e.g. threats) on its behalf. Requires no cooperation from that mod.
_Avoid_: compat shim, plugin

**Threat registry**:
The single pool of threat specs that escalation rolls from, fed by built-ins, adapters, and external mods via the `diggy-v1` remote interface.
