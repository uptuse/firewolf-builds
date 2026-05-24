// terrain_splatmap_web.wgsl — Array-texture splatmap terrain shader (WASM/WebGPU)
//
// Uses a single texture_2d_array with 4 layers (rock=0, grass=1, sand=2, snow=3)
// blended by slope+altitude. Integrates with Bevy's PBR pipeline for proper lighting.
//
// Based directly on Bevy 0.14's official array_texture.wgsl example.
// Uses hardcoded @group(2) for material bindings (Bevy 0.14 standard).

#import bevy_pbr::{
    forward_io::VertexOutput,
    mesh_view_bindings::view,
    pbr_types::{STANDARD_MATERIAL_FLAGS_DOUBLE_SIDED_BIT, PbrInput, pbr_input_new},
    pbr_functions as fns,
}
#import bevy_core_pipeline::tonemapping::tone_mapping

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

/// Compute RGBA splat weights from world-space normal.y and altitude.
/// Returns vec4: x=rock, y=grass, z=sand, w=snow
fn compute_splat_weights(normal_y: f32, world_y: f32, max_h: f32) -> vec4<f32> {
    let abs_ny = abs(normal_y);

    // Mirror terrain detection and altitude computation
    let is_mirror = step(max_h * 1.2, world_y);
    let lower_alt = world_y / max(max_h, 0.001);
    let mirror_alt = (2.0 * max_h - world_y) / max(max_h, 0.001);
    let altitude_frac = mix(lower_alt, mirror_alt, is_mirror);

    let FLAT_THRESHOLD:  f32 = 0.85;
    let STEEP_THRESHOLD: f32 = 0.60;
    let ALT_SNOW_START:  f32 = 0.55;
    let ALT_GRASS_END:   f32 = 0.40;
    let BLEND_W:         f32 = 0.08;

    // Slope masks
    let flat_mask = smoothstep(FLAT_THRESHOLD - BLEND_W, FLAT_THRESHOLD + BLEND_W, abs_ny);
    let steep_mask = 1.0 - smoothstep(STEEP_THRESHOLD - BLEND_W, STEEP_THRESHOLD + BLEND_W, abs_ny);
    let mid_mask = 1.0 - flat_mask - steep_mask;

    // Altitude masks
    let snow_alt_mask = smoothstep(ALT_SNOW_START - BLEND_W, ALT_SNOW_START + BLEND_W, altitude_frac);
    let grass_alt_mask = 1.0 - smoothstep(ALT_GRASS_END - BLEND_W, ALT_GRASS_END + BLEND_W, altitude_frac);

    // Biome weights
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
    @builtin(front_facing) is_front: bool,
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

    // Sample each layer of the array texture
    // Layer 0=rock, 1=grass, 2=sand, 3=snow
    let rock_color  = textureSample(terrain_array_tex, terrain_array_sampler, tex_uv, 0);
    let grass_color = textureSample(terrain_array_tex, terrain_array_sampler, tex_uv, 1);
    let sand_color  = textureSample(terrain_array_tex, terrain_array_sampler, tex_uv, 2);
    let snow_color  = textureSample(terrain_array_tex, terrain_array_sampler, tex_uv, 3);

    // Blend by splat weights
    let blended = rock_color  * w.x
                + grass_color * w.y
                + sand_color  * w.z
                + snow_color  * w.w;

    // ── PBR lighting integration (matches Bevy 0.14 array_texture.wgsl) ─────
    var pbr_input: PbrInput = pbr_input_new();
    pbr_input.material.base_color = blended;

    let double_sided = (pbr_input.material.flags & STANDARD_MATERIAL_FLAGS_DOUBLE_SIDED_BIT) != 0u;

    pbr_input.frag_coord = mesh.position;
    pbr_input.world_position = mesh.world_position;
    pbr_input.world_normal = fns::prepare_world_normal(
        mesh.world_normal,
        double_sided,
        is_front,
    );

    pbr_input.is_orthographic = view.clip_from_view[3].w == 1.0;
    pbr_input.N = normalize(pbr_input.world_normal);
    pbr_input.V = fns::calculate_view(mesh.world_position, pbr_input.is_orthographic);

    return tone_mapping(fns::apply_pbr_lighting(pbr_input), view.color_grading);
}
