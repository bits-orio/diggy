-- Ore veins materialize at dig time (ADR 0004): when a cover entity dies, the
-- tile's vein membership is computed from simplex noise seeded by the surface's
-- map seed — deterministic, so re-digging a collapsed area or comparing MTS
-- team worlds always yields identical veins. Veins never exist until dug.
local Simplex = require("scripts.lib.simplex")
local hash = require("scripts.lib.hash")

local ore_veins = {}

-- Hash stream ids (keep unique across all dig modules).
local S_OIL_WELL = 90

local CARVE_RADIUS = settings.startup["diggy-carve-out-radius"].value
local TENDRIL_SCALE = 1 / 40

-- Oil fields: broad blobs (scale 1/60) holding sparse individual wells.
local OIL = {
    seed = 1600,
    field_scale = 1 / 60,
    field_threshold = 0.55,
    cell = 5, -- one well candidate per 5x5 tile cell
    min_depth = 120,
    base = 28000,
    per_dist = 140,
}

-- The well candidate is the hash-champion of its cell: guaranteed spacing
-- with zero order-dependent checks (a "no well nearby?" entity scan would
-- depend on dig order and break cross-team determinism, ADR 0005).
local function cell_champion(seed, cx, cy)
    local best_x, best_y, best = cx, cy, -1
    for ix = cx, cx + OIL.cell - 1 do
        for iy = cy, cy + OIL.cell - 1 do
            local r = hash.roll(seed, ix, iy, S_OIL_WELL)
            if r > best then best, best_x, best_y = r, ix, iy end
        end
    end
    return best_x, best_y, best
end

local function is_well_champion(seed, tx, ty)
    local cx, cy = math.floor(tx / OIL.cell) * OIL.cell, math.floor(ty / OIL.cell) * OIL.cell
    local bx, by, own = cell_champion(seed, cx, cy)
    if bx ~= tx or by ~= ty then return false end
    -- Champions at cell borders can still touch a neighbouring cell's
    -- champion; the weaker of the pair yields (deterministic tie-break).
    for dx = -1, 1 do
        for dy = -1, 1 do
            if dx ~= 0 or dy ~= 0 then
                local nx, ny, theirs = cell_champion(seed, cx + dx * OIL.cell, cy + dy * OIL.cell)
                if math.abs(nx - tx) <= 2 and math.abs(ny - ty) <= 2 and theirs > own then
                    return false
                end
            end
        end
    end
    return true
end

-- Rarest first, so deep tendrils aren't shadowed by common ores.
local ORES = {
    { name = "uranium-ore", seed = 1500, width = 0.022, min_depth = 250, base = 300, per_dist = 2 },
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

    -- Oil is not a tendril: a broad field noise marks oil regions, and sparse
    -- seed-keyed wells scatter inside them in 2D (contour-following made
    -- wells line up in adjacent rows). Richness is its own scale — oil
    -- doesn't get the solid-ore 4x.
    if distance > OIL.min_depth then
        local field = Simplex.d2(x * OIL.field_scale, y * OIL.field_scale, seed + OIL.seed)
        if field > OIL.field_threshold
            and is_well_champion(seed, math.floor(x), math.floor(y)) then
            local created = surface.create_entity {
                name = "crude-oil",
                position = { x, y },
                amount = math.floor((OIL.base + distance * OIL.per_dist) * (1 + distance / 400)),
            }
            -- Wells are scattered, so use a field-sized radius for the
            -- first-discovery notice or every well would announce itself.
            if created and force
                and surface.count_entities_filtered { name = "crude-oil", position = { x, y }, radius = 12 } <= 1 then
                force.print({ "diggy.vein-discovered", "[entity=crude-oil]", created.localised_name })
            end
            return
        end
    end

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
