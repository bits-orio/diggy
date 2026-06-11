-- Nauvis map-gen takeover (ADR 0001): the whole world is generated at data
-- stage — floors, ore tendrils, water and nest pockets — then hidden under
-- solid rock cover. Runtime code only reacts to digging.
local CARVE_RADIUS = settings.startup["diggy-carve-out-radius"].value

data:extend({
    -- Open blobs inside the rock cover. Suppresses rock above 0.65;
    -- enemy nests only above 0.72, so every nest sits inside a pocket.
    {
        type = "noise-expression",
        name = "diggy_pocket",
        expression = "basis_noise{x = x, y = y, seed0 = map_seed, seed1 = 7700, input_scale = 1/24, output_scale = 1}",
    },
    -- Rare water pockets, carved out of the otherwise flat elevation.
    {
        type = "noise-expression",
        name = "diggy_water",
        expression = "basis_noise{x = x, y = y, seed0 = map_seed, seed1 = 8800, input_scale = 1/30, output_scale = 1}",
    },
})

data.raw["simple-entity"]["diggy-rock"].autoplace = {
    order = "a[diggy]-a[rock]",
    probability_expression = ("(distance > %d) * 2 - 1 - max(0, diggy_pocket - 0.65) * 1000"):format(CARVE_RADIUS),
}

-- Ore tendrils: thin ribbons of ridged noise, one seed per resource, gated by
-- depth so richer/rarer ores need deeper digs. Richness grows with depth.
local function tendril(resource, opts)
    local proto = data.raw.resource[resource]
    if not proto then return end
    proto.autoplace = {
        order = "b[diggy-ore]",
        probability_expression = (
            "(max(0, abs(basis_noise{x = x, y = y, seed0 = map_seed, seed1 = %d, input_scale = 1/40, output_scale = 1}) < %f)"
            .. " * (distance > %d)) * 2 - 1"
        ):format(opts.seed, opts.width, opts.min_depth),
        richness_expression = ("%d + distance * %d"):format(opts.base_richness, opts.depth_richness),
    }
end

tendril("iron-ore", { seed = 1100, width = 0.055, min_depth = CARVE_RADIUS + 4, base_richness = 400, depth_richness = 3 })
tendril("copper-ore", { seed = 1200, width = 0.050, min_depth = 40, base_richness = 400, depth_richness = 3 })
tendril("coal", { seed = 1300, width = 0.050, min_depth = CARVE_RADIUS + 4, base_richness = 350, depth_richness = 2 })
tendril("stone", { seed = 1400, width = 0.040, min_depth = 40, base_richness = 300, depth_richness = 2 })
tendril("uranium-ore", { seed = 1500, width = 0.022, min_depth = 250, base_richness = 300, depth_richness = 2 })
tendril("crude-oil", { seed = 1600, width = 0.018, min_depth = 120, base_richness = 120000, depth_richness = 600 })

local nauvis = data.raw.planet["nauvis"]
local mgs = nauvis.map_gen_settings

mgs.autoplace_settings = mgs.autoplace_settings or {}
local placed = {}
for _, name in pairs({
    "diggy-rock",
    "iron-ore", "copper-ore", "coal", "stone", "uranium-ore", "crude-oil",
}) do
    placed[name] = {}
end
-- Only our entities generate: no trees, vanilla rocks, fish — and no enemies;
-- hostiles enter the world exclusively via dig spawns (see scripts/dig_spawner.lua).
mgs.autoplace_settings.entity = { settings = placed, treat_missing_as_default = false }

-- Flat land everywhere except sealed water pockets; no cliffs.
mgs.property_expression_names = mgs.property_expression_names or {}
mgs.property_expression_names.elevation = "100 - max(0, diggy_water - 0.78) * 4000"
mgs.cliff_settings = { name = "cliff", cliff_elevation_0 = 1024, cliff_elevation_interval = 10, richness = 0 }
