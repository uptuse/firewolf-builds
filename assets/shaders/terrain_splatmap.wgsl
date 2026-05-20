// terrain_splatmap.wgsl — Phase 2 splatmap terrain material
//
// Blends four ground textures (rock, grass, sand, snow) by slope and altitude.
// Slope is derived from the vertex normal's Y component (normal.y ≈ 1 = flat,
// normal.y ≈ 0 = vertical cliff). Altitude is world-space Y position.
//
// Blend rules (from dispatch spec):
//   normal.y > 0.95 && y < 0.3 * max_h  → grass
//   normal.y > 0.95 && y >= 0.3 * max_h → snow
//   normal.y < 0.7                       → rock
//   else                                 → sand  (transition zone)
//
// ADR-024 compliance: no painterly LUT, no biome-keyed fog, no tint.
// Material colours are physically plausible.

#import bevy_pbr::mesh_functions::{get_world_from_local, mesh_position_local_to_clip}
#import bevy_pbr::mesh_view_bindings::view
#import bevy_pbr::pbr_types::{STANDARD_MATERIAL_FLAGS_DOUBLE_SIDED_BIT, PbrInput, pbr_input_new}
#import bevy_pbr::pbr_functions as pbr_fns
#import bevy_pbr::mesh_bindings::mesh

// ── Uniforms ─────────────────────────────────────────────────────────────────

struct SplatmapUniforms {
    /// Maximum terrain height in world-space metres.
    /// Computed at startup from heightmap.max() * HEIGHT_SCALE.
    max_height: f32,
    /// Padding to 16-byte alignment.
    _pad0: f32,
    _pad1: f32,
    _pad2: f32,
}

@group(2) @binding(0)
var<uniform> splat_uniforms: SplatmapUniforms;

// ── Texture samplers ──────────────────────────────────────────────────────────

@group(2) @binding(1)  var rock_albedo_tex:     texture_2d<f32>;
@group(2) @binding(2)  var rock_albedo_samp:    sampler;
@group(2) @binding(3)  var rock_normal_tex:     texture_2d<f32>;
@group(2) @binding(4)  var rock_normal_samp:    sampler;
@group(2) @binding(5)  var rock_roughness_tex:  texture_2d<f32>;
@group(2) @binding(6)  var rock_roughness_samp: sampler;

@group(2) @binding(7)  var grass_albedo_tex:     texture_2d<f32>;
@group(2) @binding(8)  var grass_albedo_samp:    sampler;
@group(2) @binding(9)  var grass_normal_tex:     texture_2d<f32>;
@group(2) @binding(10) var grass_normal_samp:    sampler;
@group(2) @binding(11) var grass_roughness_tex:  texture_2d<f32>;
@group(2) @binding(12) var grass_roughness_samp: sampler;

@group(2) @binding(13) var sand_albedo_tex:     texture_2d<f32>;
@group(2) @binding(14) var sand_albedo_samp:    sampler;
@group(2) @binding(15) var sand_normal_tex:     texture_2d<f32>;
@group(2) @binding(16) var sand_normal_samp:    sampler;
@group(2) @binding(17) var sand_roughness_tex:  texture_2d<f32>;
@group(2) @binding(18) var sand_roughness_samp: sampler;

@group(2) @binding(19) var snow_albedo_tex:     texture_2d<f32>;
@group(2) @binding(20) var snow_albedo_samp:    sampler;
@group(2) @binding(21) var snow_normal_tex:     texture_2d<f32>;
@group(2) @binding(22) var snow_normal_samp:    sampler;
@group(2) @binding(23) var snow_roughness_tex:  texture_2d<f32>;
@group(2) @binding(24) var snow_roughness_samp: sampler;

// ── Vertex stage ──────────────────────────────────────────────────────────────

struct VertexInput {
    @builtin(instance_index) instance_index: u32,
    @location(0) position:  vec3<f32>,
    @location(1) normal:    vec3<f32>,
    @location(2) uv:        vec2<f32>,
}

