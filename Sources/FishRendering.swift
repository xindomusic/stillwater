import SpriteKit

enum FishRendering {
    static func makeShader(source: String? = nil) -> SKShader {
        let shader = SKShader(source: source ?? shaderSource)
        // `u_canvas` is the sprite's size relative to the fish: extra room so a tail swung
        // out in a deep turn is not clipped by the sprite's edge.
        shader.uniforms = [SKUniform(name: "u_brightness", float: 0.95), SKUniform(name: "u_night", float: 0), SKUniform(name: "u_canvas", float: 1),
                           SKUniform(name: "u_legs", texture: Artwork.crabLegLabels)]
        // a_pixel: one screen pixel in the photograph's texture units, for antialiased drawn edges.
        shader.attributes = ["a_depth", "a_finPhase", "a_pose", "a_species", "a_pixel"].map { SKAttribute(name: $0, type: .float) }
            + ["a_rect0", "a_stroke", "a_fins", "a_curve", "a_rock"].map { SKAttribute(name: $0, type: .vectorFloat4) }
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
        // Long, flowing fins fan out of the body's plane: the dorsal fin leans one way and the
        // anal fin the other, more the farther they reach from the body.
        float finFan(float x, float y, vec3 center, vec3 radius, float flare) {
            float side = y >= center.y ? 1.0 : -1.0;
            return flare * side * max(0.0, abs(y - center.y) - radius.y * 0.9);
        }
        float segmentDistance(vec2 point, vec2 start, vec2 end) {
            vec2 edge = end - start;
            float t = clamp(dot(point - start, edge) / dot(edge, edge), 0.0, 1.0);
            return length(point - start - edge * t);
        }
        // The photographed crab's eight walking legs, each a two-segment limb (root → knee → foot).
        vec2 crabLegPoint(int leg, int joint) {
            int pair = leg / 2;
            vec2 p = joint == 0 ? vec2(0.36,0.63) : (joint == 1 ? vec2(0.26,0.735) : vec2(0.17,0.66));
            if (pair == 1) { p = joint == 0 ? vec2(0.33,0.57) : (joint == 1 ? vec2(0.15,0.63) : vec2(0.06,0.43)); }
            if (pair == 2) { p = joint == 0 ? vec2(0.33,0.53) : (joint == 1 ? vec2(0.14,0.50) : vec2(0.08,0.28)); }
            if (pair == 3) { p = joint == 0 ? vec2(0.36,0.49) : (joint == 1 ? vec2(0.23,0.43) : vec2(0.22,0.20)); }
            if (leg - pair * 2 == 1) { p.x = 1.0 - p.x; }
            return p;
        }
        // How the crab stands: legs splayed out sideways, knees a little above the shell's rim,
        // and every foot planted on the sand below the body.
        vec2 crabStancePoint(int leg, int joint) {
            int pair = leg / 2;
            vec2 p = joint == 0 ? vec2(0.37,0.62) : (joint == 1 ? vec2(0.24,0.63) : vec2(0.22,0.45));
            if (pair == 1) { p = joint == 0 ? vec2(0.34,0.57) : (joint == 1 ? vec2(0.19,0.58) : vec2(0.17,0.41)); }
            if (pair == 2) { p = joint == 0 ? vec2(0.34,0.53) : (joint == 1 ? vec2(0.20,0.52) : vec2(0.19,0.37)); }
            if (pair == 3) { p = joint == 0 ? vec2(0.37,0.49) : (joint == 1 ? vec2(0.24,0.47) : vec2(0.27,0.33)); }
            if (leg - pair * 2 == 1) { p.x = 1.0 - p.x; }
            return p;
        }
        vec2 rotateAbout(vec2 p, vec2 centre, float angle) {
            vec2 d = p - centre;
            return centre + vec2(d.x * cos(angle) - d.y * sin(angle), d.x * sin(angle) + d.y * cos(angle));
        }
        vec2 photoUV(vec3 p, vec2 scale, vec4 rect, float phase, float species, vec4 stroke, vec4 fins, float curl) {
            vec2 uv = p.xy * 0.5 * scale / rect.zw + 0.5;
            if (species > 3.5) {
                // Carapace stays rigid. Walking legs and antennae move from their roots.
                float crab = step(4.5, species);
                // Walking legs hang from the underside of the head (x 0.45–0.82). Each swings about its
                // root, the swing growing with distance below the body, in a wave that runs from the
                // back legs forward (a metachronal gait): the foot sweeps back planted, then lifts forward.
                if (crab < 0.5 && uv.y < 0.43 && uv.x > 0.44 && uv.x < 0.84 && stroke.x > 0.01) {
                    // Five walking legs hang from roots along the underside (x 0.50–0.78). Each swings
                    // rigidly about its root in a wave running from the back legs forward: the foot
                    // sweeps back while planted, then lifts and reaches forward.
                    vec2 source = uv;
                    float bestGap = 1.0;
                    for (int k = 0; k < 5; k++) {
                        vec2 root = vec2(0.50 + float(k) * 0.07, 0.43);
                        float legPhase = phase - float(k) * 1.1;
                        float angle = sin(legPhase) * 0.28 * stroke.x * 2.0;
                        // The two front pairs are claws: standing, they pick at the surface in quick
                        // alternate strokes, reaching forward fast and drawing back more slowly.
                        // Each stroke starts with the tip down on the surface and flicks forward and up to the mouth.
                        float pickReach = 0.0;
                        if (k >= 3) {
                            float c = fract((fins.z + float(k - 3) * 3.14159265) / 6.2831853);
                            pickReach = c < 0.25 ? c / 0.25 : 1.0 - (c - 0.25) / 0.75;
                            angle += fins.w * 0.45 * pickReach;
                        }
                        vec2 d = uv - root;
                        vec2 q = root + vec2(d.x * cos(angle) + d.y * sin(angle), -d.x * sin(angle) + d.y * cos(angle));
                        // The foot lifts off the sand as it swings forward.
                        q.y -= max(0.0, cos(legPhase)) * 0.012 * stroke.x * 2.0 * smoothstep(0.0, 0.08, 0.43 - q.y);
                        q.y += fins.w * 0.01 * (1.0 - pickReach) * step(3.0, float(k));
                        // Which leg the photographed point lies on: the rear legs slant back as they
                        // descend and the front legs slant forward.
                        float slant = -0.35 + float(k) * 0.16;
                        float gap = abs(q.x - (root.x + (0.43 - q.y) * slant));
                        if (gap < 0.04 && gap < bestGap) { bestGap = gap; source = q; }
                    }
                    // A photographed leg that has swung away leaves only water behind.
                    // A photographed leg that has swung away leaves only water behind (the claws reach higher
                    // under the head, so their old place is cleared further up).
                    float cleared = uv.x > 0.68 ? 0.41 : 0.37;
                    uv = bestGap < 1.0 ? source : (uv.y < cleared && uv.x > 0.50 - (0.43 - uv.y) * 0.35 - 0.03 ? vec2(-1.0) : uv);
                }
                // Swimmerets under the abdomen beat fast, in a wave running toward the tail, only
                // while the shrimp swims (stroke.y).
                float swimmerets = (1.0 - crab) * smoothstep(0.33, 0.37, uv.x) * (1.0 - smoothstep(0.53, 0.57, uv.x)) * (1.0 - smoothstep(0.40, 0.45, uv.y)) * smoothstep(0.30, 0.36, uv.y);
                uv.x += swimmerets * sin(fins.x * 6.0 + uv.x * 40.0) * 0.014 * stroke.y;
                // The two long antennae wave on their own rhythms, now and then sweeping wide.
                float feeler = (1.0 - crab) * smoothstep(0.69, 0.9, uv.x) * smoothstep(0.52, 0.65, uv.y);
                float reach = smoothstep(0.69, 1.0, uv.x);
                uv.y += feeler * reach * (sin(fins.x * 1.7 + uv.x * 6.0) * 0.03 + sin(fins.x * 0.45 + 1.0) * sin(fins.y * 0.8) * 0.03);
                if (curl > 0.0 && crab < 0.5) {
                    // Tail flip: the abdomen rolls down under the body from just behind the carapace, wrapped
                    // round an arc whose radius shrinks as the flip deepens, so it keeps its length and
                    // the fan tucks under the head in a C (about 170° at the deepest).
                    vec2 pivot = vec2(0.54, 0.47);
                    float bendRadius = 0.46 / (curl * 3.0 + 0.001);
                    vec2 center = pivot - vec2(0.0, bendRadius);
                    vec2 v = uv - center;
                    float around = atan(-v.x, v.y);
                    // The abdomen tapers as it curls toward the tail fan.
                    float taper = 1.0 - 0.35 * clamp(around / 3.0, 0.0, 1.0);
                    vec2 unrolled = vec2(pivot.x - bendRadius * around, pivot.y + (length(v) - bendRadius) / taper);
                    if (around > 0.0 && unrolled.x < 0.56) { uv = unrolled; }
                }
                return uv;
            }
            float loach = step(2.5, species) * (1.0 - step(3.5, species));
            // A sifting loach tips only its head down into the sand, turning it about a point just
            // behind the gills; the body stays on the bed.
            // The bend spreads over the front half, so the body curves down rather than kinking.
            float dip = loach * stroke.z * 0.12 * smoothstep(0.48, 0.85, uv.x);
            uv = rotateAbout(uv, vec2(0.62, 0.45), dip);
            if (uv.x > 0.83) { return uv; }
            float posterior = clamp((0.76 - uv.x) / 0.70, 0.0, 1.0);
            float envelope = pow(posterior, mix(2.2, 1.25, loach));
            float wave = sin(phase - posterior * mix(3.5, 7.0, loach));
            float power = stroke.x;
            // Rear-body flex grows towards the tail; the face stays anchored. An eel-like loach
            // ripples along its whole length as it works over the sand.
            uv.y -= envelope * wave * power * mix(0.006, 0.06, loach);
            uv.y -= loach * sin(phase * 0.5 - uv.x * 9.0) * (1.0 - smoothstep(0.72, 0.8, uv.x)) * 0.02;
            // Paused to sift, the rear of a loach never lies rigid: a slow ripple on its own clock.
            uv.y -= loach * min(1.0, stroke.z * 2.0) * sin(stroke.w - posterior * 4.0) * posterior * posterior * 0.022;
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
            vec2 canvas = 0.5 + (v_tex_coord - 0.5) * u_canvas;
            if (a_species > 4.5) {
                // Crabs face the camera. The shell, eyes, and claws are the photograph; the eight
                // walking legs are jointed limbs (root → knee → foot) whose feet stay planted on the
                // sand while the body moves over them, then lift and swing to the next foothold, in an
                // alternating tetrapod gait. Each leg is textured from the photographed leg it replaces.
                float crabYaw = a_pose * 0.78539816;
                vec2 uv = 0.5 + (canvas - 0.5) * a_sampleScale / a_rect0.zw * vec2(1.0 / max(0.7, cos(crabYaw)), 1.0);
                // The small claws under the shell pick at the sand while the crab stands still.
                float claws = (1.0 - smoothstep(0.08, 0.14, abs(uv.x - 0.5))) * smoothstep(0.30, 0.36, uv.y) * (1.0 - smoothstep(0.44, 0.49, uv.y));
                // a_curve for crabs: the axis the feet sweep along, how settled the legs are, and the body bob.
                float resting = a_curve.z;
                vec2 bodyUV = uv;
                // The shell rises and falls with each step; the planted feet stay where they are.
                bodyUV.y -= a_curve.w;
                bodyUV.y += claws * resting * max(0.0, sin(a_fins.x * 1.7 + step(0.5, uv.x) * 2.1)) * 0.02;
                vec4 bodyAtlas = atlasUV(bodyUV, a_rect0);
                vec4 crabColor = texture2D(u_texture, bodyAtlas.xy) * bodyAtlas.z;
                // Deepen the small claws so they read in front of the face at desktop size.
                crabColor.rgb *= 1.0 - claws * 0.42;
                // Photographed legs are replaced by the jointed ones below.
                if (texture2D(u_legs, clamp(bodyUV, 0.001, 0.999)).r > 0.02) { crabColor = vec4(0.0); }
                if (crabColor.a < 0.98) {
                    // Legs always keep their full stride; the step cycle itself follows the distance walked.
                    float power = 1.0 - a_curve.z;
                    vec2 legAxis = a_curve.xy;
                    float nearest = 1.0;
                    vec4 legColor = vec4(0.0);
                    for (int i = 0; i < 8; i++) {
                        vec2 root = crabStancePoint(i, 0) + vec2(0.0, a_curve.w), restKnee = crabStancePoint(i, 1) + vec2(0.0, a_curve.w);
                        vec2 restFoot = crabStancePoint(i, 2);
                        float side = float(i - (i / 2) * 2);
                        float pair = float(i / 2);
                        float cycle = fract((a_finPhase + mod(pair + side, 2.0) * 3.14159265 + pair * 0.12) / 6.2831853);
                        float sweep = 1.0 - 2.0 * cycle / 0.6, lift = 0.0;
                        if (cycle >= 0.6) {
                            float t = (cycle - 0.6) / 0.4;
                            sweep = -1.0 + 2.0 * t * t * (3.0 - 2.0 * t);
                            lift = sin(t * 3.14159265);
                        }
                        // crabStride 0.2: the planted foot sweeps from +0.1 to -0.1 along the walking axis
                        // (Simulation.crabStride). A crab coming to a stop lowers each lifted foot where it
                        // is, so no foot slides across the sand.
                        // A stride toward or away from the viewer is drawn foreshortened (Simulation.crabVerticalStride).
                        vec2 foot = restFoot + legAxis * vec2(1.0, 0.5) * sweep * 0.1 + vec2(0.0, lift * 0.045 * power);
                        // Two-bone reach with the knee raised, as crab legs are held.
                        float upper = length(restKnee - root), lower = length(restFoot - restKnee);
                        vec2 reach = foot - root;
                        float span = clamp(length(reach), abs(upper - lower) + 0.001, upper + lower - 0.001);
                        float bend = acos(clamp((upper * upper + span * span - lower * lower) / (2.0 * upper * span), -1.0, 1.0));
                        float heading = atan(reach.y, reach.x);
                        vec2 kneeA = root + upper * vec2(cos(heading + bend), sin(heading + bend));
                        vec2 kneeB = root + upper * vec2(cos(heading - bend), sin(heading - bend));
                        vec2 knee = kneeA.y > kneeB.y ? kneeA : kneeB;
                        foot = root + normalize(reach) * span;
                        // Distance to each segment, the leg tapering from root to tip.
                        for (int segment = 0; segment < 2; segment++) {
                            vec2 a = segment == 0 ? root : knee, b = segment == 0 ? knee : foot;
                            vec2 photoA = crabLegPoint(i, segment), photoB = crabLegPoint(i, segment + 1);
                            vec2 edge = b - a;
                            float t = clamp(dot(uv - a, edge) / dot(edge, edge), 0.0, 1.0);
                            vec2 offset = uv - (a + edge * t);
                            // Stout, flattened walking legs: a broad upper segment and a lower one tapering to a claw tip.
                            float radius = segment == 0 ? mix(0.032, 0.027, t) : mix(0.022, 0.003, t * t);
                            float d = length(offset);
                            if (d < radius + a_pixel && d / radius < nearest) {
                                nearest = d / radius;
                                vec2 normal = normalize(vec2(-edge.y, edge.x));
                                vec2 photoEdge = photoB - photoA;
                                // One shade matched to the shell, lightly tinted by the photographed leg's centre.
                                vec3 shell = vec3(0.60, 0.47, 0.32);
                                vec4 core = texture2D(u_texture, atlasUV(photoA + photoEdge * t, a_rect0).xy);
                                vec3 tint = core.a > 0.6 ? mix(shell, core.rgb / core.a, 0.3) : shell;
                                // Brown speckles like the shell's, fixed to the leg.
                                float speckle = sin(t * 61.0 + float(i) * 7.3 + dot(offset, normal) * 220.0) * sin(t * 37.0 + float(i) * 3.1);
                                tint *= 1.0 - smoothstep(0.8, 0.98, speckle) * 0.3;
                                // Rounded limb: lit along its upper edge, darker below and toward the tip.
                                float across = dot(offset, normal) / radius;
                                tint *= 0.7 + 0.32 * (1.0 - across * across) + 0.08 * across;
                                // Darker joints and an amber claw tip.
                                // Joints at the knee and part-way down the lower leg (merus, carpus, dactyl).
                                float joint = segment == 0 ? smoothstep(0.88, 1.0, t)
                                    : max(1.0 - smoothstep(0.0, 0.1, t), 1.0 - smoothstep(0.0, 0.05, abs(t - 0.45)));
                                tint = mix(tint, vec3(0.66, 0.46, 0.26), joint * 0.6);
                                if (segment == 1) { tint = mix(tint, vec3(0.58, 0.36, 0.16), smoothstep(0.72, 0.95, t)); }
                                // About one screen pixel of soft edge, whatever the crab's size.
                                float aa = max(radius * 0.08, a_pixel * 1.2);
                                float coverage = 1.0 - smoothstep(radius - aa, radius + aa * 0.5, d);
                                legColor = vec4(tint * coverage, coverage);
                            }
                        }
                    }
                    crabColor = crabColor + legColor * (1.0 - crabColor.a);
                }
                float crabWater = 0.025 + (1.15 - a_depth) * 0.065;
                crabColor.rgb = mix(crabColor.rgb, vec3(0.68,0.76,0.81) * crabColor.a, crabWater);
                crabColor.rgb *= u_brightness * mix(vec3(1.0), vec3(0.40,0.47,0.60), u_night);
                gl_FragColor = crabColor * v_color_mix.a;
            } else {
            float photoY = (canvas.y - 0.5) * a_sampleScale.y / a_rect0.w + 0.5;
            // Rows outside the photographed body are skipped, with more margin as the body turns so
            // backs, legs, and fins of a foreshortened animal are never cut off.
            float rowMargin = abs(sin(a_pose * 0.78539816)) * 0.12;
            bool outsideRows = a_visibleY.y > a_visibleY.x && (photoY < a_visibleY.x - rowMargin || photoY > a_visibleY.y + rowMargin);
            // One continuous photographed surface on a curved body and thin fin plane.
            // The angle never chooses a different atlas view.
            float yaw = a_pose * 0.78539816;
            float c = cos(yaw), s = sin(yaw);
            mat3 rotation = mat3(c,0.0,-s,0.0,1.0,0.0,s,0.0,c);
            mat3 inverse = mat3(c,0.0,s,0.0,1.0,0.0,-s,0.0,c);
            vec3 origin = inverse * vec3((canvas - 0.5) * 2.0, 2.0);
            vec3 ray = inverse * vec3(0.0,0.0,-1.0);
            vec2 centerUV = vec2(0.59,0.49);
            vec2 extentUV = vec2(0.37,0.17);
            float thickness = 0.13;
            if (a_species > 0.5 && a_species < 1.5) { centerUV = vec2(0.59,0.49); extentUV = vec2(0.36,0.105); thickness = 0.09; }
            if (a_species > 1.5 && a_species < 2.5) { centerUV = vec2(0.59,0.50); extentUV = vec2(0.36,0.23); thickness = 0.14; }
            if (a_species > 2.5 && a_species < 3.5) { centerUV = vec2(0.54,0.45); extentUV = vec2(0.44,0.077); thickness = 0.075; }
            if (a_species > 3.5 && a_species < 4.5) { centerUV = vec2(0.47,0.50); extentUV = vec2(0.27,0.085); thickness = 0.12; }
            if (a_species > 4.5) { centerUV = vec2(0.50,0.54); extentUV = vec2(0.18,0.14); thickness = 0.12; }
            vec2 photoScale = 2.0 * a_rect0.zw / a_sampleScale;
            // A quartic Bezier hull bounds the entire curved spine. This also
            // skips most empty pixels during narrow, head-on views.
            float spineExtent = max(abs(a_curve.x) / 6.0,
                max(abs(a_curve.x * 0.5 + a_curve.y * 0.25), abs(a_curve.x + a_curve.y + a_curve.z)));
            float projectedExtent = abs(c) * photoScale.x * 0.5 + abs(s) * (thickness + spineExtent) + 0.045;
            // SpriteKit's generated fragment function cannot return early.
            if (outsideRows || abs((canvas.x - 0.5) * 2.0) > projectedExtent) {
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
                        vec4 uv = atlasUV(photoUV(p, a_sampleScale, a_rect0, a_finPhase, a_species, a_stroke, a_fins, a_curve.w), a_rect0);
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
                    vec4 uv = atlasUV(photoUV(p, a_sampleScale, a_rect0, a_finPhase, a_species, a_stroke, a_fins, a_curve.w), a_rect0);
                    float opacity = texture2D(u_texture, uv.xy).a * uv.z * bodyWeight(bodyVolume(p, center, radius, photoScale, a_curve));
                    if (opacity > 0.03) { hitT = t; } else { missT = t; }
                }
                // Look a little deeper too: at grazing angles the first hit is a soft
                // photo edge, while the flesh just behind it is fully opaque.
                for (int i = 0; i < 2; i++) {
                    float t = min(tFar, hitT + stepLength * 0.6 * float(i));
                    vec3 p = origin + ray * t;
                    vec4 uv = atlasUV(photoUV(p, a_sampleScale, a_rect0, a_finPhase, a_species, a_stroke, a_fins, a_curve.w), a_rect0);
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

            // Fins: a thin sheet that follows the same bent spine as the body. Scan the ray for
            // the first place it crosses the sheet, then bisect. A single straight-line solve
            // fails when a deeply bent tail is seen edge-on in the middle of a turn.
            // Long, flowing fins (bettas, gouramis) flare outward away from the body instead of
            // lying in one flat plane, so they keep some width when the fish faces the viewer.
            float finFlare = (a_species > 1.5 && a_species < 2.5) ? 0.45 : 0.0;
            float sheetLimit = spineExtent + 0.06 + finFlare * photoScale.y * 0.5;
            float fNear = 0.0, fFar = 8.0;
            if (abs(ray.x) > 0.0001) {
                float t0 = (-0.5 * photoScale.x - origin.x) / ray.x, t1 = (0.5 * photoScale.x - origin.x) / ray.x;
                fNear = max(fNear, min(t0, t1)); fFar = min(fFar, max(t0, t1));
            }
            if (abs(ray.z) > 0.0001) {
                float t0 = (-sheetLimit - origin.z) / ray.z, t1 = (sheetLimit - origin.z) / ray.z;
                fNear = max(fNear, min(t0, t1)); fFar = min(fFar, max(t0, t1));
            }
            float finDistance = 100.0, validFin = 0.0;
            if (fFar > fNear) {
                const int sheetSteps = 12;
                float sheetStep = (fFar - fNear) / float(sheetSteps);
                float previousT = fNear;
                vec3 start = origin + ray * fNear;
                float previousGap = start.z - spine(start.x, photoScale, a_curve).x - finFan(start.x, start.y, center, radius, finFlare);
                for (int i = 1; i <= sheetSteps; i++) {
                    float t = fNear + sheetStep * float(i);
                    vec3 at = origin + ray * t;
                    float gap = at.z - spine(at.x, photoScale, a_curve).x - finFan(at.x, at.y, center, radius, finFlare);
                    if (previousGap * gap <= 0.0) {
                        float lo = previousT, hi = t, loGap = previousGap;
                        for (int k = 0; k < 5; k++) {
                            float mid = 0.5 * (lo + hi);
                            vec3 m = origin + ray * mid;
                            float midGap = m.z - spine(m.x, photoScale, a_curve).x - finFan(m.x, m.y, center, radius, finFlare);
                            if (loGap * midGap <= 0.0) { hi = mid; } else { lo = mid; loGap = midGap; }
                        }
                        finDistance = 0.5 * (lo + hi);
                        validFin = 1.0;
                        break;
                    }
                    previousT = t; previousGap = gap;
                }
            }
            vec3 finPoint = origin + ray * min(finDistance, 100.0);
            vec2 sheetBend = spine(finPoint.x, photoScale, a_curve);
            float finIncidence = abs(ray.z - sheetBend.y * ray.x) / sqrt(1.0 + sheetBend.y * sheetBend.y);
            vec4 finUV = atlasUV(photoUV(finPoint, a_sampleScale, a_rect0, a_finPhase, a_species, a_stroke, a_fins, a_curve.w), a_rect0);
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
            if (a_species > 3.5 && a_species < 4.5 && abs(a_rock.z) > 0.0) {
                // A shrimp behind a rock is hidden wherever the rock covers it: a dome standing on its
                // base line (a_rock: base centre, half-width and height, in canvas units), with a
                // slightly uneven edge. Nothing below the base line is ever hidden. Close to the rock
                // the shrimp lies in its shadow.
                float ragged = sin(canvas.y * 37.0 + canvas.x * 11.0) * 0.012;
                vec2 radii = abs(a_rock.zw);
                float r = length((canvas - a_rock.xy) / radii) + ragged;
                // A negative height: the shrimp stands wholly behind the rock, so even the legs that
                // reach below the base line are hidden.
                float aboveBase = a_rock.w < 0.0 ? 1.0 : smoothstep(-0.02, 0.02, (canvas.y - a_rock.y) / radii.y);
                color.rgb *= 1.0 - 0.3 * (1.0 - smoothstep(1.0, 1.25, r));
                color *= 1.0 - (1.0 - smoothstep(0.97, 1.03, r)) * aboveBase;
            }
            gl_FragColor = color * v_color_mix.a;
            }
            }
        }
        """
}
