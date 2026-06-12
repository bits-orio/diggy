-- The frontier void world (ADR 0007). Chunks generate as out-of-map; this
-- module builds the world at runtime: the spawn carve-out, floor reveals,
-- frontier-wall advancement, and water pools. Everything is seed-keyed
-- (ADR 0005) — identical digging yields identical worlds across MTS teams.
local Simplex = require("scripts.lib.simplex")
local hash = require("scripts.lib.hash")
local mirror = require("scripts.lib.mirror")
local ore_veins = require("scripts.ore_veins")
local collapse = require("scripts.collapse")

local world = {}

local CARVE_RADIUS = settings.startup["diggy-carve-out-radius"].value

-- Hash stream ids (keep unique across all dig modules).
local S_FLOOR, S_WALL_TREE, S_STARTER, S_STARTER_ORE, S_FISH = 50, 51, 52, 53, 54

local WATER = { scale = 1 / 30, seed = 8800, threshold = 0.78, flood_cap = 200 }
local TREES = { scale = 1 / 12, seed = 9900, threshold = 0.72 }
local STARTER_ORES = { "iron-ore", "copper-ore", "coal", "stone" }

local DIRS4 = { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }

local function floor_tile(seed, x, y)
    return "dirt-" .. hash.range(seed, x, y, S_FLOOR, 1, 7)
end

local function is_water_spot(seed, x, y)
    return Simplex.d2(x * WATER.scale, y * WATER.scale, seed + WATER.seed) > WATER.threshold
end

local function is_void(surface, x, y)
    local tile = surface.get_tile(x, y)
    return tile.valid and tile.name == "out-of-map"
end

-- Forward declarations: ensure_chunk repairs unbuilt chunks via build_chunk.
local build_chunk, chunk_key

local function ensure_chunk(surface, x, y)
    local cx, cy = math.floor(x / 32), math.floor(y / 32)
    if not surface.is_chunk_generated({ cx, cy }) then
        surface.request_to_generate_chunks({ x, y }, 0)
        surface.force_generate_chunk_requests()
    end
    -- The threaded generator produces "halo" chunks around requested ones
    -- WITHOUT firing on_chunk_generated — they'd stay as raw engine terrain.
    -- The registry makes conversion event-independent: build anything unbuilt.
    local key = chunk_key(surface, cx, cy)
    if not storage.built_chunks[key] and surface.is_chunk_generated({ cx, cy }) then
        storage.built_chunks[key] = true
        build_chunk(surface, {
            left_top = { x = cx * 32, y = cy * 32 },
            right_bottom = { x = cx * 32 + 32, y = cy * 32 + 32 },
        })
    end
end

