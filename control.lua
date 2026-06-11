local dig_tracker = require("scripts.dig_tracker")
local dig_spawner = require("scripts.dig_spawner")
local install_guard = require("scripts.install_guard")

script.on_init(function()
    dig_tracker.on_init()
    install_guard.on_init()
    dig_spawner.apply_expansion_setting()
end)

local function on_dig(event)
    dig_tracker.on_dig(event)
    dig_spawner.on_dig(event)
end

local rock_filter = { { filter = "name", name = "diggy-rock" } }
script.on_event(defines.events.on_player_mined_entity, on_dig, rock_filter)
script.on_event(defines.events.on_entity_died, on_dig, rock_filter)

script.on_event(defines.events.on_player_created, install_guard.on_player_created)
script.on_event(defines.events.on_runtime_mod_setting_changed, function(event)
    if event.setting == "diggy-enemy-expansion" then
        dig_spawner.apply_expansion_setting()
    end
end)
