import SpriteKit

/// A small air bubble seen through water, at the size it really is: mostly see-through, with the
/// water behind showing faintly brighter in its middle, a thin dark refraction band just inside
/// the edge, a silvery rim where grazing light is totally reflected (brightest on top, facing the
/// light), and one small sharp highlight.
enum BubbleRendering {
    static func makeShader() -> SKShader {
        let shader = SKShader(source: """
            void main() {
                // a_depth carries the depth plus how to draw it: +10 a bead on a leaf, +20 the
                // bubble's mirror image in the surface film (drawn upside down).
                float code = a_depth;
                float bead = step(7.5, code) * (1.0 - step(17.5, code));
                float mirrored = step(17.5, code);
                vec2 p = v_tex_coord * 2.0 - 1.0;
                p.y = mix(p.y, -p.y, mirrored);
                float radius = length(p);
                float coverage = 1.0 - smoothstep(1.0 - a_edge, 1.0, radius);
                float z = sqrt(max(0.0, 1.0 - radius * radius));
                vec3 normal = vec3(p, z);
                // The water behind, upright and barely magnified, shows through the middle.
                vec2 uv = a_waterRect.xy + a_waterRect.zw * (0.5 + p * 0.45);
                vec3 water = texture2D(u_texture, clamp(uv, 0.001, 0.999)).rgb;
                float luminance = dot(water, vec3(0.2126, 0.7152, 0.0722));
                water = mix(water, mix(water, vec3(luminance), 0.32) * vec3(0.31, 0.39, 0.51), u_night) * u_brightness;
                // A bead rather than a ring: a band that is dark along the lower edge where light is bent
                // away, a lighter middle where the bubble focuses light, the upper edge mirroring the
                // bright surface, one sharp glint toward the light and a faint one low on the other side.
                vec3 silver = mix(vec3(0.95, 0.98, 1.0), vec3(0.42, 0.50, 0.66), u_night) * u_brightness;
                float lower = clamp(0.6 - p.y * 0.6, 0.2, 1.0);
                float edgeBand = smoothstep(0.5, 0.78, radius) * (1.0 - smoothstep(0.93, 1.0, radius)) * lower;
                float topRim = smoothstep(0.7, 0.95, radius) * clamp(p.y * 1.2 + 0.2, 0.0, 1.0);
                float focus = 1.0 - smoothstep(0.0, 0.6, radius);
                float glint = pow(max(0.0, dot(normal, normalize(vec3(-0.4, 0.7, 0.6)))), 18.0);
                // A much fainter light low on the other side, tinted by the water it comes through.
                float lowGlint = pow(max(0.0, dot(normal, normalize(vec3(0.3, -0.6, 0.7)))), 40.0) * 0.18;
                float depth = code - bead * 10.0 - mirrored * 20.0;
                float distance = clamp((1.4 - depth) / 0.85, 0.0, 1.0);
                vec3 middle = water * (1.12 + focus * 0.3) + silver * 0.06;
                vec3 color = mix(middle, water * 0.35, edgeBand) + water * 0.3 * lowGlint;
                // Against dark rock or plants the dark edge is lost, so the whole rim catches the light.
                float onDark = 1.0 - smoothstep(0.25, 0.55, luminance);
                float shine = clamp(topRim * 0.9 + glint * 1.8 + smoothstep(0.75, 0.97, radius) * onDark * 0.5, 0.0, 1.0);
                color = mix(color, silver, shine);
                // A bubble only a few pixels across cannot show a ring: it reads as a dark speck with a
                // bright pinpoint of light (lighter than the water over dark rock or plants).
                // (a_edge is one screen pixel as a share of the radius, so it grows as bubbles shrink.)
                float tiny = smoothstep(0.22, 0.4, a_edge) * (1.0 - bead);
                // Dark over light water and sand, light over dark foliage and rock, with no grey middle.
                float pin = 1.0 - smoothstep(0.0, 0.5, length(p - vec2(-0.2, 0.3)));
                float speck = mix(1.4, 0.45, smoothstep(0.30, 0.38, luminance));
                vec3 speckColor = mix(water * speck, mix(silver, water + 0.25, onDark), pin);
                color = mix(color, speckColor, tiny);
                // Distant bubbles lose contrast into the water.
                vec3 haze = mix(vec3(0.62, 0.72, 0.78), vec3(0.20, 0.25, 0.33), u_night) * u_brightness;
                color = mix(color, haze, distance * 0.4 * (1.0 - 0.6 * tiny));
                float alpha = coverage * clamp(max(0.55 + edgeBand * 0.4 + shine, tiny * 0.85), 0.0, 0.97) * (1.0 - distance * 0.3);
                // A bead on a leaf sits in its own small shadow on the leaf below it.
                float crescent = smoothstep(0.55, 0.95, radius) * clamp(-p.y * 1.5, 0.0, 1.0) * bead;
                color = mix(color, water * 0.45, crescent);
                alpha = max(alpha, crescent * coverage * 0.8);
                gl_FragColor = vec4(color * alpha, alpha) * v_color_mix.a;
            }
            """)
        shader.uniforms = [SKUniform(name: "u_brightness", float: 1), SKUniform(name: "u_night", float: 0)]
        shader.attributes = [SKAttribute(name: "a_waterRect", type: .vectorFloat4), SKAttribute(name: "a_edge", type: .float), SKAttribute(name: "a_depth", type: .float)]
        return shader
    }
}
