import SpriteKit

/// An air bubble seen through water. Air bends light the opposite way to glass: the centre is
/// clear and shows a small, upside-down view of the water behind, a thin dark refraction band
/// sits just inside the edge, and grazing light is totally reflected into a bright silvery rim.
enum BubbleRendering {
    static func makeShader() -> SKShader {
        let shader = SKShader(source: """
            void main() {
                vec2 p = v_tex_coord * 2.0 - 1.0;
                float radius = length(p);
                float coverage = 1.0 - smoothstep(1.0 - a_edge, 1.0, radius);
                float z = sqrt(max(0.0, 1.0 - radius * radius));
                vec3 normal = vec3(p, z);
                // Clear centre: an inverted, minified view of the water behind the bubble.
                vec2 lens = 0.5 - p * 0.35 * z;
                vec2 uv = a_waterRect.xy + a_waterRect.zw * lens;
                vec3 water = texture2D(u_texture, clamp(uv, 0.001, 0.999)).rgb;
                float luminance = dot(water, vec3(0.2126, 0.7152, 0.0722));
                water = mix(water, mix(water, vec3(luminance), 0.32) * vec3(0.31, 0.39, 0.51), u_night) * u_brightness;
                // Thin dark band where light is bent away, then the silvery total-reflection rim.
                float band = smoothstep(0.50, 0.66, radius) * (1.0 - smoothstep(0.70, 0.80, radius));
                float rim = smoothstep(0.68, 0.94, radius);
                vec3 light = normalize(vec3(-0.35, 0.75, 0.55));
                // The window of light above reflects as a bright spot; a fainter one comes from below.
                float glint = pow(max(0.0, dot(normal, light)), 10.0) * 1.15
                            + pow(max(0.0, dot(normal, normalize(vec3(0.35, -0.6, 0.72)))), 24.0) * 0.35;
                // Light from the surface above makes the upper rim brighter than the lower.
                float skyward = 0.55 + 0.45 * clamp(p.y * 0.8 + 0.4, 0.0, 1.0);
                vec3 silver = mix(vec3(0.90, 0.96, 1.0), vec3(0.42, 0.50, 0.66), u_night) * u_brightness;
                float distance = clamp((1.4 - a_depth) / 0.85, 0.0, 1.0);
                vec3 color = water * (1.0 - band * 0.45);
                color = mix(color, silver, clamp(rim * skyward * 1.3 + glint * 1.6, 0.0, 1.0));
                // Distant bubbles lose contrast into the water.
                vec3 haze = mix(vec3(0.62, 0.72, 0.78), vec3(0.20, 0.25, 0.33), u_night) * u_brightness;
                color = mix(color, haze, distance * 0.35);
                float alpha = coverage * clamp(0.28 + band * 0.4 + rim * skyward * 1.1 + glint * 1.5, 0.0, 0.98) * (1.0 - distance * 0.3);
                gl_FragColor = vec4(color * alpha, alpha) * v_color_mix.a;
            }
            """)
        shader.uniforms = [SKUniform(name: "u_brightness", float: 1), SKUniform(name: "u_night", float: 0)]
        shader.attributes = [SKAttribute(name: "a_waterRect", type: .vectorFloat4), SKAttribute(name: "a_edge", type: .float), SKAttribute(name: "a_depth", type: .float)]
        return shader
    }
}
