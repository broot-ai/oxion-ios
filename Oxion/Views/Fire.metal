#include <metal_stdlib>
#include <SwiftUI/SwiftUI_Metal.h>
using namespace metal;

// Анимированный зелёный огонь — перенос шейдера с загрузочного экрана PWA (fire.js).
// tex — огонь, blur: R — ореол, G — силуэт.

static float h1(float2 p) { return fract(sin(dot(p, float2(127.1, 311.7))) * 43758.5453); }

static float vn(float2 p, float per) {
    float2 i = floor(p), f = fract(p);
    float2 u = f * f * (3.0 - 2.0 * f);
    float y0 = fmod(i.y, per), y1 = fmod(i.y + 1.0, per);
    if (y0 < 0) y0 += per;
    if (y1 < 0) y1 += per;
    return mix(mix(h1(float2(i.x, y0)), h1(float2(i.x + 1.0, y0)), u.x),
               mix(h1(float2(i.x, y1)), h1(float2(i.x + 1.0, y1)), u.x), u.y);
}

static float fbm(float2 p, float per) {
    float s = 0.0, a = 0.5;
    for (int k = 0; k < 4; k++) { s += a * vn(p, per); p *= 2.0; per *= 2.0; a *= 0.5; }
    return s;
}

static float4 img(texture2d<half> t, sampler sm, float2 q) {
    if (q.x < 0.0 || q.y < 0.0 || q.x > 1.0 || q.y > 1.0) return float4(0.0);
    float3 c = float3(t.sample(sm, q).rgb);
    return float4(c, max(c.r, max(c.g, c.b)));
}

static float bl(texture2d<half> t, sampler sm, float2 q) {
    return (q.x < 0.0 || q.y < 0.0 || q.x > 1.0 || q.y > 1.0) ? 0.0 : float(t.sample(sm, q).r);
}

static float fl(texture2d<half> t, sampler sm, float2 q) {
    return (q.x < 0.0 || q.y < 0.0 || q.x > 1.0 || q.y > 1.0) ? 0.0 : float(t.sample(sm, q).g);
}

[[ stitchable ]] half4 oxFire(float2 position, half4 color, float2 size, float ph, float tongues,
                              texture2d<half> tex, texture2d<half> blur) {
    constexpr sampler sm(filter::linear, address::clamp_to_edge);
    float2 uv = position / size;
    float2 q = (uv - float2(0.1, 0.17)) / 0.8;
    float s = smoothstep(0.98, 0.15, q.y);
    float2 np = float2(uv.x * 3.2, uv.y * 4.0);
    float n1 = fbm(np + float2(0.0, ph * 4.0), 4.0);
    float n2 = fbm(np * 1.3 + float2(5.2, ph * 8.0), 4.0);
    float n3 = fbm(np * 2.1 + float2(9.7, ph * 12.0), 4.0);
    float2 d = float2((n2 - 0.5) * 0.1, (n1 - 0.35) * 0.08) * s;
    float4 f = img(tex, sm, q + d);
    float erode = smoothstep(0.18, 0.42, n3 + (1.0 - s) * 0.7);
    f *= mix(1.0, erode, s * 0.85);
    float2 tq = q + float2((n2 - 0.5) * 0.1, 0.09);
    float sil = max(fl(blur, sm, tq), 0.75 * fl(blur, sm, q + float2((n2 - 0.5) * 0.16, 0.2)));
    float inside = smoothstep(0.1, 0.6, fl(blur, sm, q));
    float tn = fbm(float2(uv.x * 5.0, uv.y * 1.6) + float2(3.1, ph * 4.0), 4.0);
    float field = (tn + 0.35 * tongues * sil - 0.36) * (1.0 - inside) * smoothstep(0.95, 0.3, q.y);
    float body = smoothstep(0.38, 0.42, field) * smoothstep(0.05, 0.25, sil);
    float rimL = body - smoothstep(0.42, 0.56, field);
    float3 rim = float3(0.85, 1.0, 0.4), inner = float3(0.12, 0.36, 0.02);
    float3 tc = rim * rimL * 1.2 + inner * body;
    float ta = body * 0.4 + rimL * 0.6;
    float hb = bl(blur, sm, (q - 0.5) / 1.18 + 0.5 + d * 0.5);
    float flick = 0.9 + 0.1 * sin(ph * 6.2832 * 3.0) + 0.05 * sin(ph * 6.2832 * 7.0 + 1.3);
    float3 halo = float3(0.45, 1.0, 0.12) * hb * 0.42 * flick;
    float3 em = float3(0.0);
    for (int i = 0; i < 14; i++) {
        float fi = float(i);
        float r1 = h1(float2(fi, 1.7)), r2 = h1(float2(fi, 4.3)), r3 = h1(float2(fi, 8.9));
        float cyc = r3 > 0.5 ? 2.0 : 1.0;
        float e = fract(ph * cyc + r1);
        float2 c = float2(0.38 + r2 * 0.26 + sin(e * 6.2832 + fi) * 0.025 + (r1 - 0.5) * 0.18 * e, 0.66 - e * 0.62);
        float rad = 0.006 * (1.0 - e * 0.6);
        float dd = length(uv - c);
        em += float3(0.75, 1.0, 0.35) * 1.6 * (exp(-dd * dd / (rad * rad)) + 0.35 * exp(-dd * dd / (9.0 * rad * rad)))
              * smoothstep(0.0, 0.12, e) * (1.0 - e);
    }
    float3 col = f.rgb * flick * 1.05 + tc * (1.0 - f.a) + halo * (1.0 - f.a) + em;
    float a = clamp(max(f.a, max(ta, 0.0)) + hb * 0.42 * (1.0 - f.a) + length(em), 0.0, 1.0);
    col = clamp(col, 0.0, 1.0);
    a = max(a, max(col.r, max(col.g, col.b)));
    // прозрачный фон: цвет уже «светящийся», альфа — по яркости
    return half4(half3(col), half(a));
}