-- Reveal the contiguous water blob touching (x, y), bounded for safety.
-- Only VOID tiles flood (revealed floor and anything built on it is safe),
-- entities are never destroyed by the tile swap, and any character clipped
-- by the new shoreline is lifted to dry land — digging into a lake must
-- never drown the digger.
local function flood_water(surface, seed, x, y)
    local tiles, seen, queue = {}, {}, { { x, y } }
    local first = true
    local min_x, min_y, max_x, max_y = x, y, x, y
    while #queue > 0 and #tiles < WATER.flood_cap do
        local t = table.remove(queue)
        local key = t[1] .. "," .. t[2]
        if not seen[key] then
            seen[key] = true
            if is_water_spot(seed, t[1], t[2]) and (first or is_void(surface, t[1], t[2])) then
                first = false
                tiles[#tiles + 1] = { name = "water", position = { t[1], t[2] } }
                min_x, min_y = math.min(min_x, t[1]), math.min(min_y, t[2])
                max_x, max_y = math.max(max_x, t[1]), math.max(max_y, t[2])
                for _, d in pairs(DIRS4) do
                    ensure_chunk(surface, t[1] + d[1], t[2] + d[2])
                    queue[#queue + 1] = { t[1] + d[1], t[2] + d[2] }
                end
            end
        end
    end
    surface.set_tiles(tiles, true, false)
    mirror.set_tiles(surface, tiles)
    -- Rescue anyone the new shoreline clipped.
    for _, character in pairs(surface.find_entities_filtered {
        type = "character",
        area = { { min_x - 1, min_y - 1 }, { max_x + 2, max_y + 2 } },
    }) do
        local dry = surface.find_non_colliding_position("character", character.position, 16, 0.5)
        if dry then character.teleport(dry) end
    end
    -- Lakes hold fish: roughly one per seven water tiles, seed-keyed.
    for _, t in pairs(tiles) do
        local tx, ty = t.position[1], t.position[2]
        if hash.roll(seed, tx, ty, S_FISH) < 0.15 then
            surface.create_entity { name = "fish", position = { tx + 0.5, ty + 0.5 } }
        end
    end
end

-- Turn a void tile into frontier wall: floor underneath, cover entity on top.
-- Water spots become (part of) a pool instead — water itself is the barrier.
local function make_wall(surface, seed, x, y)
    if is_water_spot(seed, x, y) then
        flood_water(surface, seed, x, y)
        return
    end
    local floor = floor_tile(seed, x, y)
    surface.set_tiles({ { name = floor, position = { x, y } } })
    local tree = Simplex.d2(x * TREES.scale, y * TREES.scale, seed + TREES.seed) > TREES.threshold
    local name = tree and "diggy-tree" or "diggy-rock"
    surface.create_entity { name = name, position = { x + 0.5, y + 0.5 }, force = "neutral" }
    mirror.set_floor(surface, x, y, floor)
    mirror.set_rock(surface, { x = x, y = y }, true)
end

-- Carve a tile fully open (cavern carving): removes any wall entity, opens
-- void as floor with its vein. skip_vein for tiles about to be re-tiled
-- (sanctuaries), where ore would end up under water or grass.
-- Returns true only when the tile transitioned void -> floor (the caller
-- charges ceiling debt per OPENED tile exactly once; already-open overlap
-- tiles paid their +1 when they were first dug or carved).
function world.carve_tile(surface, x, y, force, skip_vein)
    ensure_chunk(surface, x, y)
    for _, entity in pairs(surface.find_entities_filtered {
        name = { "diggy-rock", "diggy-tree" },
        area = { { x + 0.05, y + 0.05 }, { x + 0.95, y + 0.95 } },
    }) do
        entity.destroy() -- no event fires for destroy(): tell the mirror
        mirror.set_rock(surface, { x = x, y = y }, false)
    end
    if not is_void(surface, x, y) then return false end

    local seed = surface.map_gen_settings.seed
    if is_water_spot(seed, x, y) then
        flood_water(surface, seed, x, y)
        return false
    end
    local floor = floor_tile(seed, x, y)
    surface.set_tiles({ { name = floor, position = { x, y } } })
    mirror.set_floor(surface, x, y, floor)
    if not skip_vein then
        ore_veins.materialize(surface, x, y, force)
    end
    return true
end

-- Advance the frontier around freshly opened tiles: void within TWO steps of
-- open floor becomes wall, keeping the boundary two layers deep so a single
-- dig never punches straight through to the void.
function world.advance_frontier(surface, tiles)
    local seed = surface.map_gen_settings.seed
    for _, t in pairs(tiles) do
        for _, d in pairs(DIRS4) do
            local n1x, n1y = t[1] + d[1], t[2] + d[2]
            ensure_chunk(surface, n1x, n1y)
            if is_void(surface, n1x, n1y) then
                make_wall(surface, seed, n1x, n1y)
            end
            for _, d2 in pairs(DIRS4) do
                local n2x, n2y = n1x + d2[1], n1y + d2[2]
                ensure_chunk(surface, n2x, n2y)
                if is_void(surface, n2x, n2y) then
                    make_wall(surface, seed, n2x, n2y)
                end
            end
        end
    end
end

function world.on_dig(dig)
    world.advance_frontier(dig.surface, { { math.floor(dig.position.x), math.floor(dig.position.y) } })
end

-- Chunks generate as void; chunks touching the spawn carve-out get the
-- starting cave built instead: open floor, a wall ring, and the starter patch.
-- Guarded by a registry: the engine generates the starting chunks before mod
-- handlers can see them, so on_init sweeps existing chunks through this too.
function build_chunk(surface, area)
    local seed = surface.map_gen_settings.seed
    local lt, rb = area.left_top, area.right_bottom
    local carve_sq = CARVE_RADIUS * CARVE_RADIUS
    local ring_sq = (CARVE_RADIUS - 2.5) * (CARVE_RADIUS - 2.5)

    local tiles, walls, ores = {}, {}, {}
    for x = lt.x, rb.x - 1 do
        for y = lt.y, rb.y - 1 do
            local d_sq = x * x + y * y
            if d_sq > carve_sq then
                tiles[#tiles + 1] = { name = "out-of-map", position = { x, y } }
            elseif x >= 5 and x <= 7 and y >= -1 and y <= 1 then
                -- Starter water hole: a guaranteed 3x3 pool near the origin.
                tiles[#tiles + 1] = { name = "water", position = { x, y } }
            else
                tiles[#tiles + 1] = { name = floor_tile(seed, x, y), position = { x, y } }
                if d_sq > ring_sq then
                    walls[#walls + 1] = { x, y }
                elseif hash.roll(seed, x, y, S_STARTER) < 0.12 and d_sq > 4 then
                    ores[#ores + 1] = { x, y }
                end
            end
        end
    end

    surface.set_tiles(tiles)
    for _, w in pairs(walls) do
        local tree = Simplex.d2(w[1] * TREES.scale, w[2] * TREES.scale, seed + TREES.seed) > TREES.threshold
        local name = tree and "diggy-tree" or "diggy-rock"
        surface.create_entity { name = name, position = { w[1] + 0.5, w[2] + 0.5 }, force = "neutral" }
    end
    -- The homestead comes pre-pillared: a stone-wall lattice across the
    -- carve-out, so the starting cave is protected by the same honest
    -- geometry as everything players build later. Minable/reusable; the
    -- spacing follows the wall-support setting so spawn starts calm.
    if lt.x <= 0 and rb.x > 0 and lt.y <= 0 and rb.y > 0 then
        local owner = game.forces.player
        local lattice_max = CARVE_RADIUS - 3
        local step = collapse.recommended_pillar_spacing()
        -- First line at or after -lattice_max on the 2 (mod step) grid —
        -- anchored off the origin so the spawn point stays clear.
        local first = -lattice_max + ((2 + lattice_max) % step)
        for x = first, lattice_max, step do
            for y = first, lattice_max, step do
                if x * x + y * y <= lattice_max * lattice_max
                    and surface.can_place_entity { name = "stone-wall", position = { x + 0.5, y + 0.5 } } then
                    surface.create_entity { name = "stone-wall", position = { x + 0.5, y + 0.5 }, force = owner }
                end
            end
        end
    end
    for _, o in pairs(ores) do
        surface.create_entity {
            name = STARTER_ORES[hash.range(seed, o[1], o[2], S_STARTER_ORE, 1, #STARTER_ORES)],
            position = { o[1] + 0.5, o[2] + 0.5 },
            amount = 160,
        }
    end
    -- The starter pool comes stocked.
    if lt.x <= 6 and rb.x > 6 and lt.y <= 0 and rb.y > 0 then
        for _, p in pairs({ { 5.5, 0.5 }, { 6.5, -0.5 }, { 7.5, 1.5 } }) do
            surface.create_entity { name = "fish", position = p }
        end
    end
    -- Bulk rebuild: any cached mirror of this chunk is stale wholesale.
    mirror.drop_chunk_at(surface, lt.x, lt.y)
end

function chunk_key(surface, x, y)
    return surface.index .. ":" .. x .. ":" .. y
end

function world.on_chunk_generated(event)
    local surface = event.surface
    if surface.name ~= "nauvis" then return end
    local key = chunk_key(surface, event.position.x, event.position.y)
    if storage.built_chunks[key] then return end
    storage.built_chunks[key] = true
    build_chunk(surface, event.area)
end

-- Chart-driven generation can produce tile-only chunks that never fire
-- on_chunk_generated — raw engine terrain, visible on the map as dirt islands
-- in the void. Charted means seen: convert on sight.
function world.on_chunk_charted(event)
    local surface = game.surfaces[event.surface_index]
    if surface.name ~= "nauvis" then return end
    local key = chunk_key(surface, event.position.x, event.position.y)
    if storage.built_chunks[key] then return end
    storage.built_chunks[key] = true
    build_chunk(surface, event.area)
end

function world.on_init()
    storage.built_chunks = {}
    local surface = game.surfaces["nauvis"]
    for chunk in surface.get_chunks() do
        local key = chunk_key(surface, chunk.x, chunk.y)
        if not storage.built_chunks[key] then
            storage.built_chunks[key] = true
            build_chunk(surface, chunk.area)
        end
    end
end

return world
