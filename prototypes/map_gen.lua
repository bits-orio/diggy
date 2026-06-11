-- Nauvis map-gen takeover (ADR 0007): the engine generates bare flat land and
-- nothing else — every chunk is converted to out-of-map void at runtime
-- (scripts/world.lua), and the world is built by digging. No autoplaced
-- entities, no cliffs, no water; pools and walls materialize from runtime noise.
local nauvis = data.raw.planet["nauvis"]
local mgs = nauvis.map_gen_settings

mgs.autoplace_settings = mgs.autoplace_settings or {}
mgs.autoplace_settings.entity = { settings = {}, treat_missing_as_default = false }

mgs.property_expression_names = mgs.property_expression_names or {}
mgs.property_expression_names.elevation = 100
mgs.cliff_settings = { name = "cliff", cliff_elevation_0 = 1024, cliff_elevation_interval = 10, richness = 0 }
