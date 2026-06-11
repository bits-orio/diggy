-- Deterministic position hashing — the only randomness source for dig
-- outcomes (ADR 0005). Every roll derives from (map seed, tile, stream), so
-- MTS teams digging the same tile get identical results. Streams keep
-- independent decisions (spawn? type? count?) uncorrelated at the same tile.
--
-- Multiplies are done in 16-bit halves: a naive 32-bit multiply overflows
-- double precision (2^53) and quantizes small values out of existence.
local band, bxor, rshift = bit32.band, bit32.bxor, bit32.rshift

local hash = {}

local function mulmod32(a, b)
    local lo = band(a, 0xffff)
    local hi = rshift(a, 16)
    return (band(hi * b, 0xffff) * 65536 + lo * b) % 4294967296
end

-- [0,1) for (seed, tile x, tile y, stream id).
function hash.roll(seed, x, y, stream)
    local h = (x * 374761393 + y * 668265263 + seed * 97 + stream * 2246822519) % 4294967296
    h = bxor(h, rshift(h, 16))
    h = mulmod32(h, 0x85ebca6b)
    h = bxor(h, rshift(h, 13))
    h = mulmod32(h, 0xc2b2ae35)
    h = bxor(h, rshift(h, 16))
    return h / 4294967296
end

-- Integer in [min, max] for the same inputs.
function hash.range(seed, x, y, stream, min, max)
    return min + math.floor(hash.roll(seed, x, y, stream) * (max - min + 1))
end

return hash
