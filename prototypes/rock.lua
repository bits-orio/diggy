-- The frontier-wall rock: a tile-sized minable entity spawned at runtime
-- wherever the wall advances (ADR 0007). Bots cannot deconstruct it —
-- digging is by hand or by damage.
local rock = table.deepcopy(data.raw["simple-entity"]["big-rock"])
rock.name = "diggy-rock"
rock.flags = { "placeable-neutral", "not-deconstructable" }
-- Full-tile hitbox: the wall is script-placed (no autoplace packing to
-- appease anymore), so the box covers exactly the tile the rock occupies.
rock.collision_box = { { -0.49, -0.49 }, { 0.49, 0.49 } }
rock.selection_box = { { -0.5, -0.5 }, { 0.5, 0.5 } }
rock.minable = {
    mining_time = 1.5,
    results = { { type = "item", name = "stone", amount_min = 4, amount_max = 9 } },
}
rock.map_color = { r = 0.20, g = 0.16, b = 0.13 }
rock.max_health = 500
rock.dying_explosion = "rock-damaged-explosion"

-- Mixed big/huge rock sprites, scaled to ~1.5 tiles so the visible rock
-- roughly matches its full-tile hitbox (the wall is a contiguous line of
-- per-tile rocks, so moderate overlap still reads as solid mass).
local variations = {}
for _, source in pairs({ "big-rock", "huge-rock" }) do
    local pictures = data.raw["simple-entity"][source].pictures
    for _, picture in pairs(table.deepcopy(pictures)) do
        local sprites = picture.layers or { picture }
        for _, sprite in pairs(sprites) do
            sprite.scale = (sprite.scale or 1) * 0.7
            if sprite.shift then
                local sx = sprite.shift[1] or sprite.shift.x or 0
                local sy = sprite.shift[2] or sprite.shift.y or 0
                sprite.shift = { sx * 0.7, sy * 0.7 }
            end
        end
        variations[#variations + 1] = picture
    end
end
rock.pictures = variations

-- Collapse rubble: identical wall-grade cover, but a DISTINCT prototype so
-- the dig pipeline can tell re-digs from first digs. Mining rubble must
-- never re-roll the tile's seed-keyed outcomes (veins, spawns, caverns,
-- treasure) — those fired when the tile was first opened.
local rubble = table.deepcopy(rock)
rubble.name = "diggy-rubble"
rubble.map_color = { r = 0.16, g = 0.13, b = 0.11 }
rubble.minable = {
    mining_time = 1.0,
    results = { { type = "item", name = "stone", amount_min = 2, amount_max = 5 } },
}

data:extend({ rock, rubble })
