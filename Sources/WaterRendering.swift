enum WaterRendering {
    static let shaderSource = """
        void main() {
            vec2 uv = v_tex_coord;
            vec2 regions = texture2D(u_regions, uv).rg;
            // A shared current with different local phases; roots stay anchored to the bed.
            float stemHeight = pow(clamp((uv.y - 0.075) / 0.65, 0.0, 1.0), 1.25);
            float current = sin(u_clock * 0.68 + uv.x * 8.0)
                          + 0.30 * sin(u_clock * 1.13 + uv.x * 23.0 + uv.y * 7.0);
            float sway = regions.r * stemHeight * u_sway;
            uv.x += current * 0.007 * sway;
            uv.y += sin(u_clock * 0.81 + uv.x * 19.0) * 0.0015 * sway;

            // Refract the surface texture locally, without moving rocks or the camera.
            float surface = smoothstep(0.64, 0.94, v_tex_coord.y) * regions.g * u_shimmer;
            uv.x += sin(v_tex_coord.y * 48.0 + u_clock * 0.72 + sin(v_tex_coord.x * 12.0)) * 0.016 * surface;
            uv.y += sin(v_tex_coord.x * 32.0 - u_clock * 0.93 + v_tex_coord.y * 11.0) * 0.007 * surface;
            vec4 color = texture2D(u_texture, clamp(uv, 0.001, 0.999));

            // Slowly moving light bands on sand and stones, strongest by day.
            vec2 lightUV = v_tex_coord * vec2(36.0, 22.0);
            float c0 = sin(lightUV.x + sin(lightUV.y * 0.73 + u_clock * 0.37) - u_clock * 0.46);
            float c1 = sin(lightUV.y + sin(lightUV.x * 0.61 - u_clock * 0.29) + u_clock * 0.31);
            float caustic = pow(max(0.0, 1.0 - abs(c0 + c1) * 0.65), 5.0);
            float bed = 1.0 - smoothstep(0.20, 0.65, v_tex_coord.y);
            color.rgb *= 1.0 + (caustic - 0.26) * 0.32 * bed * u_shimmer * (1.0 - regions.r * 0.6) * (1.0 - u_night * 0.80);
            float luminance = dot(color.rgb, vec3(0.2126, 0.7152, 0.0722));
            vec3 moonlight = mix(color.rgb, vec3(luminance), 0.32) * vec3(0.31, 0.39, 0.51);
            color.rgb = mix(color.rgb, moonlight, u_night) * u_brightness;
            gl_FragColor = color;
        }
        """
}
