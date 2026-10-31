/// Metal source for the four first-launch intro candidates. Compiled at runtime (no Metal toolchain needed).
///
/// Every effect is an overlay of light: premultiplied color drawn over the real screen, never a capture of it.
/// Coordinates are in points relative to Park's menu bar icon (`origin`), with y pointing down, so each effect
/// can start from, or settle on, the place where Park lives.
enum IntroShaders {
    static let source = """
    #include <metal_stdlib>
    using namespace metal;

    struct Uniforms {
        float time;        // seconds into the effect
        float fadeOut;     // 0…1, a skip fading everything away
        float2 resolution; // drawable size in pixels
        float2 origin;     // Park's icon, in pixels from the top left
        float scale;       // pixels per point
        float duration;
    };
    struct VOut { float4 position [[position]]; };

    // One triangle that covers the screen.
    vertex VOut fxVertex(uint id [[vertex_id]]) {
        float2 p = float2((id << 1) & 2, id & 2);
        VOut out; out.position = float4(p * 2.0 - 1.0, 0.0, 1.0);
        return out;
    }

    // The website's dawn, from night to first light.
    constant float3 NAVY    = float3(0.043, 0.106, 0.212);
    constant float3 DUSK    = float3(0.086, 0.243, 0.525);
    constant float3 SIGN    = float3(0.118, 0.314, 0.659);
    constant float3 DAWN    = float3(0.612, 0.753, 0.918);
    constant float3 HORIZON = float3(0.812, 0.878, 0.961);
    constant float3 FIRST   = float3(0.890, 0.933, 0.980);

    static float hash(float2 p) { return fract(sin(dot(p, float2(12.9898, 78.233))) * 43758.5453); }

    static float vnoise(float2 p) {
        float2 i = floor(p), f = fract(p);
        float2 u = f * f * (3.0 - 2.0 * f);
        return mix(mix(hash(i), hash(i + float2(1, 0)), u.x),
                   mix(hash(i + float2(0, 1)), hash(i + float2(1, 1)), u.x), u.y);
    }

    static float fbm(float2 p) {
        float s = 0.0, a = 0.5;
        for (int i = 0; i < 4; i++) { s += a * vnoise(p); p = p * 2.03 + float2(17.0, 5.0); a *= 0.5; }
        return s;
    }

    static float easeOut(float x) { x = clamp(x, 0.0, 1.0); return 1.0 - pow(1.0 - x, 3.0); }
    static float easeInOut(float x) {
        x = clamp(x, 0.0, 1.0);
        return x < 0.5 ? 4.0 * x * x * x : 1.0 - pow(-2.0 * x + 2.0, 3.0) * 0.5;
    }
    // Rises over [a, b], holds, falls over [c, d].
    static float window(float t, float a, float b, float c, float d) { return smoothstep(a, b, t) * (1.0 - smoothstep(c, d, t)); }
    static float gauss(float x, float w) { return exp(-(x * x) / (w * w)); }

    // Light settling on Park's icon: a small bright core inside a wide, soft bloom.
    static float iconGlow(float d) { return exp(-d / 9.0) * 0.85 + exp(-d / 34.0) * 0.32 + exp(-d / 120.0) * 0.1; }

    // Layering in premultiplied space: a tint covers what's beneath; light adds to it.
    static void tint(thread float3& rgb, thread float& a, float3 c, float amount) {
        amount = clamp(amount, 0.0, 1.0);
        rgb = rgb * (1.0 - amount) + c * amount;
        a = a + amount * (1.0 - a);
    }
    static void light(thread float3& rgb, thread float& a, float3 c, float amount) {
        amount = max(amount, 0.0);
        rgb += c * amount;
        a = a + min(amount * 0.38, 1.0) * (1.0 - a);
    }

    static float4 finish(float3 rgb, float a, float2 pixel, float t, float fadeOut) {
        float keep = 1.0 - fadeOut;
        rgb *= keep; a *= keep;
        // Fine grain keeps soft gradients from banding.
        rgb += (hash(pixel + fract(t) * 91.7) - 0.5) * 0.03 * a;
        return float4(clamp(rgb, 0.0, 1.0), clamp(a, 0.0, 1.0));
    }

    // The light that settles on Park's icon. A soft blue halo first, so it reads on a light menu bar,
    // then the glow itself.
    static void settle(thread float3& rgb, thread float& a, float d, float amount) {
        tint(rgb, a, SIGN, exp(-d / 46.0) * 0.26 * amount);
        light(rgb, a, mix(DAWN, FIRST, exp(-d / 14.0)), iconGlow(d) * amount);
    }

    // 1 · Ripple — one glassy ring of light spreads from Park's icon, a fainter echo follows,
    // and the light settles back on the icon. Wayfinding: this is where Park lives.
    fragment float4 rippleFragment(VOut in [[stage_in]], constant Uniforms& u [[buffer(0)]]) {
        float t = u.time;
        float2 p = (in.position.xy - u.origin) / u.scale;
        float d = length(p);
        float H = u.resolution.y / u.scale;
        float3 rgb = float3(0.0); float a = 0.0;

        for (int i = 0; i < 2; i++) {
            float ti = t - (i == 0 ? 0.0 : 0.36);
            if (ti <= 0.0) continue;
            float k = clamp(ti / 1.9, 0.0, 1.0);
            float r = mix(6.0, H * 1.15, easeOut(k));
            float w = mix(6.0, 64.0, k);
            float strength = (i == 0 ? 1.0 : 0.42) * pow(1.0 - k, 1.4) * smoothstep(0.0, 0.07, ti);
            float x = d - r;
            // Like light through a lens: a tinted body behind the crest, a bright crest, a hairline ahead of it.
            float body  = gauss(x + w * 0.6, w * 0.75) * strength;
            float crest = gauss(x, max(1.8, w * 0.17)) * strength;
            float hair  = gauss(x - w * 0.24, 1.3 + w * 0.05) * strength;
            tint(rgb, a, SIGN, body * 0.34 + crest * 0.16);
            light(rgb, a, DAWN, crest * 0.7);
            light(rgb, a, FIRST, hair * 0.42);
        }
        float touch  = exp(-d / 10.0) * window(t, 0.0, 0.06, 0.1, 0.45) * 0.7;
        light(rgb, a, mix(DAWN, FIRST, exp(-d / 14.0)), touch);
        settle(rgb, a, d, window(t, 0.95, 1.6, 2.25, 2.9));
        return finish(rgb, a, in.position.xy, t, u.fadeOut);
    }

    // Smooth 1D noise around a circle, so shafts vary without looking regular.
    static float angularNoise(float x, float seed) {
        float i = floor(x), f = fract(x);
        float s = f * f * (3.0 - 2.0 * f);
        return mix(hash(float2(i, seed)), hash(float2(i + 1.0, seed)), s);
    }

    // 2 · Dawn — soft shafts of morning light pour down from Park's icon through a clean blue haze,
    // then draw back into it.
    fragment float4 dawnFragment(VOut in [[stage_in]], constant Uniforms& u [[buffer(0)]]) {
        float t = u.time;
        float2 p = (in.position.xy - u.origin) / u.scale;
        float H = u.resolution.y / u.scale;
        float r = length(p) / H;
        // Angle measured from straight down, wrapped onto 18 noise cells.
        float an = (atan2(p.x, p.y) + M_PI_F) / (2.0 * M_PI_F) * 18.0;

        float beams = 0.0;
        beams += pow(angularNoise(an * 1.0 + t * 0.10, 3.1), 3.0) * 0.55;
        beams += pow(angularNoise(an * 2.0 - t * 0.08, 7.7), 4.0) * 0.5;
        beams += pow(angularNoise(an * 3.0 + t * 0.13, 1.3), 6.0) * 0.35;

        // The light reaches down as it blooms, then gathers back toward the icon.
        float reach = mix(0.22, 1.55, easeOut(t / 1.3)) * (1.0 - 0.88 * easeInOut((t - 1.45) / 1.15));
        float extent = 1.0 - smoothstep(reach * 0.35, reach, r);
        float env = smoothstep(0.0, 0.5, t) * (1.0 - smoothstep(2.35, 2.9, t));
        float shafts = beams * extent * (0.35 + 0.65 * exp(-r * 1.3));
        float wash = exp(-r * 3.2) * 0.5 * extent;
        float lightAmount = (shafts * 1.15 + wash) * env;

        float3 rgb = float3(0.0); float a = 0.0;
        // A clean blue haze where the light falls, never a gray veil over everything.
        tint(rgb, a, mix(DUSK, SIGN, 0.5), env * (0.07 + 0.17 * extent));
        float3 c = mix(SIGN, DAWN, smoothstep(0.04, 0.45, lightAmount));
        c = mix(c, FIRST, smoothstep(0.6, 1.2, lightAmount));
        light(rgb, a, c, lightAmount * 0.6);
        settle(rgb, a, length(p), window(t, 1.55, 2.05, 2.35, 2.9));
        return finish(rgb, a, in.position.xy, t, u.fadeOut);
    }

    // 3 · Clearing — a frosted veil settles over the screen, then draws itself up into Park's icon,
    // leaving the desktop clear behind it. The gesture of putting things away.
    fragment float4 clearingFragment(VOut in [[stage_in]], constant Uniforms& u [[buffer(0)]]) {
        float t = u.time;
        float2 p = (in.position.xy - u.origin) / u.scale;
        float d = length(p);
        float W = u.resolution.x / u.scale, H = u.resolution.y / u.scale;
        float diag = length(float2(W, H)) * 1.02;

        float settleIn = smoothstep(0.0, 0.5, t);
        float k = easeInOut((t - 0.5) / 1.75);
        float R = mix(diag, 0.0, k);
        float inside = 1.0 - smoothstep(R - 8.0, R + 8.0, d);
        float frost = fbm(p / 300.0 + float2(0.0, t * 0.08));

        float3 rgb = float3(0.0); float a = 0.0;
        // Frost: cool, slightly blue, a little uneven like etched glass.
        tint(rgb, a, mix(mix(HORIZON, DAWN, 0.3), FIRST, frost), 0.28 * settleIn * inside * (0.88 + 0.24 * frost));
        // The edge as it gathers in: a blue shadow just inside, a line of light on the edge.
        float rimOn = smoothstep(0.42, 0.65, t) * (1.0 - smoothstep(0.96, 1.0, k));
        float rimWidth = 12.0 + 26.0 * (1.0 - k);
        tint(rgb, a, SIGN, gauss(d - R + rimWidth * 1.3, rimWidth * 1.4) * 0.16 * rimOn);
        light(rgb, a, mix(DAWN, FIRST, 0.55), gauss(d - R, rimWidth) * 0.6 * rimOn);
        // Everything it gathered arrives at the icon.
        settle(rgb, a, d, 1.15 * window(t, 1.75, 2.2, 2.45, 3.0));
        return finish(rgb, a, in.position.xy, t, u.fadeOut);
    }

    // Distance from a point to a vertical segment.
    static float vSeg(float2 q, float x, float y0, float y1) {
        float dy = max(max(y0 - q.y, q.y - y1), 0.0);
        return length(float2(q.x - x, dy));
    }

    // 4 · Lanes — painted lines of light glide in like a row of parking bays, the rest fade away, and one bay
    // stays, framing where Park's panel opens under its icon.
    fragment float4 lanesFragment(VOut in [[stage_in]], constant Uniforms& u [[buffer(0)]]) {
        float t = u.time;
        float2 q = (in.position.xy - u.origin) / u.scale;
        float W = u.resolution.x / u.scale;

        // The bay matches the panel: 340 points wide, hanging just below the menu bar.
        float halfW = 184.0, top = 18.0, depth = 372.0, bottom = top + depth;
        float pitch = halfW * 2.0;
        float env = smoothstep(0.0, 0.35, t) * (1.0 - smoothstep(2.35, 3.0, t));

        float3 rgb = float3(0.0); float a = 0.0;
        // Evening asphalt: a light, cool dusk wash so white lines read on any desktop.
        float2 bayCenter = float2(0.0, top + depth * 0.5);
        tint(rgb, a, mix(DUSK, SIGN, 0.45), 0.15 * env * (1.0 - smoothstep(120.0, 820.0, length(q - bayCenter))));

        // The row glides in from the right and comes to rest.
        float slide = (1.0 - easeOut(t / 1.05)) * W * 0.55;
        float lines = 0.0;
        for (int n = -4; n <= 5; n++) {
            float x = -halfW + float(n) * pitch + slide;
            float isBay = (n == 0 || n == 1) ? 1.0 : 0.0;
            float keep = isBay > 0.5 ? 1.0 : (0.55 * (1.0 - smoothstep(0.95, 1.5, t)));
            float dist = vSeg(q, x, top, bottom);
            lines += (gauss(dist, 1.6) * 0.9 + exp(-dist / 11.0) * 0.16) * keep;
        }
        // The back of the bay paints across once the row has settled.
        float paint = easeOut((t - 0.85) / 0.6);
        float x1 = -halfW + pitch * paint;
        float dx = max(max(-halfW - q.x, q.x - x1), 0.0);
        float back = length(float2(dx, q.y - bottom));
        lines += (gauss(back, 1.6) * 0.9 + exp(-back / 11.0) * 0.16) * step(0.001, paint);

        light(rgb, a, FIRST, lines * env * 0.95);
        // Inside the bay, a faint cool fill, as if the space were lit.
        float inBay = step(-halfW, q.x) * step(q.x, halfW) * step(top, q.y) * step(q.y, bottom);
        tint(rgb, a, SIGN, inBay * 0.08 * window(t, 1.2, 1.65, 2.2, 2.9));
        settle(rgb, a, length(q), window(t, 1.35, 1.85, 2.4, 3.0));
        return finish(rgb, a, in.position.xy, t, u.fadeOut);
    }
    """
}
