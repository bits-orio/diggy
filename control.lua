local mts = require("scripts.mts")
local mirror = require("scripts.lib.mirror")
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
local admin_kit = require("scripts.admin_kit")
local sim = require("scripts.sim")

-- No crashed spaceship in a cave: disable freeplay's crash site and intro.
-- (Mods init before the freeplay scenario reads these flags.)
local function disable_crash_site()
    if remote.interfaces["freeplay"] then
        pcall(remote.call, "freeplay", "set_disable_crashsite", true)
        pcall(remote.call, "freeplay", "set_skip_intro", true)
    end
end

-- Re-judge every cell currently wearing a warning marker — stale after
-- anything that changes what supports are worth (research, host tuning).
-- Snapshot the keys first: evaluate_around -> sync_marker mutates
-- storage.warn_renders (cleared cells remove their key), so iterating the
-- live table would feed `next` a stale key ("invalid key to 'next'").
local function refresh_warned_cells()
    local renders = storage.warn_renders
    if not renders then return end
    local keys = {}
    for wkey in pairs(renders) do
        keys[#keys + 1] = wkey
    end
    for _, wkey in pairs(keys) do
        local si, cx, cy = wkey:match("^(%d+):(-?%d+),(-?%d+)$")
        local surface = si and game.surfaces[tonumber(si)]
        if surface and surface.valid then
            collapse.evaluate_around(surface, { x = tonumber(cx), y = tonumber(cy) }, 2)
        end
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
    if not storage.pending_collapses then collapse.on_init() end
    -- ADR 0008: the stress ledger is gone; clear dead state from old saves.
    storage.stress = nil
    storage.new_tiles = nil
    storage.support_reach = nil
    storage.collapse_log = storage.collapse_log or {}
    storage.warn_renders = storage.warn_renders or {}
    storage.telegraphs = storage.telegraphs or {}
    -- Warning markers live in ALT view now: upgrade live ones in place,
    -- then re-judge them so the severity opacity paints on.
    for _, id in pairs(storage.warn_renders) do
        local obj = rendering.get_object_by_id(id)
        if obj then obj.only_in_alt_mode = true end
    end
    refresh_warned_cells()
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

    -- Heal saves that doubled the spawn ring on MTS team surfaces (the
    -- ensure_chunk -> build_chunk rebuild, fixed in world.build_chunk). The
    -- duplicates only ever land in the carve-out, so a tight per-surface
    -- sweep removes the extra cover, keeping one per tile.
    local removed = 0
    for _, surface in pairs(game.surfaces) do
        if surface.valid then
            local seen = {}
            for _, e in pairs(surface.find_entities_filtered {
                name = { "diggy-rock", "diggy-tree", "diggy-rubble" },
                area = { { -64, -64 }, { 64, 64 } },
            }) do
                local key = math.floor(e.position.x) .. "," .. math.floor(e.position.y)
                if seen[key] then
                    e.destroy()
                    removed = removed + 1
                else
                    seen[key] = true
                end
            end
        end
    end
    if removed > 0 then
        log("[DIGGY] removed " .. removed .. " duplicated spawn-ring cover entities")
    end

    -- Saves store runtime settings, so defaults shipped by old releases stick
    -- forever. Rebase saves still on the exact old shipped defaults (the
    -- "every rock spawns biters" era) to the current ones; custom values are
    -- left untouched.
    local rebase = {
        ["diggy-dig-biter-chance"] = { old = { [1.0] = true, [0.015] = true }, new = 0.1 },
        ["diggy-dig-nest-chance"] = { old = { [0.1] = true, [0.01] = true, [0.002] = true, [0.05] = true }, new = 0.02 },
        ["diggy-cavern-worm-multiplier"] = { old = { [1.0] = true, [2.0] = true }, new = 1.5 },
        ["diggy-cavern-chance"] = { old = { [0.02] = true, [0.03] = true }, new = 0.05 },
        ["diggy-treasure-chance"] = { old = { [0.004] = true }, new = 0.005 },
        ["diggy-pack-size-multiplier"] = { old = { [1.0] = true }, new = 2.0 },
        ["diggy-collapse-broadcast"] = { old = { [true] = true }, new = false },
        -- The support-economy levers settled on tuned defaults (1.5 catches
        -- the old strut default clamped into the new range).
        ["diggy-wall-support"] = { old = { [5] = true }, new = 3 },
        ["diggy-strut-strength-max"] = { old = { [2] = true, [1.5] = true }, new = 1 },
        ["diggy-wall-crowding"] = { old = { [1] = true }, new = 1.2 },
    }
    for name, r in pairs(rebase) do
        if r.old[settings.global[name].value] then
            settings.global[name] = { value = r.new }
            game.print({ "diggy.setting-rebased", { "mod-setting-name." .. name }, tostring(r.new) })
        end
    end
end)

