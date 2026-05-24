// sky_dome.wgsl — Half-day / half-night sky dome with sun and moon
//
// The sky is split into two hemispheres based on the sun direction:
// - Pixels facing the sun → daytime sky (blue gradient, sun disc, clouds)
// - Pixels facing the moon → nighttime sky (dark blue, moon disc, stars)
// A smooth blend zone transitions between the two halves.
//
// BUG FIX A23: Sun/moon disc rendering now uses angular distance (acos of dot)
// instead of raw dot product for the disc threshold. This prevents distortion
// at the edges of the FOV when looking left/right. The disc is defined by a
// fixed angular radius in radians, which is view-direction-independent.

#import bevy_pbr::mesh_functions::{get_world_from_local, mesh_position_local_to_clip}
#import bevy_pbr::mesh_view_bindings::view

struct SkyUniforms {
    sun_direction: vec4<f32>,
    moon_direction: vec4<f32>,
    sun_elevation: f32,
    _pad0: f32,
    _pad1: f32,
    _pad2: f32,
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

// ── Noise utilities ─────────────────────────────────────────────────────────

fn hash(p: vec2<f32>) -> f32 {
    let h = dot(p, vec2<f32>(127.1, 311.7));
    return fract(sin(h) * 43758.5453123);
}

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

// ── Fragment shader ─────────────────────────────────────────────────────────

// Sun/moon angular radii in radians.
// Sun: ~1.8 degrees = 0.0314 rad (visible disc)
// Moon: ~2.7 degrees = 0.0471 rad (3x bigger than real, stylized)
const SUN_ANGULAR_RADIUS: f32 = 0.0314;
const SUN_EDGE_SOFTNESS: f32 = 0.005;
const MOON_ANGULAR_RADIUS: f32 = 0.0471;
const MOON_EDGE_SOFTNESS: f32 = 0.004;

@fragment
fn fragment(in: VertexOutput) -> @location(0) vec4<f32> {
    let cam_pos = view.world_position.xyz;
    let view_dir = normalize(in.world_pos - cam_pos);
    let elevation = view_dir.y;

    let sun_dir = normalize(sky.sun_direction.xyz);
    let moon_dir = normalize(sky.moon_direction.xyz);

    // ── Hemisphere blend factor ─────────────────────────────────────────────
    // Use the horizontal component of the sun direction to split the sky.
    // sun_facing: 1.0 = looking directly at sun, 0.0 = looking at moon.
    let sun_dot_horiz = dot(normalize(vec3<f32>(view_dir.x, 0.0, view_dir.z)),
                            normalize(vec3<f32>(sun_dir.x, 0.0, sun_dir.z)));
    // Hard binary split: no gradient, instant transition at the midpoint.
    let day_factor = step(0.0, sun_dot_horiz);

    // ── DAY SKY (sun hemisphere) ────────────────────────────────────────────
    let day_zenith = vec3<f32>(0.15, 0.35, 0.75);
    let day_horizon = vec3<f32>(0.55, 0.72, 0.92);
    let day_ground = vec3<f32>(0.25, 0.30, 0.40);

    var day_sky: vec3<f32>;
    if (elevation > 0.0) {
        let t = pow(elevation, 0.6);
        day_sky = mix(day_horizon, day_zenith, t);
    } else {
        let t = pow(-elevation, 0.8);
        day_sky = mix(day_horizon, day_ground, t);
    }

    // Sun disc — computed using angular distance for distortion-free rendering.
    // The angular distance between view_dir and sun_dir is acos(dot(view, sun)).
    // We compare this angle to the sun's angular radius.
    let sun_dot_full = dot(view_dir, sun_dir);
    let sun_angle = acos(clamp(sun_dot_full, -1.0, 1.0));
    let sun_disc = 1.0 - smoothstep(SUN_ANGULAR_RADIUS - SUN_EDGE_SOFTNESS, SUN_ANGULAR_RADIUS + SUN_EDGE_SOFTNESS, sun_angle);
    let sun_color = vec3<f32>(4.0, 0.2, 2.0); // HDR hot pink
    day_sky += sun_disc * sun_color * 3.0;

    // Sun halo — uses angular falloff (wider, softer glow around sun)
    let sun_halo_angle = max(1.0 - sun_angle / 0.5, 0.0); // fades over ~28 degrees
    let halo = pow(sun_halo_angle, 4.0) * 0.4;
    let halo_color = vec3<f32>(1.0, 0.85, 0.6);
    day_sky += halo * halo_color;

    // Horizon glow near sun
    let horizon_glow = pow(sun_halo_angle, 2.0) * max(1.0 - abs(elevation) * 3.0, 0.0) * 0.3;
    let glow_color = vec3<f32>(1.0, 0.7, 0.4);
    day_sky += horizon_glow * glow_color;

    // Clouds (day side only)
    if (elevation > 0.02) {
        let cloud_uv = view_dir.xz / (elevation + 0.1) * 0.5;
        let cloud_density = fbm(cloud_uv * 3.0);
        let cloud_amount = smoothstep(0.45, 0.65, cloud_density);
        let cloud_lit = 0.8 + 0.2 * max(dot(vec3<f32>(0.0, 1.0, 0.0), sun_dir), 0.0);
        let cloud_color_val = vec3<f32>(0.95, 0.95, 0.97) * cloud_lit;
        let cloud_fade = smoothstep(0.02, 0.15, elevation);
        day_sky = mix(day_sky, cloud_color_val, cloud_amount * cloud_fade * 0.6);
    }

    // ── NIGHT SKY (moon hemisphere) ─────────────────────────────────────────
    let night_zenith = vec3<f32>(0.02, 0.02, 0.08);
    let night_horizon = vec3<f32>(0.03, 0.04, 0.10);
    let night_ground = vec3<f32>(0.01, 0.01, 0.03);

    var night_sky: vec3<f32>;
    if (elevation > 0.0) {
        let t = pow(elevation, 0.6);
        night_sky = mix(night_horizon, night_zenith, t);
    } else {
        let t = pow(-elevation, 0.8);
        night_sky = mix(night_horizon, night_ground, t);
    }

    // Moon disc — angular distance for distortion-free rendering.
    let moon_dot_full = dot(view_dir, moon_dir);
    let moon_angle = acos(clamp(moon_dot_full, -1.0, 1.0));
    let moon_disc = 1.0 - smoothstep(MOON_ANGULAR_RADIUS - MOON_EDGE_SOFTNESS, MOON_ANGULAR_RADIUS + MOON_EDGE_SOFTNESS, moon_angle);
    let moon_color = vec3<f32>(1.5, 1.6, 2.0); // HDR cool blue-white
    night_sky += moon_disc * moon_color * 2.0;

    // Moon halo — angular falloff (subtle blue glow)
    let moon_halo_angle = max(1.0 - moon_angle / 0.3, 0.0); // fades over ~17 degrees
    let moon_halo = pow(moon_halo_angle, 6.0) * 0.2;
    night_sky += moon_halo * vec3<f32>(0.4, 0.5, 0.8);

    // Stars (night side)
    if (elevation > 0.05) {
        let star_uv = view_dir.xz / (elevation + 0.01) * 20.0;
        let star_val = hash(floor(star_uv));
        let star_threshold = 0.992;
        if (star_val > star_threshold) {
            let star_brightness = (star_val - star_threshold) / (1.0 - star_threshold);
            night_sky += vec3<f32>(0.8, 0.85, 1.0) * star_brightness * 0.8;
        }
    }

    // ── Blend day and night ─────────────────────────────────────────────────
    let final_color = mix(night_sky, day_sky, day_factor);

    return vec4<f32>(final_color, 1.0);
}
