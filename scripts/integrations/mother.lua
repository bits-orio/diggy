-- Bundled adapter for the Mother mod (ADR 0002 door #1): Mother is pure
-- data-stage with vanilla unit AI, so spawning its prototypes directly is
-- safe. Mothers also appear organically from our spitter nests (Mother
-- injects itself into spitter-spawner result_units at data stage); this
-- adapter adds the depth-gated dig encounter on top.
--
-- Prototype names are tier-dependent and vary with SchallEndgameEvolution
-- installed, so candidates are resolved by pattern; invalid names are
-- filtered at spawn time by the registry.
local threats = require("scripts.threats")

if script.active_mods["Mother"] then
    local mothers, big_mothers = {}, {}
    -- Cover the tier range both with and without SchallEndgameEvolution.
    for tier = 5, 16 do
        mothers[#mothers + 1] = ("Schall-category-%d-mother-spitter"):format(tier)
        big_mothers[#big_mothers + 1] = ("Schall-category-%d-big-mother-spitter"):format(tier)
    end

    -- Tiers unlock by depth (weakest existing tier first) and early
    -- encounters arrive weakened — the first mother should be a hard fight,
    -- not a forced restart.
    threats.register_bundled {
        name = "mother",
        entities = mothers,
        min_depth = 300,
        chance = 0.003,
        depth_step = 80,
        health_ramp = { start = 0.3, full_depth = 900 },
        announce = "diggy.mother-emerges",
    }
    threats.register_bundled {
        name = "big-mother",
        entities = big_mothers,
        min_depth = 600,
        chance = 0.0015,
        depth_step = 100,
        health_ramp = { start = 0.5, full_depth = 1500 },
        announce = "diggy.big-mother-emerges",
    }
end
