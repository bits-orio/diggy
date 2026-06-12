-- Per-surface dig accounting: depth is the progression axis (gates threats,
-- feeds milestones — both consume the stats exposed here). Digging itself
-- carries no evolution cost: clearing the nests you uncover is penalty
-- enough.
local dig_tracker = {}

function dig_tracker.on_init()
    storage.digs = {}
end

local function stats_for(surface)
    local stats = storage.digs[surface.index]
    if not stats then
        stats = { volume = 0, depth = 0 }
        storage.digs[surface.index] = stats
    end
    return stats
end

-- Receives the dig context snapshot from control.lua, for every dig
-- regardless of tool: hand, explosives, fire, vehicle.
function dig_tracker.on_dig(dig)
    local surface = dig.surface
    local stats = stats_for(surface)

    stats.volume = stats.volume + 1
    local p = dig.position
    local depth = math.sqrt(p.x * p.x + p.y * p.y)
    if depth > stats.depth then
        stats.depth = depth
    end
end

function dig_tracker.get_stats(surface)
    return stats_for(surface)
end

return dig_tracker
