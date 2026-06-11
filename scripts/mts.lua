-- Optional Multi-Team Support integration. All calls are pcall-guarded and
-- made from event context only (never main chunk / on_load), per MTS's
-- consumer guidance. Every helper degrades cleanly when MTS is absent.
local mts = {}

function mts.available()
    return script.active_mods["multi-team-support"] ~= nil
        and remote.interfaces["mts-v1"] ~= nil
end

-- The force that owns a surface (each MTS team plays its own surface).
-- Standalone fallback: the vanilla player force.
function mts.surface_owner_force(surface)
    if mts.available() then
        local ok, owner = pcall(remote.call, "mts-v1", "get_surface_owner", surface.name)
        if ok and owner and game.forces[owner] then
            return game.forces[owner]
        end
    end
    return game.forces.player
end

-- MTS-styled coloured team label ("[color]Team X[/color] [Leader]").
-- Falls back to the force name when MTS is absent or the force isn't a team.
function mts.team_label(force)
    if mts.available() then
        local ok, label = pcall(remote.call, "mts-v1", "get_team_label", force.name)
        if ok and label then return label end
    end
    return force.name
end

-- Occupied team forces other than `force` (for cross-team broadcasts).
-- Standalone: empty — there is nobody else to tell.
function mts.other_team_forces(force)
    local others = {}
    if mts.available() then
        local ok, teams = pcall(remote.call, "mts-v1", "get_team_list")
        if ok and teams then
            for _, team in pairs(teams) do
                if team.is_occupied and team.force_name ~= force.name then
                    local other = game.forces[team.force_name]
                    if other then others[#others + 1] = other end
                end
            end
        end
    end
    return others
end

return mts
