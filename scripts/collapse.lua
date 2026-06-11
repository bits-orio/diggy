-- Cave collapse, ported faithfully from RedMew Diggy's diggy_cave_collapse:
-- a per-surface stress map at 2x2 cell resolution. Revealing space adds
-- stress (blurred disc mask, size 9, ring weights 2/3/4); supports — wall
-- rocks, stone walls, reinforced flooring — subtract it. Crossing 3.57
-- triggers a delayed cave-in that re-walls the area and crushes entities
-- into buried crushed remains (CONTEXT.md). Stress math is deterministic;
-- identical digging collapses identically across MTS teams.
local hash = require("scripts.lib.hash")
local mts = require("scripts.mts")

local collapse = {}

local STRESS_THRESHOLD = 3.57
local NEAR_THRESHOLD = 3.3
local COLLAPSE_DELAY_TICKS = 150 -- original: 2.5s
local NEW_TILE_GRACE_TICKS = 180 -- original: 3s; fresh reveals plug, not chain
local COLLAPSE_MASK_FACTOR = 16 -- original: collapse_threshold_total_strength

-- Support strengths (original Template.support_beam_entities, adapted:
-- our wall entities stand in for big-rock/huge-rock, void reveal = out-of-map).
local SUPPORTS = {
    -- The natural wall is the great support: any cell within mask reach of a
    -- remaining rock face is heavily relieved, which is what creates the
    -- felt "grace distance" between standing rock and a possible collapse.
    -- Collapses belong in the middle of wide unsupported clearings — and
    -- leaving natural rock pillars becomes a real strategy, as in the
    -- original Diggy. Digging stays symmetric: +4 when a rock dies, -4 when
    -- the frontier replaces it, so tunneling is still stress-negative.
    ["diggy-rock"] = 4,
    ["diggy-tree"] = 4,
    ["stone-wall"] = 3,
    ["nuclear-reactor"] = 4,
}
local TILE_SUPPORTS = {
    ["stone-path"] = 0.03,
    ["concrete"] = 0.04,
    ["hazard-concrete-left"] = 0.04,
    ["hazard-concrete-right"] = 0.04,
    ["refined-concrete"] = 0.06,
    ["refined-hazard-concrete-left"] = 0.06,
    ["refined-hazard-concrete-right"] = 0.06,
}
local VOID_REVEAL_STRESS = 1 -- original: out-of-map support strength

collapse.SUPPORT_NAMES = { "diggy-rock", "diggy-tree", "stone-wall", "nuclear-reactor" }

