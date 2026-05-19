# CTF-Glacier

**CTF-Glacier** is a vertical ice biome map designed for high-speed, high-risk flag runs.

## Player Intent
The core intent of Glacier is verticality combined with low-friction movement. The glacier surface heavily reduces ski-friction (foreshadowing the NEW-50 friction tuning), which makes mid-flag-grab ski-strafes incredibly fast but lethal if miscalculated. The map features a central 50-meter ice-tower that provides a commanding high-ground sniper position. Crucially, this high ground is contestable: both teams can ski up the lee side of the tower using strategically placed ramps.

## Route Variants
Glacier offers two primary route variants for attackers and flag carriers:
1. **Low River Basin:** A high-speed, low-friction run across the frozen river connecting the two cliff bases. It offers heavy cover from ice boulders and shards but leaves players vulnerable to plunging fire from the tower.
2. **Ice-Tower Flank:** A vertical route that uses the lee ramps to launch onto the central tower. This route is slower but secures the high ground, allowing attackers to clear out snipers before diving into the enemy cliff base.

## Assets and Dependencies
- Relies on the existing `MapManifest` schema and post-NEW-10 tier vocabulary.
- Uses the `splatmap` layer index for ice (no new textures required).
- Reuses existing placeholder assets (`base_core`, `flag_stand`, `spawn_pad`, `tower_a`, `ski_ramp_a`, `ski_ramp_b`, `capture_zone`, etc.) from the map assets catalog.
