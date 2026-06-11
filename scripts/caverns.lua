-- Caverns (ADR 0006): a dig's seed-keyed roll can breach a tunnel that snakes
-- outward, sometimes ending in a room with a depth-gated personality. Carved
-- tiles materialize veins and chart, but per-tile spawn/treasure rolls are
-- skipped — the room's contents are the sole source of its danger and loot.
local hash = require("scripts.lib.hash")
local world = require("scripts.world")
local treasure = require("scripts.treasure")
local dig_spawner = require("scripts.dig_spawner")
local collapse = require("scripts.collapse")

local caverns = {}

local COUNTDOWN_TICKS = 15 * 60

function caverns.on_init()
    storage.cavern_rooms = storage.cavern_rooms or {}
    storage.cavern_worms = storage.cavern_worms or {}
    storage.cavern_countdowns = storage.cavern_countdowns or {}
    storage.next_cavern_id = storage.next_cavern_id or 1
end

-- While a nest room's worms live, no collapse can trigger inside it.
collapse.protection_check = function(surface, x, y)
    for _, room in pairs(storage.cavern_rooms or {}) do
        if room.protected and room.surface_index == surface.index then
            local dx, dy = x - room.cx, y - room.cy
            if dx * dx + dy * dy <= (room.radius + 2) * (room.radius + 2) then
                return true
            end
        end
    end
    return false
end

-- Hash stream ids (keep unique across all dig modules).
local S_TRIGGER, S_DIR, S_LEN, S_TURN = 40, 41, 42, 43
local S_ROOM, S_RADIUS, S_TYPE, S_CONTENT = 44, 45, 46, 47

local MIN_DEPTH = 30 -- never breach a cavern right at the carve-out
local DIRS = { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }

-- Room personalities by minimum depth; weights picked per seed-keyed roll.
local ROOM_TYPES = {
    { kind = "empty", min_depth = 0, weight = 50 },
    { kind = "nest", min_depth = 75, weight = 30 },
    { kind = "hoard", min_depth = 140, weight = 15 },
    { kind = "sanctuary", min_depth = 180, weight = 8 },
}

