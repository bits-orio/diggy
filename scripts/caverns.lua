-- Caverns (ADR 0006): a dig's seed-keyed roll can breach a tunnel that snakes
-- outward, sometimes ending in a room with a depth-gated personality. Carved
-- tiles materialize veins and chart, but per-tile spawn/treasure rolls are
-- skipped — the room's contents are the sole source of its danger and loot.
local hash = require("scripts.lib.hash")
local ore_veins = require("scripts.ore_veins")
local treasure = require("scripts.treasure")
local dig_spawner = require("scripts.dig_spawner")

local caverns = {}

-- Hash stream ids (keep unique across all dig modules).
local S_TRIGGER, S_DIR, S_LEN, S_TURN = 40, 41, 42, 43
local S_ROOM, S_RADIUS, S_TYPE, S_CONTENT = 44, 45, 46, 47

local MIN_DEPTH = 30 -- never breach a cavern right at the carve-out
local DIRS = { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }

-- Room personalities by minimum depth; weights picked per seed-keyed roll.
local ROOM_TYPES = {
    { kind = "empty", min_depth = 0, weight = 50 },
    { kind = "nest", min_depth = 100, weight = 30 },
    { kind = "hoard", min_depth = 140, weight = 15 },
    { kind = "sanctuary", min_depth = 180, weight = 8 },
}

-- Remove cover on a tile without raising dig events (no recursion), then run
-- the carve-reveal pipeline: veins materialize, nothing else rolls.
local function carve_tile(surface, x, y, force, materialize)
    local cover = surface.find_entities_filtered {
        name = { "diggy-rock", "diggy-tree" },
        area = { { x + 0.05, y + 0.05 }, { x + 0.95, y + 0.95 } },
    }
    if #cover == 0 then return end
    for _, entity in pairs(cover) do
        entity.destroy()
    end
    if materialize then
        ore_veins.materialize(surface, x, y, force)
    end
end

local function carve_disc(surface, cx, cy, radius, force, materialize)
    for x = cx - radius, cx + radius do
        for y = cy - radius, cy + radius do
            local dx, dy = x - cx, y - cy
            if dx * dx + dy * dy <= radius * radius then
                carve_tile(surface, x, y, force, materialize)
            end
        end
    end
end

local function populate_nest(surface, cx, cy, radius, seed)
    local tier = dig_spawner.tier_for(game.forces.enemy.get_evolution_factor(surface))
    local center = { cx + 0.5, cy + 0.5 }
    local spawners = hash.range(seed, cx, cy, S_CONTENT, 1, 2)
    for i = 1, spawners do
        local kind = hash.roll(seed, cx, cy, S_CONTENT + 10 + i) < 0.6 and "biter-spawner" or "spitter-spawner"
        local spot = surface.find_non_colliding_position(kind, center, radius, 0.5)
        if spot then surface.create_entity { name = kind, position = spot, force = "enemy" } end
    end
    local worms = hash.range(seed, cx, cy, S_CONTENT + 20, 1, 2)
    for _ = 1, worms do
        local spot = surface.find_non_colliding_position(tier.worm, center, radius, 0.5)
        if spot then surface.create_entity { name = tier.worm, position = spot, force = "enemy" } end
    end
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
    for _ = 1, 3 do
        local spot = surface.find_non_colliding_position("fish", { cx + 0.5, cy + 0.5 }, 3, 0.3)
        if spot then surface.create_entity { name = "fish", position = spot } end
    end
end

local function make_room(surface, cx, cy, seed, force)
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

    -- Sanctuaries replace terrain, so veins would end up under water; skip them.
    carve_disc(surface, cx, cy, radius, force, picked.kind ~= "sanctuary")
    if picked.kind == "nest" then
        populate_nest(surface, cx, cy, radius, seed)
    elseif picked.kind == "hoard" then
        populate_hoard(surface, cx, cy, radius, seed, depth)
    elseif picked.kind == "sanctuary" then
        populate_sanctuary(surface, cx, cy, radius, seed)
    end
    return radius
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

    for step = 1, length do
        cx, cy = cx + dir[1], cy + dir[2]
        -- 2-wide swath: the tile plus its perpendicular neighbour.
        carve_tile(surface, cx, cy, force, true)
        carve_tile(surface, cx + dir[2], cy + dir[1], force, true)
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
        radius = make_room(surface, cx, cy, seed, force)
        min_x, min_y = math.min(min_x, cx - radius), math.min(min_y, cy - radius)
        max_x, max_y = math.max(max_x, cx + radius), math.max(max_y, cy + radius)
    end

    if force then
        force.chart(surface, { { min_x - 2, min_y - 2 }, { max_x + 2, max_y + 2 } })
        force.print({ radius > 0 and "diggy.cavern-room-breached" or "diggy.cavern-breached" })
    end
end

return caverns
