# Diggy

A standalone Factorio mod recreating RedMew's Diggy scenario: the world is solid rock, and the factory grows by digging it out — with cave-ins punishing unsupported ceilings. First-class optional integration with Multi Team Support (MTS).

## Language

### World

**Diggy world**:
The nauvis surface as redefined by this mod — fully pre-generated terrain (floors, ore, water pockets) hidden under solid rock cover.
_Avoid_: diggy surface, cave surface

**Rock cover**:
The solid mass of minable rock entities autoplaced over all undug terrain. Mining it is how the world is revealed.
_Avoid_: walls, void rocks

**Tree cover**:
Tiny patches of dense trees mixed into the rock cover. Same rules as rock (bot-proof, hides terrain, counts as a dig) but quicker to mine — and flammable.
_Avoid_: forest

**Dig**:
The death of a cover entity (rock or tree) — by hand-mining or by damage (explosives, fire, vehicles, gunfire) — revealing the terrain beneath and rolling for veins, treasure, and dig spawns. Construction robots cannot deconstruct cover; explosives and fire are the automation paths for mass digging.
_Avoid_: excavate, void removal (the scenario-era term — no longer accurate)

**Ore vein**:
Ore that materializes at the dug tile, computed from noise seeded by the map seed — deterministic, but not existing as entities until dug. Veins never pre-generate (except the starter patch).
_Avoid_: ore patch, scattered resources (scenario-era term)

**Starter patch**:
The only pre-generated ore: a light-density mix inside the spawn carve-out, enough to hand-mine basic defenses before the first dig.

**Spawn carve-out**:
The small pre-revealed safe area at the map origin where a team starts, ringed by rock cover.
_Avoid_: starting zone (the scenario-era term)

**Pocket**:
A pre-generated open space inside the rock cover (water or treasure pocket), sealed until dug into. Pockets are always benign — hostiles never pre-exist (see Dig spawn).
_Avoid_: room (scenario-era term), nest pocket (rejected design)

**Treasure**:
Loot containers sealed inside the rock cover or pockets, found by digging. There is no coin currency and no market in this mod.
_Avoid_: coin, market (scenario-era concepts, deliberately cut)

### Structural mechanics

**Support**:
An entity that counteracts stress on nearby ceiling (walls, refined flooring, remaining rock).
_Avoid_: support beam entity

**Stress**:
The per-tile structural load accumulated as terrain is revealed without nearby support. Tracked per surface.

**Collapse**:
The cave-in that re-seals an area with rock cover when stress exceeds the threshold. Entities in the area are crushed into buried crushed remains; the terrain and ore beneath persist.
_Avoid_: cave-in (in code; fine in prose)

**Crushed remains**:
A non-colliding corpse entity left where a building was crushed by a collapse, holding its inventories. It is buried under the new rock cover and lootable after re-digging.
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

**Evolution pressure**:
The contribution of total volume dug to enemy evolution — greed makes the baseline meaner, while depth decides what shows up.

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
