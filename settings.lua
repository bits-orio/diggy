data:extend({
    -- Startup: consumed at data stage by the nauvis map-gen takeover.
    {
        type = "int-setting",
        setting_type = "startup",
        name = "diggy-carve-out-radius",
        default_value = 12,
        minimum_value = 6,
        maximum_value = 40,
        order = "a",
    },
    -- Runtime: difficulty knobs, host-tunable mid-game.
    {
        type = "double-setting",
        setting_type = "runtime-global",
        name = "diggy-evolution-per-dig",
        default_value = 0.000002,
        minimum_value = 0,
        maximum_value = 0.001,
        order = "b-a",
    },
})