local COVER = { ["diggy-rock"] = true, ["diggy-tree"] = true, ["diggy-rubble"] = true }

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
    -- The cover entity is leaving the world (the engine removes it after
    -- this event resolves — the mirror must not wait for that).
    mirror.set_rock(dig.surface, dig.position, false)
    -- Rubble re-digs are inert: stress and charting only. The tile's
    -- seed-keyed outcomes (vein, spawns, cavern, treasure, ore yield) fired
    -- when it FIRST opened; re-rolling them respawned the same worms and
    -- re-announced the same tunnels forever.
    if dig.name == "diggy-rubble" then
        collapse.evaluate_around(dig.surface, dig.position, nil, dig.player_index)
        charting.on_dig(dig)
        return
    end
    dig_tracker.on_dig(dig)
    world.on_dig(dig) -- stress + frontier advance
    ore_veins.on_dig(dig)
    treasure.on_dig(dig)
    dig_spawner.on_dig(dig)
    threats.on_dig(dig)
    caverns.on_dig(dig)
    charting.on_dig(dig)
    -- Geometry changed: re-evaluate stress around the dig (after the
    -- frontier advance and any carving, so the world is current).
    collapse.evaluate_around(dig.surface, dig.position, nil, dig.player_index)
end

-- Public API (ADR 0002 door #2): external mods register declarative threat
-- specs; rolls are seed-keyed like everything else.
remote.add_interface("diggy-v1", {
    register_threat = threats.register_external,
    -- Headless test hooks (used by the maintainer's automated benchmarks).
    debug_sim = function(bare) sim.start(nil, bare) end,
    debug_sim_stop = function() sim.stop(nil) end,
    debug_max_stress = function(surface_index, x1, y1, x2, y2)
        return collapse.max_in_area(game.surfaces[surface_index], x1, y1, x2, y2)
    end,
    -- Exactness proof for the mirror's event coverage (ADR 0009).
    debug_mirror_check = function(surface_index, x1, y1, x2, y2)
        return mirror.check(game.surfaces[surface_index], x1, y1, x2, y2)
    end,
    -- Drift probe for the layer-2 stress cache (ADR 0009).
    debug_cache_check = function(surface_index, x1, y1, x2, y2)
        return collapse.cache_check(game.surfaces[surface_index], x1, y1, x2, y2)
    end,
    debug_protected = function(surface_index, x, y)
        return collapse.is_protected(game.surfaces[surface_index], x, y)
    end,
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
        -- A wall or reactor: gone from the mirror first, then re-evaluate
        -- everything its live reach was holding up.
        mirror.support_removed(entity)
        collapse.evaluate_around(entity.surface, entity.position,
            collapse.reach_radius(entity.force), event.player_index)
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
    mirror.support_added(entity)
    collapse.evaluate_around(entity.surface, entity.position, collapse.reach_radius(entity.force))
end
script.on_event(defines.events.on_built_entity, on_built, support_filter)
script.on_event(defines.events.on_robot_built_entity, on_built, support_filter)
script.on_event(defines.events.script_raised_built, on_built, support_filter)
script.on_event(defines.events.script_raised_revive, on_built, support_filter)

local function on_tiles_changed(surface, tiles, player_index)
    for _, t in pairs(tiles) do
        mirror.refresh_tile(surface, t.position)
        collapse.evaluate_around(surface, t.position, 3, player_index)
    end
end
script.on_event(defines.events.on_player_built_tile, function(event)
    on_tiles_changed(game.surfaces[event.surface_index], event.tiles, event.player_index)
end)
script.on_event(defines.events.on_robot_built_tile, function(event)
    on_tiles_changed(event.robot.surface, event.tiles)
end)
script.on_event(defines.events.on_player_mined_tile, function(event)
    on_tiles_changed(game.surfaces[event.surface_index], event.tiles, event.player_index)
end)
script.on_event(defines.events.on_robot_mined_tile, function(event)
    on_tiles_changed(event.robot.surface, event.tiles)
end)
-- Other mods (MTS included) may re-tile script-side; stay current.
script.on_event(defines.events.script_raised_set_tiles, function(event)
    on_tiles_changed(game.surfaces[event.surface_index], event.tiles)
end)

script.on_nth_tick(30, function()
    collapse.on_heartbeat()
    caverns.on_heartbeat()
end)

-- Mirror housekeeping (ADR 0009). Wipe on join: every peer — including the
-- joiner, who starts empty — then derives identical cache content from
-- identical events, which is what lockstep requires of local caches.
script.on_event(defines.events.on_player_joined_game, function()
    mirror.wipe()
    collapse.wipe_cache()
end)
script.on_event(defines.events.on_surface_deleted, function(event)
    mirror.drop_surface(event.surface_index)
    collapse.drop_surface_cache(event.surface_index)
end)
script.on_event(defines.events.on_surface_cleared, function(event)
    mirror.drop_surface(event.surface_index)
    collapse.drop_surface_cache(event.surface_index)
end)
-- Two-strike chunk eviction keeps RAM bounded to active areas.
script.on_nth_tick(1800, function()
    mirror.sweep()
end)

-- Support Struts completing widens every wall's reach instantly: re-judge
-- the cells currently wearing warning markers so stale warnings clear.
script.on_event(defines.events.on_research_finished, function(event)
    if not event.research.name:find("diggy-support-reach", 1, true) then return end
    -- Every wall's cached contribution just changed: start over.
    collapse.wipe_cache()
    refresh_warned_cells()
end)


commands.add_command("diggy-sim", { "diggy.command-sim" }, function(event)
    local player = event.player_index and game.get_player(event.player_index)
    if not player then return end
    if not player.admin then
        player.print({ "diggy.admin-only" })
        return
    end
    local param = event.parameter or ""
    if param == "stop" then
        sim.stop(player)
    else
        sim.start(player, param:find("bare") ~= nil, param:find("slow") ~= nil)
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

commands.add_command("diggy-mirror-check", { "diggy.command-mirror-check" }, function(event)
    local player = event.player_index and game.get_player(event.player_index)
    if not player then return end
    if not player.admin then
        player.print({ "diggy.admin-only" })
        return
    end
    local p = player.position
    local r = mirror.check(player.surface, p.x - 96, p.y - 96, p.x + 96, p.y + 96)
    player.print({ "diggy.mirror-check", r.chunks, r.mismatches, r.first or "-" })
end)

-- Pop-text animation and pending-collapse countdowns: per tick, but a
-- single table check each when nothing is animating.
script.on_event(defines.events.on_tick, function(event)
    pop_text.tick(event.tick)
    collapse.tick()
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
    elseif event.setting == "diggy-wall-support"
        or event.setting == "diggy-strut-strength-max"
        or event.setting == "diggy-wall-crowding" then
        -- The strength basis moved: wall records carry strength (rebuild
        -- facts), LUTs and cached values bake it in (rebuild derivations),
        -- then re-judge what's currently warning. Everything else updates
        -- on the next world event near it.
        mirror.wipe()
        collapse.stress_basis_changed()
        refresh_warned_cells()
    end
end)
