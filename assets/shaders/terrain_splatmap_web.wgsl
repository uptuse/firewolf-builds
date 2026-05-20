// terrain_splatmap_web.wgsl — Simplified splatmap terrain material for WebGL2
//
// This is the WebGL-compatible version that uses only 4 albedo textures
// (no normal maps, no roughness maps) to stay within WebGL2's 16 texture
// unit limit (GL_MAX_TEXTURE_IMAGE_UNITS).
//
// Blends four ground textures (rock, grass, sand, snow) by slope and altitude.
// Includes basic directional lighting for depth perception.

#import bevy_pbr::mesh_functions::{get_world_from_local, mesh_position_local_to_clip}
#import bevy_pbr::mesh_view_bindings::view
#import bevy_pbr::mesh_bindings::mesh

// ── Uniforms ─────────────────────────────────────────────────────────────────

struct SplatmapUniforms {
    max_height: f32,
    _pad0: f32,
    _pad1: f32,
    _pad2: f32,
}

@group(2) @binding(0)
var<uniform> splat_uniforms: SplatmapUniforms;

// ── Texture samplers (4 albedo only) ─────────────────────────────────────────

@group(2) @binding(1) var rock_albedo_tex:  texture_2d<f32>;
@group(2) @binding(2) var rock_albedo_samp: sampler;

@group(2) @binding(3) var grass_albedo_tex:  texture_2d<f32>;
@group(2) @binding(4) var grass_albedo_samp: sampler;

@group(2) @binding(5) var sand_albedo_tex:  texture_2d<f32>;
@group(2) @binding(6) var sand_albedo_samp: sampler;

@group(2) @binding(7) var snow_albedo_tex:  texture_2d<f32>;
@group(2) @binding(8) var snow_albedo_samp: sampler;

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
    @location(3)             splat_weights: vec4<f32>,
}

/// Compute RGBA splat weights from world-space normal.y and altitude.
///
/// Uses abs(normal_y) so the mirror (inverted) terrain gets the same biome
/// variety as the lower terrain — without this, the downward-facing normals
/// would always classify as "steep" and render entirely as rock.
///
/// Altitude thresholds tuned for HEIGHT_SCALE=150:
///   - Below 40% (~60m): grass on flat, rock on steep
///   - 40%-55% (~60m-83m): sand transition zone
///   - Above 55% (~83m): snow on flat, rock on steep
fn compute_splat_weights(normal_y: f32, world_y: f32, max_h: f32) -> vec4<f32> {
    // Use absolute value of normal.y so mirror terrain (normals pointing down)
    // still gets biome blending based on slope steepness.
    let abs_ny = abs(normal_y);

    // For mirror terrain, compute altitude relative to mirror plane.
    // Mirror verts range from mirror_y (at lower terrain valleys) down to
    // mirror_y - max_h (at lower terrain peaks). We want the mirror's
    // "peaks" (lowest Y) to get snow, and its "valleys" (highest Y) to get grass.
    // Approximation: mirror_y ≈ 2*max_h, so altitude_frac for mirror is
    // (2*max_h - world_y) / max_h. For lower terrain it's world_y / max_h.
    let is_mirror = step(max_h * 1.2, world_y); // 1.0 if above ~120% of max_h (mirror)
    let lower_alt = world_y / max(max_h, 0.001);
    let mirror_alt = (2.0 * max_h - world_y) / max(max_h, 0.001);
    let altitude_frac = mix(lower_alt, mirror_alt, is_mirror);

    let FLAT_THRESHOLD:  f32 = 0.85;
    let STEEP_THRESHOLD: f32 = 0.60;
    let ALT_SNOW_START:  f32 = 0.55;
    let ALT_GRASS_END:   f32 = 0.40;
    let BLEND_W:         f32 = 0.08;

    // Slope masks (using abs_ny for mirror support)
    let flat_mask = smoothstep(FLAT_THRESHOLD - BLEND_W, FLAT_THRESHOLD + BLEND_W, abs_ny);
    let steep_mask = 1.0 - smoothstep(STEEP_THRESHOLD - BLEND_W, STEEP_THRESHOLD + BLEND_W, abs_ny);
    let mid_mask = 1.0 - flat_mask - steep_mask;

    // Altitude masks
    let snow_alt_mask = smoothstep(ALT_SNOW_START - BLEND_W, ALT_SNOW_START + BLEND_W, altitude_frac);
    let grass_alt_mask = 1.0 - smoothstep(ALT_GRASS_END - BLEND_W, ALT_GRASS_END + BLEND_W, altitude_frac);

    // Biome weights:
    // Rock: steep slopes at any altitude
    let rock_weight = steep_mask;
    // Grass: flat areas below grass altitude
    let grass_weight = flat_mask * grass_alt_mask;
    // Snow: flat areas above snow altitude
    let snow_weight = flat_mask * snow_alt_mask;
    // Sand: everything else (mid slopes, mid altitudes)
    let sand_weight = mid_mask + flat_mask * (1.0 - grass_alt_mask) * (1.0 - snow_alt_mask);

    let weights = vec4<f32>(
        rock_weight,
        grass_weight,
        sand_weight,
        snow_weight,
    );

    let total = weights.x + weights.y + weights.z + weights.w;
    return weights / max(total, 0.001);
}

@vertex
fn vertex(in: VertexInput) -> VertexOutput {
    var out: VertexOutput;

    let world_from_local = get_world_from_local(in.instance_index);
    let world_pos4 = world_from_local * vec4<f32>(in.position, 1.0);
    out.world_pos = world_pos4.xyz;

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

@fragment
fn fragment(in: VertexOutput) -> @location(0) vec4<f32> {
    // UV tiling
    let TILE_SCALE: f32 = 192.0;
    let uv = fract(in.uv * TILE_SCALE);
    let w  = in.splat_weights;

    // Sample 4 albedo textures
    let rock_alb  = textureSample(rock_albedo_tex,  rock_albedo_samp,  uv);
    let grass_alb = textureSample(grass_albedo_tex, grass_albedo_samp, uv);
    let sand_alb  = textureSample(sand_albedo_tex,  sand_albedo_samp,  uv);
    let snow_alb  = textureSample(snow_albedo_tex,  snow_albedo_samp,  uv);

    let blended_albedo = rock_alb  * w.x
                       + grass_alb * w.y
                       + sand_alb  * w.z
                       + snow_alb  * w.w;

    // ── Basic directional lighting ───────────────────────────────────────────
    // Sun direction: from upper-right, slightly behind the camera
    let sun_dir = normalize(vec3<f32>(0.4, 0.8, 0.3));
    let normal = normalize(in.world_normal);

    // Lambertian diffuse
    let n_dot_l = max(dot(normal, sun_dir), 0.0);

    // Ambient + diffuse lighting
    let ambient = 0.35;
    let diffuse = 0.65;
    let light_intensity = ambient + diffuse * n_dot_l;

    // Apply lighting to albedo
    let lit_color = blended_albedo.rgb * light_intensity;

    // ── Distance fog ────────────────────────────────────────────────────────
    // Subtle distance fog helps show depth. Same fog color for both terrains;
    // the blue texture set on the mirror terrain provides visual distinction.
    let cam_pos = view.world_position.xyz;
    let dist = length(in.world_pos - cam_pos);
    let fog_start = 500.0;
    let fog_end = 2500.0;
    let fog_color = vec3<f32>(0.45, 0.65, 0.85); // match clear color
    let fog_factor = clamp((dist - fog_start) / (fog_end - fog_start), 0.0, 0.6);

    let final_color = mix(lit_color, fog_color, fog_factor);

    return vec4<f32>(final_color, 1.0);
}
