-- Hand-mining rock yields a mix of ores on top of its stone (the Mountain
-- Fortress feel), seed-keyed by tile (ADR 0005) so every MTS team mining the
-- same tile gets the same haul. Mix richness grows slowly with depth. Trees
-- just give wood.
local hash = require("scripts.lib.hash")

local dig_yield = {}

-- Hash stream ids (keep unique across all dig modules).
local S_ORE_PICK, S_ORE_COUNT = 30, 31

local EXTRA_ORES = {
    { name = "iron-ore", weight = 40 },
    { name = "copper-ore", weight = 30 },
    { name = "coal", weight = 30 },
}
local TOTAL_WEIGHT = 0
for _, ore in pairs(EXTRA_ORES) do TOTAL_WEIGHT = TOTAL_WEIGHT + ore.weight end

local function pick_ore(seed, x, y)
    local roll = hash.roll(seed, x, y, S_ORE_PICK) * TOTAL_WEIGHT
    for _, ore in pairs(EXTRA_ORES) do
        roll = roll - ore.weight
        if roll <= 0 then return ore.name end
    end
    return EXTRA_ORES[#EXTRA_ORES].name
end

function dig_yield.on_player_mined(event)
    if event.entity.name ~= "diggy-rock" then return end
    local p = event.entity.position
    local x, y = math.floor(p.x), math.floor(p.y)
    local seed = event.entity.surface.map_gen_settings.seed
    local depth_bonus = math.floor(math.sqrt(p.x * p.x + p.y * p.y) / 100)
    event.buffer.insert {
        name = pick_ore(seed, x, y),
        count = hash.range(seed, x, y, S_ORE_COUNT, 2, 5) + depth_bonus,
    }
end

return dig_yield
