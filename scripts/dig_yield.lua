-- Hand-mining rock yields a random mix of ores on top of its stone (the
-- Mountain Fortress feel) — deliberately random, unlike vein placement, which
-- is deterministic. Mix richness grows slowly with depth. Trees just give wood.
local dig_yield = {}

local EXTRA_ORES = {
    { name = "iron-ore", weight = 40 },
    { name = "copper-ore", weight = 30 },
    { name = "coal", weight = 30 },
}
local TOTAL_WEIGHT = 0
for _, ore in pairs(EXTRA_ORES) do TOTAL_WEIGHT = TOTAL_WEIGHT + ore.weight end

local function pick_ore()
    local roll = math.random(TOTAL_WEIGHT)
    for _, ore in pairs(EXTRA_ORES) do
        roll = roll - ore.weight
        if roll <= 0 then return ore.name end
    end
end

function dig_yield.on_player_mined(event)
    if event.entity.name ~= "diggy-rock" then return end
    local p = event.entity.position
    local depth_bonus = math.floor(math.sqrt(p.x * p.x + p.y * p.y) / 100)
    event.buffer.insert {
        name = pick_ore(),
        count = math.random(2, 5) + depth_bonus,
    }
end

return dig_yield
