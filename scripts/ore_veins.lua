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
    { name = "iron-ore", seed = 1100, width = 0.055, min_depth = CARVE_RADIUS + 4, base = 400, per_dist = 3 },
    { name = "copper-ore", seed = 1200, width = 0.050, min_depth = 40, base = 400, per_dist = 3 },
    { name = "coal", seed = 1300, width = 0.050, min_depth = CARVE_RADIUS + 4, base = 350, per_dist = 2 },
    { name = "stone", seed = 1400, width = 0.040, min_depth = 40, base = 300, per_dist = 2 },
}

function ore_veins.on_dig(dig)
    local surface = dig.surface
    local x = math.floor(dig.position.x) + 0.5
    local y = math.floor(dig.position.y) + 0.5

    local tile = surface.get_tile(x, y)
    if not tile.valid or tile.name:find("water", 1, true) then
        return
    end

    local distance = math.sqrt(x * x + y * y)
    local seed = surface.map_gen_settings.seed

    for _, ore in pairs(ORES) do
        if distance > ore.min_depth then
            local noise = Simplex.d2(x * TENDRIL_SCALE, y * TENDRIL_SCALE, seed + ore.seed)
            if math.abs(noise) < ore.width then
                local created = surface.create_entity {
                    name = ore.name,
                    position = { x, y },
                    amount = math.floor(ore.base + distance * ore.per_dist),
                }
                -- First exposure of a vein (no same ore adjacent yet) gets a
                -- chat notice — scoped to the digger's force, so under MTS
                -- only that team sees its own discoveries.
                if created
                    and surface.count_entities_filtered { name = ore.name, position = { x, y }, radius = 1.6 } <= 1 then
                    local force = dig.force
                    if not force and dig.player_index then
                        force = game.get_player(dig.player_index).force
                    end
                    if force then
                        force.print({ "diggy.vein-discovered", "[entity=" .. ore.name .. "]", created.localised_name })
                    end
                end
                return
            end
        end
    end
end

return ore_veins
