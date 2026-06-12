-- Admin test kit (/diggy-kit): everything needed to playtest the dig/collapse
-- loop fast — 4x manual mining, a stack of pillars, and MK2 armor with
-- fusion power, shields, lasers, roboports, and a bot swarm.
local admin_kit = {}

-- { name, count }; fills the MK2 grid exactly (100/100 slots).
local EQUIPMENT = {
    { "fission-reactor-equipment", 2 }, -- base 2.0 name for the portable reactor
    { "personal-roboport-mk2-equipment", 2 },
    { "exoskeleton-equipment", 2 },
    { "battery-mk2-equipment", 2 },
    { "energy-shield-mk2-equipment", 2 },
    { "personal-laser-defense-equipment", 8 },
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
        for _, spec in pairs(EQUIPMENT) do
            for _ = 1, spec[2] do
                local eq = armor.grid.put { name = spec[1] }
                -- Arrive charged: full energy buffers (batteries included)
                -- and shields, no waiting on the reactors.
                if eq then
                    eq.energy = eq.max_energy
                    if eq.max_shield > 0 then
                        eq.shield = eq.max_shield
                    end
                end
            end
        end
    end

    player.insert { name = "stone-wall", count = 400 }
    player.insert { name = "construction-robot", count = 50 }
    player.print({ "diggy.kit-given" })
end

return admin_kit
