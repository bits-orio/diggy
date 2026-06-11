local dig_tracker = require("scripts.dig_tracker")
local install_guard = require("scripts.install_guard")

script.on_init(function()
    dig_tracker.on_init()
    install_guard.on_init()
end)

local rock_filter = { { filter = "name", name = "diggy-rock" } }
script.on_event(defines.events.on_player_mined_entity, dig_tracker.on_dig, rock_filter)
script.on_event(defines.events.on_entity_died, dig_tracker.on_dig, rock_filter)

script.on_event(defines.events.on_player_created, install_guard.on_player_created)
