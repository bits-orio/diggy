local mts = require("scripts.mts")
local pop_text = require("scripts.pop_text")
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

-- No crashed spaceship in a cave: disable freeplay's crash site and intro.
-- (Mods init before the freeplay scenario reads these flags.)
local function disable_crash_site()
    if remote.interfaces["freeplay"] then
        pcall(remote.call, "freeplay", "set_disable_crashsite", true)
        pcall(remote.call, "freeplay", "set_skip_intro", true)
    end
end

script.on_init(function()
    disable_crash_site()
    dig_tracker.on_init()
    charting.on_init()
    collapse.on_init()
    threats.on_init()
    caverns.on_init()
    pop_text.on_init()
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
    storage.support_reach = storage.support_reach or {}
    caverns.on_init()
    pop_text.on_init()
    -- Retire the old screen-frame countdown (replaced by world pop texts).
    for _, player in pairs(game.players) do
        local frame = player.gui.screen["diggy-cavern-countdown"]
        if frame then frame.destroy() end
    end

    -- Clear crash-site debris from saves created before it was disabled.
    local nauvis = game.surfaces["nauvis"]
    if nauvis and nauvis.valid then
        for _, entity in pairs(nauvis.find_entities_filtered { area = { { -80, -80 }, { 80, 80 } } }) do
            if entity.valid and entity.name:find("crash%-site") then
                entity.destroy()
            end
        end
    end

    -- Saves store runtime settings, so defaults shipped by old releases stick
    -- forever. Rebase saves still on the exact old shipped defaults (the
    -- "every rock spawns biters" era) to the current ones; custom values are
    -- left untouched.
    local rebase = {
        ["diggy-dig-biter-chance"] = { old = { [1.0] = true, [0.015] = true }, new = 0.1 },
        ["diggy-dig-nest-chance"] = { old = { [0.1] = true, [0.01] = true, [0.002] = true }, new = 0.05 },
        ["diggy-cavern-worm-multiplier"] = { old = { [1.0] = true }, new = 2.0 },
        ["diggy-cavern-chance"] = { old = { [0.02] = true }, new = 0.03 },
    }
    for name, r in pairs(rebase) do
        if r.old[settings.global[name].value] then
            settings.global[name] = { value = r.new }
            game.print({ "diggy.setting-rebased", { "mod-setting-name." .. name }, tostring(r.new) })
        end
    end
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
for _, name in pairs({ "small-worm-turret", "medium-worm-turret", "big-worm-turret", "behemoth-worm-turret" }) do
    removal_filter[#removal_filter + 1] = { filter = "name", name = name }
end
local NESTS = { ["biter-spawner"] = true, ["spitter-spawner"] = true }
for name in pairs(NESTS) do
    removal_filter[#removal_filter + 1] = { filter = "name", name = name }
end

-- Support reach grows with researched diggy-support-reach tiers (per force).
local function support_reach(force)
    local reach = 4
    for i = 1, 6 do
        local tech = force.technologies["diggy-support-reach-" .. i]
        if tech and tech.researched then reach = reach + 1 end
    end
    return reach
end

-- Worm deaths can arm their cavern room (see caverns.on_worm_died).
local WORMS = {
    ["small-worm-turret"] = true,
    ["medium-worm-turret"] = true,
    ["big-worm-turret"] = true,
    ["behemoth-worm-turret"] = true,
}

local function on_removed(event)
    local entity = event.entity
    if COVER[entity.name] then
        if event.buffer then
            dig_yield.on_player_mined(event)
        end
        on_dig(event)
    elseif WORMS[entity.name] then
        caverns.on_worm_died(entity)
    elseif NESTS[entity.name] then
        dig_spawner.on_nest_died(entity)
    else
        local reach = storage.support_reach and storage.support_reach[entity.unit_number]
        if storage.support_reach then storage.support_reach[entity.unit_number] = nil end
        collapse.support_removed(entity.surface, entity.position, entity.name, event.player_index, reach)
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
    local reach = support_reach(entity.force)
    if storage.support_reach and entity.unit_number then
        storage.support_reach[entity.unit_number] = reach
    end
    collapse.support_added(entity.surface, entity.position, entity.name, reach)
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

script.on_nth_tick(30, function()
    collapse.on_heartbeat()
    caverns.on_heartbeat()
end)

local admin_kit = require("scripts.admin_kit")
local sim = require("scripts.sim")

commands.add_command("diggy-sim", { "diggy.command-sim" }, function(event)
    local player = event.player_index and game.get_player(event.player_index)
    if not player then return end
    if not player.admin then
        player.print({ "diggy.admin-only" })
        return
    end
    local param = event.parameter
    if param == "stop" then
        sim.stop(player)
    else
        sim.start(player, param == "bare")
    end
end)

commands.add_command("diggy-mine", { "diggy.command-mine" }, function(event)
    local player = event.player_index and game.get_player(event.player_index)
    if not player then return end
    if not player.admin then
        player.print({ "diggy.admin-only" })
        return
    end
    if not player.character then
        player.print({ "diggy.kit-needs-character" })
        return
    end
    local value = tonumber(event.parameter) or 10
    local before = player.character_mining_speed_modifier
    player.character_mining_speed_modifier = value
    player.print({ "diggy.mine-set", string.format("%.1f", before), string.format("%.1f", value) })
end)

commands.add_command("diggy-kit", { "diggy.command-kit" }, function(event)
    local player = event.player_index and game.get_player(event.player_index)
    if not player then return end
    if not player.admin then
        player.print({ "diggy.admin-only" })
        return
    end
    admin_kit.give(player)
end)

commands.add_command("diggy-stress", { "diggy.command-stress" }, function(event)
    local player = event.player_index and game.get_player(event.player_index)
    if player then collapse.debug_overlay(player) end
end)
commands.add_command("diggy-vent", { "diggy.command-vent" }, function(event)
    local player = event.player_index and game.get_player(event.player_index)
    if not player then return end
    if not player.admin then
        player.print({ "diggy.admin-only" })
        return
    end
    collapse.vent(player, tonumber(event.parameter))
end)

-- Pop-text animation: per tick, but a single table check when nothing is
-- animating (countdowns are the only spawner today).
script.on_event(defines.events.on_tick, function(event)
    pop_text.tick(event.tick)
    sim.step()
end)

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