-- Disc masks: three rings, relative weights 2 (ring), 3 (disc), 4 (center),
-- normalized to sum 1. Base radius 4 (the original's size-9 mask); larger
-- radii exist for the support-reach research, built on demand.
local BASE_RADIUS = 4
local MASKS = {}

local function build_mask(radius)
    local radius_sq = (radius + 0.2) * (radius + 0.2)
    local center_sq = radius_sq / 9
    local disc_sq = radius_sq * 4 / 9
    local weights = { ring = 2, disc = 3, center = 4 }
    local sum = 0
    for x = -radius, radius do
        for y = -radius, radius do
            local d = x * x + y * y
            if d <= center_sq then
                sum = sum + weights.center
            elseif d <= disc_sq then
                sum = sum + weights.disc
            elseif d <= radius_sq then
                sum = sum + weights.ring
            end
        end
    end
    local mask = {}
    for x = -radius, radius do
        for y = -radius, radius do
            local d = x * x + y * y
            local w
            if d <= center_sq then
                w = weights.center
            elseif d <= disc_sq then
                w = weights.disc
            elseif d <= radius_sq then
                w = weights.ring
            end
            if w then
                mask[#mask + 1] = { x = x, y = y, value = w / sum }
            end
        end
    end
    return mask
end

local function mask_for(radius)
    radius = radius or BASE_RADIUS
    if not MASKS[radius] then
        MASKS[radius] = build_mask(radius)
    end
    return MASKS[radius]
end

local MASK = mask_for(BASE_RADIUS)

function collapse.on_init()
    storage.stress = {}
    storage.new_tiles = {}
    storage.pending_collapses = {}
    storage.collapse_count = {}
    -- Reach (mask radius) per placed support, keyed by unit_number: removal
    -- must undo with the SAME mask it was placed with, or stress corrupts.
    storage.support_reach = {}
end

local function cell_key(x, y)
    return x .. "," .. y
end

-- Injected by caverns.lua: returns true while a cell sits inside a cavern
-- room still under worm protection (no triggers there until the worms die).
collapse.protection_check = nil

local function trigger(surface, x, y, player_index)
    if not settings.global["diggy-collapse-enabled"].value then return end
    if collapse.protection_check and collapse.protection_check(surface, x, y) then return end

    -- Fresh reveals plug with a single rock instead of chain-collapsing —
    -- this is what lets cavern rooms open without instantly caving in.
    local expiry = storage.new_tiles[surface.index .. ":" .. cell_key(x, y)]
    if expiry and game.tick < expiry then
        local tile = surface.get_tile(x, y)
        if surface.count_entities_filtered { name = collapse.SUPPORT_NAMES, position = { x + 0.5, y + 0.5 }, radius = 0.4 } == 0
            and tile.valid and tile.name ~= "out-of-map" and not tile.name:find("water", 1, true) then
            surface.create_entity { name = "diggy-rock", position = { x + 0.5, y + 0.5 }, force = "neutral" }
        end
        return
    end

    -- Cracking warning, then the ceiling comes down after the delay.
    local force = player_index and game.get_player(player_index).force
        or mts.surface_owner_force(surface)
    for _, player in pairs(force.connected_players) do
        player.create_local_flying_text {
            text = { "diggy.cracking-sound-" .. hash.range(surface.map_gen_settings.seed, x, y, 60, 1, 2) },
            position = { x, y },
            color = { r = 1, g = 0.3, b = 0 },
        }
    end
    storage.pending_collapses[#storage.pending_collapses + 1] = {
        surface_index = surface.index,
        x = x,
        y = y,
        player_index = player_index,
        at_tick = game.tick + COLLAPSE_DELAY_TICKS,
    }
end

-- While true, positive stress never triggers (used for batch-loading a
-- cavern's deferred stress at activation).
local suppress_triggers = false

-- Add a fraction to one stress cell; trigger when crossing thresholds.
local function add_cell(surface, x, y, fraction, player_index)
    x = 2 * math.floor(x * 0.5)
    y = 2 * math.floor(y * 0.5)

    local map = storage.stress[surface.index]
    if not map then
        map = {}
        storage.stress[surface.index] = map
    end
    local key = cell_key(x, y)
    local value = (map[key] or 0) + fraction
    map[key] = value

    if fraction > 0 and not suppress_triggers then
        if value > STRESS_THRESHOLD then
            trigger(surface, x, y, player_index)
        elseif value > NEAR_THRESHOLD then
            for _ = 1, 4 do
                surface.create_particle {
                    name = "big-rock-stone-particle-medium",
                    position = { x + math.random(), y + math.random() },
                    movement = { 0, 0 },
                    height = 1,
                    vertical_speed = -0.04,
                    frame_speed = 1,
                }
            end
        end
    end
    return value
end

-- Apply the blurred mask around a position. A wider radius (support-reach
-- research) spreads a proportionally larger total so per-cell strength stays
-- constant — reach grows, protection never thins.
local function stress_add(surface, position, factor, player_index, radius)
    local mask = mask_for(radius)
    if radius and radius ~= BASE_RADIUS then
        factor = factor * (#mask / #MASK)
    end
    local x0, y0 = math.floor(position.x), math.floor(position.y)
    for _, m in pairs(mask) do
        add_cell(surface, x0 + m.x, y0 + m.y, m.value * factor, player_index)
    end
end

-- Public API ----------------------------------------------------------------

-- A tile was opened (dig or cavern carve): void support removed + grace mark.
function collapse.tile_revealed(surface, x, y, player_index)
    storage.new_tiles[surface.index .. ":" .. cell_key(2 * math.floor(x * 0.5), 2 * math.floor(y * 0.5))] =
        game.tick + NEW_TILE_GRACE_TICKS
    stress_add(surface, { x = x, y = y }, VOID_REVEAL_STRESS, player_index)
end

function collapse.support_added(surface, position, name, reach)
    local strength = SUPPORTS[name]
    if strength then
        stress_add(surface, position, -strength, nil, reach)
    end
end

function collapse.support_removed(surface, position, name, player_index, reach)
    local strength = SUPPORTS[name]
    if strength then
        stress_add(surface, position, strength, player_index, reach)
    end
end

function collapse.on_built_tile(surface, new_tile, tiles)
    local new_strength = TILE_SUPPORTS[new_tile.name]
    for _, tile in pairs(tiles) do
        if new_strength then
            add_cell(surface, tile.position.x, tile.position.y, -new_strength)
        end
        local old_strength = TILE_SUPPORTS[tile.old_tile.name]
        if old_strength then
            add_cell(surface, tile.position.x, tile.position.y, old_strength)
        end
    end
end

function collapse.on_mined_tile(surface, tiles, player_index)
    for _, tile in pairs(tiles) do
        local strength = TILE_SUPPORTS[tile.old_tile.name]
        if strength then
            add_cell(surface, tile.position.x, tile.position.y, strength, player_index)
        end
    end
end

-- Collapse execution ---------------------------------------------------------

-- Crush an entity: with crushed-remains recovery enabled (off by default),
-- inventories go into a buried character-corpse (CONTEXT.md "Crushed
-- remains"); otherwise the building and its contents are simply destroyed.
local function crush(surface, entity)
    -- Characters just die: their vanilla death corpse already preserves the
    -- full inventory. Extracting it first created a SECOND corpse with
    -- copies of everything — free item duplication per collapse death.
    if entity.type == "character" then
        entity.die()
        return
    end
    if not settings.global["diggy-crushed-remains"].value then
        entity.die()
        return
    end
    local stacks = {}
    for i = 1, 10 do
        local ok, inventory = pcall(entity.get_inventory, i)
        if ok and inventory and inventory.valid then
            for j = 1, #inventory do
                local stack = inventory[j]
                if stack.valid_for_read then
                    stacks[#stacks + 1] = { name = stack.name, count = stack.count, quality = stack.quality }
                end
            end
        end
    end
    if #stacks > 0 then
        local corpse = surface.create_entity {
            name = "character-corpse",
            position = entity.position,
            inventory_size = #stacks,
        }
        if corpse then
            local inv = corpse.get_inventory(defines.inventory.character_corpse)
            for _, s in pairs(stacks) do
                inv.insert(s)
            end
        end
    end
    entity.die()
end

local function execute(pending)
    local surface = game.surfaces[pending.surface_index]
    if not surface or not surface.valid then return end

    -- Collect cells still over-stressed within the collapse mask.
    local map = storage.stress[pending.surface_index] or {}
    local positions = {}
    for _, m in pairs(MASK) do
        local cx = 2 * math.floor((pending.x + m.x) * 0.5)
        local cy = 2 * math.floor((pending.y + m.y) * 0.5)
        local value = map[cell_key(cx, cy)] or 0
        if value >= STRESS_THRESHOLD - m.value * COLLAPSE_MASK_FACTOR then
            positions[cell_key(cx, cy)] = { x = cx, y = cy }
        end
    end
    if not next(positions) then return end

    surface.create_entity { name = "big-explosion", position = { pending.x, pending.y } }

    local rocks = 0
    for _, cell in pairs(positions) do
        -- Each 2x2 stress cell re-walls its four tiles unless supported.
        for dx = 0, 1 do
            for dy = 0, 1 do
                local tx, ty = cell.x + dx, cell.y + dy
                local supported = false
                for _, entity in pairs(surface.find_entities_filtered {
                    area = { { tx + 0.05, ty + 0.05 }, { tx + 0.95, ty + 0.95 } },
                }) do
                    if SUPPORTS[entity.name] then
                        supported = true
                    elseif entity.name == "character-corpse" or entity.type == "resource" then
                        -- buried, not crushed
                    elseif entity.type == "character" or entity.health then
                        crush(surface, entity)
                    end
                end
                local tile = surface.get_tile(tx, ty)
                if not supported and tile.valid and tile.name ~= "out-of-map"
                    and not tile.name:find("water", 1, true) then
                    surface.create_entity { name = "diggy-rock", position = { tx + 0.5, ty + 0.5 }, force = "neutral" }
                    -- Fallen rock supports the ceiling again (the original
                    -- registered collapse rocks through its placement events).
                    stress_add(surface, { x = tx + 0.5, y = ty + 0.5 }, -SUPPORTS["diggy-rock"])
                    rocks = rocks + 1
                end
            end
        end
    end

    if rocks > 0 then
        storage.collapse_count[pending.surface_index] = (storage.collapse_count[pending.surface_index] or 0) + 1
        local force = pending.player_index and game.get_player(pending.player_index).force
            or mts.surface_owner_force(surface)
        force.print({ "diggy.cave-collapse" })
        -- Cross-team schadenfreude (host-toggleable): other MTS teams hear
        -- about it with the suffering team's coloured label.
        if settings.global["diggy-collapse-broadcast"].value then
            local label = mts.team_label(force)
            for _, other in pairs(mts.other_team_forces(force)) do
                other.print({ "diggy.cave-collapse-other", label })
            end
        end
        -- add_custom_alert needs a LuaEntity at the alert location; the
        -- original used a throwaway rock as the target, destroyed right after.
        local target = surface.create_entity {
            name = "diggy-rock",
            position = { pending.x + 0.5, pending.y + 0.5 },
            force = "neutral",
        }
        if target then
            for _, player in pairs(force.connected_players) do
                player.add_custom_alert(target, { type = "item", name = "stone" }, { "diggy.cave-collapse" }, true)
            end
            target.destroy()
        end
    end
end

-- Cavern activation: batch-load the room's deferred reveal stress (+1 per
-- carved tile, triggers suppressed) and return the cells that ended over the
-- collapse threshold — the cavern's failure zone.
function collapse.arm_area(surface, tiles, factor)
    factor = factor or VOID_REVEAL_STRESS
    suppress_triggers = true
    local hot = {}
    for _, t in pairs(tiles) do
        for _, m in pairs(MASK) do
            local value = add_cell(surface, t[1] + m.x, t[2] + m.y, m.value * factor)
            if value > STRESS_THRESHOLD then
                local cx = 2 * math.floor((t[1] + m.x) * 0.5)
                local cy = 2 * math.floor((t[2] + m.y) * 0.5)
                hot[cell_key(cx, cy)] = { x = cx, y = cy }
            end
        end
    end
    suppress_triggers = false
    local list = {}
    for _, c in pairs(hot) do list[#list + 1] = c end
    return list
end

-- Cavern collapse: like execute(), but over given cells and deliberately
-- sparse — an ancient ceiling sheds about half its mass, not all of it.
-- The failure zone is re-checked against the LIVE stress map at execution:
-- pillars placed during the countdown push cells back under threshold and
-- those cells hold. Enough pillars and nothing falls at all.
function collapse.sparse_collapse(surface, cells, force, seed)
    local map = storage.stress[surface.index] or {}
    local live = {}
    for _, cell in pairs(cells) do
        if (map[cell_key(cell.x, cell.y)] or 0) > STRESS_THRESHOLD then
            live[#live + 1] = cell
        end
    end
    cells = live
    if #cells == 0 then return 0 end

    local rocks = 0
    for _, cell in pairs(cells) do
        for dx = 0, 1 do
            for dy = 0, 1 do
                local tx, ty = cell.x + dx, cell.y + dy
                local supported = false
                for _, entity in pairs(surface.find_entities_filtered {
                    area = { { tx + 0.05, ty + 0.05 }, { tx + 0.95, ty + 0.95 } },
                }) do
                    if SUPPORTS[entity.name] then
                        supported = true
                    elseif entity.name == "character-corpse" or entity.type == "resource" then
                        -- buried, not crushed
                    elseif entity.type == "character" or entity.health then
                        crush(surface, entity)
                    end
                end
                local tile = surface.get_tile(tx, ty)
                if not supported and tile.valid and tile.name ~= "out-of-map"
                    and not tile.name:find("water", 1, true)
                    and hash.roll(seed, tx, ty, 80) < 0.55 then
                    surface.create_entity { name = "diggy-rock", position = { tx + 0.5, ty + 0.5 }, force = "neutral" }
                    stress_add(surface, { x = tx + 0.5, y = ty + 0.5 }, -SUPPORTS["diggy-rock"])
                    rocks = rocks + 1
                end
            end
        end
    end
    if rocks > 0 and force then
        force.print({ "diggy.cavern-collapsed" })
    end
    return rocks
end

-- The only timer in the mod: a 0.5s heartbeat that fires pending collapses
-- (the original used a task scheduler for the same 2.5s delay).
function collapse.on_heartbeat()
    local pending = storage.pending_collapses
    if not pending or #pending == 0 then return end
    local now = game.tick
    for i = #pending, 1, -1 do
        if pending[i].at_tick <= now then
            local job = table.remove(pending, i)
            execute(job)
        end
    end
end

return collapse
