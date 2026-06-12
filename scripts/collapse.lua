-- Cave collapse via STATELESS geometry stress (ADR 0008): a cell's stress is
-- a pure function of the current world —
--   stress = LOAD x (mask-weighted open-floor fraction)
--            - Σ support contributions (entities by live reach, flooring)
-- recomputed on demand for cells affected by each world-changing event.
-- No ledger, no history, no possibility of poisoned saves. Thresholds, mask
-- shape and support strengths preserve the tuned outcome: a fully open
-- unsupported cell reads exactly 4.0 against the 3.57 threshold, and a
-- stone-wall lattice with 3-tile gaps holds (~2.5-3.0). Wall strength 5 is
-- the deliberate deviation from the original's 3 (see ADR 0008 history).
local hash = require("scripts.lib.hash")
local mts = require("scripts.mts")
local pop_text = require("scripts.pop_text")

local collapse = {}

local STRESS_THRESHOLD = 3.57
local NEAR_THRESHOLD = 3.3
local COLLAPSE_DELAY_TICKS = 150 -- original: 2.5s
local COLLAPSE_MASK_FACTOR = 16 -- original: collapse_threshold_total_strength
local LOAD = 4.0 -- a fully open, unsupported cell

local SUPPORTS = {
    ["diggy-rock"] = 2,
    ["diggy-tree"] = 2,
    ["diggy-rubble"] = 2,
    ["stone-wall"] = 5,
    ["nuclear-reactor"] = 6,
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

collapse.SUPPORT_NAMES = { "diggy-rock", "diggy-tree", "diggy-rubble", "stone-wall", "nuclear-reactor" }
local BASE_RADIUS = 4
local MAX_REACH = 10

-- Disc mask (size 9 at base): rings 2/3/4 normalized. value_of(d²) gives the
-- per-point weight; supports with researched reach use wider masks, scaled
-- so per-cell strength stays constant.
local MASKS = {}

local function build_mask(radius)
    local radius_sq = (radius + 0.2) * (radius + 0.2)
    local center_sq = radius_sq / 9
    local disc_sq = radius_sq * 4 / 9
    local weights = { ring = 2, disc = 3, center = 4 }
    local sum, points = 0, 0
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
                sum = sum + w
                points = points + 1
            end
        end
    end
    return {
        radius = radius,
        points = points,
        value_of = function(d_sq)
            if d_sq <= center_sq then return weights.center / sum end
            if d_sq <= disc_sq then return weights.disc / sum end
            if d_sq <= radius_sq then return weights.ring / sum end
            return 0
        end,
    }
end

local function mask_for(radius)
    radius = math.min(math.max(radius or BASE_RADIUS, BASE_RADIUS), MAX_REACH)
    if not MASKS[radius] then MASKS[radius] = build_mask(radius) end
    return MASKS[radius]
end
local BASE_MASK = mask_for(BASE_RADIUS)

function collapse.on_init()
    storage.pending_collapses = {}
    storage.collapse_count = {}
    storage.collapse_log = {}
    storage.warn_renders = {}
end

local function cell_key(x, y)
    return x .. "," .. y
end

-- Injected by caverns.lua: true while a worm-guarded room covers the cell.
collapse.protection_check = nil

-- Live Support Struts reach per force: research benefits ALL walls at once.
local reach_cache, reach_cache_tick = {}, -1
local function force_reach(force)
    if reach_cache_tick ~= game.tick then
        reach_cache, reach_cache_tick = {}, game.tick
    end
    local cached = reach_cache[force.index]
    if cached then return cached end
    local reach = BASE_RADIUS
    for i = 1, 6 do
        local tech = force.technologies["diggy-support-reach-" .. i]
        if tech and tech.researched then reach = reach + 1 end
    end
    reach_cache[force.index] = reach
    return reach
end

-- ── The function (cell coords are even; a cell spans 2x2 tiles) ──────────

function collapse.compute_cell(surface, cx, cy)
    -- One pass over the base mask: open-ceiling load + own-cell flooring.
    local load_w = 0
    local flooring = 0
    for ox = -BASE_RADIUS, BASE_RADIUS do
        for oy = -BASE_RADIUS, BASE_RADIUS do
            local w = BASE_MASK.value_of(ox * ox + oy * oy)
            if w > 0 then
                local tile = surface.get_tile(cx + ox, cy + oy)
                if tile.valid then
                    local name = tile.name
                    if name ~= "out-of-map" and not name:find("water", 1, true) then
                        load_w = load_w + w
                        if ox >= 0 and ox <= 1 and oy >= 0 and oy <= 1 then
                            local ts = TILE_SUPPORTS[name]
                            if ts then flooring = flooring + ts end
                        end
                    end
                end
            end
        end
    end
    -- A cell holds 4 mask points; fully open ⇒ 4 x Σw = LOAD.
    local value = LOAD * load_w - flooring

    -- Supports within maximum possible reach, each by its own (live) mask.
    for _, entity in pairs(surface.find_entities_filtered {
        name = collapse.SUPPORT_NAMES,
        position = { cx + 1, cy + 1 },
        radius = MAX_REACH + 1.5,
    }) do
        local strength = SUPPORTS[entity.name]
        local reach = BASE_RADIUS
        if entity.name == "stone-wall" or entity.name == "nuclear-reactor" then
            reach = force_reach(entity.force)
        end
        local mask = mask_for(reach)
        local dx = cx - math.floor(entity.position.x)
        local dy = cy - math.floor(entity.position.y)
        local w = mask.value_of(dx * dx + dy * dy)
        if w > 0 then
            value = value - strength * (mask.points / BASE_MASK.points) * 4 * w
        end
    end
    return value
end

-- ── Markers, triggers, evaluation ────────────────────────────────────────

-- A cell is evaluable only if its anchor tile is real ground: void cells
-- beyond the frontier see open neighbors and read high, but nothing there
-- can fall. Every evaluator must apply this — values at void cells are
-- measurement artifacts, not hazards.
local function cell_exists(surface, cx, cy)
    local tile = surface.get_tile(cx, cy)
    return tile.valid and tile.name ~= "out-of-map"
end

local function sync_marker(surface, cx, cy, value)
    storage.warn_renders = storage.warn_renders or {}
    local wkey = surface.index .. ":" .. cell_key(cx, cy)
    local marker = storage.warn_renders[wkey]
    if value > NEAR_THRESHOLD and not marker then
        local obj = rendering.draw_sprite {
            sprite = "utility/warning_icon",
            surface = surface,
            target = { cx + 1, cy + 1 },
            x_scale = 0.45,
            y_scale = 0.45,
            tint = { r = 1, g = 0.55, b = 0.1, a = 0.65 },
        }
        if obj then storage.warn_renders[wkey] = obj.id end
    elseif value <= NEAR_THRESHOLD and marker then
        local obj = rendering.get_object_by_id(marker)
        if obj then obj.destroy() end
        storage.warn_renders[wkey] = nil
    end
end

local function trigger(surface, cx, cy, player_index)
    if not settings.global["diggy-collapse-enabled"].value then return end
    if collapse.protection_check and collapse.protection_check(surface, cx, cy) then return end
    for _, p in pairs(storage.pending_collapses) do
        if p.surface_index == surface.index and p.x == cx and p.y == cy then return end
    end

    -- Unmissable telegraph at the failure point (it can be tiles away from
    -- the dig that caused it).
    local force = player_index and game.get_player(player_index).force
        or mts.surface_owner_force(surface)
    pop_text.spawn(surface, { x = cx + 1, y = cy + 1 },
        { "diggy.collapse-imminent-pop" }, { r = 1, g = 0.25, b = 0.05 }, force)
    for _, player in pairs(force.connected_players) do
        player.create_local_flying_text {
            text = { "diggy.cracking-sound-" .. hash.range(surface.map_gen_settings.seed, cx, cy, 60, 1, 2) },
            position = { cx, cy },
            color = { r = 1, g = 0.3, b = 0 },
        }
    end
    storage.pending_collapses[#storage.pending_collapses + 1] = {
        surface_index = surface.index,
        x = cx,
        y = cy,
        player_index = player_index,
        at_tick = game.tick + COLLAPSE_DELAY_TICKS,
    }
end

-- THE entry point after any world-changing event: evaluate every cell within
-- `radius` tiles, sync warning markers, trigger pendings.
function collapse.evaluate_around(surface, position, radius, player_index)
    radius = radius or (BASE_RADIUS + 2)
    local x0, y0 = math.floor(position.x), math.floor(position.y)
    for cx = 2 * math.floor((x0 - radius) * 0.5), x0 + radius, 2 do
        for cy = 2 * math.floor((y0 - radius) * 0.5), y0 + radius, 2 do
            if cell_exists(surface, cx, cy) then
                local value = collapse.compute_cell(surface, cx, cy)
                sync_marker(surface, cx, cy, value)
                if value > STRESS_THRESHOLD then
                    trigger(surface, cx, cy, player_index)
                end
            end
        end
    end
end

-- Cells over threshold within a disc (cavern arming, diagnostics).
function collapse.hot_cells(surface, cx, cy, radius)
    local hot = {}
    for x = 2 * math.floor((cx - radius) * 0.5), cx + radius, 2 do
        for y = 2 * math.floor((cy - radius) * 0.5), cy + radius, 2 do
            if cell_exists(surface, x, y) and collapse.compute_cell(surface, x, y) > STRESS_THRESHOLD then
                hot[#hot + 1] = { x = x, y = y }
            end
        end
    end
    return hot
end

function collapse.max_in_area(surface, x1, y1, x2, y2)
    local maxv = 0
    for x = 2 * math.floor(x1 * 0.5), x2, 2 do
        for y = 2 * math.floor(y1 * 0.5), y2, 2 do
            if cell_exists(surface, x, y) then
                local v = collapse.compute_cell(surface, x, y)
                if v > maxv then maxv = v end
            end
        end
    end
    return maxv
end

-- Debug overlay (/diggy-stress): computed live, painted for 10 seconds.
function collapse.debug_overlay(player)
    local surface = player.surface
    local px, py = math.floor(player.position.x), math.floor(player.position.y)
    local shown = 0
    for x = px - 40, px + 40, 2 do
        for y = py - 40, py + 40, 2 do
            local cx, cy = 2 * math.floor(x * 0.5), 2 * math.floor(y * 0.5)
            local tile = surface.get_tile(cx, cy)
            if tile.valid and tile.name ~= "out-of-map" then
                local value = collapse.compute_cell(surface, cx, cy)
                if value > 0.05 or value < -0.05 then
                    local t = math.min(math.max(value / STRESS_THRESHOLD, 0), 1)
                    rendering.draw_text {
                        text = string.format("%.1f", value),
                        surface = surface,
                        target = { cx + 1, cy + 1 },
                        color = value < 0 and { r = 0.4, g = 0.7, b = 1 }
                            or { r = t, g = 1 - t, b = 0 },
                        scale = 0.8,
                        alignment = "center",
                        time_to_live = 600,
                        players = { player.index },
                    }
                    shown = shown + 1
                end
            end
        end
    end
    player.print({ "diggy.stress-overlay", shown })
end

-- ── Collapse execution ────────────────────────────────────────────────────

-- Crush an entity: with crushed-remains recovery enabled (off by default),
-- inventories go into a buried character-corpse; otherwise destroyed.
local function crush(surface, entity)
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

local function log_collapse(surface_index, x, y)
    storage.collapse_count[surface_index] = (storage.collapse_count[surface_index] or 0) + 1
    storage.collapse_log = storage.collapse_log or {}
    storage.collapse_log[#storage.collapse_log + 1] =
        { surface_index = surface_index, x = x, y = y, tick = game.tick }
    if #storage.collapse_log > 60 then table.remove(storage.collapse_log, 1) end
end

-- Fill one cell's tiles with rubble where unsupported; crush what stands.
local function fill_cell(surface, cellx, celly, density, seed)
    local rocks = 0
    for dx = 0, 1 do
        for dy = 0, 1 do
            local tx, ty = cellx + dx, celly + dy
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
                and (density >= 1 or hash.roll(seed, tx, ty, 80) < density) then
                surface.create_entity { name = "diggy-rubble", position = { tx + 0.5, ty + 0.5 }, force = "neutral" }
                rocks = rocks + 1
            end
        end
    end
    return rocks
end

local function execute(pending)
    local surface = game.surfaces[pending.surface_index]
    if not surface or not surface.valid then return end

    -- Live re-evaluation at execution: pillars placed during the 2.5s
    -- warning are honored; cells they saved don't fall.
    local positions = {}
    for ox = -BASE_RADIUS, BASE_RADIUS do
        for oy = -BASE_RADIUS, BASE_RADIUS do
            local w = BASE_MASK.value_of(ox * ox + oy * oy)
            if w > 0 then
                local cx = 2 * math.floor((pending.x + ox) * 0.5)
                local cy = 2 * math.floor((pending.y + oy) * 0.5)
                local key = cell_key(cx, cy)
                if positions[key] == nil then
                    local value = cell_exists(surface, cx, cy)
                        and collapse.compute_cell(surface, cx, cy) or 0
                    positions[key] = value >= STRESS_THRESHOLD - w * COLLAPSE_MASK_FACTOR
                        and { x = cx, y = cy } or false
                end
            end
        end
    end

    local any = false
    for _, v in pairs(positions) do
        if v then any = true end
    end
    if not any then return end

    surface.create_entity { name = "big-explosion", position = { pending.x, pending.y } }

    local rocks = 0
    local seed = surface.map_gen_settings.seed
    for _, cell in pairs(positions) do
        if cell then
            rocks = rocks + fill_cell(surface, cell.x, cell.y, 1, seed)
        end
    end

    if rocks > 0 then
        log_collapse(pending.surface_index, pending.x, pending.y)
        local force = pending.player_index and game.get_player(pending.player_index).force
            or mts.surface_owner_force(surface)
        force.print({ "diggy.cave-collapse" })
        if settings.global["diggy-collapse-broadcast"].value then
            local label = mts.team_label(force)
            for _, other in pairs(mts.other_team_forces(force)) do
                other.print({ "diggy.cave-collapse-other", label })
            end
        end
        local target = surface.create_entity {
            name = "diggy-rubble",
            position = { pending.x + 0.5, pending.y + 0.5 },
            force = "neutral",
        }
        if target then
            for _, player in pairs(force.connected_players) do
                player.add_custom_alert(target, { type = "item", name = "stone" }, { "diggy.cave-collapse" }, true)
            end
            target.destroy()
        end
        -- New rubble changed the geometry: refresh markers around the site.
        collapse.evaluate_around(surface, { x = pending.x, y = pending.y }, BASE_RADIUS * 2)
    end
end

-- Cavern collapse: sparse (~55%) over the given cells, live re-checked —
-- cells pillared back under threshold during the countdown are spared.
function collapse.sparse_collapse(surface, cells, force, seed)
    local live = {}
    for _, cell in pairs(cells) do
        if collapse.compute_cell(surface, cell.x, cell.y) > STRESS_THRESHOLD then
            live[#live + 1] = cell
        end
    end
    if #live == 0 then return 0 end

    local rocks = 0
    for _, cell in pairs(live) do
        rocks = rocks + fill_cell(surface, cell.x, cell.y, 0.55, seed)
    end
    if rocks > 0 then
        log_collapse(surface.index, live[1].x, live[1].y)
        if force then force.print({ "diggy.cavern-collapsed" }) end
        collapse.evaluate_around(surface, { x = live[1].x, y = live[1].y }, BASE_RADIUS * 3)
    end
    return rocks
end

-- The only timer in the mod: a 0.5s heartbeat that fires pending collapses.
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
