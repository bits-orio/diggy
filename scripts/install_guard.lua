-- Diggy's world only exists on maps created with the mod: already-generated
-- chunks can never be regenerated. Detect a mid-save install and warn loudly.
local install_guard = {}

function install_guard.on_init()
    local nauvis = game.surfaces["nauvis"]
    -- On a fresh map, the origin chunk is not generated yet when on_init runs;
    -- if it is generated but holds no rock cover, this mod was added mid-save.
    if nauvis.is_chunk_generated({ 0, 0 })
        and nauvis.count_entities_filtered { name = "diggy-rock", limit = 1 } == 0 then
        storage.mid_save_install = true
    end
end

function install_guard.on_player_created(event)
    if storage.mid_save_install then
        game.get_player(event.player_index).print({ "diggy.mid-save-install" })
    end
end

return install_guard
