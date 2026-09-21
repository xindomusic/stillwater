import SpriteKit

enum FishRendering {
    static func makeShader(source: String? = nil) -> SKShader {
        let shader = SKShader(source: source ?? shaderSource)
        shader.uniforms = [SKUniform(name: "u_brightness", float: 0.95), SKUniform(name: "u_night", float: 0), SKUniform(name: "u_correspondence", texture: Artwork.turnCorrespondence)]
        shader.attributes = ["a_depth", "a_finPhase", "a_activity", "a_pose", "a_species"].map { SKAttribute(name: $0, type: .float) }
            + ["a_rect0", "a_rect1"].map { SKAttribute(name: $0, type: .vectorFloat4) }
            + [SKAttribute(name: "a_sampleScale", type: .vectorFloat2)]
        return shader
    }
    static let shaderSource = """
        vec2 bodyUV(vec2 point, float pose, float activity, float finPhase) {
            float direction = cos(pose * 0.78539816);
            float longitudinal = mix(1.0 - point.x, point.x, smoothstep(-0.2, 0.2, direction));
            float tail = pow(1.0 - longitudinal, 1.5);
            float sideView = abs(direction);
            float flex = (0.006 + activity * 0.011) * sideView;
            // A traveling wave bends the trunk before reaching the tail; the head stays steady.
            point.y += sin(finPhase - longitudinal * 6.5) * flex * (0.15 + tail);
            float fin = smoothstep(0.075, 0.27, abs(point.y - 0.5));
            point.x += sin(finPhase * 1.6 + point.y * 12.0) * 0.007 * fin;
            point.y += sin(finPhase * 0.37) * 0.002 * (1.0 - tail);
            return point;
        }
        vec2 flowUV(vec2 point, vec2 cell) {
            // Stored rows use image coordinates (top down); SpriteKit UVs point up.
            vec2 local = clamp(vec2(point.x, 1.0 - point.y), 0.00390625, 0.99609375);
            vec2 atlasUV = (cell + local) / 8.0;
            atlasUV.y = 1.0 - atlasUV.y;
            return atlasUV;
        }
        vec3 poseUV(vec2 point, vec4 rect) {
            vec2 samplePoint = rect.xy + point * rect.zw;
            float inside = step(rect.x, samplePoint.x) * step(samplePoint.x, rect.x + rect.z)
                         * step(rect.y, samplePoint.y) * step(samplePoint.y, rect.y + rect.w);
            return vec3(clamp(samplePoint, rect.xy + 0.0006, rect.xy + rect.zw - 0.0006), inside);
        }
        void main() {
            vec2 uv = bodyUV(v_tex_coord, a_pose, a_activity, a_finPhase);
            float blend = smoothstep(0.0, 1.0, fract(a_pose));
            float silhouetteWidth = mix(a_rect0.z, a_rect1.z, blend);
            vec2 local = (uv - 0.5) * a_sampleScale / vec2(silhouetteWidth, 0.5) + 0.5;
            float reverse = step(0.5, blend);
            float amount = mix(blend, 1.0 - blend, reverse);
            vec2 sourceUV = local;
            vec2 cell = vec2(floor(a_pose), a_species * 2.0 + reverse);
            // Invert only the visible view's displacement; no image analysis runs in the app.
            if (amount > 0.0005) {
                for (int i = 0; i < 3; i++) {
                    vec2 flow = (texture2D(u_correspondence, flowUV(sourceUV, cell)).rg * 255.0 - 128.0) / 254.0;
                    sourceUV = local - amount * flow * vec2(1.0, -1.0);
                }
            }
            // One visible surface: unrelated generated views must never become a double exposure.
            // Correspondence warps each photograph toward the intermediate orientation.
            vec3 point = poseUV(sourceUV, mix(a_rect0, a_rect1, reverse));
            vec4 color = texture2D(u_texture, point.xy) * point.z;
            float waterMix = 0.025 + (1.15 - a_depth) * 0.065;
            color.rgb = mix(color.rgb, vec3(0.68, 0.76, 0.81) * color.a, waterMix);
            color.rgb *= u_brightness * mix(vec3(1.0), vec3(0.40, 0.47, 0.60), u_night);
            gl_FragColor = color * v_color_mix.a;
        }
        """
}
