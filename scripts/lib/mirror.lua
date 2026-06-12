-- Chunk-local mirror of the world facts that stress computation reads
-- (ADR 0009): per-tile codes and support entities, held in module locals.
--
-- Soundness rules that make this cache safe where the old ledger wasn't:
--   * It stores FACTS (assignments), never accumulations — a missed event
--     leaves one stale code, fixed by the next write or chunk rebuild;
--     nothing compounds.
--   * It is never saved: chunks rebuild lazily from the engine after load.
--   * It is wiped whenever a player joins, so every peer (including the
--     joiner, who starts empty) derives identical content from identical
--     events — the lockstep-determinism requirement for local caches.
--   * Mutations flow through the same choke points that already announce
--     world changes to collapse.evaluate_around.
local mirror = {}

-- Tile codes: 0 void, 1 water, 2 open floor, 3/4/5 flooring tiers;
-- +8 flags rock-grade cover on the tile (diggy rock/tree/rubble).
mirror.VOID, mirror.WATER, mirror.FLOOR = 0, 1, 2
local FLOOR_CODES = {
    ["stone-path"] = 3,
    ["concrete"] = 4,
    ["hazard-concrete-left"] = 4,
    ["hazard-concrete-right"] = 4,
    ["refined-concrete"] = 5,
    ["refined-hazard-concrete-left"] = 5,
    ["refined-hazard-concrete-right"] = 5,
}
-- Ceiling support per flooring code (own cell only), by tile code.
mirror.FLOOR_SUPPORT = { [3] = 0.03, [4] = 0.04, [5] = 0.06 }

local ROCK_NAMES = { "diggy-rock", "diggy-tree", "diggy-rubble" }
local WALL_NAMES = { "stone-wall", "nuclear-reactor" }

-- Wall strength is host-tunable. Records carry the value they were built
-- with, so a settings change wipes the mirror (control.lua) and records
-- rebuild with the new strength.
local function support_strength(name)
    if name == "stone-wall" then
        return settings.global["diggy-wall-support"].value
    end
    return 6 -- nuclear reactor
end

-- surfaces[surface_index][chunk_x][chunk_y] = {
--   grid = int[1024], walls = { {x, y, s, f} ... }, idle = bool }
local surfaces = {}

-- collapse registers here to keep derived values current (ADR 0009 layer 2):
-- tile changes carry old/new codes, wall changes carry the record and a
-- sign, bulk changes carry a tile rectangle whose content was rebuilt or
-- forgotten wholesale.
local tile_listener, wall_listener, bulk_listener

function mirror.on_tile_change(fn)
    tile_listener = fn
end

function mirror.on_wall_change(fn)
    wall_listener = fn
end

function mirror.on_bulk_change(fn)
    bulk_listener = fn
end

local function notify_bulk(surface_index, cx32, cy32)
    if bulk_listener then
        bulk_listener(surface_index, cx32 * 32, cy32 * 32, cx32 * 32 + 31, cy32 * 32 + 31)
    end
end

local function code_for(name)
    if name == "out-of-map" then return 0 end
    if name:find("water", 1, true) then return 1 end
    return FLOOR_CODES[name] or 2
end

