import SpriteKit

enum FishRendering {
    static func makeShader(source: String? = nil) -> SKShader {
        let shader = SKShader(source: source ?? shaderSource)
        shader.uniforms = [SKUniform(name: "u_brightness", float: 0.95), SKUniform(name: "u_night", float: 0)]
        shader.attributes = ["a_depth", "a_finPhase", "a_pose", "a_species"].map { SKAttribute(name: $0, type: .float) }
            + ["a_rect0", "a_stroke", "a_fins", "a_curve"].map { SKAttribute(name: $0, type: .vectorFloat4) }
            + ["a_sampleScale", "a_visibleY"].map { SKAttribute(name: $0, type: .vectorFloat2) }
        return shader
    }
    static let shaderSource = """
        // Lateral centerline and its slope: the head leads while the posterior
        // bends behind it. Polynomial coefficients are prepared once per fish.
        vec2 spine(float x, vec2 photoScale, vec4 curve) {
            float u = clamp((0.78 - (x / photoScale.x + 0.5)) / 0.76, 0.0, 1.0);
            float z = u * u * (curve.x + u * (curve.y + u * curve.z));
            float slope = -(2.0 * curve.x * u + 3.0 * curve.y * u * u + 4.0 * curve.z * u * u * u) / (0.76 * photoScale.x);
            return vec2(z, slope);
        }
        float segmentDistance(vec2 point, vec2 start, vec2 end) {
            vec2 edge = end - start;
            float t = clamp(dot(point - start, edge) / dot(edge, edge), 0.0, 1.0);
            return length(point - start - edge * t);
        }
        vec2 crabUV(vec2 uv, float phase, vec4 stroke, vec4 fins) {
            // Eight photographed walking legs: four rooted pairs around a rigid shell.
            vec2 shell = (uv - vec2(0.5, 0.575)) / vec2(0.22, 0.145);
            float outside = smoothstep(0.96, 1.25, dot(shell, shell));
            if (outside < 0.001) { return uv; }
            float closest = 2.0, selected = 0.0;
            vec2 pivot = vec2(0.5), knee = vec2(0.5);
            for (int i = 0; i < 8; i++) {
                int pair = i / 2;
                vec2 root = vec2(0.36,0.63), joint = vec2(0.26,0.735), foot = vec2(0.17,0.66);
                if (pair == 1) { root = vec2(0.33,0.57); joint = vec2(0.15,0.63); foot = vec2(0.06,0.43); }
                if (pair == 2) { root = vec2(0.33,0.53); joint = vec2(0.14,0.50); foot = vec2(0.08,0.28); }
                if (pair == 3) { root = vec2(0.36,0.49); joint = vec2(0.23,0.43); foot = vec2(0.22,0.20); }
                if (i - pair * 2 == 1) { root.x = 1.0 - root.x; joint.x = 1.0 - joint.x; foot.x = 1.0 - foot.x; }
                float distance = min(segmentDistance(uv,root,joint), segmentDistance(uv,joint,foot));
                if (distance < closest) { closest = distance; selected = float(i); pivot = root; knee = joint; }
            }
            float side = mod(selected,2.0);
            float pair = floor(selected * 0.5);
            float rhythm = phase * 0.8 + mod(pair + side,2.0) * 3.14159265;
            rhythm += pair * 0.17 + sin(fins.x * 0.43 + selected * 2.4) * 0.16;
            float power = min(1.0, stroke.x * 2.8) * outside;
            float angle = sin(rhythm) * 0.13 * power * mix(-1.0,1.0,side);
            vec2 offset = uv - pivot;
            uv = pivot + mat2(cos(angle),-sin(angle),sin(angle),cos(angle)) * offset;
            float lower = smoothstep(0.025,0.12,length(uv - knee));
            uv.y -= pow(max(0.0,sin(rhythm)),2.0) * 0.016 * power * lower;
            return uv;
        }
        vec2 photoUV(vec3 p, vec2 scale, vec4 rect, float phase, float species, vec4 stroke, vec4 fins) {
            vec2 uv = p.xy * 0.5 * scale / rect.zw + 0.5;
            if (species > 4.5) { return crabUV(uv,phase,stroke,fins); }
            if (species > 3.5) {
                // Carapace stays rigid. Walking legs and antennae move from their roots.
                float crab = step(4.5, species);
                float leg = 1.0 - smoothstep(mix(0.31, 0.40, crab), mix(0.41, 0.48, crab), uv.y);
                if (crab > 0.5) { leg = max(leg, smoothstep(0.14, 0.34, abs(uv.x - 0.5))); }
                float stride = sin(phase + uv.x * 31.0 + crab * uv.y * 17.0);
                uv.x += leg * stride * stroke.x * 0.021;
                uv.y += leg * cos(phase + uv.x * 31.0) * stroke.x * 0.012;
                float feeler = (1.0 - crab) * smoothstep(0.69, 0.9, uv.x) * smoothstep(0.52, 0.65, uv.y);
                uv.y += feeler * sin(fins.x + uv.x * 6.0) * fins.w * 0.008;
                return uv;
            }
            if (uv.x > 0.83) { return uv; }
            float loach = step(2.5, species) * (1.0 - step(3.5, species));
            float posterior = clamp((0.76 - uv.x) / 0.70, 0.0, 1.0);
            float envelope = pow(posterior, mix(2.2, 1.25, loach));
            float wave = sin(phase - posterior * mix(3.5, 7.0, loach));
            float power = stroke.x;
            // Rear-body flex grows towards the tail; the face stays anchored.
            uv.y -= envelope * wave * power * mix(0.006, 0.014, loach);
            // Lateral tail sweep foreshortens the caudal fin around its root.
            float caudal = 1.0 - smoothstep(0.22, 0.34, uv.x);
            float sweep = sin(phase - 3.3) * power * 0.72 + stroke.y * 0.28;
            uv.x = mix(uv.x, 0.29 + (uv.x - 0.29) / max(0.64, cos(sweep)), caudal);
            float fan = 1.0 + caudal * (sin(phase - 4.0) * power * 0.10 + (fins.z - 0.5) * 0.12);
            uv.y = 0.49 + (uv.y - 0.49) / fan;
            // Fin roots remain attached while their outer edges flex on independent rhythms.
            float finSpan = smoothstep(0.24, 0.37, uv.x) * (1.0 - smoothstep(0.66, 0.81, uv.x));
            float dorsal = smoothstep(mix(0.57, 0.48, loach), mix(0.75, 0.57, loach), uv.y) * finSpan;
            float ventral = (1.0 - smoothstep(mix(0.26, 0.33, loach), mix(0.41, 0.41, loach), uv.y)) * finSpan;
            if (dorsal + ventral > 0.001) {
                float dorsalWave = sin(fins.y + uv.x * 8.0);
                float ventralWave = sin(fins.y * 1.13 - uv.x * 6.0 + 1.7);
                uv.x += (dorsal * dorsalWave - ventral * ventralWave) * fins.w * 0.018;
                uv.y += (dorsal * dorsalWave + ventral * ventralWave * 0.65) * fins.w * 0.016;
            }
            vec2 shoulder = (uv - vec2(0.69, mix(0.42, 0.43, loach))) / vec2(0.12, 0.13);
            float pectoral = max(0.0, 1.0 - dot(shoulder, shoulder));
            if (pectoral > 0.001) {
                float scull = sin(fins.x) + 0.22 * sin(fins.x * 2.0 + 0.7);
                uv.x += pectoral * scull * fins.w * 0.014;
                uv.y += pectoral * cos(fins.x + 0.6) * fins.w * 0.009;
            }
            return uv;
        }
        vec4 atlasUV(vec2 uv, vec4 rect) {
            float inside = step(0.0, uv.x) * step(uv.x, 1.0) * step(0.0, uv.y) * step(uv.y, 1.0);
            return vec4(rect.xy + clamp(uv, 0.002, 0.998) * rect.zw, inside, 0.0);
        }
        // Squared, normalized distance from the bent body axis: <= 1.0 is inside the body.
        float bodyVolume(vec3 p, vec3 center, vec3 radius, vec2 photoScale, vec4 curve) {
            vec3 q = (vec3(p.xy, p.z - spine(p.x, photoScale, curve).x) - center) / radius;
            return dot(q, q);
        }
        // Soft body edge, so the silhouette of a head-on fish stays antialiased.
        float bodyWeight(float volume) { return 1.0 - smoothstep(0.86, 1.0, volume); }
        void main() {
            // Transparent atlas margins need no projection or fin calculations.
            float photoY = (v_tex_coord.y - 0.5) * a_sampleScale.y / a_rect0.w + 0.5;
            bool outsideRows = a_visibleY.y > a_visibleY.x && (photoY < a_visibleY.x || photoY > a_visibleY.y);
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
            if (a_species > 0.5 && a_species < 1.5) { centerUV = vec2(0.59,0.49); extentUV = vec2(0.36,0.105); thickness = 0.09; }
            if (a_species > 1.5 && a_species < 2.5) { centerUV = vec2(0.59,0.50); extentUV = vec2(0.36,0.23); thickness = 0.14; }
            if (a_species > 2.5 && a_species < 3.5) { centerUV = vec2(0.54,0.45); extentUV = vec2(0.44,0.077); thickness = 0.075; }
            if (a_species > 3.5 && a_species < 4.5) { centerUV = vec2(0.47,0.50); extentUV = vec2(0.27,0.085); thickness = 0.065; }
            if (a_species > 4.5) { centerUV = vec2(0.50,0.54); extentUV = vec2(0.18,0.14); thickness = 0.12; }
            vec2 photoScale = 2.0 * a_rect0.zw / a_sampleScale;
            // A quartic Bezier hull bounds the entire curved spine. This also
            // skips most empty pixels during narrow, head-on views.
            float spineExtent = max(abs(a_curve.x) / 6.0,
                max(abs(a_curve.x * 0.5 + a_curve.y * 0.25), abs(a_curve.x + a_curve.y + a_curve.z)));
            float projectedExtent = abs(c) * photoScale.x * 0.5 + abs(s) * (thickness + spineExtent) + 0.045;
            // SpriteKit's generated fragment function cannot return early.
            if (outsideRows || abs((v_tex_coord.x - 0.5) * 2.0) > projectedExtent) {
                gl_FragColor = vec4(0.0);
            } else {
            vec3 center = vec3((centerUV - 0.5) * photoScale, 0.0);
            vec3 radius = vec3(extentUV * photoScale, thickness);

            // Body: march the ray through the bent body volume and stop at the first
            // opaque photo sample. A single ellipsoid intersection used to sample the
            // transparent tip beyond the snout during head-on turns, leaving a hollow
            // ring, and its linearized bend could converge to a detached second body.
            float zLimit = thickness + spineExtent + 0.02;
            float tNear = 0.0, tFar = 8.0;
            bool bodyPossible = abs(origin.y - center.y) < radius.y;
            if (abs(ray.x) > 0.0001) {
                float t0 = (center.x - radius.x - origin.x) / ray.x, t1 = (center.x + radius.x - origin.x) / ray.x;
                tNear = max(tNear, min(t0, t1)); tFar = min(tFar, max(t0, t1));
            } else if (abs(origin.x - center.x) > radius.x) { bodyPossible = false; }
            if (abs(ray.z) > 0.0001) {
                float t0 = (-zLimit - origin.z) / ray.z, t1 = (zLimit - origin.z) / ray.z;
                tNear = max(tNear, min(t0, t1)); tFar = min(tFar, max(t0, t1));
            } else if (abs(origin.z) > zLimit) { bodyPossible = false; }
            bodyPossible = bodyPossible && tFar > tNear;
            // Steps scale with the chord through the body: about 4 for a side view, where
            // the ray crosses only the body's thickness, up to 20 for a head-on view.
            const int maximumSteps = 20;
            float chord = max(0.0, tFar - tNear);
            int bodySteps = int(clamp(ceil(chord / (thickness * 0.5)), 4.0, float(maximumSteps)));
            float stepLength = chord / float(bodySteps);
            float missT = tNear, hitT = -1.0;
            if (bodyPossible) {
                for (int i = 0; i <= maximumSteps; i++) {
                    if (i > bodySteps) { break; }
                    float t = tNear + stepLength * float(i);
                    vec3 p = origin + ray * t;
                    float weight = bodyWeight(bodyVolume(p, center, radius, photoScale, a_curve));
                    if (weight > 0.0) {
                        vec4 uv = atlasUV(photoUV(p, a_sampleScale, a_rect0, a_finPhase, a_species, a_stroke, a_fins), a_rect0);
                        if (texture2D(u_texture, uv.xy).a * uv.z * weight > 0.03) { hitT = t; break; }
                    }
                    missT = t;
                }
            }
            vec4 body = vec4(0.0);
            vec3 bodyPoint = origin;
            if (hitT >= 0.0) {
                // Bisect between the last empty sample and the hit for a smooth surface.
                for (int i = 0; i < 4; i++) {
                    float t = (missT + hitT) * 0.5;
                    vec3 p = origin + ray * t;
                    vec4 uv = atlasUV(photoUV(p, a_sampleScale, a_rect0, a_finPhase, a_species, a_stroke, a_fins), a_rect0);
                    float opacity = texture2D(u_texture, uv.xy).a * uv.z * bodyWeight(bodyVolume(p, center, radius, photoScale, a_curve));
                    if (opacity > 0.03) { hitT = t; } else { missT = t; }
                }
                // Look a little deeper too: at grazing angles the first hit is a soft
                // photo edge, while the flesh just behind it is fully opaque.
                for (int i = 0; i < 2; i++) {
                    float t = min(tFar, hitT + stepLength * 0.6 * float(i));
                    vec3 p = origin + ray * t;
                    vec4 uv = atlasUV(photoUV(p, a_sampleScale, a_rect0, a_finPhase, a_species, a_stroke, a_fins), a_rect0);
                    vec4 sampleColor = texture2D(u_texture, uv.xy) * uv.z * bodyWeight(bodyVolume(p, center, radius, photoScale, a_curve));
                    if (i == 0 || sampleColor.a > body.a) { body = sampleColor; bodyPoint = p; }
                }
                vec3 surface = origin + ray * hitT;
                vec2 bodyCurve = spine(surface.x, photoScale, a_curve);
                vec3 normal = (surface - center - vec3(0.0,0.0,bodyCurve.x)) / (radius * radius);
                normal.x -= bodyCurve.y * normal.z;
                normal = normalize(rotation * normal);
                body.rgb *= 0.78 + 0.24 * max(0.0, dot(normal, normalize(vec3(-0.3,0.6,0.9))));
            }

            // Fins: a thin plane that follows the same bent spine as the body.
            float finDistance = abs(ray.z) > 0.06 ? -origin.z / ray.z : 100.0;
            float finIncidence = abs(ray.z);
            for (int i = 0; i < 3; i++) {
                vec3 at = origin + ray * finDistance;
                vec2 bend = spine(at.x, photoScale, a_curve);
                float derivative = ray.z - bend.y * ray.x;
                finIncidence = abs(derivative) / sqrt(1.0 + bend.y * bend.y);
                if (abs(derivative) > 0.025) { finDistance -= clamp((at.z - bend.x) / derivative, -0.6, 0.6); }
            }
            vec3 finPoint = origin + ray * min(finDistance, 100.0);
            vec4 finUV = atlasUV(photoUV(finPoint, a_sampleScale, a_rect0, a_finPhase, a_species, a_stroke, a_fins), a_rect0);
            // A grazing ray may not converge to the fin surface. Reject that
            // spurious projection instead of drawing detached duplicate fins.
            float residual = abs(finPoint.z - spine(finPoint.x, photoScale, a_curve).x);
            float validFin = step(finDistance, 10.0) * step(0.0, finDistance) * (1.0 - smoothstep(0.003, 0.018, residual));
            // Subpixel fins lose projected coverage smoothly as their plane turns edge-on.
            float finCoverage = smoothstep(0.025, 0.18, finIncidence);
            vec4 fin = texture2D(u_texture, finUV.xy) * finUV.z * validFin * finCoverage;

            vec4 color = fin;
            if (body.a > 0.0) {
                color = validFin < 0.5 || hitT <= finDistance + 0.001
                    ? body + fin * (1.0 - body.a) : fin + body * (1.0 - fin.a);
            }
            float waterMix = 0.025 + (1.15 - a_depth) * 0.065;
            color.rgb = mix(color.rgb, vec3(0.68,0.76,0.81) * color.a, waterMix);
            color.rgb *= u_brightness * mix(vec3(1.0), vec3(0.40,0.47,0.60), u_night);
            if (a_species > 3.5 && a_species < 4.5 && a_stroke.z > 0.0) {
                // A shrimp passes behind its refuge from the leading side. The
                // visible part stays opaque instead of becoming a ghost silhouette.
                float axis = mix(v_tex_coord.x,1.0 - v_tex_coord.x,a_stroke.w);
                float edge = 1.06 - a_stroke.z * 1.12;
                color *= 1.0 - smoothstep(edge - 0.025,edge + 0.025,axis);
            }
            gl_FragColor = color * v_color_mix.a;
            }
        }
        """
}
