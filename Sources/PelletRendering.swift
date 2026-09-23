import SpriteKit

/// Soaked micro-pellets: small, slightly irregular granules with a wet sheen. Each one gets
/// its own tint between tan and red-brown, and distant ones are smaller, bluer, and softer.
enum PelletRendering {
    static func makeShader() -> SKShader {
        let shader = SKShader(source: """
            float grainNoise(vec3 p) {
                return sin(p.x * 23.0 + sin(p.y * 17.0)) * sin(p.y * 19.0 + p.z * 21.0) * sin(p.z * 29.0 + p.x * 13.0);
            }
            void main() {
                vec2 p = v_tex_coord * 2.0 - 1.0;
                // A lumpy, not perfectly round, outline that turns as the pellet tumbles.
                float angle = atan(p.y, p.x) + a_roll;
                float outline = 0.86 + 0.05 * sin(angle * 3.0 + a_seed * 4.1) + 0.035 * sin(angle * 5.0 + a_seed * 1.7 + a_tumble);
                float r = length(p) / outline;
                float coverage = 1.0 - smoothstep(1.0 - max(0.02, a_edge), 1.0, r);
                vec3 normal = normalize(vec3(p / outline, sqrt(max(0.0, 1.0 - r * r))));
                // Surface detail is fixed to the pellet, so it rolls as the pellet tumbles.
                float ct = cos(a_tumble), st = sin(a_tumble);
                vec3 body = vec3(normal.x * ct - normal.z * st, normal.y, normal.x * st + normal.z * ct);
                float grain = grainNoise(body * 1.6 + a_seed);
                // Per-pellet tint: tan, brown, or red-brown.
                float tint = fract(a_seed * 0.6180339);
                vec3 base = mix(vec3(0.60, 0.40, 0.20), vec3(0.55, 0.22, 0.12), tint);
                base = mix(base, vec3(0.42, 0.26, 0.14), step(0.72, tint));
                vec3 light = normalize(vec3(-0.45, 0.65, 0.62));
                float diffuse = max(0.0, dot(normal, light)) * 0.75 + 0.25;
                // A soaked pellet darkens toward its rim and carries a small wet highlight.
                float rim = pow(1.0 - normal.z, 2.0);
                vec3 color = base * diffuse * (1.0 + grain * 0.12) * (1.0 - rim * 0.35);
                float sheen = pow(max(0.0, dot(reflect(-light, normal), vec3(0.0, 0.0, 1.0))), 28.0);
                float distance = clamp((1.4 - a_depth) / 0.85, 0.0, 1.0);
                color += vec3(0.85, 0.82, 0.75) * sheen * 0.45 * (1.0 - distance * 0.7);
                // Water between the pellet and the viewer: far pellets lose contrast and turn blue-green.
                color = mix(color, vec3(0.50, 0.62, 0.68), distance * 0.45);
                color *= u_brightness * mix(vec3(1.0), vec3(0.40, 0.47, 0.60), u_night);
                gl_FragColor = vec4(color * coverage, coverage) * v_color_mix.a;
            }
            """)
        shader.uniforms = [SKUniform(name: "u_brightness", float: 1), SKUniform(name: "u_night", float: 0)]
        shader.attributes = ["a_depth", "a_tumble", "a_roll", "a_seed", "a_edge"].map { SKAttribute(name: $0, type: .float) }
        return shader
    }
}
