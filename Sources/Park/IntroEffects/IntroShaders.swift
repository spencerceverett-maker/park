/// Metal source for the first-launch intro candidates. Compiled at runtime (no Metal toolchain needed).
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
        // Fine grain keeps soft gradients from banding: a little texture where there's light, plus a
        // one-step dither so faint halos don't show 8-bit rings.
        float n = hash(pixel + fract(t) * 91.7) - 0.5;
        float lit = step(0.002, a);
        rgb += n * 0.03 * a + n * (2.0 / 255.0) * lit;
        a += n * (2.0 / 255.0) * lit;
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

    // ─── The gathering family ───────────────────────────────────────────────────────────────────
    // Light gathers from the whole screen into Park's icon and ends as a soft ring around it, echoing
    // the coin. Motion is organic: noise-shaped edges, eased timing that varies a little per element.

    constant float HALO_R = 15.0;

    static float2 rot(float2 v, float r) { float c = cos(r), s = sin(r); return float2(c * v.x - s * v.y, s * v.x + c * v.y); }
    static float smin(float a, float b, float k) {
        float h = clamp(0.5 + 0.5 * (b - a) / k, 0.0, 1.0);
        return mix(b, a, h) - k * h * (1.0 - h);
    }
    static float2 bezier(float2 a, float2 b, float2 c, float s) { return mix(mix(a, b, s), mix(b, c, s), s); }

    // The ring the light settles into: a blue bed so it reads on a light menu bar, then a soft line of light.
    static void halo(thread float3& rgb, thread float& a, float d, float amount) {
        float x = d - HALO_R;
        tint(rgb, a, SIGN, (exp(-d / 40.0) * 0.16 + gauss(x, 6.0) * 0.2) * amount);
        light(rgb, a, mix(DAWN, FIRST, 0.6), (gauss(x, 1.9) * 0.8 + exp(-abs(x) / 9.0) * 0.22) * amount);
    }

    // 5 · Gather — soft rings start wide and contract into the icon at slightly different paces,
    // their edges gently wavering. Ripples in reverse.
    fragment float4 gatherFragment(VOut in [[stage_in]], constant Uniforms& u [[buffer(0)]]) {
        float t = u.time;
        float2 p = (in.position.xy - u.origin) / u.scale;
        float d = length(p);
        float2 dir = p / max(d, 0.001);
        float diag = length(u.resolution / u.scale);
        float3 rgb = float3(0.0); float a = 0.0;

        for (int i = 0; i < 5; i++) {
            float fi = float(i);
            float delay = fi * 0.16 + hash(float2(fi, 3.0)) * 0.1;
            float span = 1.5 + hash(float2(fi, 7.0)) * 0.4;
            if (t < delay) continue;
            float k = clamp((t - delay) / span, 0.0, 1.0);
            float e = easeInOut(k);
            float r = mix(diag * (0.5 + 0.13 * fi), HALO_R, e);
            // Wavering edges, quieter as each ring tightens.
            float waver = (vnoise(dir * 2.4 + float2(fi * 5.1, t * 0.6 + fi)) - 0.5) * 2.0
                        + (vnoise(dir * 5.0 + float2(fi * 2.3 - t * 0.5, 9.0)) - 0.5) * 0.35;
            float x = d - r - waver * (r - HALO_R) * 0.055;
            float w = mix(52.0, 3.0, e);
            float strength = smoothstep(0.0, 0.3, t - delay) * (1.0 - smoothstep(0.82, 1.0, k)) * (1.0 - fi * 0.11);
            // Moving inward, so the soft body trails outside the crest.
            float body  = gauss(x - w * 0.7, w) * strength;
            float crest = gauss(x, max(1.6, w * 0.16)) * strength;
            tint(rgb, a, SIGN, body * 0.26 + crest * 0.12);
            light(rgb, a, DAWN, crest * 0.6);
            light(rgb, a, FIRST, gauss(x + 1.0, max(1.0, w * 0.05)) * 0.3 * strength);
        }
        halo(rgb, a, d, window(t, 1.45, 2.05, 2.5, 3.0));
        return finish(rgb, a, in.position.xy, t, u.fadeOut);
    }

    // 6 · Liquid — a pool of blue light gathers, flows across the screen like a liquid and pours itself into
    // the icon, rounding into the ring.
    fragment float4 liquidFragment(VOut in [[stage_in]], constant Uniforms& u [[buffer(0)]]) {
        float t = u.time;
        float2 p = (in.position.xy - u.origin) / u.scale;
        float d = length(p);
        float W = u.resolution.x / u.scale, H = u.resolution.y / u.scale;
        float2 O = u.origin / u.scale;
        float2 S = float2(0.24 * W, 0.74 * H) - O;
        float2 C = float2(0.78 * W, 1.02 * H) - O;

        // The surface wobbles while it flows and calms as it arrives.
        float calm = 1.0 - smoothstep(1.7, 2.3, t);
        float2 q = p + (float2(fbm(p / 160.0 + float2(t * 0.45, 0.0)), fbm(p / 160.0 + float2(7.3, -t * 0.35))) - 0.5) * 56.0 * calm;

        float sd = 1e5;
        for (int j = 0; j < 7; j++) {
            float fj = float(j);
            float s = easeInOut((t - 0.3 - fj * 0.04 - hash(float2(fj, 2.0)) * 0.03) / 1.6);
            float2 c = bezier(S, C, float2(0.0), s)
                     + float2(sin(t * 1.7 + fj * 1.3), cos(t * 1.3 + fj * 2.1)) * (1.0 - s) * 22.0;
            float grow = easeOut((t - fj * 0.05) / 0.55);
            float r = grow * mix(64.0 - fj * 5.0, 9.0 + fj * 0.4, smoothstep(0.72, 1.0, s));
            sd = smin(sd, length(q - c) - r, mix(70.0, 14.0, s));
        }
        float env = smoothstep(0.0, 0.35, t) * (1.0 - smoothstep(2.15, 2.65, t));
        float inside = smoothstep(2.0, -5.0, sd);
        float depth = clamp(-sd / 45.0, 0.0, 1.0);

        float3 rgb = float3(0.0); float a = 0.0;
        tint(rgb, a, SIGN, exp(-max(sd, 0.0) / 22.0) * 0.08 * env);            // the light it casts
        tint(rgb, a, mix(SIGN, DUSK, depth * 0.5), inside * (0.18 + 0.12 * depth) * env);
        light(rgb, a, DAWN, inside * depth * 0.22 * env);                       // lit from within
        light(rgb, a, mix(DAWN, FIRST, 0.7), gauss(sd, 1.8) * 0.6 * env);       // the meniscus
        halo(rgb, a, d, window(t, 1.75, 2.2, 2.5, 3.0));
        return finish(rgb, a, in.position.xy, t, u.fadeOut);
    }

    // 7 · Fireflies — the screen-wide part: a faint pull of blue where the motes converge, then the ring.
    // The motes themselves are drawn by moteVertex/moteFragment.
    fragment float4 firefliesFragment(VOut in [[stage_in]], constant Uniforms& u [[buffer(0)]]) {
        float t = u.time;
        float2 p = (in.position.xy - u.origin) / u.scale;
        float d = length(p);
        float3 rgb = float3(0.0); float a = 0.0;
        tint(rgb, a, SIGN, exp(-d / 240.0) * 0.07 * window(t, 0.7, 1.6, 2.2, 2.9));
        halo(rgb, a, d, window(t, 1.75, 2.25, 2.5, 3.0));
        return finish(rgb, a, in.position.xy, t, u.fadeOut);
    }

    static float potential(float2 q) { return vnoise(q) + 0.5 * vnoise(q * 2.1 + float2(3.1, 7.7)); }
    // Divergence-free flow, so the motes swirl rather than bunch up.
    static float2 curl(float2 q) {
        const float e = 0.02;
        return float2(potential(q + float2(0, e)) - potential(q - float2(0, e)),
                      potential(q - float2(e, 0)) - potential(q + float2(e, 0))) / (2.0 * e);
    }

    struct MoteOut { float4 position [[position]]; float2 local; float size; float bright; };

    vertex MoteOut moteVertex(uint vid [[vertex_id]], uint iid [[instance_id]], constant Uniforms& u [[buffer(0)]]) {
        float fi = float(iid), t = u.time;
        float h1 = hash(float2(fi, 1.3)), h2 = hash(float2(fi, 4.7)), h3 = hash(float2(fi, 8.1)), h4 = hash(float2(fi, 2.9));
        float W = u.resolution.x / u.scale, H = u.resolution.y / u.scale;
        float2 pos = float2(h1 * W, 0.04 * H + h2 * 0.96 * H) - u.origin / u.scale;

        // Drift on the current.
        float drift = min(t, 2.4);
        for (int k = 0; k < 8; k++) {
            pos += curl(pos / 280.0 + float2(0.0, float(k) * 0.04)) * drift / 8.0 * 34.0;
        }
        // Then gathered: each on its own schedule, spiralling into a place on the ring.
        float g = easeInOut((t - (0.45 + h3 * 0.6)) / (0.95 + h4 * 0.5));
        float theta = h2 * 6.2831853 + t * 0.5;
        float2 target = float2(cos(theta), sin(theta)) * (HALO_R + (h1 - 0.5) * 5.0);
        pos = target + rot(pos - target, g * 1.2) * (1.0 - g);

        MoteOut out;
        out.size = mix(1.2, 2.8, h4 * h4) * (1.0 - 0.3 * g);
        float ext = out.size * 6.0;
        float2 corner = float2(float(vid & 1), float(vid >> 1)) * 2.0 - 1.0;
        out.local = corner * ext;
        float2 pixel = u.origin + (pos + out.local) * u.scale;
        out.position = float4(pixel.x / u.resolution.x * 2.0 - 1.0, 1.0 - pixel.y / u.resolution.y * 2.0, 0.0, 1.0);
        out.bright = smoothstep(0.0, 0.35 + h1 * 0.5, t) * (0.8 + 0.2 * sin(t * 2.6 + h2 * 40.0))
                   * (1.0 - smoothstep(2.35, 2.85, t)) * (1.0 - u.fadeOut);
        return out;
    }

    fragment float4 moteFragment(MoteOut in [[stage_in]]) {
        float dd = length(in.local);
        float3 rgb = float3(0.0); float a = 0.0;
        tint(rgb, a, SIGN, gauss(dd, in.size * 1.7) * 0.55 + exp(-dd / (in.size * 2.2)) * 0.12);
        light(rgb, a, mix(DAWN, FIRST, 0.5), gauss(dd, in.size * 0.7) * 0.7 + exp(-dd / (in.size * 1.6)) * 0.12);
        return float4(rgb, a) * in.bright;
    }

    // 8 · Tide — a soft wave of light rolls in from every edge with an uneven, foamy front and closes in
    // on the icon.
    fragment float4 tideFragment(VOut in [[stage_in]], constant Uniforms& u [[buffer(0)]]) {
        float t = u.time;
        float2 p = (in.position.xy - u.origin) / u.scale;
        float d = length(p);
        float2 dir = p / max(d, 0.001);
        float diag = length(u.resolution / u.scale);

        float2 res = u.resolution / u.scale, o = u.origin / u.scale;
        float farthest = length(max(o, res - o));
        float k = easeInOut((t - 0.05) / 1.95);
        // A gentle surge, in and back, as it comes.
        float R = mix(farthest * 0.97, HALO_R, k) + sin(t * 4.2) * 22.0 * (1.0 - k) * smoothstep(0.0, 0.3, t);
        float shape = (vnoise(dir * 2.2 + float2(t * 0.35, 1.7)) - 0.5) * 1.4
                    + (vnoise(dir * 5.0 + float2(4.1, -t * 0.5)) - 0.5) * 0.6
                    + (vnoise(p / 260.0 + float2(t * 0.2, -t * 0.14)) - 0.5) * 1.1;
        float amp = (R - HALO_R) * 0.11;
        float x = d - R - shape * amp;                       // x > 0: behind the front, where the water is
        float env = smoothstep(0.0, 0.3, t) * (1.0 - smoothstep(1.75, 2.25, t));

        float3 rgb = float3(0.0); float a = 0.0;
        float water = smoothstep(-4.0, 14.0, x) * exp(-max(x, 0.0) / 170.0);
        tint(rgb, a, mix(SIGN, DAWN, 0.25), water * 0.14 * env);
        // The body of the wave: a soft swell of blue just behind the front, so it reads as water, not a line.
        tint(rgb, a, SIGN, gauss(x - 34.0, 34.0) * 0.2 * env);
        float foam = smoothstep(0.35, 0.85, fbm(p / 40.0 + float2(t * 0.7, -t * 0.4)));
        light(rgb, a, mix(DAWN, FIRST, 0.5), (gauss(x, 3.0 + amp * 0.03) * 0.5 + gauss(x - 6.0, 18.0) * 0.12) * env);
        light(rgb, a, FIRST, gauss(x - 14.0, 16.0) * foam * 0.16 * env);
        // A smaller swell following behind.
        float x2 = x - (60.0 + 50.0 * (1.0 - k));
        light(rgb, a, DAWN, gauss(x2, 4.0 + amp * 0.04) * 0.26 * env * (1.0 - k));
        halo(rgb, a, d, window(t, 1.55, 2.05, 2.5, 3.0));
        return finish(rgb, a, in.position.xy, t, u.fadeOut);
    }

    // 9 · Bloom — watercolor blooms of blue spread across the screen, then draw back into Park, as if inhaled.
    fragment float4 bloomFragment(VOut in [[stage_in]], constant Uniforms& u [[buffer(0)]]) {
        float t = u.time;
        float2 p = (in.position.xy - u.origin) / u.scale;
        float d = length(p);
        float W = u.resolution.x / u.scale, H = u.resolution.y / u.scale;
        float2 O = u.origin / u.scale;

        float sd = 1e5;
        for (int i = 0; i < 6; i++) {
            float fi = float(i);
            float h1 = hash(float2(fi, 11.0)), h2 = hash(float2(fi, 23.0)), h3 = hash(float2(fi, 37.0));
            float2 home = float2((0.08 + 0.84 * h1) * W, (0.12 + 0.8 * h2) * H) - O;
            float spread = easeOut((t - 0.04 - fi * 0.08) / (0.85 + h3 * 0.3));
            float inhale = easeInOut((t - 0.85 - h3 * 0.3) / (1.0 + h1 * 0.2));
            float2 c = mix(home, float2(0.0), inhale);
            float r = spread * mix(80.0 + h3 * 90.0, 8.0, inhale);
            float edge = (fbm(p / 110.0 + float2(fi * 7.1, t * 0.12)) - 0.5) * r * 0.4;
            sd = smin(sd, length(p - c) - r + edge, 40.0);
        }
        float env = smoothstep(0.0, 0.25, t) * (1.0 - smoothstep(2.05, 2.55, t));
        float inside = smoothstep(3.0, -8.0, sd);
        float grain = fbm(p / 14.0) - 0.5;

        float3 rgb = float3(0.0); float a = 0.0;
        // A thin wash inside, a little uneven like pigment settling, darker where the water dried at the edge.
        tint(rgb, a, mix(SIGN, DAWN, 0.3), inside * (0.085 + grain * 0.04) * env);
        tint(rgb, a, SIGN, gauss(sd + 4.0, 5.0) * 0.14 * env);
        light(rgb, a, DAWN, inside * 0.06 * env);
        halo(rgb, a, d, window(t, 1.7, 2.15, 2.5, 3.0));
        return finish(rgb, a, in.position.xy, t, u.fadeOut);
    }
    """
}
