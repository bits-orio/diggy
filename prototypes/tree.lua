-- Tree cover: tiny patches of dense trees mixed into the rock cover. Same
-- rules as rock (tile-sized, bot-proof, hides terrain, digging it counts) but
-- quicker to mine — and flammable, which makes fire an aggressive dig tool.
local tree = table.deepcopy(data.raw.tree["tree-02"])
tree.name = "diggy-tree"
tree.flags = { "placeable-neutral", "not-deconstructable", "breaths-air" }
tree.collision_box = { { -0.49, -0.49 }, { 0.49, 0.49 } }
tree.selection_box = { { -0.5, -0.5 }, { 0.5, 0.5 } }
tree.minable = {
    mining_time = 0.5,
    results = { { type = "item", name = "wood", amount_min = 2, amount_max = 4 } },
}
tree.map_color = { r = 0.13, g = 0.22, b = 0.10 }
tree.autoplace = nil -- set in map_gen.lua

data:extend({ tree })
