#import bevy_pbr::forward_io::VertexOutput

@group(2) @binding(0) var<uniform> sun_dir: vec3<f32>;
@group(2) @binding(1) var<uniform> max_h: f32;

@fragment
fn fragment(in: VertexOutput) -> @location(0) vec4<f32> {
    // 1. dot(fragDirHorizontal, sunDirHorizontal)
    // The cylinder is centered at x=0, z=0.
    let frag_pos = in.world_position.xyz;
    let frag_dir_horizontal = normalize(vec3<f32>(frag_pos.x, 0.0, frag_pos.z));
    
    // dot product ranges from -1 to 1
    let terminator = dot(frag_dir_horizontal, sun_dir);
    
    // Map terminator to 0..1 for color mixing
    let day_night_mix = smoothstep(-0.2, 0.2, terminator);
    
    // 2. frag.y / max_h
    // Since the cylinder sits between max_h and mirror_y (which is 2 * max_h),
    // the local y from the bottom of the cylinder is frag_pos.y - max_h.
    // The gradient should go from warm at the lower terrain (max_h) to cool at the mirror plane (2 * max_h).
    let vertical_t = clamp((frag_pos.y - max_h) / max_h, 0.0, 1.0);
    
    // Colors
    let day_warm = vec3<f32>(0.9, 0.8, 0.6); // Warm at lower terrain
    let day_cool = vec3<f32>(0.4, 0.6, 0.9); // Cool at mirror plane
    let night_warm = vec3<f32>(0.1, 0.1, 0.2); // Night lower
    let night_cool = vec3<f32>(0.05, 0.05, 0.1); // Night upper
    
    let day_color = mix(day_warm, day_cool, vertical_t);
    let night_color = mix(night_warm, night_cool, vertical_t);
    
    let final_color = mix(night_color, day_color, day_night_mix);
    
    return vec4<f32>(final_color, 1.0);
}
