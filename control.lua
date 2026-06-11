local dig_tracker = require("scripts.dig_tracker")
local dig_spawner = require("scripts.dig_spawner")
local dig_yield = require("scripts.dig_yield")
local ore_veins = require("scripts.ore_veins")
local treasure = require("scripts.treasure")
local charting = require("scripts.charting")
local install_guard = require("scripts.install_guard")

script.on_init(function()
    dig_tracker.on_init()
    charting.on_init()
    install_guard.on_init()
    dig_spawner.apply_expansion_setting()
end)

-- A dig is the death/mining of any cover entity (rock or tree). Snapshot the
-- context up front: handlers may invalidate the dying entity as a side effect
-- (e.g. creating entities at its tile), so none of them touch it directly.
local function on_dig(event)
    local entity = event.entity
    local dig = {
        surface = entity.surface,
        position = entity.position,
        force = event.force,
        player_index = event.player_index,
    }
    dig_tracker.on_dig(dig)
    ore_veins.on_dig(dig)
    treasure.on_dig(dig)
    dig_spawner.on_dig(dig)
    charting.on_dig(dig)
end

local cover_filter = {
    { filter = "name", name = "diggy-rock" },
    { filter = "name", name = "diggy-tree" },
}
script.on_event(defines.events.on_player_mined_entity, function(event)
    dig_yield.on_player_mined(event)
    on_dig(event)
end, cover_filter)
script.on_event(defines.events.on_entity_died, on_dig, cover_filter)

script.on_event(defines.events.on_player_created, function(event)
    charting.on_player_created(event)
    install_guard.on_player_created(event)
end)

script.on_event(defines.events.on_runtime_mod_setting_changed, function(event)
    if event.setting == "diggy-enemy-expansion" then
        dig_spawner.apply_expansion_setting()
    end
end)
