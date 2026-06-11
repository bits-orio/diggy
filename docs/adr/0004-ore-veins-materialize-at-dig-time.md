# Ore veins materialize at dig time from seeded runtime noise

Amends ADR 0001: floors and water remain data-stage, but ore does not pre-generate. When a cover entity dies, runtime simplex noise (seeded by the surface's map seed, the same algorithm the original scenario used) decides whether that tile belongs to a vein and creates the resource entity on the spot. A light starter patch inside the carve-out is the only pre-generated ore.

Why: playtest showed pre-generated ore leaking through cover visuals, and lazily materialized veins eliminate the spoiler class entirely (map, preview, radar) while keeping the determinism that matters — identical vein layouts per seed across re-digs of collapsed areas and across MTS team worlds. Mountain Fortress's random-raffle veins were considered and rejected: randomness breaks cross-team fairness.

Cost: the new-game map preview no longer shows ore (only land/water/cover), and vein shapes live in runtime Lua instead of noise-expression prototypes — a deliberate retreat from "100% data-stage terrain" for the one layer where hiding information is the gameplay.
