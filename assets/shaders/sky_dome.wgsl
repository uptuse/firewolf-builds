// sky_dome.wgsl — Procedural sky dome shader
//
// Renders a gradient sky with sun disc, halo, and subtle cloud wisps.
// Applied to an inverted sphere that surrounds the entire scene.

#import bevy_pbr::mesh_functions::{get_world_from_local, mesh_position_local_to_clip}
#import bevy_pbr::mesh_view_bindings::view

struct SkyUniforms {
    sun_direction: vec4<f32>,
}

@group(2) @binding(0)
var<uniform> sky: SkyUniforms;

struct VertexInput {
    @builtin(instance_index) instance_index: u32,
    @location(0) position: vec3<f32>,
    @location(1) normal:   vec3<f32>,
    @location(2) uv:       vec2<f32>,
}

struct VertexOutput {
    @builtin(position) clip_position: vec4<f32>,
    @location(0) world_pos: vec3<f32>,
    @location(1) world_normal: vec3<f32>,
}

@vertex
fn vertex(in: VertexInput) -> VertexOutput {
    var out: VertexOutput;
    let world_from_local = get_world_from_local(in.instance_index);
    let world_pos4 = world_from_local * vec4<f32>(in.position, 1.0);
    out.world_pos = world_pos4.xyz;
    out.world_normal = normalize((world_from_local * vec4<f32>(in.normal, 0.0)).xyz);
    out.clip_position = mesh_position_local_to_clip(
        world_from_local,
        vec4<f32>(in.position, 1.0),
    );
    return out;
}

// Simple hash for procedural noise
fn hash(p: vec2<f32>) -> f32 {
    let h = dot(p, vec2<f32>(127.1, 311.7));
    return fract(sin(h) * 43758.5453123);
}

// Value noise
fn noise(p: vec2<f32>) -> f32 {
    let i = floor(p);
    let f = fract(p);
    let u = f * f * (3.0 - 2.0 * f);

    let a = hash(i + vec2<f32>(0.0, 0.0));
    let b = hash(i + vec2<f32>(1.0, 0.0));
    let c = hash(i + vec2<f32>(0.0, 1.0));
    let d = hash(i + vec2<f32>(1.0, 1.0));

    return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

// Fractal noise for clouds
fn fbm(p: vec2<f32>) -> f32 {
    var value = 0.0;
    var amplitude = 0.5;
    var pos = p;
    for (var i = 0; i < 4; i++) {
        value += amplitude * noise(pos);
        pos *= 2.0;
        amplitude *= 0.5;
    }
    return value;
}

@fragment
fn fragment(in: VertexOutput) -> @location(0) vec4<f32> {
    // View direction from camera to fragment
    let cam_pos = view.world_position.xyz;
    let view_dir = normalize(in.world_pos - cam_pos);

    // Elevation: -1 (nadir) to +1 (zenith)
    let elevation = view_dir.y;

    // ── Sky gradient ─────────────────────────────────────────────────────────
    // Zenith: deep blue
    let zenith_color = vec3<f32>(0.15, 0.35, 0.75);
    // Horizon: pale blue
    let horizon_color = vec3<f32>(0.55, 0.72, 0.92);
    // Below horizon: dark blue-gray
    let ground_color = vec3<f32>(0.25, 0.30, 0.40);

    var sky_color: vec3<f32>;
    if (elevation > 0.0) {
        // Above horizon: smooth gradient from horizon to zenith
        let t = pow(elevation, 0.6);
        sky_color = mix(horizon_color, zenith_color, t);
    } else {
        // Below horizon: darken
        let t = pow(-elevation, 0.8);
        sky_color = mix(horizon_color, ground_color, t);
    }

    // ── Sun ──────────────────────────────────────────────────────────────────
    let sun_dir = normalize(sky.sun_direction.xyz);
    let sun_dot = dot(view_dir, sun_dir);

    // Sun disc (sharp bright circle)
    let sun_disc = smoothstep(0.9995, 0.9998, sun_dot);
    let sun_color = vec3<f32>(1.0, 0.95, 0.8);

    // Sun halo (soft glow around sun)
    let halo = pow(max(sun_dot, 0.0), 8.0) * 0.3;
    let halo_color = vec3<f32>(1.0, 0.85, 0.6);

    // Horizon glow near sun
    let horizon_glow = pow(max(sun_dot, 0.0), 3.0) * max(1.0 - abs(elevation) * 3.0, 0.0) * 0.2;
    let glow_color = vec3<f32>(1.0, 0.7, 0.4);

    sky_color += sun_disc * sun_color;
    sky_color += halo * halo_color;
    sky_color += horizon_glow * glow_color;

    // ── Clouds ───────────────────────────────────────────────────────────────
    // Only above horizon
    if (elevation > 0.02) {
        // Project view direction onto a plane for cloud UV
        let cloud_uv = view_dir.xz / (elevation + 0.1) * 0.5;
        let cloud_density = fbm(cloud_uv * 3.0);

        // Threshold for cloud visibility
        let cloud_threshold = 0.45;
        let cloud_amount = smoothstep(cloud_threshold, cloud_threshold + 0.2, cloud_density);

        // Cloud color (white, slightly lit by sun)
        let cloud_lit = 0.8 + 0.2 * max(dot(vec3<f32>(0.0, 1.0, 0.0), sun_dir), 0.0);
        let cloud_color_val = vec3<f32>(0.95, 0.95, 0.97) * cloud_lit;

        // Fade clouds near horizon to avoid hard edge
        let cloud_fade = smoothstep(0.02, 0.15, elevation);
        sky_color = mix(sky_color, cloud_color_val, cloud_amount * cloud_fade * 0.6);
    }

    return vec4<f32>(sky_color, 1.0);
}