-- Build a chunk's mirror from the engine — the ground-truth read that every
-- repair path reduces to.
local function sync_chunk(surface, cx32, cy32)
    local grid, walls = {}, {}
    local x0, y0 = cx32 * 32, cy32 * 32
    for i = 1, 1024 do
        grid[i] = 0
    end
    if surface.is_chunk_generated({ cx32, cy32 }) then
        local area = { { x0, y0 }, { x0 + 32, y0 + 32 } }
        for _, t in pairs(surface.find_tiles_filtered { area = area, name = "out-of-map", invert = true }) do
            local p = t.position
            grid[(p.y - y0) * 32 + (p.x - x0) + 1] = code_for(t.name)
        end
        for _, e in pairs(surface.find_entities_filtered { area = area, name = ROCK_NAMES }) do
            local p = e.position
            local i = (math.floor(p.y) - y0) * 32 + (math.floor(p.x) - x0) + 1
            if grid[i] >= 2 and grid[i] < 8 then grid[i] = grid[i] + 8 end
        end
        for _, e in pairs(surface.find_entities_filtered { area = area, name = WALL_NAMES }) do
            local p = e.position
            walls[#walls + 1] =
                { x = math.floor(p.x), y = math.floor(p.y), s = support_strength(e.name), f = e.force.index }
        end
    end
    return { grid = grid, walls = walls, idle = false }
end

local function chunk_at(surface, cx32, cy32)
    local si = surface.index
    local sx = surfaces[si]
    if not sx then
        sx = {}
        surfaces[si] = sx
    end
    local col = sx[cx32]
    if not col then
        col = {}
        sx[cx32] = col
    end
    local chunk = col[cy32]
    if not chunk then
        chunk = sync_chunk(surface, cx32, cy32)
        col[cy32] = chunk
    end
    chunk.idle = false
    return chunk
end

-- ── Hot reads ─────────────────────────────────────────────────────────────

function mirror.tile_value(surface, x, y)
    local cx32, cy32 = math.floor(x / 32), math.floor(y / 32)
    local chunk = chunk_at(surface, cx32, cy32)
    return chunk.grid[(y - cy32 * 32) * 32 + (x - cx32 * 32) + 1]
end

-- Fill `out` with the 9x9 tile codes around cell (cx, cy), row-major (y
-- outer) — the compute hot path reads the grid arrays directly instead of
-- paying a function call per tile.
function mirror.fill_window(surface, cx, cy, out)
    local n = 0
    for ty = cy - 4, cy + 4 do
        local cy32 = math.floor(ty / 32)
        local row = (ty - cy32 * 32) * 32 + 1
        local tx = cx - 4
        while tx <= cx + 4 do
            local cx32 = math.floor(tx / 32)
            local grid = chunk_at(surface, cx32, cy32).grid
            local last = math.min(cx + 4, cx32 * 32 + 31)
            local base = row - cx32 * 32
            for x = tx, last do
                n = n + 1
                out[n] = grid[base + x]
            end
            tx = last + 1
        end
    end
end

-- Fill `out` with every wall/reactor record near cell (cx, cy); returns the
-- count. Window covers the maximum researchable reach.
function mirror.walls_near(surface, cx, cy, out)
    local n = 0
    for cxc = math.floor((cx - 11) / 32), math.floor((cx + 12) / 32) do
        for cyc = math.floor((cy - 11) / 32), math.floor((cy + 12) / 32) do
            local walls = chunk_at(surface, cxc, cyc).walls
            for i = 1, #walls do
                n = n + 1
                out[n] = walls[i]
            end
        end
    end
    return n
end

-- ── Assignments (the choke points call these alongside their world edits) ──

local function cached_chunk(surface, x, y)
    -- Setters never force a sync: an uncached chunk simply rebuilds fresh
    -- (already including this change) on its first read.
    local sx = surfaces[surface.index]
    local col = sx and sx[math.floor(x / 32)]
    return col and col[math.floor(y / 32)]
end

local function grid_index(x, y)
    return (y - math.floor(y / 32) * 32) * 32 + (x - math.floor(x / 32) * 32) + 1
end

local function set_code(surface, x, y, code)
    local chunk = cached_chunk(surface, x, y)
    if not chunk then return end
    local i = grid_index(x, y)
    local old = chunk.grid[i]
    if old == code then return end
    chunk.grid[i] = code
    chunk.idle = false
    if tile_listener then tile_listener(surface.index, x, y, old, code) end
end

function mirror.set_rock(surface, position, present)
    -- Force-synced: removals announce a DYING entity that engine queries may
    -- still report mid-event. Syncing first and then assigning makes the
    -- engine's removal timing irrelevant.
    local x, y = math.floor(position.x), math.floor(position.y)
    local chunk = chunk_at(surface, math.floor(x / 32), math.floor(y / 32))
    local v = chunk.grid[grid_index(x, y)]
    if present and v >= 2 and v < 8 then
        set_code(surface, x, y, v + 8)
    elseif not present and v >= 8 then
        set_code(surface, x, y, v - 8)
    end
end

-- Set a tile's floor from its (new) name, preserving any rock flag.
function mirror.set_floor(surface, x, y, name)
    local chunk = cached_chunk(surface, x, y)
    if not chunk then return end
    local code = code_for(name)
    if code >= 2 and chunk.grid[grid_index(x, y)] >= 8 then code = code + 8 end
    set_code(surface, x, y, code)
end

-- Mirror a surface.set_tiles call: pass the same tile array.
function mirror.set_tiles(surface, tiles)
    for _, t in pairs(tiles) do
        local p = t.position
        mirror.set_floor(surface, p[1] or p.x, p[2] or p.y, t.name)
    end
end

-- Re-read one tile from the engine (tile events fire after the change).
function mirror.refresh_tile(surface, position)
    local x, y = math.floor(position.x or position[1]), math.floor(position.y or position[2])
    if not cached_chunk(surface, x, y) then return end
    mirror.set_floor(surface, x, y, surface.get_tile(x, y).name)
end

function mirror.support_added(entity)
    local chunk = cached_chunk(entity.surface, entity.position.x, entity.position.y)
    if not chunk then return end
    local x, y = math.floor(entity.position.x), math.floor(entity.position.y)
    local record = { x = x, y = y, s = support_strength(entity.name), f = entity.force.index }
    chunk.walls[#chunk.walls + 1] = record
    chunk.idle = false
    if wall_listener then wall_listener(entity.surface.index, record, 1) end
end

function mirror.support_removed(entity)
    -- Force-synced, same reasoning as set_rock: the dying wall may still be
    -- visible to a mid-event chunk sync; correcting after guarantees truth.
    local x, y = math.floor(entity.position.x), math.floor(entity.position.y)
    local chunk = chunk_at(entity.surface, math.floor(x / 32), math.floor(y / 32))
    local walls = chunk.walls
    for i = #walls, 1, -1 do
        if walls[i].x == x and walls[i].y == y then
            local record = walls[i]
            walls[i] = walls[#walls]
            walls[#walls] = nil
            if wall_listener then wall_listener(entity.surface.index, record, -1) end
        end
    end
    chunk.idle = false
end

-- Bulk rebuilds (chunk conversion) just drop the chunk; it re-syncs on read.
-- Derived values near it can no longer trust their deltas: announce the rect.
function mirror.drop_chunk_at(surface, x, y)
    local cx32, cy32 = math.floor(x / 32), math.floor(y / 32)
    local sx = surfaces[surface.index]
    local col = sx and sx[cx32]
    if col and col[cy32] then
        col[cy32] = nil
        notify_bulk(surface.index, cx32, cy32)
    end
end

function mirror.drop_surface(surface_index)
    surfaces[surface_index] = nil
end

-- Wiped on every player join: all peers (including the joiner, who starts
-- empty) then rebuild identically. Also the config-change reset.
function mirror.wipe()
    surfaces = {}
end

-- Two-strike eviction, run from a slow nth_tick: chunks not read since the
-- last sweep are dropped. Keeps RAM bounded to active areas on big servers.
-- Evictions announce as bulk changes: cached cells must not outlive the
-- mirror chunks whose changes would have kept them honest.
function mirror.sweep()
    for si, sx in pairs(surfaces) do
        for cx32, col in pairs(sx) do
            for cy32, chunk in pairs(col) do
                if chunk.idle then
                    col[cy32] = nil
                    notify_bulk(si, cx32, cy32)
                else
                    chunk.idle = true
                end
            end
        end
    end
end

-- ── Verification (admin command / headless harness) ──────────────────────

-- Compare every CACHED chunk intersecting the area against a fresh engine
-- read. Returns total mismatched tiles/walls — exactness proof for the
-- event coverage.
function mirror.check(surface, x1, y1, x2, y2)
    local checked, mismatches, first = 0, 0, nil
    local sx = surfaces[surface.index]
    if not sx then return { chunks = 0, mismatches = 0 } end
    for cx32 = math.floor(x1 / 32), math.floor(x2 / 32) do
        local col = sx[cx32]
        for cy32 = math.floor(y1 / 32), math.floor(y2 / 32) do
            local chunk = col and col[cy32]
            if chunk then
                checked = checked + 1
                local fresh = sync_chunk(surface, cx32, cy32)
                for i = 1, 1024 do
                    if chunk.grid[i] ~= fresh.grid[i] then
                        mismatches = mismatches + 1
                        first = first
                            or string.format("tile (%d,%d) cached=%d fresh=%d",
                                cx32 * 32 + (i - 1) % 32, cy32 * 32 + math.floor((i - 1) / 32),
                                chunk.grid[i], fresh.grid[i])
                    end
                end
                if #chunk.walls ~= #fresh.walls then
                    mismatches = mismatches + 1
                    first = first or string.format("walls in chunk (%d,%d): cached=%d fresh=%d",
                        cx32, cy32, #chunk.walls, #fresh.walls)
                end
            end
        end
    end
    return { chunks = checked, mismatches = mismatches, first = first }
end

return mirror
