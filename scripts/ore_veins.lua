-- Ore veins materialize at dig time (ADR 0004): when a cover entity dies, the
-- tile's vein membership is computed from simplex noise seeded by the surface's
-- map seed — deterministic, so re-digging a collapsed area or comparing MTS
-- team worlds always yields identical veins. Veins never exist until dug.
local Simplex = require("scripts.lib.simplex")

local ore_veins = {}

local CARVE_RADIUS = settings.startup["diggy-carve-out-radius"].value
local TENDRIL_SCALE = 1 / 40

-- Rarest first, so deep tendrils aren't shadowed by common ores.
local ORES = {
    { name = "uranium-ore", seed = 1500, width = 0.022, min_depth = 250, base = 300, per_dist = 2 },
    { name = "crude-oil", seed = 1600, width = 0.018, min_depth = 120, base = 120000, per_dist = 600 },
    { name = "iron-ore", seed = 1100, width = 0.055, min_depth = CARVE_RADIUS + 4, base = 500, per_dist = 3.5 },
    { name = "copper-ore", seed = 1200, width = 0.050, min_depth = 40, base = 350, per_dist = 2.5 },
    { name = "coal", seed = 1300, width = 0.050, min_depth = CARVE_RADIUS + 4, base = 350, per_dist = 2 },
    { name = "stone", seed = 1400, width = 0.040, min_depth = 40, base = 300, per_dist = 2 },
}

-- Materialize the vein (if any) at a tile — used for manual digs and for
-- cavern-carved tiles alike. `force` (optional) receives the discovery notice.
function ore_veins.materialize(surface, tile_x, tile_y, force)
    local x, y = tile_x + 0.5, tile_y + 0.5

    local tile = surface.get_tile(tile_x, tile_y)
    if not tile.valid or tile.name:find("water", 1, true) then
        return
    end

    local distance = math.sqrt(x * x + y * y)
    local seed = surface.map_gen_settings.seed

    -- Depth pays off twice: tendrils fatten (up to ~3.5x base width) and
    -- richness grows super-linearly, so deep veins are wide and dense. The
    -- flat 4x keeps a digging-constrained economy fed (every ore tile costs
    -- digs to even reach).
    local width_mult = math.min(1 + distance / 350, 3.5)
    local richness_mult = (1 + distance / 400) * 4

    for _, ore in pairs(ORES) do
        if distance > ore.min_depth then
            local noise = Simplex.d2(x * TENDRIL_SCALE, y * TENDRIL_SCALE, seed + ore.seed)
            if math.abs(noise) < ore.width * width_mult then
                local created = surface.create_entity {
                    name = ore.name,
                    position = { x, y },
                    amount = math.floor((ore.base + distance * ore.per_dist) * richness_mult),
                }
                -- First exposure of a vein (no same ore adjacent yet) gets a
                -- chat notice — scoped to the digger's force, so under MTS
                -- only that team sees its own discoveries.
                if created and force
                    and surface.count_entities_filtered { name = ore.name, position = { x, y }, radius = 1.6 } <= 1 then
                    force.print({ "diggy.vein-discovered", "[entity=" .. ore.name .. "]", created.localised_name })
                end
                return
            end
        end
    end
end

function ore_veins.on_dig(dig)
    ore_veins.materialize(dig.surface, math.floor(dig.position.x), math.floor(dig.position.y), dig.force)
end

return ore_veins
