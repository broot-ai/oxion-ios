#include <metal_stdlib>
#include <SwiftUI/SwiftUI_Metal.h>
using namespace metal;

// Распад сообщения на сотни мелких частиц (как удаление в Telegram).
// t: 0…1 — прогресс, size — размер пузыря. Частицы улетают вверх-вправо волной справа налево.

static float oxHash(float2 p) {
    return fract(sin(dot(p, float2(12.9898, 78.233))) * 43758.5453);
}

[[ stitchable ]] half4 oxDissolve(float2 pos, SwiftUI::Layer layer, float t, float2 size) {
    const float cell = 2.5;
    float2 c = floor(pos / cell);
    float r1 = oxHash(c);
    float r2 = oxHash(c + 31.7);
    float r3 = oxHash(c + 77.1);
    // волна идёт справа налево, у каждой частицы своя задержка
    float wave = 1.0 - clamp(pos.x / max(size.x, 1.0), 0.0, 1.0);
    float delay = wave * 0.45 + r1 * 0.2;
    float k = clamp((t - delay) / 0.5, 0.0, 1.0);
    if (k <= 0.0) { return layer.sample(pos); }
    float ang = -1.2 + r2 * 1.9; // в основном вверх и вправо
    float2 dir = float2(cos(ang), sin(ang));
    float dist = (18.0 + r3 * 70.0) * k * k;
    float2 src = pos - dir * dist + float2(sin(r1 * 40.0 + t * 9.0), cos(r2 * 40.0 + t * 7.0)) * 2.0 * k;
    half4 col = layer.sample(src);
    // частица мерцает и гаснет; часть частиц исчезает раньше — «рассыпается» на атомы
    float alive = step(r3 * 0.9, 1.0 - k);
    return col * half((1.0 - k) * alive);
}
