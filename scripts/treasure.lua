-- Treasure sealed in the cover (CONTEXT.md "Treasure"): presence AND contents
-- are seed-keyed by tile (ADR 0005), so MTS team worlds hide identical chests
-- with identical loot in identical places. Contents scale with depth.
local hash = require("scripts.lib.hash")

local treasure = {}

-- Hash stream ids (keep unique across all dig modules).
local S_PRESENCE, S_PICKS, S_ITEM, S_AMOUNT = 20, 21, 22, 23

local LOOT_TIERS = {
    {
        max_depth = 120,
        chest = "wooden-chest",
        loot = {
            { name = "firearm-magazine", min = 10, max = 40 },
            { name = "iron-gear-wheel", min = 10, max = 30 },
            { name = "shotgun-shell", min = 8, max = 24 },
            { name = "iron-plate", min = 20, max = 60 },
            { name = "stone-wall", min = 5, max = 15 },
        },
    },
    {
        max_depth = 300,
        chest = "iron-chest",
        loot = {
            { name = "piercing-rounds-magazine", min = 10, max = 30 },
            { name = "steel-plate", min = 10, max = 40 },
            { name = "grenade", min = 5, max = 20 },
            { name = "electronic-circuit", min = 20, max = 60 },
            { name = "gun-turret", min = 1, max = 3 },
        },
    },
    {
        max_depth = math.huge,
        chest = "steel-chest",
        loot = {
            { name = "uranium-rounds-magazine", min = 10, max = 30 },
            { name = "cluster-grenade", min = 4, max = 12 },
            { name = "advanced-circuit", min = 20, max = 50 },
            { name = "laser-turret", min = 1, max = 2 },
            { name = "explosives", min = 10, max = 40 },
        },
    },
}

local function tier_for(depth)
    for _, tier in pairs(LOOT_TIERS) do
        if depth <= tier.max_depth then return tier end
    end
end

function treasure.on_dig(dig)
    local surface = dig.surface
    local x = math.floor(dig.position.x)
    local y = math.floor(dig.position.y)

    local seed = surface.map_gen_settings.seed
    local chance = settings.global["diggy-treasure-chance"].value
    if hash.roll(seed, x, y, S_PRESENCE) >= chance then
        return
    end

    local depth = math.sqrt(x * x + y * y)
    local tier = tier_for(depth)
    local position = surface.find_non_colliding_position(tier.chest, { x + 0.5, y + 0.5 }, 2, 0.5)
    if not position then return end

    local chest = surface.create_entity { name = tier.chest, position = position, force = "neutral" }
    for i = 1, hash.range(seed, x, y, S_PICKS, 2, 3) do
        local item = tier.loot[hash.range(seed, x, y, S_ITEM + i * 100, 1, #tier.loot)]
        chest.insert { name = item.name, count = hash.range(seed, x, y, S_AMOUNT + i * 100, item.min, item.max) }
    end
end

return treasure
