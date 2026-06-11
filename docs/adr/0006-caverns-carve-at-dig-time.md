# Caverns carve open at dig time, not at map generation

Borrowed from Warp Drive Machine's cave loop: a dig can breach a tunnel that snakes outward and may end in a room. We implement this by carving — removing cover entities in a hash-derived shape when the triggering dig's seed-keyed roll fires — rather than pre-generating open pockets and detecting breaches. WDM's `math.random` rolls are replaced with (seed, tile, stream) hashes per ADR 0005, so every team digging the same tile breaches the same cavern with the same contents.

Carved tiles materialize ore veins and chart for the digging force, but skip per-tile spawn/treasure rolls; the room's depth-gated content system (empty / nest / hoard / sanctuary in v1) owns its danger and loot — otherwise room danger would scale with room area and large rooms would be instant biter floods.

Considered alternative: pre-generated noise pockets populated on first breach. Rejected for v1: needs breach detection and region tracking, shows cavern structure in the map preview, and loses the "space opens FROM your dig" feel that motivated the feature. Room contents spawning at carve time keeps the standing constraint intact: hostiles enter the world only as dig consequences.
