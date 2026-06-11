local mts = require("scripts.mts")
local world = require("scripts.world")
local collapse = require("scripts.collapse")
local threats = require("scripts.threats")
require("scripts.integrations.mother")
local dig_tracker = require("scripts.dig_tracker")
local dig_spawner = require("scripts.dig_spawner")
local dig_yield = require("scripts.dig_yield")
local ore_veins = require("scripts.ore_veins")
local treasure = require("scripts.treasure")
local caverns = require("scripts.caverns")
local charting = require("scripts.charting")
local install_guard = require("scripts.install_guard")

script.on_init(function()
    dig_tracker.on_init()
    charting.on_init()
    collapse.on_init()
    threats.on_init()
    install_guard.on_init()
    -- Guard first: on a mid-save install the world conversion must not run,
    -- or it would void an existing base.
    if not storage.mid_save_install then
        world.on_init()
    end
    dig_spawner.apply_expansion_setting()
end)

script.on_configuration_changed(function()
    if not storage.stress then collapse.on_init() end
end)

local COVER = { ["diggy-rock"] = true, ["diggy-tree"] = true }

-- A dig is the death/mining of a cover entity. Snapshot the context up front:
-- handlers may invalidate the dying entity as a side effect, so none of them
-- touch it directly.
local function on_dig(event)
    local entity = event.entity
    local force = event.force
    if not force and event.player_index then
        force = game.get_player(event.player_index).force
    end
    if not force or force.name == "neutral" or force.name == "enemy" then
        -- Player-less digs (fire, biters chewing the wall): attribute to the
        -- surface's owning team under MTS, the player force standalone.
        force = mts.surface_owner_force(entity.surface)
    end
    local dig = {
        surface = entity.surface,
        position = entity.position,
        name = entity.name,
        force = force,
        player_index = event.player_index,
    }
    dig_tracker.on_dig(dig)
    world.on_dig(dig) -- stress + frontier advance
    ore_veins.on_dig(dig)
    treasure.on_dig(dig)
    dig_spawner.on_dig(dig)
    threats.on_dig(dig)
    caverns.on_dig(dig)
    charting.on_dig(dig)
end

-- Public API (ADR 0002 door #2): external mods register declarative threat
-- specs; rolls are seed-keyed like everything else.
remote.add_interface("diggy-v1", {
    register_threat = threats.register_external,
})

-- Covers dig; other support entities (walls, reactors) feed the stress map.
local removal_filter = {}
for _, name in pairs(collapse.SUPPORT_NAMES) do
    removal_filter[#removal_filter + 1] = { filter = "name", name = name }
end

local function on_removed(event)
    local entity = event.entity
    if COVER[entity.name] then
        if event.buffer then
            dig_yield.on_player_mined(event)
        end
        on_dig(event)
    else
        collapse.support_removed(entity.surface, entity.position, entity.name, event.player_index)
    end
end

script.on_event(defines.events.on_player_mined_entity, on_removed, removal_filter)
script.on_event(defines.events.on_robot_mined_entity, on_removed, removal_filter)
script.on_event(defines.events.on_entity_died, on_removed, removal_filter)

local support_filter = {
    { filter = "name", name = "stone-wall" },
    { filter = "name", name = "nuclear-reactor" },
}
local function on_built(event)
    local entity = event.entity
    collapse.support_added(entity.surface, entity.position, entity.name)
end
script.on_event(defines.events.on_built_entity, on_built, support_filter)
script.on_event(defines.events.on_robot_built_entity, on_built, support_filter)
script.on_event(defines.events.script_raised_built, on_built, support_filter)
script.on_event(defines.events.script_raised_revive, on_built, support_filter)

script.on_event(defines.events.on_player_built_tile, function(event)
    collapse.on_built_tile(game.surfaces[event.surface_index], event.tile, event.tiles)
end)
script.on_event(defines.events.on_robot_built_tile, function(event)
    collapse.on_built_tile(event.robot.surface, event.tile, event.tiles)
end)
script.on_event(defines.events.on_player_mined_tile, function(event)
    collapse.on_mined_tile(game.surfaces[event.surface_index], event.tiles, event.player_index)
end)
script.on_event(defines.events.on_robot_mined_tile, function(event)
    collapse.on_mined_tile(event.robot.surface, event.tiles)
end)

script.on_nth_tick(30, collapse.on_heartbeat)

script.on_event(defines.events.on_chunk_generated, world.on_chunk_generated)
script.on_event(defines.events.on_chunk_charted, world.on_chunk_charted)

script.on_event(defines.events.on_player_created, function(event)
    charting.on_player_created(event)
    install_guard.on_player_created(event)
end)

script.on_event(defines.events.on_runtime_mod_setting_changed, function(event)
    if event.setting == "diggy-enemy-expansion" then
        dig_spawner.apply_expansion_setting()
    end
end)
