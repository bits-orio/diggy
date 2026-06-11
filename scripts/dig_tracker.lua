-- Per-surface dig accounting: volume dug drives evolution pressure, depth is
-- the progression axis (gates threats, feeds milestones — both consume the
-- stats exposed here).
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

-- Fires for any death/mining of a diggy-rock (event handlers are filtered by
-- control.lua), i.e. every dig regardless of tool: hand, explosives, vehicle.
function dig_tracker.on_dig(event)
    local entity = event.entity
    local surface = entity.surface
    local stats = stats_for(surface)

    stats.volume = stats.volume + 1
    local p = entity.position
    local depth = math.sqrt(p.x * p.x + p.y * p.y)
    if depth > stats.depth then
        stats.depth = depth
    end

    local per_dig = settings.global["diggy-evolution-per-dig"].value
    if per_dig > 0 then
        local enemy = game.forces.enemy
        local evolution = enemy.get_evolution_factor(surface)
        enemy.set_evolution_factor(math.min(1, evolution + per_dig), surface)
    end
end

function dig_tracker.get_stats(surface)
    return stats_for(surface)
end

return dig_tracker
