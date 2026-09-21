import SpriteKit

enum FishRendering {
    static func makeShader(source: String? = nil) -> SKShader {
        let shader = SKShader(source: source ?? shaderSource)
        shader.uniforms = [SKUniform(name: "u_brightness", float: 0.95), SKUniform(name: "u_night", float: 0)]
        shader.attributes = ["a_depth", "a_finPhase", "a_activity", "a_pose", "a_species"].map { SKAttribute(name: $0, type: .float) }
            + ["a_rect0", "a_rect1"].map { SKAttribute(name: $0, type: .vectorFloat4) }
            + [SKAttribute(name: "a_sampleScale", type: .vectorFloat2)]
        return shader
    }
    static let shaderSource = """
        vec2 photoUV(vec3 p, vec2 scale, vec4 rect, float phase, float activity) {
            vec2 uv = p.xy * 0.5 * scale / rect.zw + 0.5;
            float tail = pow(clamp(1.0 - uv.x, 0.0, 1.0), 1.5);
            uv.y += sin(phase - uv.x * 6.5) * (0.005 + activity * 0.009) * (0.15 + tail);
            return uv;
        }
        vec4 atlasUV(vec2 uv, vec4 rect) {
            float inside = step(0.0, uv.x) * step(uv.x, 1.0) * step(0.0, uv.y) * step(uv.y, 1.0);
            return vec4(rect.xy + clamp(uv, 0.002, 0.998) * rect.zw, inside, 0.0);
        }
        void main() {
            // One continuous photographed surface on a curved body and thin fin plane.
            // The angle never chooses a different atlas view.
            float yaw = a_pose * 0.78539816;
            float c = cos(yaw), s = sin(yaw);
            mat3 rotation = mat3(c,0.0,-s,0.0,1.0,0.0,s,0.0,c);
            mat3 inverse = mat3(c,0.0,s,0.0,1.0,0.0,-s,0.0,c);
            vec3 origin = inverse * vec3((v_tex_coord - 0.5) * 2.0, 2.0);
            vec3 ray = inverse * vec3(0.0,0.0,-1.0);
            vec2 centerUV = vec2(0.59,0.49);
            vec2 extentUV = vec2(0.37,0.17);
            float thickness = 0.13;
            if (a_species > 1.5 && a_species < 2.5) { centerUV = vec2(0.59,0.50); extentUV = vec2(0.36,0.23); thickness = 0.14; }
            if (a_species > 2.5) { centerUV = vec2(0.54,0.45); extentUV = vec2(0.44,0.077); thickness = 0.075; }
            vec2 photoScale = 2.0 * a_rect0.zw / a_sampleScale;
            vec3 center = vec3((centerUV - 0.5) * photoScale, 0.0);
            vec3 radius = vec3(extentUV * photoScale, thickness);
            vec3 o = (origin - center) / radius, d = ray / radius;
            float A = dot(d,d), B = dot(o,d), C = dot(o,o) - 1.0;
            float discriminant = B * B - A * C;
            float bodyDistance = discriminant >= 0.0 ? (-B - sqrt(max(0.0, discriminant))) / A : 100.0;
            float finDistance = abs(ray.z) > 0.001 ? -origin.z / ray.z : 100.0;
            vec3 finPoint = origin + ray * min(finDistance, 100.0);
            vec4 finUV = atlasUV(photoUV(finPoint, a_sampleScale, a_rect0, a_finPhase, a_activity), a_rect0);
            float validFin = step(finDistance, 10.0) * step(0.0, finDistance);
            // Subpixel fins lose projected coverage smoothly as their plane turns edge-on.
            float finCoverage = smoothstep(0.0, 0.12, abs(ray.z));
            vec4 fin = texture2D(u_texture, finUV.xy) * finUV.z * validFin * finCoverage;
            vec3 bodyPoint = origin + ray * min(bodyDistance, 100.0);
            vec2 bodyPhoto = photoUV(bodyPoint, a_sampleScale, a_rect0, a_finPhase, a_activity);
            vec4 bodyUV = atlasUV(bodyPhoto, a_rect0);
            vec4 body = texture2D(u_texture, bodyUV.xy) * bodyUV.z;
            // Soften subpixel edges of the projected curved body, especially head-on loaches.
            body *= smoothstep(0.0, 0.14, max(0.0, discriminant) / A);
            float hasBody = step(0.0, discriminant) * step(0.0, bodyDistance);
            vec3 normal = normalize(rotation * ((bodyPoint - center) / (radius * radius)));
            float light = 0.78 + 0.24 * max(0.0, dot(normal, normalize(vec3(-0.3,0.6,0.9))));
            body.rgb *= light;
            vec4 color = fin;
            if (hasBody > 0.5) {
                color = validFin < 0.5 || bodyDistance <= finDistance + 0.001
                    ? body + fin * (1.0 - body.a) : fin + body * (1.0 - fin.a);
            }
            float waterMix = 0.025 + (1.15 - a_depth) * 0.065;
            color.rgb = mix(color.rgb, vec3(0.68,0.76,0.81) * color.a, waterMix);
            color.rgb *= u_brightness * mix(vec3(1.0), vec3(0.40,0.47,0.60), u_night);
            gl_FragColor = color * v_color_mix.a;
        }
        """
}
