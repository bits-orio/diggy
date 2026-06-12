-- Self-contained repeatable benchmark (/diggy-sim [bare|stop]):
--   2. clears a 32x32 hall east of the player at 4 digs/tick (real-time
--      pacing so grace timers and collapse delays behave like play),
--   3. maintains an EXACT square stone-wall lattice with 3-tile gaps
--      (anchor snapped to the lattice, walls force-placed on-point — no
--      find_non_colliding drift, idempotent across reruns),
--   4. logs progress to factorio-current.log every 2 seconds and prints a
--      PASS/FAIL verdict at the end (pillared mode passes on zero collapses).
local collapse = require("scripts.collapse")

local sim = {}

local DIGS_PER_TICK = 4
local LOG_EVERY = 120
local SIZE = 32 -- multiple of 4; lattice points at +2 step 4
local LIMIT = 1600

local function total_collapses()
    local count = 0
    for _, c in pairs(storage.collapse_count or {}) do count = count + c end
    return count
end

local function slog(s, message)
    log(string.format("[DIGGY-SIM] t=%d mode=%s %s", game.tick, s.bare and "bare" or "pillared", message))
end

-- ── Evidence: every run archives artifacts under script-output/<run_id>/ ──

-- Region dump: per tile "x,y,cell_stress,code" (#void ~water .floor W/R/T).
local function dump_stress(s, stage)
    local surface = game.surfaces[s.surface_index]
    local memo = {}
    local out = {}
    for y = s.y1 - 8, s.y1 + SIZE + 8 do
        for x = s.x1 - 8, s.x1 + SIZE + 8 do
            local cx, cy = 2 * math.floor(x * 0.5), 2 * math.floor(y * 0.5)
            local mkey = cx .. "," .. cy
            local v = memo[mkey]
            if v == nil then
                -- Mirror evaluate_around: cells whose anchor tile is void are
                -- never evaluated by the engine, so the dump reads them as 0.
                local anchor = surface.get_tile(cx, cy)
                v = (anchor.valid and anchor.name ~= "out-of-map")
                    and collapse.compute_cell(surface, cx, cy) or 0
                memo[mkey] = v
            end
            local t = surface.get_tile(x, y)
            local code = "."
            if not t.valid or t.name == "out-of-map" then
                code = "#"
            elseif t.name:find("water", 1, true) then
                code = "~"
            end
            local box = { { x + 0.05, y + 0.05 }, { x + 0.95, y + 0.95 } }
            if surface.count_entities_filtered { name = "stone-wall", area = box } > 0 then
                code = "W"
            elseif surface.count_entities_filtered { name = "diggy-rock", area = box } > 0 then
                code = "R"
            elseif surface.count_entities_filtered { name = "diggy-tree", area = box } > 0 then
                code = "T"
            end
            out[#out + 1] = x .. "," .. y .. "," .. string.format("%.2f", v) .. "," .. code
        end
    end
    helpers.write_file(s.run_id .. "/stress-" .. stage .. ".csv", table.concat(out, "\n"))
end

-- Real screenshot when a renderer exists (graphical client); silent no-op
-- headless. Centered on the hall, zoomed to include the surroundings.
local function shoot(s, stage)
    pcall(game.take_screenshot, {
        surface = game.surfaces[s.surface_index],
        position = { s.x1 + SIZE / 2, s.y1 + SIZE / 2 },
        resolution = { 1280, 1280 },
        zoom = 0.55,
        path = s.run_id .. "/shot-" .. stage .. ".png",
        show_entity_info = true,
        daytime = 0,
        water_tick = 0,
    })
end

local function archive(s, stage)
    dump_stress(s, stage)
    shoot(s, stage)
end

-- player is optional: headless callers (diggy-v1 debug_sim) anchor at spawn.
-- slow mode digs ~10/s instead of 240/s and repaints the stress overlay
-- every 10 seconds, so a player can watch the ledger evolve step by step.
function sim.start(player, bare, slow)
    if storage.sim then
        if player then player.print({ "diggy.sim-already-running" }) end
        return
    end
    local surface = player and player.surface or game.surfaces["nauvis"]
    local p = player and player.position or { x = 12, y = 0 }
    local x1 = math.floor(p.x) + 4
    local y1 = math.floor(p.y) - SIZE / 2
    -- Snap the anchor so the lattice lands identically on reruns.
    x1 = x1 - (x1 % 4)
    y1 = y1 - (y1 % 4)

    storage.sim = {
        surface_index = surface.index,
        x1 = x1,
        y1 = y1,
        player_index = player and player.index or nil,
        force_name = player and player.force.name or "player",
        bare = bare or false,
        dug = 0,
        started_tick = game.tick,
        collapses_at_start = total_collapses(),
        last_log = game.tick,
        run_id = string.format("diggy-sim-%s-t%d", bare and "bare" or "pillared", game.tick),
        slow = slow or false,
    }
    slog(storage.sim, string.format("start region=(%d,%d)..(%d,%d) artifacts=script-output/%s/", x1, y1, x1 + SIZE, y1 + SIZE, storage.sim.run_id))
    archive(storage.sim, "start")
    if player then player.print({ "diggy.sim-started", bare and "bare" or "pillared" }) end
end

local function status(s, surface)
    return string.format("dug=%d collapses=%d max_stress=%.2f walls=%d",
        s.dug,
        total_collapses() - s.collapses_at_start,
        collapse.max_in_area(surface, s.x1, s.y1, s.x1 + SIZE, s.y1 + SIZE),
        surface.count_entities_filtered { name = "stone-wall", area = { { s.x1, s.y1 }, { s.x1 + SIZE, s.y1 + SIZE } } })
end

local function finish(s, aborted)
    storage.sim = nil
    local surface = game.surfaces[s.surface_index]
    if not surface or not surface.valid then return end
    -- Verdict counts only collapses INSIDE the test region (+margin): the
    -- sim's edge digging can legitimately topple adjacent old unsupported
    -- space, which is the player's debt, not the lattice's failure.
    local collapses, outside = 0, 0
    for _, entry in pairs(storage.collapse_log or {}) do
        if entry.tick >= s.started_tick and entry.surface_index == s.surface_index then
            if entry.x >= s.x1 - 6 and entry.x <= s.x1 + SIZE + 6
                and entry.y >= s.y1 - 6 and entry.y <= s.y1 + SIZE + 6 then
                collapses = collapses + 1
            else
                outside = outside + 1
            end
        end
    end
    if outside > 0 then
        slog(s, string.format("note: %d collapse(s) OUTSIDE the region — adjacent unsupported space pushed over by edge digging", outside))
    end
    local maxv = collapse.max_in_area(surface, s.x1, s.y1, s.x1 + SIZE, s.y1 + SIZE)
    local verdict
    if aborted then
        verdict = "ABORTED"
    elseif s.bare then
        verdict = collapses > 0 and "PASS (bare mode collapsed, as expected)" or "FAIL (bare mode survived?)"
    else
        verdict = (collapses == 0 and maxv < 3.57) and "PASS" or "FAIL"
    end
    local summary = "finish " .. status(s, surface) .. " verdict=" .. verdict
    slog(s, summary)
    archive(s, "end")
    helpers.write_file(s.run_id .. "/summary.txt",
        string.format("run=%s\nmode=%s\nregion=(%d,%d)..(%d,%d)\n%s\nduration_s=%d\n",
            s.run_id, s.bare and "bare" or "pillared", s.x1, s.y1, s.x1 + SIZE, s.y1 + SIZE,
            summary, math.floor((game.tick - s.started_tick) / 60)))
    local player = s.player_index and game.get_player(s.player_index)
    if player then
        player.print({ "diggy.sim-finished", verdict, s.dug,
            collapses, string.format("%.2f", maxv),
            math.floor((game.tick - s.started_tick) / 60) })
    end
end

function sim.stop(player)
    local s = storage.sim
    if s then
        finish(s, true)
    elseif player then
        player.print({ "diggy.sim-not-running" })
    end
end

function sim.step()
    local s = storage.sim
    if not s then return end
    local surface = game.surfaces[s.surface_index]
    if not surface or not surface.valid then
        storage.sim = nil
        return
    end
    if s.slow then
        if game.tick % 6 ~= 0 then return end
        if s.player_index and game.tick % 600 == 0 then
            local player = game.get_player(s.player_index)
            if player and player.connected then
                pcall(collapse.debug_overlay, player)
            end
        end
    end
    local x2, y2 = s.x1 + SIZE, s.y1 + SIZE

    -- One scan per tick; dig the best candidates (burrow toward the region,
    -- then sweep it west to east).
    local candidates = {}
    local in_region = 0
    for _, r in pairs(surface.find_entities_filtered { name = { "diggy-rock", "diggy-tree" } }) do
        if r.valid then
            local p = r.position
            local d
            if p.x >= s.x1 and p.x <= x2 and p.y >= s.y1 and p.y <= y2 then
                d = (p.x - s.x1) * 100 + math.abs(p.y - (s.y1 + SIZE / 2))
                in_region = in_region + 1
            else
                local dx = math.max(s.x1 - p.x, 0, p.x - x2)
                local dy = math.max(s.y1 - p.y, 0, p.y - y2)
                d = 1000000 + dx * dx + dy * dy
            end
            candidates[#candidates + 1] = { r, d }
        end
    end
    table.sort(candidates, function(a, b) return a[2] < b[2] end)

    -- The hall is done when its interior holds no more wall: stop digging
    -- (never eat the boundary outward), let pending collapses resolve for a
    -- few seconds, then judge.
    if s.region_seen and in_region == 0 then
        if not s.settle_until then
            s.settle_until = game.tick + 300
            slog(s, "region clear — settling " .. status(s, surface))
        elseif game.tick >= s.settle_until then
            finish(s)
            return
        end
    elseif #candidates == 0 then
        finish(s)
        return
    else
        for i = 1, math.min(s.slow and 1 or DIGS_PER_TICK, #candidates) do
            local entry = candidates[i]
            if entry[1].valid then
                if entry[2] < 1000000 then s.region_seen = true end
                entry[1].die(s.force_name)
                s.dug = s.dug + 1
                if s.dug >= LIMIT then
                    finish(s)
                    return
                end
            end
        end
    end

    -- Exact lattice: walls go on the snapped grid points, force-placed
    -- (script placement ignores collision, so nothing drifts off-grid).
    if not s.bare then
        for x = s.x1 + 2, x2 - 2, 4 do
            for y = s.y1 + 2, y2 - 2, 4 do
                local tile = surface.get_tile(x, y)
                if tile.valid and tile.name ~= "out-of-map" and not tile.name:find("water", 1, true)
                    and surface.count_entities_filtered { name = { "stone-wall", "diggy-rock", "diggy-tree" }, position = { x + 0.5, y + 0.5 }, radius = 0.4 } == 0 then
                    surface.create_entity { name = "stone-wall", position = { x + 0.5, y + 0.5 }, force = s.force_name, raise_built = true }
                end
            end
        end
    end

    if game.tick - s.last_log >= LOG_EVERY then
        s.last_log = game.tick
        slog(s, status(s, surface))
    end
end

return sim
