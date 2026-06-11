# All dig-outcome randomness is seed-keyed deterministic

No dig outcome uses `math.random`. Every roll — vein membership, spawn occurrence, pack size, biter/spitter pick, treasure presence, loot picks and amounts, mining yield mix — derives from a hash of (map seed, tile position, stream id) via `scripts/lib/hash.lua`, or from seeded simplex noise for veins. Stream ids keep independent decisions at the same tile uncorrelated.

Why: under MTS, fairness across teams is absolute — teams race on identically-seeded worlds, so two teams digging the same tile must face the same ore, the same ambush, the same loot. Anything less turns the race into a dice game. The only intentional asymmetry is unit *tier*, which follows each team's own evolution (a consequence of their choices, not luck).

Consequence for future features: anything random-feeling (caverns, threats from the registry, events) must draw from the same seed-keyed hash streams. `math.random` in a dig path is a bug.
