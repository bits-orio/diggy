-- Diggy's world only exists on maps created with the mod: already-generated
-- chunks can never be regenerated. Detect a mid-save install and warn loudly.
local install_guard = {}

function install_guard.on_init()
    -- A fresh map runs on_init at tick 0 (during creation); a mod added to an
    -- existing save runs it later. Crucial: world.on_init must NOT void an
    -- existing base, so this flag is checked before any world conversion.
    if game.tick > 0 then
        storage.mid_save_install = true
    end
end

function install_guard.on_player_created(event)
    if storage.mid_save_install then
        game.get_player(event.player_index).print({ "diggy.mid-save-install" })
    end
end

return install_guard