-- Carving delegates to world.carve_tile (entity removal + void→floor + vein)
-- and records each tile so the frontier can be advanced around the cavern.
local function carve_tile(surface, x, y, force, carved, skip_vein)
    world.carve_tile(surface, x, y, force, skip_vein)
    carved[#carved + 1] = { x, y }
end

local function carve_disc(surface, cx, cy, radius, force, carved, skip_vein)
    for x = cx - radius, cx + radius do
        for y = cy - radius, cy + radius do
            local dx, dy = x - cx, y - cy
            if dx * dx + dy * dy <= radius * radius then
                carve_tile(surface, x, y, force, carved, skip_vein)
            end
        end
    end
end

-- Returns the unit_numbers of the worms guarding the room.
local function populate_nest(surface, cx, cy, radius, seed)
    local tier = dig_spawner.tier_for(game.forces.enemy.get_evolution_factor(surface))
    local center = { cx + 0.5, cy + 0.5 }
    local spawners = hash.range(seed, cx, cy, S_CONTENT, 1, 2)
    for i = 1, spawners do
        local kind = hash.roll(seed, cx, cy, S_CONTENT + 10 + i) < 0.6 and "biter-spawner" or "spitter-spawner"
        local spot = surface.find_non_colliding_position(kind, center, radius, 0.5)
        if spot then surface.create_entity { name = kind, position = spot, force = "enemy" } end
    end
    local worm_ids = {}
    local worms = math.floor(
        hash.range(seed, cx, cy, S_CONTENT + 20, 2, 4)
        * settings.global["diggy-cavern-worm-multiplier"].value + 0.5)
    for i = 1, worms do
        -- Spread worms across the room; fall back to the room center.
        local target = {
            cx + 0.5 + hash.range(seed, cx, cy, S_CONTENT + 50 + i, -radius + 2, radius - 2),
            cy + 0.5 + hash.range(seed, cx, cy, S_CONTENT + 60 + i, -radius + 2, radius - 2),
        }
        local spot = surface.find_non_colliding_position(tier.worm, target, 4, 0.5)
            or surface.find_non_colliding_position(tier.worm, center, radius, 0.5)
        if spot then
            local worm = surface.create_entity { name = tier.worm, position = spot, force = "enemy" }
            if worm then worm_ids[#worm_ids + 1] = worm.unit_number end
        end
    end
    return worm_ids
end

local function populate_hoard(surface, cx, cy, radius, seed, depth)
    for i = 1, hash.range(seed, cx, cy, S_CONTENT, 2, 4) do
        local x = cx + hash.range(seed, cx, cy, S_CONTENT + 30 + i, -radius + 2, radius - 2)
        local y = cy + hash.range(seed, cx, cy, S_CONTENT + 40 + i, -radius + 2, radius - 2)
        treasure.spawn_chest(surface, x, y, depth)
    end
end

local function populate_sanctuary(surface, cx, cy, radius, seed)
    local tiles = {}
    for x = cx - radius, cx + radius do
        for y = cy - radius, cy + radius do
            local dx, dy = x - cx, y - cy
            local d2 = dx * dx + dy * dy
            if d2 <= radius * radius then
                local name
                if d2 <= 9 then
                    name = "water"
                else
                    name = "grass-" .. hash.range(seed, x, y, S_CONTENT, 1, 4)
                end
                tiles[#tiles + 1] = { name = name, position = { x, y } }
            end
        end
    end
    surface.set_tiles(tiles)
    -- Place fish directly on the pool tiles; find_non_colliding from land
    -- tends to fail for water-bound entities.
    for _, offset in pairs({ { 0.5, 0.5 }, { -0.5, -0.5 }, { 1.5, -0.5 } }) do
        surface.create_entity { name = "fish", position = { cx + offset[1], cy + offset[2] } }
    end
end

-- Activate a room's collapse mechanics: load its deferred stress; if the
-- ceiling is failing, start the 15-second countdown toward a sparse cave-in.
local function arm_room(room)
    local surface = game.surfaces[room.surface_index]
    if not surface or not surface.valid then return end
    room.protected = false

    local hot = collapse.arm_area(surface, room.tiles)
    room.tiles = nil -- no longer needed; don't bloat the save
    if #hot == 0 then return end

    local force = game.forces[room.force_index] or game.forces.player
    storage.cavern_countdowns[#storage.cavern_countdowns + 1] = {
        surface_index = room.surface_index,
        cells = hot,
        at_tick = game.tick + COUNTDOWN_TICKS,
        force_index = force.index,
        cx = room.cx,
        cy = room.cy,
    }
    force.print({ "diggy.cavern-armed" })
end

local function make_room(surface, cx, cy, seed, force, carved)
    local radius = hash.range(seed, cx, cy, S_RADIUS, 6, 14)
    local depth = math.sqrt(cx * cx + cy * cy)

    local pool, total = {}, 0
    for _, room in pairs(ROOM_TYPES) do
        if depth >= room.min_depth then
            pool[#pool + 1] = room
            total = total + room.weight
        end
    end
    local roll = hash.roll(seed, cx, cy, S_TYPE) * total
    local picked = pool[#pool]
    for _, room in pairs(pool) do
        roll = roll - room.weight
        if roll <= 0 then
            picked = room
            break
        end
    end

    -- Room tiles are tracked separately: they carry the cavern's deferred
    -- stress, loaded when the room arms.
    local room_tiles = {}
    -- Sanctuaries replace terrain, so veins would end up under water; skip them.
    carve_disc(surface, cx, cy, radius, force, room_tiles, picked.kind == "sanctuary")
    for _, t in pairs(room_tiles) do carved[#carved + 1] = t end

    local worm_ids = {}
    if picked.kind == "nest" then
        worm_ids = populate_nest(surface, cx, cy, radius, seed)
    elseif picked.kind == "hoard" then
        populate_hoard(surface, cx, cy, radius, seed, depth)
    elseif picked.kind == "sanctuary" then
        populate_sanctuary(surface, cx, cy, radius, seed)
    end

    -- Sanctuaries are truly stable; every other room owes the ceiling its
    -- due — immediately if nothing guards it, or once its last worm dies.
    if picked.kind ~= "sanctuary" then
        local id = storage.next_cavern_id
        storage.next_cavern_id = id + 1
        local room = {
            id = id,
            surface_index = surface.index,
            cx = cx,
            cy = cy,
            radius = radius,
            force_index = force and force.index or game.forces.player.index,
            tiles = room_tiles,
            worms = #worm_ids,
            protected = #worm_ids > 0,
        }
        storage.cavern_rooms[id] = room
        for _, unit in pairs(worm_ids) do
            storage.cavern_worms[unit] = id
        end
        if not room.protected then
            arm_room(room)
            storage.cavern_rooms[id] = nil
        end
    end
    return radius
end

-- A guarding worm died: when the last one falls, the room arms.
function caverns.on_worm_died(entity)
    local id = storage.cavern_worms and storage.cavern_worms[entity.unit_number]
    if not id then return end
    storage.cavern_worms[entity.unit_number] = nil
    local room = storage.cavern_rooms[id]
    if not room or not room.protected then return end
    room.worms = room.worms - 1
    if room.worms <= 0 then
        arm_room(room)
        storage.cavern_rooms[id] = nil
    end
end

-- Countdown display, MTS-popover style: a top-centre screen frame per player
-- on the affected force, updated each heartbeat.
local function update_countdown_gui(force, seconds)
    for _, player in pairs(force.connected_players) do
        local frame = player.gui.screen["diggy-cavern-countdown"]
        if seconds then
            if not frame then
                frame = player.gui.screen.add { type = "frame", name = "diggy-cavern-countdown" }
                frame.add { type = "label", name = "text", style = "heading_1_label" }
                local res, scale = player.display_resolution, player.display_scale
                frame.location = { x = math.floor(res.width / 2 - 170 * scale), y = math.floor(90 * scale) }
            end
            frame.text.caption = { "diggy.cavern-countdown", seconds }
        elseif frame then
            frame.destroy()
        end
    end
end

function caverns.on_heartbeat()
    local countdowns = storage.cavern_countdowns
    if not countdowns or #countdowns == 0 then return end
    local now = game.tick
    local remaining_by_force = {}
    for i = #countdowns, 1, -1 do
        local cd = countdowns[i]
        local surface = game.surfaces[cd.surface_index]
        if not surface or not surface.valid then
            table.remove(countdowns, i)
        elseif cd.at_tick <= now then
            table.remove(countdowns, i)
            local force = game.forces[cd.force_index]
            collapse.sparse_collapse(surface, cd.cells, force, surface.map_gen_settings.seed)
        else
            local secs = math.ceil((cd.at_tick - now) / 60)
            local f = cd.force_index
            if not remaining_by_force[f] or secs < remaining_by_force[f] then
                remaining_by_force[f] = secs
            end
        end
    end
    for _, force in pairs(game.forces) do
        update_countdown_gui(force, remaining_by_force[force.index])
    end
end

function caverns.on_dig(dig)
    local position = dig.position
    local x, y = math.floor(position.x), math.floor(position.y)
    if x * x + y * y < MIN_DEPTH * MIN_DEPTH then return end

    local surface = dig.surface
    local seed = surface.map_gen_settings.seed
    if hash.roll(seed, x, y, S_TRIGGER) >= settings.global["diggy-cavern-chance"].value then
        return
    end

    local force = dig.force
    local dir = DIRS[hash.range(seed, x, y, S_DIR, 1, 4)]
    local length = hash.range(seed, x, y, S_LEN, 12, 40)
    local cx, cy = x, y
    local min_x, min_y, max_x, max_y = x, y, x, y
    local carved = {}

    for step = 1, length do
        cx, cy = cx + dir[1], cy + dir[2]
        -- 3-wide swath: the tile plus both perpendicular neighbours.
        carve_tile(surface, cx, cy, force, carved)
        carve_tile(surface, cx + dir[2], cy + dir[1], force, carved)
        carve_tile(surface, cx - dir[2], cy - dir[1], force, carved)
        min_x, min_y = math.min(min_x, cx), math.min(min_y, cy)
        max_x, max_y = math.max(max_x, cx), math.max(max_y, cy)
        -- Snake: reconsider heading every few steps.
        if step % 3 == 0 then
            local turn = hash.roll(seed, cx, cy, S_TURN)
            if turn < 0.25 then
                dir = { dir[2], dir[1] }
            elseif turn < 0.5 then
                dir = { -dir[2], -dir[1] }
            end
        end
    end

    local radius = 0
    if hash.roll(seed, cx, cy, S_ROOM) < 0.4 then
        radius = make_room(surface, cx, cy, seed, force, carved)
        min_x, min_y = math.min(min_x, cx - radius), math.min(min_y, cy - radius)
        max_x, max_y = math.max(max_x, cx + radius), math.max(max_y, cy + radius)
    end

    -- Wall off every void tile touching the carved space — the cavern gets
    -- its own frontier instead of bleeding into blackness.
    world.advance_frontier(surface, carved)

    if force then
        force.chart(surface, { { min_x - 2, min_y - 2 }, { max_x + 2, max_y + 2 } })
        force.print({ radius > 0 and "diggy.cavern-room-breached" or "diggy.cavern-breached" })
    end
end

return caverns
