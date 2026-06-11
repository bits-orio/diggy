-- Dig spawns: hostiles enter the world exclusively as a consequence of digging
-- (CONTEXT.md "Dig spawn"). All rolls are seed-keyed by tile (ADR 0005), so
-- MTS teams digging the same tile face identical spawns — except unit tier,
-- which follows the team's own evolution. This module is the seed the threat
-- registry (ADR 0002) grows from.
local hash = require("scripts.lib.hash")

local dig_spawner = {}

-- No hostiles shallower than this; the carve-out and early base stay calm.
local PEACEFUL_DEPTH = 60
-- Nests stay sparse: at most this many spawners within the cap radius.
local NEST_CAP, NEST_CAP_RADIUS = 2, 40

-- Hash stream ids (keep unique across all dig modules).
local S_SPAWN, S_TYPE, S_COUNT, S_NEST_KIND = 10, 11, 12, 13

local UNIT_LADDER = {
    { evolution = 0.00, biter = "small-biter", spitter = "small-spitter", worm = "small-worm-turret" },
    { evolution = 0.25, biter = "medium-biter", spitter = "medium-spitter", worm = "medium-worm-turret" },
    { evolution = 0.55, biter = "big-biter", spitter = "big-spitter", worm = "big-worm-turret" },
    { evolution = 0.85, biter = "behemoth-biter", spitter = "behemoth-spitter", worm = "behemoth-worm-turret" },
}

local function tier_for(evolution)
    local tier = UNIT_LADDER[1]
    for _, candidate in pairs(UNIT_LADDER) do
        if evolution >= candidate.evolution then tier = candidate end
    end
    return tier
end

local function spawn_units(surface, position, tier, seed, x, y)
    for i = 1, hash.range(seed, x, y, S_COUNT, 1, 2) do
        local name = hash.roll(seed, x, y, S_TYPE + i * 100) < 0.7 and tier.biter or tier.spitter
        -- The dying cover entity still occupies its tile during the event, so
        -- a collision-free spot often doesn't exist yet; spawning at the dig
        -- position is fine — the cover is gone by the end of the tick.
        local spot = surface.find_non_colliding_position(name, position, 4, 0.5) or position
        surface.create_entity { name = name, position = spot, force = "enemy" }
    end
end

local function spawn_nest(surface, position, tier, seed, x, y)
    if surface.count_entities_filtered {
            type = "unit-spawner", position = position, radius = NEST_CAP_RADIUS, limit = NEST_CAP,
        } >= NEST_CAP then
        return spawn_units(surface, position, tier, seed, x, y)
    end
    local name = hash.roll(seed, x, y, S_NEST_KIND) < 0.6 and "biter-spawner" or "spitter-spawner"
    -- A spawner needs open space; in a tight tunnel fall back to a worm, and
    -- failing even that, to units.
    local spot = surface.find_non_colliding_position(name, position, 5, 0.5)
    if not spot then
        name = tier.worm
        spot = surface.find_non_colliding_position(name, position, 3, 0.5)
    end
    if spot then
        surface.create_entity { name = name, position = spot, force = "enemy" }
    else
        spawn_units(surface, position, tier, seed, x, y)
    end
end

function dig_spawner.on_dig(dig)
    local position = dig.position
    if position.x * position.x + position.y * position.y < PEACEFUL_DEPTH * PEACEFUL_DEPTH then
        return
    end

    local surface = dig.surface
    local seed = surface.map_gen_settings.seed
    local x = math.floor(position.x)
    local y = math.floor(position.y)

    local nest_chance = settings.global["diggy-dig-nest-chance"].value
    local unit_chance = settings.global["diggy-dig-biter-chance"].value
    local roll = hash.roll(seed, x, y, S_SPAWN)
    if roll >= nest_chance + unit_chance then
        return
    end

    local tier = tier_for(game.forces.enemy.get_evolution_factor(surface))
    if roll < nest_chance then
        spawn_nest(surface, position, tier, seed, x, y)
    else
        spawn_units(surface, position, tier, seed, x, y)
    end
end

-- Expansion would let nests appear without digging; keep it host-controlled
-- and off by default.
function dig_spawner.apply_expansion_setting()
    game.map_settings.enemy_expansion.enabled = settings.global["diggy-enemy-expansion"].value
end

return dig_spawner
