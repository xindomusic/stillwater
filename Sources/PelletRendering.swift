import SpriteKit

enum PelletRendering {
    static func makeShader() -> SKShader {
        let shader = SKShader(source: """
            float pellet(vec3 p) {
                vec2 q = vec2(length(p.yz) - 0.22, abs(p.x) - 0.44);
                return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - 0.045;
            }
            vec3 localPoint(vec3 p, mat3 orientation) {
                return vec3(dot(p, orientation[0]), dot(p, orientation[1]), dot(p, orientation[2]));
            }
            void main() {
                float cy = cos(a_tumble), sy = sin(a_tumble);
                float cx = cos(a_tumble * 0.61 + a_seed), sx = sin(a_tumble * 0.61 + a_seed);
                float cz = cos(a_roll), sz = sin(a_roll);
                mat3 orientation = mat3(cz,sz,0.0,-sz,cz,0.0,0.0,0.0,1.0)
                    * mat3(cy,0.0,-sy,0.0,1.0,0.0,sy,0.0,cy)
                    * mat3(1.0,0.0,0.0,0.0,cx,sx,0.0,-sx,cx);
                vec3 origin = localPoint(vec3((v_tex_coord - 0.5) * 2.0, 1.6), orientation);
                vec3 ray = localPoint(vec3(0.0, 0.0, -1.0), orientation);
                float travel = 0.0;
                float closest = 10.0;
                vec3 hit = origin;
                float edge = max(0.004, a_edge);
                for (int i = 0; i < 24; i++) {
                    vec3 p = origin + ray * travel;
                    float d = pellet(p);
                    if (d < closest) { closest = d; hit = p; }
                    if (d < 0.002 || travel > 3.2) { break; }
                    travel += max(0.003, d * 0.90);
                }
                float coverage = 1.0 - smoothstep(0.0, edge, closest);
                float e = 0.008;
                vec3 normal = normalize(vec3(pellet(hit + vec3(e,0.0,0.0)) - pellet(hit - vec3(e,0.0,0.0)),
                    pellet(hit + vec3(0.0,e,0.0)) - pellet(hit - vec3(0.0,e,0.0)),
                    pellet(hit + vec3(0.0,0.0,e)) - pellet(hit - vec3(0.0,0.0,e))));
                vec3 worldNormal = orientation * normal;
                float diffuse = max(0.0, dot(worldNormal, normalize(vec3(-0.45,0.65,0.8))));
                float grain = sin(hit.x * 81.0 + a_seed + sin(hit.z * 39.0))
                            * sin(hit.y * 69.0 + hit.z * 71.0 + sin(hit.x * 53.0));
                vec3 color = vec3(0.52,0.31,0.13) * (0.47 + 0.73 * diffuse + grain * 0.055);
                float distance = clamp((1.4 - a_depth) / 0.85, 0.0, 1.0);
                color = mix(color, vec3(0.53,0.64,0.71), distance * 0.30);
                color *= u_brightness * mix(vec3(1.0), vec3(0.40,0.47,0.60), u_night);
                gl_FragColor = vec4(color * coverage, coverage) * v_color_mix.a;
            }
            """)
        shader.uniforms = [SKUniform(name: "u_brightness", float: 1), SKUniform(name: "u_night", float: 0)]
        shader.attributes = ["a_depth", "a_tumble", "a_roll", "a_seed", "a_edge"].map { SKAttribute(name: $0, type: .float) }
        return shader
    }
}
