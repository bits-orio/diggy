-- The rock cover: a tile-sized minable entity that autoplace packs solid
-- (spike-verified: anything larger leaves walkable gaps). Bots cannot
-- deconstruct it — digging is by hand or by damage.
local rock = table.deepcopy(data.raw["simple-entity"]["big-rock"])
rock.name = "diggy-rock"
rock.flags = { "placeable-neutral", "not-deconstructable" }
rock.collision_box = { { -0.45, -0.45 }, { 0.45, 0.45 } }
rock.selection_box = { { -0.5, -0.5 }, { 0.5, 0.5 } }
rock.minable = {
    mining_time = 1.5,
    results = { { type = "item", name = "stone", amount_min = 4, amount_max = 9 } },
}
rock.map_color = { r = 0.20, g = 0.16, b = 0.13 }
rock.max_health = 500
rock.dying_explosion = "rock-damaged-explosion"

-- Big-rock sprites are drawn for a ~2-tile entity; halve them to fit one tile.
-- (Proper cave-wall art is a later polish pass — see docs/BACKLOG.md.)
for _, variation in pairs(rock.pictures) do
    local sprites = variation.layers or { variation }
    for _, sprite in pairs(sprites) do
        sprite.scale = (sprite.scale or 1) * 0.5
        if sprite.shift then
            local sx = sprite.shift[1] or sprite.shift.x or 0
            local sy = sprite.shift[2] or sprite.shift.y or 0
            sprite.shift = { sx * 0.5, sy * 0.5 }
        end
    end
end

data:extend({ rock })
