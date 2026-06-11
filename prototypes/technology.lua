-- Dig-speed progression: 30 character-mining-speed technologies in six groups
-- of five, each group gated by the next science pack. Per-tier bonus ramps
-- linearly so the final tier (5th space tier) grants exactly +100%. Force-
-- level, so under MTS each team researches its own digging speed.
local GROUPS = {
    { gate = "steel-axe", packs = { "automation-science-pack" } },
    { gate = "logistic-science-pack", packs = { "automation-science-pack", "logistic-science-pack" } },
    { gate = "chemical-science-pack", packs = { "automation-science-pack", "logistic-science-pack", "chemical-science-pack" } },
    { gate = "production-science-pack", packs = { "automation-science-pack", "logistic-science-pack", "chemical-science-pack", "production-science-pack" } },
    { gate = "utility-science-pack", packs = { "automation-science-pack", "logistic-science-pack", "chemical-science-pack", "utility-science-pack" } },
    { gate = "space-science-pack", packs = { "automation-science-pack", "logistic-science-pack", "chemical-science-pack", "utility-science-pack", "space-science-pack" } },
}
local STEPS = 5
local TOTAL_TIERS = #GROUPS * STEPS
local FIRST_MODIFIER, LAST_MODIFIER = 0.2, 1.0

local technologies = {}
local tier = 0
for group_index, group in ipairs(GROUPS) do
    for step = 1, STEPS do
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

        technologies[#technologies + 1] = {
            type = "technology",
            name = "diggy-dig-speed-" .. tier,
            localised_name = { "", { "technology-name.diggy-dig-speed" }, " " .. tier },
            localised_description = { "technology-description.diggy-dig-speed" },
            icons = {
                { icon = "__base__/graphics/technology/steel-axe.png", icon_size = 256 },
            },
            effects = {
                { type = "character-mining-speed", modifier = math.floor(modifier * 100 + 0.5) / 100 },
            },
            prerequisites = prerequisites,
            unit = {
                count = math.floor(50 * group_index * step * 0.75),
                ingredients = ingredients,
                time = 15 + group_index * 15,
            },
            order = "diggy-" .. string.format("%02d", tier),
        }
    end
end

data:extend(technologies)
