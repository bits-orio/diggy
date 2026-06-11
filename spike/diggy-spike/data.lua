-- Spike: rock cover entity + nauvis map-gen takeover.
-- Questions under test (ADR 0001):
--   1. Can a rock entity autoplace at full density over all terrain?
--   2. Can the spawn carve-out be a pure distance expression?
--   3. Can pockets (rock-free voids) come from noise, with nests confined to them?
--   4. Does "not-deconstructable" coexist with hand-minable?
--   5. Does ore autoplace beneath rocks?

local rock = table.deepcopy(data.raw["simple-entity"]["big-rock"])
rock.name = "diggy-rock"
rock.flags = { "placeable-neutral", "not-deconstructable" }
rock.minable = { mining_time = 2, results = { { type = "item", name = "stone", amount_min = 5, amount_max = 12 } } }
rock.map_color = { r = 0.35, g = 0.28, b = 0.22 }
-- Tile-sized so autoplace packs it solid: one rock per tile, gaps narrower than
-- the character's collision box.
rock.collision_box = { { -0.45, -0.45 }, { 0.45, 0.45 } }
rock.selection_box = { { -0.5, -0.5 }, { 0.5, 0.5 } }
-- Pocket noise: blobs where rock is suppressed. Same expression reused (negated)
-- to confine enemy bases to pockets.
local POCKET = "basis_noise{x = x, y = y, seed0 = map_seed, seed1 = 7700, input_scale = 1/24, output_scale = 1}"
rock.autoplace = {
  order = "a[diggy]-a[rock]",
  -- solid coverage, minus the spawn carve-out (distance < 12) and pockets
  probability_expression = "(distance > 12) * 2 - 1 - max(0, " .. POCKET .. " - 0.65) * 1000"
}

data:extend({ rock })

-- Crude ore tendrils via ridged noise, just to prove ore-under-rock + preview behavior.
local iron = data.raw.resource["iron-ore"]
iron.autoplace = {
  order = "b",
  probability_expression = "(max(0, abs(basis_noise{x = x, y = y, seed0 = map_seed, seed1 = 1100, input_scale = 1/40, output_scale = 1}) < 0.06) * (distance > 6)) * 2 - 1",
  richness_expression = "500 + distance * 2"
}

-- Confine enemy bases to pockets (test: do nests pre-spawn inside sealed pockets?)
for _, name in pairs({ "biter-spawner", "spitter-spawner", "small-worm-turret", "medium-worm-turret" }) do
  local proto = data.raw["unit-spawner"][name] or data.raw["turret"][name]
  if proto then
    proto.autoplace = {
      order = "c",
      probability_expression = "(max(0, " .. POCKET .. " - 0.72) * (distance > 40)) * 2 - 1"
    }
  end
end