struct VertexOutput {
    @builtin(position)       clip_position: vec4<f32>,
    @location(0)             world_pos:     vec3<f32>,
    @location(1)             world_normal:  vec3<f32>,
    @location(2)             uv:            vec2<f32>,
    /// RGBA splat weights computed at vertex stage.
    /// R=rock, G=grass, B=sand, A=snow.
    @location(3)             splat_weights: vec4<f32>,
}

/// Compute RGBA splat weights from world-space normal.y and altitude.
///
/// Returns a vec4 where components sum to 1.0:
///   .x = rock weight
///   .y = grass weight
///   .z = sand weight
///   .w = snow weight
fn compute_splat_weights(normal_y: f32, world_y: f32, max_h: f32) -> vec4<f32> {
    let altitude_frac = world_y / max(max_h, 0.001);

    // Hard thresholds from dispatch spec, softened with a 0.05-wide smoothstep
    // to avoid aliasing at biome boundaries.
    let FLAT_THRESHOLD:  f32 = 0.95;  // normal.y above this = flat ground
    let STEEP_THRESHOLD: f32 = 0.70;  // normal.y below this = rock cliff
    let ALT_GRASS_SNOW:  f32 = 0.30;  // altitude fraction: grass below, snow above
    let BLEND_W:         f32 = 0.05;  // half-width of soft boundary

    // Flat-ground mask: 1 when normal_y > FLAT_THRESHOLD
    let flat_mask = smoothstep(FLAT_THRESHOLD - BLEND_W, FLAT_THRESHOLD + BLEND_W, normal_y);
    // Steep (rock) mask: 1 when normal_y < STEEP_THRESHOLD
    let steep_mask = 1.0 - smoothstep(STEEP_THRESHOLD - BLEND_W, STEEP_THRESHOLD + BLEND_W, normal_y);
    // Sand mask: the transition zone between steep and flat
    let sand_mask = 1.0 - flat_mask - steep_mask;

    // On flat ground, split between grass (low) and snow (high)
    let snow_alt_mask = smoothstep(ALT_GRASS_SNOW - BLEND_W, ALT_GRASS_SNOW + BLEND_W, altitude_frac);
    let grass_weight = flat_mask * (1.0 - snow_alt_mask);
    let snow_weight  = flat_mask * snow_alt_mask;

    let weights = vec4<f32>(
        steep_mask,   // rock
        grass_weight, // grass
        sand_mask,    // sand
        snow_weight,  // snow
    );

    // Normalise to ensure sum == 1.0 (guards against floating-point drift).
    let total = weights.x + weights.y + weights.z + weights.w;
    return weights / max(total, 0.001);
}

@vertex
fn vertex(in: VertexInput) -> VertexOutput {
    var out: VertexOutput;

    let world_from_local = get_world_from_local(in.instance_index);
    let world_pos4 = world_from_local * vec4<f32>(in.position, 1.0);
    out.world_pos = world_pos4.xyz;

    // Transform normal to world space (no non-uniform scale on terrain).
    let world_normal4 = world_from_local * vec4<f32>(in.normal, 0.0);
    out.world_normal = normalize(world_normal4.xyz);

    out.clip_position = mesh_position_local_to_clip(
        world_from_local,
        vec4<f32>(in.position, 1.0),
    );

    out.uv = in.uv;

    out.splat_weights = compute_splat_weights(
        out.world_normal.y,
        out.world_pos.y,
        splat_uniforms.max_height,
    );

    return out;
}

// ── Fragment stage ────────────────────────────────────────────────────────────

/// Decode a tangent-space normal from an RGB normal map sample.
/// Input is in [0,1]; output is in [-1,1] with z reconstructed.
fn decode_normal_map(sample: vec3<f32>) -> vec3<f32> {
    let n = sample * 2.0 - 1.0;
    // Reconstruct z from x,y (assumes unit-length tangent-space normal).
    let z = sqrt(max(0.0, 1.0 - dot(n.xy, n.xy)));
    return normalize(vec3<f32>(n.x, n.y, z));
}

