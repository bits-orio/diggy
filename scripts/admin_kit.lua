-- Admin test kit (/diggy-kit): everything needed to playtest the dig/collapse
-- loop fast — 4x manual mining, a stack of pillars, and MK2 armor with
-- fusion power, roboports, and a bot swarm.
local admin_kit = {}

local EQUIPMENT = {
    "fission-reactor-equipment", -- base 2.0 name for the portable reactor
    "fission-reactor-equipment",
    "personal-roboport-mk2-equipment",
    "personal-roboport-mk2-equipment",
    "exoskeleton-equipment",
    "exoskeleton-equipment",
    "battery-mk2-equipment",
    "battery-mk2-equipment",
}

function admin_kit.give(player)
    if not player.character then
        player.print({ "diggy.kit-needs-character" })
        return
    end

    player.character_mining_speed_modifier = 4.0

    local armor_inv = player.get_inventory(defines.inventory.character_armor)
    local armor
    if armor_inv and armor_inv.is_empty() then
        armor_inv.insert("power-armor-mk2")
        armor = armor_inv[1]
    else
        player.print({ "diggy.kit-armor-skipped" })
    end
    if armor and armor.valid_for_read and armor.grid then
        for _, name in pairs(EQUIPMENT) do
            armor.grid.put { name = name }
        end
    end

    player.insert { name = "stone-wall", count = 400 }
    player.insert { name = "construction-robot", count = 50 }
    player.print({ "diggy.kit-given" })
end

return admin_kit
