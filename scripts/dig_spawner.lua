-- Dig spawns: hostiles enter the world exclusively as a consequence of digging
-- (CONTEXT.md "Dig spawn"). Each dig rolls — commonly units, rarely a nest or
-- worm materializing in the revealed space. This module is the seed the threat
-- registry (ADR 0002) grows from.
local dig_spawner = {}

-- No hostiles shallower than this; the carve-out and early base stay calm.
local PEACEFUL_DEPTH = 60
-- Nests stay sparse: at most this many spawners within the cap radius.
local NEST_CAP, NEST_CAP_RADIUS = 2, 40

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

local function spawn_units(surface, position, tier)
    for _ = 1, math.random(1, 2) do
        local name = math.random() < 0.7 and tier.biter or tier.spitter
        local spot = surface.find_non_colliding_position(name, position, 4, 0.5)
        if spot then
            surface.create_entity { name = name, position = spot, force = "enemy" }
        end
    end
end

local function spawn_nest(surface, position, tier)
    if surface.count_entities_filtered {
            type = "unit-spawner", position = position, radius = NEST_CAP_RADIUS, limit = NEST_CAP,
        } >= NEST_CAP then
        return spawn_units(surface, position, tier)
    end
    local name = math.random() < 0.6 and "biter-spawner" or "spitter-spawner"
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
        spawn_units(surface, position, tier)
    end
end

function dig_spawner.on_dig(event)
    local entity = event.entity
    local position = entity.position
    if position.x * position.x + position.y * position.y < PEACEFUL_DEPTH * PEACEFUL_DEPTH then
        return
    end

    local nest_chance = settings.global["diggy-dig-nest-chance"].value
    local unit_chance = settings.global["diggy-dig-biter-chance"].value
    local roll = math.random()
    if roll >= nest_chance + unit_chance then
        return
    end

    local surface = entity.surface
    local tier = tier_for(game.forces.enemy.get_evolution_factor(surface))
    if roll < nest_chance then
        spawn_nest(surface, position, tier)
    else
        spawn_units(surface, position, tier)
    end
end

-- Expansion would let nests appear without digging; keep it host-controlled
-- and off by default.
function dig_spawner.apply_expansion_setting()
    game.map_settings.enemy_expansion.enabled = settings.global["diggy-enemy-expansion"].value
end

return dig_spawner
