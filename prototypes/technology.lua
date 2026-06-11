-- Dig-speed progression: 35 character-mining-speed technologies — five per
-- science group, except the space group which has ten. Per-tier bonus ramps
-- linearly so the final (10th space) tier grants exactly +100%. Force-level,
-- so under MTS each team researches its own digging speed.
local GROUPS = {
    { gate = "steel-axe", steps = 5, packs = { "automation-science-pack" } },
    { gate = "logistic-science-pack", steps = 5, packs = { "automation-science-pack", "logistic-science-pack" } },
    { gate = "chemical-science-pack", steps = 5, packs = { "automation-science-pack", "logistic-science-pack", "chemical-science-pack" } },
    { gate = "production-science-pack", steps = 5, packs = { "automation-science-pack", "logistic-science-pack", "chemical-science-pack", "production-science-pack" } },
    { gate = "utility-science-pack", steps = 5, packs = { "automation-science-pack", "logistic-science-pack", "chemical-science-pack", "utility-science-pack" } },
    { gate = "space-science-pack", steps = 10, packs = { "automation-science-pack", "logistic-science-pack", "chemical-science-pack", "utility-science-pack", "space-science-pack" } },
}
local TOTAL_TIERS = 0
for _, group in pairs(GROUPS) do TOTAL_TIERS = TOTAL_TIERS + group.steps end
local FIRST_MODIFIER, LAST_MODIFIER = 0.2, 1.0

local technologies = {}
local tier = 0
local cumulative = 0
for group_index, group in ipairs(GROUPS) do
    for step = 1, group.steps do
        tier = tier + 1
        local prerequisites = {}
        if tier == 1 then
            prerequisites = { group.gate }
        elseif step == 1 then
            prerequisites = { "diggy-dig-speed-" .. (tier - 1), group.gate }
        else
            prerequisites = { "diggy-dig-speed-" .. (tier - 1) }
        end

        local ingredients = {}
        for _, pack in pairs(group.packs) do
            ingredients[#ingredients + 1] = { pack, 1 }
        end

        local modifier = FIRST_MODIFIER + (LAST_MODIFIER - FIRST_MODIFIER) * (tier - 1) / (TOTAL_TIERS - 1)
        modifier = math.floor(modifier * 100 + 0.5) / 100
        cumulative = cumulative + modifier

        technologies[#technologies + 1] = {
            type = "technology",
            name = "diggy-dig-speed-" .. tier,
            localised_name = { "", { "technology-name.diggy-dig-speed" }, " " .. tier },
            localised_description = { "technology-description.diggy-dig-speed-exact",
                tostring(math.floor(modifier * 100 + 0.5)),
                tostring(math.floor(cumulative * 100 + 0.5)) },
            icons = {
                { icon = "__base__/graphics/technology/steel-axe.png", icon_size = 256 },
            },
            effects = {
                { type = "character-mining-speed", modifier = modifier },
            },
            prerequisites = prerequisites,
            unit = {
                count = math.floor(50 * group_index * step * 1.25),
                ingredients = ingredients,
                time = 15 + group_index * 15,
            },
            order = "diggy-" .. string.format("%02d", tier),
        }
    end
end

-- Support reach: each tier extends how far wall/reactor supports project
-- their stress relief, letting pillars stand one tile further apart.
-- Gated chemical → production → utility → space, then two more space tiers.
local SUPPORT_TIERS = {
    { gate = "chemical-science-pack", packs = { "automation-science-pack", "logistic-science-pack", "chemical-science-pack" } },
    { gate = "production-science-pack", packs = { "automation-science-pack", "logistic-science-pack", "chemical-science-pack", "production-science-pack" } },
    { gate = "utility-science-pack", packs = { "automation-science-pack", "logistic-science-pack", "chemical-science-pack", "production-science-pack", "utility-science-pack" } },
    { gate = "space-science-pack", packs = { "automation-science-pack", "logistic-science-pack", "chemical-science-pack", "production-science-pack", "utility-science-pack", "space-science-pack" } },
    { gate = nil, packs = { "automation-science-pack", "logistic-science-pack", "chemical-science-pack", "production-science-pack", "utility-science-pack", "space-science-pack" } },
    { gate = nil, packs = { "automation-science-pack", "logistic-science-pack", "chemical-science-pack", "production-science-pack", "utility-science-pack", "space-science-pack" } },
}

for tier, def in ipairs(SUPPORT_TIERS) do
    local prerequisites = {}
    if tier == 1 then
        prerequisites = { def.gate }
    elseif def.gate then
        prerequisites = { "diggy-support-reach-" .. (tier - 1), def.gate }
    else
        prerequisites = { "diggy-support-reach-" .. (tier - 1) }
    end
    local ingredients = {}
    for _, pack in pairs(def.packs) do
        ingredients[#ingredients + 1] = { pack, 1 }
    end
    technologies[#technologies + 1] = {
        type = "technology",
        name = "diggy-support-reach-" .. tier,
        localised_name = { "", { "technology-name.diggy-support-reach" }, " " .. tier },
        localised_description = { "technology-description.diggy-support-reach-exact",
            tostring(3 + tier), tostring(4 + tier) },
        icons = {
            { icon = "__base__/graphics/technology/stone-wall.png", icon_size = 256 },
        },
        effects = {
            { type = "nothing", effect_description = { "technology-effect.diggy-support-reach-exact",
                tostring(3 + tier), tostring(4 + tier) } },
        },
        prerequisites = prerequisites,
        unit = {
            count = 150 * tier,
            ingredients = ingredients,
            time = 45,
        },
        order = "diggy-s" .. tier,
    }
end

data:extend(technologies)
