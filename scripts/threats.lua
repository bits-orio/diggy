-- Threat registry (ADR 0002): a single pool of declarative threat specs that
-- dig rolls draw from, fed by two doors — bundled adapters (integrations/)
-- for mods that don't know Diggy exists, and the diggy-v1 remote
-- register_threat for mods that opt in. Rolls are seed-keyed per tile
-- (ADR 0005); spec order is stable, so outcomes are identical across teams.
--
-- Spec: {
--   name       = unique string,
--   entities   = { prototype names ORDERED weakest..strongest; invalid skipped },
--   min_depth  = number,            -- gate: only digs deeper than this roll
--   chance     = number in (0,1],   -- per-dig roll once gated
--   announce   = optional locale key printed to the digging team on spawn,
--   depth_step = optional number — every step past min_depth unlocks the next
--                entity tier (instead of a random pick), so shallow
--                encounters are the weakest that exist,
--   health_ramp = optional {start, full_depth} — spawn at start fraction of
--                max health at min_depth, ramping to full by full_depth, so
--                the FIRST encounter is survivable even when only one
--                prototype tier exists.
-- }
local hash = require("scripts.lib.hash")

local threats = {}

local S_THREAT_BASE = 70 -- hash stream block: 70 + spec index (keep clear)

-- Bundled adapter specs: rebuilt every load (static config, never stored).
local bundled = {}

function threats.register_bundled(spec)
    bundled[#bundled + 1] = spec
end

function threats.on_init()
    storage.external_threats = storage.external_threats or {}
end

-- Remote door: external specs are plain data, persisted in storage. Re-runs
-- replace by name so consumers can re-register each session safely.
function threats.register_external(spec)
    if type(spec) ~= "table" or type(spec.name) ~= "string"
        or type(spec.entities) ~= "table" or #spec.entities == 0
        or type(spec.min_depth) ~= "number" or type(spec.chance) ~= "number" then
        error("diggy-v1 register_threat: spec needs name, entities[], min_depth, chance")
    end
    storage.external_threats = storage.external_threats or {}
    for i, existing in pairs(storage.external_threats) do
        if existing.name == spec.name then
            storage.external_threats[i] = spec
            return
        end
    end
    storage.external_threats[#storage.external_threats + 1] = spec
end

local function spawn_threat(spec, surface, position, force, seed, x, y, depth)
    local candidates = {}
    for _, name in pairs(spec.entities) do
        if prototypes.entity[name] then
            candidates[#candidates + 1] = name
        end
    end
    if #candidates == 0 then return end

    -- Tier by depth band (weakest first) when the spec asks for progression;
    -- otherwise a seed-keyed pick.
    local name
    if spec.depth_step then
        local band = 1 + math.floor((depth - spec.min_depth) / spec.depth_step)
        name = candidates[math.min(math.max(band, 1), #candidates)]
    else
        name = candidates[hash.range(seed, x, y, S_THREAT_BASE + 50, 1, #candidates)]
    end

    -- Spawn a few tiles away from the dig: the announcement should buy the
    -- digger a beat to react, not narrate their death.
    local angle = hash.roll(seed, x, y, S_THREAT_BASE + 51) * 2 * math.pi
    local away = { position.x + math.cos(angle) * 10, position.y + math.sin(angle) * 10 }
    local spot = surface.find_non_colliding_position(name, away, 6, 0.5)
        or surface.find_non_colliding_position(name, position, 10, 0.5)
        or position
    local entity = surface.create_entity { name = name, position = spot, force = "enemy" }

    -- First encounters arrive weakened: health ramps from ramp.start at the
    -- gate to full strength by ramp.full_depth.
    local ramp = spec.health_ramp
    if entity and ramp then
        local progress = (depth - spec.min_depth) / math.max(ramp.full_depth - spec.min_depth, 1)
        local fraction = math.min(1, ramp.start + (1 - ramp.start) * math.max(progress, 0))
        entity.health = entity.max_health * fraction
    end

    if spec.announce and force then
        force.print({ spec.announce })
    end
end

function threats.on_dig(dig)
    local position = dig.position
    local depth_sq = position.x * position.x + position.y * position.y

    local surface = dig.surface
    local seed = surface.map_gen_settings.seed
    local x, y = math.floor(position.x), math.floor(position.y)

    local index = 0
    local function roll_pool(pool)
        for _, spec in pairs(pool) do
            index = index + 1
            if depth_sq >= spec.min_depth * spec.min_depth
                and hash.roll(seed, x, y, S_THREAT_BASE + index) < spec.chance then
                spawn_threat(spec, surface, position, dig.force, seed, x, y, math.sqrt(depth_sq))
            end
        end
    end
    roll_pool(bundled)
    roll_pool(storage.external_threats or {})
end

return threats
