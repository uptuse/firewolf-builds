// terrain_splatmap_web.wgsl — Array-texture splatmap terrain shader (WASM/WebGPU)
//
// Uses a single texture_2d_array with 4 layers (rock=0, grass=1, sand=2, snow=3)
// blended by slope+altitude. Simple N·L lighting.
//
// Uses textureSampleLevel (explicit LOD=0) instead of textureSample because
// implicit LOD calculation for texture_2d_array is unreliable on BrowserWebGPU.
//
// Based on Bevy 0.14's official array_texture.wgsl pattern.
// Uses hardcoded @group(2) for material bindings (Bevy 0.14 standard).

#import bevy_pbr::forward_io::VertexOutput

// ── Material bindings (group 2 = Bevy 0.14 material bind group) ─────────────

struct SplatmapUniforms {
    sun_direction: vec4<f32>,
    max_height: f32,
    _pad1: f32,
    _pad2: f32,
    _pad3: f32,
}

@group(2) @binding(0)
var<uniform> splat_uniforms: SplatmapUniforms;

@group(2) @binding(1)
var terrain_array_tex: texture_2d_array<f32>;

@group(2) @binding(2)
var terrain_array_sampler: sampler;

// ── Splat weight computation ────────────────────────────────────────────────

fn compute_splat_weights(normal_y: f32, world_y: f32, max_h: f32) -> vec4<f32> {
    let abs_ny = abs(normal_y);

    let is_mirror = step(max_h * 1.2, world_y);
    let lower_alt = world_y / max(max_h, 0.001);
    let mirror_alt = (2.0 * max_h - world_y) / max(max_h, 0.001);
    let altitude_frac = mix(lower_alt, mirror_alt, is_mirror);

    let FLAT_THRESHOLD:  f32 = 0.85;
    let STEEP_THRESHOLD: f32 = 0.60;
    let ALT_SNOW_START:  f32 = 0.55;
    let ALT_GRASS_END:   f32 = 0.40;
    let BLEND_W:         f32 = 0.08;

    let flat_mask = smoothstep(FLAT_THRESHOLD - BLEND_W, FLAT_THRESHOLD + BLEND_W, abs_ny);
    let steep_mask = 1.0 - smoothstep(STEEP_THRESHOLD - BLEND_W, STEEP_THRESHOLD + BLEND_W, abs_ny);
    let mid_mask = 1.0 - flat_mask - steep_mask;

    let snow_alt_mask = smoothstep(ALT_SNOW_START - BLEND_W, ALT_SNOW_START + BLEND_W, altitude_frac);
    let grass_alt_mask = 1.0 - smoothstep(ALT_GRASS_END - BLEND_W, ALT_GRASS_END + BLEND_W, altitude_frac);

    let rock_weight = steep_mask;
    let grass_weight = flat_mask * grass_alt_mask;
    let snow_weight = flat_mask * snow_alt_mask;
    let sand_weight = mid_mask + flat_mask * (1.0 - grass_alt_mask) * (1.0 - snow_alt_mask);

    let weights = vec4<f32>(rock_weight, grass_weight, sand_weight, snow_weight);
    let total = weights.x + weights.y + weights.z + weights.w;
    return weights / max(total, 0.001);
}

// ── Fragment stage ──────────────────────────────────────────────────────────

@fragment
fn fragment(
    mesh: VertexOutput,
) -> @location(0) vec4<f32> {
    // World-space tiling UV (1 tile = 8m)
    let tile_scale = 0.125;
    let tex_uv = mesh.world_position.xz * tile_scale;

    // Compute splat weights from world normal and position
    let normal = normalize(mesh.world_normal);
    let w = compute_splat_weights(
        normal.y,
        mesh.world_position.y,
        splat_uniforms.max_height,
    );

    // Sample each layer of the array texture using explicit LOD 0
    // (textureSample with implicit LOD is unreliable for array textures on BrowserWebGPU)
    let rock_color  = textureSampleLevel(terrain_array_tex, terrain_array_sampler, tex_uv, 0, 0.0);
    let grass_color = textureSampleLevel(terrain_array_tex, terrain_array_sampler, tex_uv, 1, 0.0);
    let sand_color  = textureSampleLevel(terrain_array_tex, terrain_array_sampler, tex_uv, 2, 0.0);
    let snow_color  = textureSampleLevel(terrain_array_tex, terrain_array_sampler, tex_uv, 3, 0.0);

    // Blend by splat weights
    let blended = rock_color  * w.x
                + grass_color * w.y
                + sand_color  * w.z
                + snow_color  * w.w;

    // Simple directional lighting (N·L)
    let sun_dir = normalize(vec3<f32>(0.4, 0.8, 0.3));
    let ndotl = max(dot(normal, sun_dir), 0.0);
    let ambient = 0.3;
    let lit = blended.rgb * (ambient + (1.0 - ambient) * ndotl);

    return vec4<f32>(lit, 1.0);
}
