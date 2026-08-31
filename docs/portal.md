# Diggy
> The world is solid rock. Mind the ceiling.

[![Discord](https://img.shields.io/badge/Discord-join%20the%20server-5865F2?logo=discord&logoColor=white)](https://discord.gg/tWz4FT74pH) [![GitHub](https://img.shields.io/badge/GitHub-source-181717?logo=github&logoColor=white)](https://github.com/bits-orio/diggy)

Nauvis starts as one unbroken slab of black rock. You dig your factory out of it by hand, and every cave you carve is held up only by the rock you leave standing: take too much and the ceiling comes down on your machines. Diggy is a standalone reimagining of [RedMew's Diggy scenario](https://github.com/Refactorio/RedMew) for Factorio 2.0, rebuilt as a normal mod. Install it, start a map, play alone or with friends. No server and no scenario file required.

## Status

Playable start to finish and under active development, so expect balance and settings to keep moving. Bug reports are genuinely useful at this stage.

One thing to know before you install: Diggy needs a brand-new map. The world is generated as you dig, so the mod cannot turn an existing save to rock. Add it to a running game and nothing happens; start a fresh map and the whole planet is stone.

## Quick start

1. Enable Diggy and start a **new** map.
2. You spawn in a small cleared cave. Mine the black wall around it to open more ground.
3. Leave pillars of rock standing as you widen a room, or brace the ceiling with stone walls and stone or concrete flooring.
4. Turn on ALT view. Ceiling strain is drawn right on the tiles.
5. Dig deeper. Ore gets richer, caverns get stranger, and the things you unearth get meaner.

Difficulty is host-tunable from mod settings and most of it applies mid-game: wall strength, support reach, cavern countdown, threat and treasure rates, and whether collapses bury your buildings.

## Features

### Dig the world out

- **Everything is rock.** The map is generated as solid stone and opened into caves at runtime. Only what you have revealed exists, so there is nothing waiting in the dark to spoil.
- **Dig by hand or by force.** Mine the frontier wall, or break it with explosives, fire, vehicles and gunfire. Construction robots cannot deconstruct it, so opening ground is always a deliberate act. Tree-cover patches clear faster, but they burn.
- **Ore and treasure surface as you dig.** Veins are computed from the map seed at the moment a tile opens rather than pre-placed, and they fatten and richen with depth. Sealed loot chests sit at fixed seed-keyed spots, scaling with how deep you found them.
- **Caverns carve themselves.** A dig can breach a snaking tunnel, sometimes ending in a room: an empty cave, a nest room of spawners guarded by worms, a hoard of chests, or a rare sanctuary with grass, water and fish. While a room's worms live, nothing in it can fall, so the only way in is to fight. Kill the last guardian and the ancient ceiling starts a countdown.

### Cave-ins

- **Stress is pure geometry.** A ceiling cell's load is read live from what is actually around it, open floor minus nearby support, never accumulated in hidden bookkeeping. Identical layouts always read identically, and rock falls exactly where the geometry says it should.
- **Hold it up.** Remaining rock, stone walls, nuclear reactors and stone or concrete flooring all brace the ceiling. Your spawn cave comes pre-pillared so the homestead starts safe.
- **You can see the danger coming.** Strain shows as warning triangles in ALT view, shading yellow to red and fading faint to solid by severity. Every failing tile gets a box, a live countdown, and an honest verdict when the timer runs out.
- **Crushed, not gone.** Buildings caught in a cave-in are buried with their inventories. Dig them back out to recover the materials. Off by default; turn it on if you want the rubble to matter.

### Down there with you

- **Hostiles only exist once you dig them up.** Enemies enter the world as dig spawns and room contents, and depth gates the tiers: deeper digs unlock meaner things. Vanilla expansion is off by default, so the caves stay exactly as dangerous as your digging makes them, and evolution rises from the nests you clear rather than from mining.
- **Two research lines that matter underground.** Thirty-five tiers of team-wide manual mining speed, and six tiers of support struts that extend the reach of every wall and reactor the instant a tier lands, so your pillars can stand further apart.

## Compatibility

- Requires Factorio 2.0 or newer.
- Single player and multiplayer, vanilla or modded.
- Space Age is optional and supported where present.
- Diggy replaces Nauvis map generation, so it will not co-exist with another mod that overhauls Nauvis terrain.

## Works with

- **[Multi-Team Support](https://mods.factorio.com/mod/multi-team-support)** (optional, auto-detected). Every team digs its own copy of the exact same world. Veins, tunnels, treasure and spawns all derive from the map seed, so races are fair down to the tile, and a team's collapse can be broadcast to its rivals with a coloured team label.
- **[Mother](https://mods.factorio.com/mod/Mother)** (optional). A bundled adapter wires its enemies into the depth-gated dig pool with no cooperation needed from that mod.
- **Other mods' enemies.** The `diggy-v1` remote interface lets any mod register threats declaratively; rolls stay seed-keyed so registered enemies appear identically for every team. [How to register](https://github.com/bits-orio/diggy/blob/master/README.md).

Also from the same author, if you are building a multi-team server: [Land Title Registry](https://mods.factorio.com/mod/land-title-registry) and [MTS Dimension Warp](https://mods.factorio.com/mod/mts-dimension-warp).

## Links

- [Source on GitHub](https://github.com/bits-orio/diggy)
- [Report a bug](https://github.com/bits-orio/diggy/issues)
- [Admin commands and the mod-author API](https://github.com/bits-orio/diggy/blob/master/README.md)
- [Community Discord](https://discord.gg/tWz4FT74pH)

## Development

Developed with AI coding assistants alongside human review and in-game testing. Issues and pull requests are welcome on [GitHub](https://github.com/bits-orio/diggy).

License: GPL v3, derived from RedMew's GPL-3.0 Diggy scenario.
