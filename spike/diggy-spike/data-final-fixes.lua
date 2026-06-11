-- Take over nauvis map generation: our entities must be opted into the planet's
-- autoplace settings, and competing scenery/cliffs/trees removed.
local nauvis = data.raw.planet["nauvis"]
local mgs = nauvis.map_gen_settings

mgs.autoplace_settings = mgs.autoplace_settings or {}
local ent = mgs.autoplace_settings.entity or { settings = {} }
ent.settings = ent.settings or {}
ent.settings["diggy-rock"] = {}
ent.settings["iron-ore"] = {}
ent.settings["biter-spawner"] = {}
ent.settings["spitter-spawner"] = {}
ent.settings["small-worm-turret"] = {}
ent.settings["medium-worm-turret"] = {}
-- Drop everything else (trees, vanilla rocks, other ores, fish) from generation.
ent.treat_missing_as_default = false
mgs.autoplace_settings.entity = ent

-- Flatten water: keep land everywhere (water pockets are a later design pass).
mgs.property_expression_names = mgs.property_expression_names or {}
mgs.property_expression_names.elevation = 100

-- No cliffs.
mgs.cliff_settings = { name = "cliff", cliff_elevation_0 = 1024, cliff_elevation_interval = 10, richness = 0 }
