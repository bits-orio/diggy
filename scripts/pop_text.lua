-- Animated world-anchored pop texts, in the spirit of MTS's pop_text "rip"
-- preset: explosive overshoot pop, then the text rises while wobbling
-- side-to-side and fades out. Entries animate per tick (early-out when idle).
local pop_text = {}

local sin, min = math.sin, math.min

local function ease_out_cubic(t)
    local u = 1 - t
    return 1 - u * u * u
end

function pop_text.on_init()
    storage.pop_texts = storage.pop_texts or {}
end

function pop_text.spawn(surface, position, text, color, force)
    storage.pop_texts = storage.pop_texts or {}
    local obj = rendering.draw_text {
        text = text,
        surface = surface,
        target = position,
        color = color,
        scale = 0.1,
        font = "default-game",
        alignment = "center",
        scale_with_zoom = true,
        forces = force and { force } or nil,
    }
    if not obj then return end
    storage.pop_texts[#storage.pop_texts + 1] = {
        text_id = obj.id,
        created_tick = game.tick,
        lifetime = 55,
        x = position.x or position[1],
        y = position.y or position[2],
        base_scale = 2.2,
        r = color.r,
        g = color.g,
        b = color.b,
    }
end

function pop_text.tick(now)
    local entries = storage.pop_texts
    if not entries or #entries == 0 then return end

    local write = 1
    for read = 1, #entries do
        local e = entries[read]
        local age = now - e.created_tick
        local progress = min(1, age / e.lifetime)
        local obj = rendering.get_object_by_id(e.text_id)
        if obj and progress < 1 then
            -- Overshoot pop, then settle.
            local mul
            if age < 4 then
                mul = 3.2 * (age / 4)
            elseif age < 10 then
                mul = 3.2 - 2.0 * ((age - 4) / 6)
            else
                mul = 1.2
            end
            local dx = sin(age * 0.45) * 0.35 -- the wobble
            local dy = -3.5 * ease_out_cubic(progress) -- the rise
            local alpha = progress < 0.6 and 1 or (1 - (progress - 0.6) / 0.4)
            obj.target = { x = e.x + dx, y = e.y + dy }
            obj.scale = e.base_scale * mul
            obj.color = { r = e.r, g = e.g, b = e.b, a = alpha }
            entries[write] = e
            write = write + 1
        elseif obj then
            obj.destroy()
        end
    end
    for i = #entries, write, -1 do
        entries[i] = nil
    end
end

return pop_text
