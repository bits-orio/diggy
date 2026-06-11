-- Dig-speed progression: 18 manual-mining-speed technologies in six groups of
-- three, each group gated by the next science pack. Force-level, so under MTS
-- each team researches its own digging speed.
local GROUPS = {
    { gate = "steel-axe", modifier = 0.20, packs = { "automation-science-pack" } },
    { gate = "logistic-science-pack", modifier = 0.25, packs = { "automation-science-pack", "logistic-science-pack" } },
    { gate = "chemical-science-pack", modifier = 0.30, packs = { "automation-science-pack", "logistic-science-pack", "chemical-science-pack" } },
    { gate = "production-science-pack", modifier = 0.35, packs = { "automation-science-pack", "logistic-science-pack", "chemical-science-pack", "production-science-pack" } },
    { gate = "utility-science-pack", modifier = 0.40, packs = { "automation-science-pack", "logistic-science-pack", "chemical-science-pack", "utility-science-pack" } },
    { gate = "space-science-pack", modifier = 0.50, packs = { "automation-science-pack", "logistic-science-pack", "chemical-science-pack", "utility-science-pack", "space-science-pack" } },
}

local technologies = {}
local tier = 0
for group_index, group in ipairs(GROUPS) do
    for step = 1, 3 do
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

        technologies[#technologies + 1] = {
            type = "technology",
            name = "diggy-dig-speed-" .. tier,
            localised_name = { "", { "technology-name.diggy-dig-speed" }, " " .. tier },
            localised_description = { "technology-description.diggy-dig-speed" },
            icons = {
                { icon = "__base__/graphics/technology/steel-axe.png", icon_size = 256 },
            },
            effects = {
                { type = "character-mining-speed", modifier = group.modifier },
            },
            prerequisites = prerequisites,
            unit = {
                count = 50 * group_index * step,
                ingredients = ingredients,
                time = 15 + group_index * 15,
            },
            order = "diggy-" .. string.format("%02d", tier),
        }
    end
end

data:extend(technologies)
