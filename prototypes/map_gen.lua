-- Nauvis map-gen takeover (ADR 0001, amended by ADR 0004): floors and water
-- are generated at data stage, hidden under solid rock/tree cover. Ore does
-- NOT pre-generate — veins materialize at dig time from seeded runtime noise
-- (scripts/ore_veins.lua), except a light mixed starter patch in the carve-out.
local CARVE_RADIUS = settings.startup["diggy-carve-out-radius"].value

data:extend({
    -- Tiny tree-cover patches mixed into the rock mass.
    {
        type = "noise-expression",
        name = "diggy_trees",
        expression = "basis_noise{x = x, y = y, seed0 = map_seed, seed1 = 9900, input_scale = 1/12, output_scale = 1}",
    },
    -- Rare sealed water pockets, carved out of the otherwise flat elevation.
    {
        type = "noise-expression",
        name = "diggy_water",
        expression = "basis_noise{x = x, y = y, seed0 = map_seed, seed1 = 8800, input_scale = 1/30, output_scale = 1}",
    },
})

data.raw["simple-entity"]["diggy-rock"].autoplace = {
    order = "a[diggy]-a[rock]",
    -- Solid everywhere outside the carve-out; tree patches displace rock.
    probability_expression = ("(distance > %d) * 2 - 1 - max(0, diggy_trees - 0.72) * 1000"):format(CARVE_RADIUS),
}

data.raw.tree["diggy-tree"].autoplace = {
    order = "a[diggy]-b[tree]",
    probability_expression = ("(max(0, diggy_trees - 0.72) * (distance > %d)) * 2 - 1"):format(CARVE_RADIUS),
}

-- Starter patch: light-density mixed ore inside the carve-out so a fresh team
-- can hand-mine enough for basic defenses before the first real dig.
local function starter_patch(resource, seed)
    data.raw.resource[resource].autoplace = {
        order = "b[diggy-starter]",
        probability_expression = (
            "((distance < %d) * (basis_noise{x = x, y = y, seed0 = map_seed, seed1 = %d, input_scale = 1/5, output_scale = 1} > 0.55)) * 2 - 1"
        ):format(CARVE_RADIUS - 1, seed),
        richness_expression = "80",
    }
end

starter_patch("iron-ore", 5510)
starter_patch("copper-ore", 5520)
starter_patch("coal", 5530)
starter_patch("stone", 5540)

local nauvis = data.raw.planet["nauvis"]
local mgs = nauvis.map_gen_settings

mgs.autoplace_settings = mgs.autoplace_settings or {}
local placed = {}
for _, name in pairs({
    "diggy-rock", "diggy-tree",
    "iron-ore", "copper-ore", "coal", "stone",
}) do
    placed[name] = {}
end
-- Only our entities generate. No vanilla terrain content, no pre-placed ore
-- beyond the starter patch, and no enemies; hostiles and ore veins enter the
-- world exclusively through digging.
mgs.autoplace_settings.entity = { settings = placed, treat_missing_as_default = false }

-- Flat land everywhere except sealed water pockets; no cliffs.
mgs.property_expression_names = mgs.property_expression_names or {}
mgs.property_expression_names.elevation = "100 - max(0, diggy_water - 0.78) * 4000"
mgs.cliff_settings = { name = "cliff", cliff_elevation_0 = 1024, cliff_elevation_interval = 10, richness = 0 }
