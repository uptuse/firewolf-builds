# Terrain Textures — PBR Assets (ambientCG)

Real PBR terrain textures sourced from [ambientCG](https://ambientcg.com/) (CC0 Public Domain).

## Sources
| Biome | Asset ID | Description |
|-------|----------|-------------|
| Rock  | Rock030  | Grey-brown cracked rock face |
| Grass | Grass004 | Dense green grass with leaf detail |
| Sand  | Ground026| Sandy ground with pebbles |
| Snow  | Snow003  | Fresh powder snow |

## Layout
```
assets/textures/terrain/
  rock/
    albedo.png     — Rock030 Color (1K downsampled to 256x256)
    normal.png     — Rock030 NormalGL
    roughness.png  — Rock030 Roughness
  grass/
    albedo.png     — Grass004 Color
    normal.png     — Grass004 NormalGL
    roughness.png  — Grass004 Roughness
  sand/
    albedo.png     — Ground026 Color
    normal.png     — Ground026 NormalGL
    roughness.png  — Ground026 Roughness
  snow/
    albedo.png     — Snow003 Color
    normal.png     — Snow003 NormalGL
    roughness.png  — Snow003 Roughness
```

## Specification
- Resolution: 256 × 256 pixels
- Format: PNG, RGB, no alpha
- License: CC0 (Public Domain)
- Source: https://ambientcg.com/

## Notes
- These textures are used on the native build only (12 texture slots).
- On WASM/WebGPU, the terrain shader is fully procedural (no textures loaded).
- The splatmap shader blends biomes by slope and altitude.
