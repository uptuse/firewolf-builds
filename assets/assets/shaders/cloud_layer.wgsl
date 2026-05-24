// Cloud layer shader — procedural animated clouds at the midpoint between terrains.
// Renders a translucent fog/cloud plane with drifting noise patterns.
// Uses Bevy's standard mesh/view bindings for correct transforms.

#import bevy_pbr::mesh_functions::{get_world_from_local, mesh_position_local_to_clip}
#import bevy_pbr::mesh_view_bindings::view
#import bevy_pbr::mesh_bindings::mesh

// ── Uniforms ────────────────────────────────────────────────────────────────

struct CloudUniforms {
    time: f32,
    layer_y: f32,
    thickness: f32,
    _pad: f32,
};

@group(2) @binding(0)
var<uniform> cloud: CloudUniforms;

// ── Vertex ──────────────────────────────────────────────────────────────────

struct VertexInput {
    @builtin(instance_index) instance_index: u32,
    @location(0) position: vec3<f32>,
    @location(1) normal: vec3<f32>,
    @location(2) uv: vec2<f32>,
};

struct VertexOutput {
    @builtin(position) clip_position: vec4<f32>,
    @location(0) world_pos: vec3<f32>,
    @location(1) uv: vec2<f32>,
};

@vertex
fn vertex(in: VertexInput) -> VertexOutput {
    var out: VertexOutput;
    let world_from_local = get_world_from_local(in.instance_index);
    let world_pos4 = world_from_local * vec4<f32>(in.position, 1.0);
    out.world_pos = world_pos4.xyz;
    out.clip_position = mesh_position_local_to_clip(
        world_from_local,
        vec4<f32>(in.position, 1.0),
    );
    out.uv = in.uv;
    return out;
}

// ── Noise functions ─────────────────────────────────────────────────────────

fn hash2(p: vec2<f32>) -> f32 {
    let h = dot(p, vec2<f32>(127.1, 311.7));
    return fract(sin(h) * 43758.5453);
}

fn noise2d(p: vec2<f32>) -> f32 {
    let i = floor(p);
    let f = fract(p);
    let u = f * f * (3.0 - 2.0 * f); // smoothstep

    let a = hash2(i + vec2<f32>(0.0, 0.0));
    let b = hash2(i + vec2<f32>(1.0, 0.0));
    let c = hash2(i + vec2<f32>(0.0, 1.0));
    let d = hash2(i + vec2<f32>(1.0, 1.0));

    return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

fn fbm(p: vec2<f32>) -> f32 {
    var value = 0.0;
    var amplitude = 0.5;
    var pos = p;

    for (var i = 0; i < 4; i = i + 1) {
        value += amplitude * noise2d(pos);
        pos *= 2.2;
        amplitude *= 0.5;
    }
    return value;
}

// ── Fragment ────────────────────────────────────────────────────────────────

@fragment
fn fragment(in: VertexOutput) -> @location(0) vec4<f32> {
    // Scale world position to UV space for noise sampling
    let world_uv = in.world_pos.xz * 0.001;

    // Animate: drift slowly over time
    let drift = vec2<f32>(cloud.time * 0.006, cloud.time * 0.004);

    // Two layers of FBM noise at different scales and speeds
    let n1 = fbm(world_uv * 4.0 + drift);
    let n2 = fbm(world_uv * 8.0 - drift * 1.3 + vec2<f32>(5.3, 2.7));

    // Combine noise layers
    let cloud_density = n1 * 0.6 + n2 * 0.4;

    // Threshold: only show clouds where density is above a cutoff
    let cutoff = 0.38;
    let cloud_alpha = smoothstep(cutoff, cutoff + 0.15, cloud_density);

    // Distance fade: fade out clouds far from camera
    let cam_xz = view.world_position.xz;
    let cam_dist = length(in.world_pos.xz - cam_xz);
    let dist_fade = 1.0 - smoothstep(600.0, 1500.0, cam_dist);

    // Vertical proximity fade: fade when player is very close to the cloud layer
    let vert_dist = abs(view.world_position.y - cloud.layer_y);
    let vert_fade = smoothstep(3.0, 25.0, vert_dist);

    // Final alpha — keep it subtle
    let alpha = cloud_alpha * dist_fade * vert_fade * 0.45;

    // Discard fully transparent fragments to avoid z-fighting
    if (alpha < 0.01) {
        discard;
    }

    // Cloud color: white with slight blue tint, darker at denser areas
    let base_color = vec3<f32>(0.88, 0.92, 1.0);
    let shadow_color = vec3<f32>(0.55, 0.6, 0.75);
    let color = mix(shadow_color, base_color, cloud_density);

    return vec4<f32>(color, alpha);
}
