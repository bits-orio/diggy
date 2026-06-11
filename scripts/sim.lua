-- Repeatable in-game test scenario (/diggy-sim): clears a fixed 30x30 hall
-- east of the player at a steady pace (so grace timers and collapse delays
-- behave like real play), pillaring a 3-tile-gap stone-wall grid as it goes —
-- the same benchmark the headless tests use. "/diggy-sim bare" skips the
-- pillars (expect collapses); "/diggy-sim stop" aborts and reports.
local sim = {}

local DIGS_PER_TICK = 4
local W, H = 30, 30
local LIMIT = 1500

local function total_collapses()
    local count = 0
    for _, c in pairs(storage.collapse_count or {}) do count = count + c end
    return count
end

function sim.start(player, bare)
    if storage.sim then
        player.print({ "diggy.sim-already-running" })
        return
    end
    local p = player.position
    storage.sim = {
        surface_index = player.surface.index,
        x1 = math.floor(p.x) + 4,
        y1 = math.floor(p.y) - H / 2,
        player_index = player.index,
        force_name = player.force.name,
        bare = bare or false,
        dug = 0,
        started_tick = game.tick,
        collapses_at_start = total_collapses(),
    }
    player.print({ "diggy.sim-started", bare and "bare" or "pillared" })
end

local function finish(s, aborted)
    storage.sim = nil
    local player = game.get_player(s.player_index)
    if not player then return end
    local map = storage.stress[s.surface_index] or {}
    local maxv = -99
    for x = s.x1, s.x1 + W, 2 do
        for y = s.y1, s.y1 + H, 2 do
            local v = map[(2 * math.floor(x * 0.5)) .. "," .. (2 * math.floor(y * 0.5))] or 0
            if v > maxv then maxv = v end
        end
    end
    player.print({ "diggy.sim-finished",
        aborted and "aborted" or "done",
        s.dug,
        total_collapses() - s.collapses_at_start,
        string.format("%.2f", maxv),
        math.floor((game.tick - s.started_tick) / 60),
    })
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
    local x2, y2 = s.x1 + W, s.y1 + H

    -- One scan per tick; dig the best few candidates from it.
    local candidates = {}
    for _, r in pairs(surface.find_entities_filtered { name = { "diggy-rock", "diggy-tree" } }) do
        if r.valid then
            local p = r.position
            local d
            if p.x >= s.x1 and p.x <= x2 and p.y >= s.y1 and p.y <= y2 then
                d = (p.x - s.x1) * 100 + math.abs(p.y - (s.y1 + H / 2))
            else
                local dx = math.max(s.x1 - p.x, 0, p.x - x2)
                local dy = math.max(s.y1 - p.y, 0, p.y - y2)
                d = 1000000 + dx * dx + dy * dy
            end
            candidates[#candidates + 1] = { r, d }
        end
    end
    table.sort(candidates, function(a, b) return a[2] < b[2] end)

    for i = 1, math.min(DIGS_PER_TICK, #candidates) do
        local entry = candidates[i]
        if entry[2] >= 2000000 then
            finish(s)
            return
        end
        if entry[1].valid then
            entry[1].die(s.force_name)
            s.dug = s.dug + 1
            if s.dug >= LIMIT then
                finish(s)
                return
            end
        end
    end
    if #candidates == 0 then
        finish(s)
        return
    end

    -- Pillar pass: keep the 3-tile-gap grid current on freshly opened floor.
    if not s.bare then
        for x = s.x1 + 2, x2 - 2, 4 do
            for y = s.y1 + 2, y2 - 2, 4 do
                local tile = surface.get_tile(x, y)
                if tile.valid and tile.name ~= "out-of-map" and not tile.name:find("water", 1, true)
                    and surface.count_entities_filtered { name = "stone-wall", position = { x + 0.5, y + 0.5 }, radius = 1 } == 0 then
                    local spot = surface.find_non_colliding_position("stone-wall", { x + 0.5, y + 0.5 }, 1, 0.5)
                    if spot then
                        surface.create_entity { name = "stone-wall", position = spot, force = s.force_name, raise_built = true }
                    end
                end
            end
        end
    end
end

return sim
