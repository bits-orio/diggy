-- Spike runtime tests. Run automatically shortly after map creation; results go
-- to the log prefixed with [SPIKE] for grepping.
local function out(msg)
  print("[SPIKE] " .. msg)
  log("[SPIKE] " .. msg)
end

local function run_tests()
  local s = game.surfaces["nauvis"]

  -- T1: rock coverage density near spawn ring (24..56 box, excluding carve-out)
  local rocks = s.count_entities_filtered { name = "diggy-rock", area = { { 24, 24 }, { 56, 56 } } }
  out(("T1 rock density: %d diggy-rocks in 32x32 area (%.2f per tile)"):format(rocks, rocks / 1024))

  -- T1b: walkability — every tile in the test box should intersect a rock's
  -- collision box (modulo pockets). Count uncovered tiles.
  local uncovered = 0
  for x = 24, 55 do
    for y = 24, 55 do
      if s.count_entities_filtered { name = "diggy-rock", area = { { x + 0.1, y + 0.1 }, { x + 0.9, y + 0.9 } } } == 0 then
        uncovered = uncovered + 1
      end
    end
  end
  out(("T1b coverage: %d/1024 tiles have no rock bbox overlap (pocket tiles ok, corridors bad)"):format(uncovered))

  -- T2: carve-out is rock-free (circle, strictly inside the distance-12 gate)
  local carve = s.count_entities_filtered { name = "diggy-rock", position = { 0, 0 }, radius = 11 }
  out(("T2 carve-out: %d rocks within radius 11 of origin (want 0)"):format(carve))

  -- T3: not-deconstructable vs minable
  local rock = s.find_entities_filtered { name = "diggy-rock", limit = 1 }[1]
  if rock then
    local ok = rock.order_deconstruction(game.forces.player)
    out(("T3a order_deconstruction returned %s, to_be_deconstructed=%s (want false/false)"):format(tostring(ok), tostring(rock.to_be_deconstructed(game.forces.player))))
    out(("T3b minable=%s, mineable_properties.minable=%s (want true/true)"):format(tostring(rock.minable), tostring(rock.prototype.mineable_properties.minable)))
    local mined = rock.mine { ignore_minable = false, raise_destroyed = true }
    out(("T3c entity.mine() returned %s (want true => hand-mining path works)"):format(tostring(mined)))
  else
    out("T3 FAIL: no diggy-rock found")
  end

  -- T4: crushed remains — character-corpse with inventory, rock spawned on top
  local pos = { 100.5, 100.5 }
  local corpse = s.create_entity { name = "character-corpse", position = pos, inventory_size = 10 }
  if corpse then
    local inv = corpse.get_inventory(defines.inventory.character_corpse)
    local inserted = inv and inv.insert { name = "iron-plate", count = 50 } or 0
    local rock_on_top = s.create_entity { name = "diggy-rock", position = pos }
    out(("T4a corpse created, inserted=%d, rock-on-top=%s (want 50/true)"):format(inserted, tostring(rock_on_top ~= nil)))
    if rock_on_top then
      rock_on_top.destroy()
      out(("T4b after rock removed: corpse valid=%s, still holds=%d iron-plate (want true/50)"):format(tostring(corpse.valid), corpse.valid and corpse.get_inventory(defines.inventory.character_corpse).get_item_count("iron-plate") or -1))
    end
  else
    out("T4 FAIL: character-corpse creation returned nil")
  end

  -- T5: ore under rocks — sample tiles that hold both
  local ores = s.find_entities_filtered { name = "iron-ore", limit = 200 }
  local both = 0
  for _, o in pairs(ores) do
    if s.count_entities_filtered { name = "diggy-rock", position = o.position, radius = 1.5 } > 0 then both = both + 1 end
  end
  out(("T5 ore-under-rock: %d/%d sampled iron-ore tiles have a rock within 1.5 tiles"):format(both, #ores))

  -- T6: nests confined to pockets (spawners exist + no rock within 2 tiles)
  local spawners = s.find_entities_filtered { type = "unit-spawner", limit = 20 }
  local sealed = 0
  for _, sp in pairs(spawners) do
    if s.count_entities_filtered { name = "diggy-rock", position = sp.position, radius = 6 } > 0 then sealed = sealed + 1 end
  end
  out(("T6 pockets: %d spawners found in generated area; %d have rock cover within 6 tiles (sealed)"):format(#spawners, sealed))

  -- T7: chunk generation performance at scale
  local prof = game.create_profiler()
  s.request_to_generate_chunks({ 0, 0 }, 16) -- 33x33 chunks ≈ 1089 chunks
  s.force_generate_chunk_requests()
  prof.stop()
  log { "", "[SPIKE] T7 generate ~1089 chunks: ", prof }
  local total_rocks = s.count_entities_filtered { name = "diggy-rock" }
  out(("T7 world now holds %d diggy-rock entities"):format(total_rocks))

  out("ALL TESTS DONE")
end

script.on_event(defines.events.on_tick, function(e)
  if e.tick >= 5 then
    script.on_event(defines.events.on_tick, nil)
    local ok, err = pcall(run_tests)
    if not ok then out("ERROR: " .. tostring(err)) end
  end
end)
