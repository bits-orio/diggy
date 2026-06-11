-- The map starts black except roughly one chunk at the origin; the chart grows
-- as the cover is dug away. (The original scenario got this for free from
-- out-of-map tiles; our terrain is real, so we control the chart instead.)
local charting = {}

local START_CHART = { { -16, -16 }, { 15, 15 } }
local DIG_CHART_RADIUS = 4

function charting.on_init()
    storage.chart_reset = {}
end

-- The engine charts a generous starting area for each force; wipe it down to
-- the carve-out chunk the first time we see a player on that force.
function charting.on_player_created(event)
    local player = game.get_player(event.player_index)
    local force = player.force
    if storage.chart_reset[force.index] then return end
    storage.chart_reset[force.index] = true

    local surface = player.surface
    force.clear_chart(surface)
    force.chart(surface, START_CHART)
end

function charting.on_dig(dig)
    local force = dig.force
    if not force and dig.player_index then
        force = game.get_player(dig.player_index).force
    end
    if not force then return end

    local p = dig.position
    force.chart(dig.surface, {
        { p.x - DIG_CHART_RADIUS, p.y - DIG_CHART_RADIUS },
        { p.x + DIG_CHART_RADIUS, p.y + DIG_CHART_RADIUS },
    })
end

return charting
