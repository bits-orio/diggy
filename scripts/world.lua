-- The frontier void world (ADR 0007). Chunks generate as out-of-map; this
-- module builds the world at runtime: the spawn carve-out, floor reveals,
-- frontier-wall advancement, and water pools. Everything is seed-keyed
-- (ADR 0005) — identical digging yields identical worlds across MTS teams.
local Simplex = require("scripts.lib.simplex")
local hash = require("scripts.lib.hash")
local ore_veins = require("scripts.ore_veins")
local collapse = require("scripts.collapse")

local world = {}

local CARVE_RADIUS = settings.startup["diggy-carve-out-radius"].value

-- Hash stream ids (keep unique across all dig modules).
local S_FLOOR, S_WALL_TREE, S_STARTER, S_STARTER_ORE = 50, 51, 52, 53

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
local function flood_water(surface, seed, x, y)
    local tiles, seen, queue = {}, {}, { { x, y } }
    while #queue > 0 and #tiles < WATER.flood_cap do
        local t = table.remove(queue)
        local key = t[1] .. "," .. t[2]
        if not seen[key] then
            seen[key] = true
            if is_water_spot(seed, t[1], t[2]) then
                tiles[#tiles + 1] = { name = "water", position = { t[1], t[2] } }
                for _, d in pairs(DIRS4) do
                    ensure_chunk(surface, t[1] + d[1], t[2] + d[2])
                    queue[#queue + 1] = { t[1] + d[1], t[2] + d[2] }
                end
            end
        end
    end
    surface.set_tiles(tiles)
end

-- Turn a void tile into frontier wall: floor underneath, cover entity on top.
-- Water spots become (part of) a pool instead — water itself is the barrier.
local function make_wall(surface, seed, x, y)
    if is_water_spot(seed, x, y) then
        flood_water(surface, seed, x, y)
        return
    end
    surface.set_tiles({ { name = floor_tile(seed, x, y), position = { x, y } } })
    local tree = Simplex.d2(x * TREES.scale, y * TREES.scale, seed + TREES.seed) > TREES.threshold
    local name = tree and "diggy-tree" or "diggy-rock"
    surface.create_entity { name = name, position = { x + 0.5, y + 0.5 }, force = "neutral" }
    collapse.support_added(surface, { x = x + 0.5, y = y + 0.5 }, name)
end

-- Carve a tile fully open (cavern carving): removes any wall entity, opens
-- void as floor with its vein. skip_vein for tiles about to be re-tiled
-- (sanctuaries), where ore would end up under water or grass.
function world.carve_tile(surface, x, y, force, skip_vein)
    ensure_chunk(surface, x, y)
    for _, entity in pairs(surface.find_entities_filtered {
        name = { "diggy-rock", "diggy-tree" },
        area = { { x + 0.05, y + 0.05 }, { x + 0.95, y + 0.95 } },
    }) do
        -- destroy() raises no events, so hand the support back explicitly.
        collapse.support_removed(surface, entity.position, entity.name)
        entity.destroy()
    end
    if not is_void(surface, x, y) then return end

    local seed = surface.map_gen_settings.seed
    if is_water_spot(seed, x, y) then
        flood_water(surface, seed, x, y)
        return
    end
    surface.set_tiles({ { name = floor_tile(seed, x, y), position = { x, y } } })
    if not skip_vein then
        ore_veins.materialize(surface, x, y, force)
    end
    -- Carved space stresses the ceiling like any reveal, but with the fresh-
    -- tile grace so rooms open up instead of instantly caving in.
    collapse.tile_revealed(surface, x, y)
end

-- Advance the frontier around freshly opened tiles: every adjacent void tile
-- becomes wall.
function world.advance_frontier(surface, tiles)
    local seed = surface.map_gen_settings.seed
    for _, t in pairs(tiles) do
        for _, d in pairs(DIRS4) do
            local nx, ny = t[1] + d[1], t[2] + d[2]
            ensure_chunk(surface, nx, ny)
            if is_void(surface, nx, ny) then
                make_wall(surface, seed, nx, ny)
            end
        end
    end
end

function world.on_dig(dig)
    -- Original stress model per dig: the dug wall's support is gone (+2
    -- blurred), the opened tile stresses the ceiling (+1 blurred, with grace),
    -- and any new wall spawned by the frontier advance subtracts its support.
    collapse.support_removed(dig.surface, dig.position, dig.name, dig.player_index)
    collapse.tile_revealed(dig.surface, math.floor(dig.position.x), math.floor(dig.position.y), dig.player_index)
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
    local ring_sq = (CARVE_RADIUS - 1.5) * (CARVE_RADIUS - 1.5)

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
        -- Ring walls register as supports (the original "stress-hacked" its
        -- starting ring) so digging them out later is stress-neutral.
        collapse.support_added(surface, { x = w[1] + 0.5, y = w[2] + 0.5 }, name)
    end
    for _, o in pairs(ores) do
        surface.create_entity {
            name = STARTER_ORES[hash.range(seed, o[1], o[2], S_STARTER_ORE, 1, #STARTER_ORES)],
            position = { o[1] + 0.5, o[2] + 0.5 },
            amount = 80,
        }
    end
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