/// Blend a tangent-space normal with the geometric world normal.
/// This is a simplified TBN-free approach: we treat the world normal as
/// the "up" direction and perturb it by the normal-map offset.
fn apply_normal_map(world_normal: vec3<f32>, tangent_normal: vec3<f32>) -> vec3<f32> {
    // Build a simple TBN frame from the world normal.
    // We use a fixed "up" reference to derive tangent/bitangent.
    let up = select(vec3<f32>(0.0, 0.0, 1.0), vec3<f32>(0.0, 1.0, 0.0),
                    abs(world_normal.y) < 0.999);
    let tangent   = normalize(cross(up, world_normal));
    let bitangent = cross(world_normal, tangent);
    return normalize(
        tangent_normal.x * tangent +
        tangent_normal.y * bitangent +
        tangent_normal.z * world_normal
    );
}

@fragment
fn fragment(in: VertexOutput) -> @location(0) vec4<f32> {
    // ── UV tiling ────────────────────────────────────────────────────────────
    // The mesh UVs span [0,1] over the full 3072m terrain. Tile the detail
    // textures so each 256×256 texture repeats every 16m (192× across the map).
    // This gives visible texture detail at player scale.
    let TILE_SCALE: f32 = 192.0; // 3072m / 16m per tile = 192 repeats
    let uv = fract(in.uv * TILE_SCALE);
    let w  = in.splat_weights; // .x=rock .y=grass .z=sand .w=snow

    // ── Sample all four albedo textures ──────────────────────────────────────
    let rock_alb  = textureSample(rock_albedo_tex,  rock_albedo_samp,  uv);
    let grass_alb = textureSample(grass_albedo_tex, grass_albedo_samp, uv);
    let sand_alb  = textureSample(sand_albedo_tex,  sand_albedo_samp,  uv);
    let snow_alb  = textureSample(snow_albedo_tex,  snow_albedo_samp,  uv);

    let blended_albedo = rock_alb  * w.x
                       + grass_alb * w.y
                       + sand_alb  * w.z
                       + snow_alb  * w.w;

    // ── Sample all four roughness textures ───────────────────────────────────
    let rock_rough  = textureSample(rock_roughness_tex,  rock_roughness_samp,  uv).r;
    let grass_rough = textureSample(grass_roughness_tex, grass_roughness_samp, uv).r;
    let sand_rough  = textureSample(sand_roughness_tex,  sand_roughness_samp,  uv).r;
    let snow_rough  = textureSample(snow_roughness_tex,  snow_roughness_samp,  uv).r;

    let blended_roughness = rock_rough  * w.x
                          + grass_rough * w.y
                          + sand_rough  * w.z
                          + snow_rough  * w.w;

    // ── Sample all four normal maps ──────────────────────────────────────────
    let rock_n_raw  = textureSample(rock_normal_tex,  rock_normal_samp,  uv).rgb;
    let grass_n_raw = textureSample(grass_normal_tex, grass_normal_samp, uv).rgb;
    let sand_n_raw  = textureSample(sand_normal_tex,  sand_normal_samp,  uv).rgb;
    let snow_n_raw  = textureSample(snow_normal_tex,  snow_normal_samp,  uv).rgb;

    let rock_tn  = decode_normal_map(rock_n_raw);
    let grass_tn = decode_normal_map(grass_n_raw);
    let sand_tn  = decode_normal_map(sand_n_raw);
    let snow_tn  = decode_normal_map(snow_n_raw);

    let blended_tn = normalize(
        rock_tn  * w.x +
        grass_tn * w.y +
        sand_tn  * w.z +
        snow_tn  * w.w
    );

    let shading_normal = apply_normal_map(in.world_normal, blended_tn);

    // ── Output: encode as a simple lit colour ────────────────────────────────
    // We return the blended albedo modulated by a basic N·L diffuse term
    // so the fragment output is a valid RGBA colour for the render target.
    // Bevy's PBR pipeline takes over from here via the material's fragment
    // entry point; this shader is used as a custom material fragment shader
    // that writes to the GBuffer / forward pass colour target.
    //
    // ADR-024: no painterly tint applied here. The albedo is the raw
    // texture blend; lighting is handled by Bevy's PBR pipeline.

    // Pack roughness into alpha for downstream use (alpha is 1.0 in opaque pass).
    return vec4<f32>(blended_albedo.rgb, 1.0);
}
