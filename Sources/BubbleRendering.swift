import SpriteKit

enum BubbleRendering {
    static func makeShader() -> SKShader {
        let shader = SKShader(source: """
            void main() {
                vec2 p = v_tex_coord * 2.0 - 1.0;
                float radius = length(p);
                float coverage = 1.0 - smoothstep(1.0 - a_edge, 1.0, radius);
                float z = sqrt(max(0.0, 1.0 - dot(p, p)));
                vec3 normal = vec3(p, z);
                float rim = pow(1.0 - z, 3.0);
                vec3 light = normalize(vec3(-0.40, 0.57, 0.72));
                float glint = pow(max(0.0, dot(normal, light)), 65.0);
                float reflection = pow(max(0.0, dot(normal, light)), 7.0) * rim;
                // The center transmits the surrounding water; only the curved rim reflects strongly.
                vec2 lens = v_tex_coord + p * z * 0.18;
                vec2 uv = a_waterRect.xy + a_waterRect.zw * lens;
                vec3 water = texture2D(u_texture, clamp(uv, 0.001, 0.999)).rgb;
                float luminance = dot(water, vec3(0.2126, 0.7152, 0.0722));
                water = mix(water, mix(water, vec3(luminance), 0.32) * vec3(0.31, 0.39, 0.51), u_night) * u_brightness;
                float darkEdge = rim * max(0.0, dot(normal.xy, normalize(vec2(0.65, -0.75))));
                vec3 color = water * (1.0 - darkEdge * 0.72);
                vec3 reflectedLight = mix(vec3(0.93, 0.98, 1.0), vec3(0.40, 0.49, 0.65), u_night);
                color = mix(color, reflectedLight, clamp(glint * 0.95 + reflection * 1.2, 0.0, 1.0));
                float alpha = coverage * clamp(0.12 + rim * 0.58 + glint * 0.70, 0.0, 0.94);
                gl_FragColor = vec4(color * alpha, alpha) * v_color_mix.a;
            }
            """)
        shader.uniforms = [SKUniform(name: "u_brightness", float: 1), SKUniform(name: "u_night", float: 0)]
        shader.attributes = [SKAttribute(name: "a_waterRect", type: .vectorFloat4), SKAttribute(name: "a_edge", type: .float)]
        return shader
    }
}
