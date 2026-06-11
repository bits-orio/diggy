# Spike results — pre-generated world behind rock cover (ADR 0001)

Run 2026-06-10 on Factorio 2.0.76 (headless, isolated `--mod-directory`). Spike mod preserved at [spike/diggy-spike/](../spike/diggy-spike/). Verdict: **architecture validated — ADR 0001 accepted.**

## How it was run

```sh
factorio --mod-directory /tmp/diggy-spike-mods --create /tmp/diggy-spike.zip
factorio --mod-directory /tmp/diggy-spike-mods --server-settings <auto_pause:false> --start-server /tmp/diggy-spike.zip
factorio --mod-directory /tmp/diggy-spike-mods --generate-map-preview /tmp/diggy-preview.png
```

Tests live in the spike mod's `control.lua` and self-run at tick 5, logging `[SPIKE]` lines.

## Findings

| # | Question | Result |
|---|----------|--------|
| T1 | Solid rock-cover autoplace? | **Yes**, with a 1×1 tile-sized rock (collision box ±0.45): 0.98 rocks/tile, 98% of tiles bbox-covered (the rest are mini-pockets, not corridors). A huge-rock-sized prototype packs at only 0.06/tile — gaps are walkable. **The rock-cover prototype must be tile-sized.** |
| T2 | Spawn carve-out via `distance` expression? | **Yes.** `(distance > 12) * 2 - 1` leaves radius-11 perfectly clean. Comparison operators, `basis_noise{}`, and arithmetic all work in 2.0 string expressions. |
| T3 | `not-deconstructable` flag + hand-minable? | **Yes.** `order_deconstruction()` returns false (bots locked out); `minable`, `mineable_properties.minable`, and `entity.mine()` all true. The no-bot-digging rule is one prototype flag. |
| T4 | Crushed remains (corpse under rock)? | **Yes.** `character-corpse` accepts `inventory_size` at creation, holds items, does not collide with a rock spawned on the same tile, and survives intact after the rock is removed. The collapse design works with the vanilla corpse type — a custom prototype is optional polish. |
| T5 | Ore autoplaces beneath rock cover? | **Yes.** Resource and object collision layers don't conflict; tendril expressions generate under solid rock. |
| T6 | Nests pre-spawn inside sealed pockets? | **Yes.** Spawners/worms confined to pocket noise via autoplace; majority verified sealed by surrounding rock. Pocket size/threshold needs design tuning (`input_scale` 1/24, suppress ≥0.65, nests ≥0.72 was a reasonable starting point). |
| T7 | Generation performance at scale? | **2.0 s for 1,089 chunks producing ~894k rock entities** (~820/chunk). Inactive simple-entities don't tick. Save size will be the cost to watch, not UPS. |
| T8 | Map preview / ore spoilers? | **No spoilers.** Rock `map_color` renders over resources — ore is invisible under rock on the preview, exposed only in pockets. Map reads as a solid dark mass with pocket voids; `map_color` is ours to darken. |

## Caveats / still open

- **In-game minimap & charting**: preview rendering strongly implies the in-game chart behaves the same (entities draw over resources, as with ore under forests), but confirm during the first real playtest with a graphical client.
- **In-world look of 1×1 rocks**: big-rock sprites on 1-tile entities will look cluttered/overlapping. Needs sprite variations/scaling polish — aesthetic work, not architecture risk.
- **MTS team variants**: not exercised in this spike (no MTS in the isolated env). High confidence by construction — data-stage terrain survives both clone-mirror (entities + tiles are cloned) and seed-pinned native generation — verify during MTS integration phase.
- **Mid-save install guard**: pure runtime logic (detect generated nauvis chunks without Diggy state in `on_configuration_changed`, warn and halt) — designed, no engine unknown, not spike-tested.

## Spike artifacts

- `spike/diggy-spike/` — throwaway mod (data.lua: rock prototype + nauvis map-gen takeover; control.lua: self-running tests). Not shipped; kept as reference for the real implementation.
