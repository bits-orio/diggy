-- Treasure sealed in the cover (CONTEXT.md "Treasure"): presence is decided by
-- a deterministic position hash of the map seed, so MTS team worlds hide their
-- chests in identical places. Contents scale with depth.
local treasure = {}

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

-- Deterministic [0,1) hash of (seed, tile). Multiplies are done in 16-bit
-- halves: a naive 32-bit multiply overflows double precision (2^53) and the
-- quantization makes small roll values unreachable — chests would never spawn.
local band, bxor, rshift = bit32.band, bit32.bxor, bit32.rshift

local function mulmod32(a, b)
    local lo = band(a, 0xffff)
    local hi = rshift(a, 16)
    return (band(hi * b, 0xffff) * 65536 + lo * b) % 4294967296
end

local function position_roll(seed, x, y)
    local h = (x * 374761393 + y * 668265263 + seed * 97) % 4294967296
    h = bxor(h, rshift(h, 16))
    h = mulmod32(h, 0x85ebca6b)
    h = bxor(h, rshift(h, 13))
    h = mulmod32(h, 0xc2b2ae35)
    h = bxor(h, rshift(h, 16))
    return h / 4294967296
end

local function tier_for(depth)
    for _, tier in pairs(LOOT_TIERS) do
        if depth <= tier.max_depth then return tier end
    end
end

function treasure.on_dig(dig)
    local surface = dig.surface
    local x = math.floor(dig.position.x)
    local y = math.floor(dig.position.y)

    local chance = settings.global["diggy-treasure-chance"].value
    if position_roll(surface.map_gen_settings.seed, x, y) >= chance then
        return
    end

    local depth = math.sqrt(x * x + y * y)
    local tier = tier_for(depth)
    local position = surface.find_non_colliding_position(tier.chest, { x + 0.5, y + 0.5 }, 2, 0.5)
    if not position then return end

    local chest = surface.create_entity { name = tier.chest, position = position, force = "neutral" }
    for _ = 1, math.random(2, 3) do
        local item = tier.loot[math.random(#tier.loot)]
        chest.insert { name = item.name, count = math.random(item.min, item.max) }
    end
end

return treasure
