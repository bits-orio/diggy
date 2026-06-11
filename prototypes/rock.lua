-- The frontier-wall rock: a tile-sized minable entity spawned at runtime
-- wherever the wall advances (ADR 0007). Bots cannot deconstruct it —
-- digging is by hand or by damage.
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

-- Mixed big/huge rock sprites at natural size: collision stays one tile so
-- autoplace packs a rock per tile, while the oversized sprites overlap their
-- neighbours and hide the terrain and ore beneath until dug (the Mountain
-- Fortress trick). Selection stays a precise single tile.
local variations = {}
for _, source in pairs({ "big-rock", "huge-rock" }) do
    local pictures = data.raw["simple-entity"][source].pictures
    for _, picture in pairs(table.deepcopy(pictures)) do
        variations[#variations + 1] = picture
    end
end
rock.pictures = variations

data:extend({ rock })
