# Pre-generated world behind rock cover, not runtime void conversion

Status: accepted (spike passed 2026-06-10 — see ../SPIKE.md); ore layer amended by ADR 0004

The original RedMew Diggy scenario fills all chunks with `out-of-map` tiles and *creates* terrain at dig time via runtime Lua noise. We invert this: nauvis's map generation is redefined at data stage (2.0 noise expressions) so the full world — cave floors, ore tendrils, water pockets — exists from chunk generation, hidden under solid autoplaced rock-cover entities. Digging *reveals* terrain instead of creating it.

Why: terrain defined at data stage means the new-game map preview works, map-gen sliders can apply, and MTS per-team nauvis variants inherit identical terrain by seed with no special-casing — the runtime mod only manages dig/collapse state. The cost is divergence from the scenario's model and engine-behavior risk (minimap ore spoilers through rock cover, rock entity density performance, losing the black-void aesthetic), to be settled by an in-game spike before the architecture is locked.

Considered alternative: faithful port of the void-conversion model (~90% of terrain logic stays runtime Lua). Rejected unless the spike kills option B.
