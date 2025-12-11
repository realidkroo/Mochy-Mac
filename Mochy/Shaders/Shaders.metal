#include <metal_stdlib>
#include <SwiftUI/SwiftUI_Metal.h>
using namespace metal;

// smooth 0 to 1 bell, the same curve the android lyrics shaders use
static float bellCurve(float distance, float span) {
    float w = 1.0 - min(1.0, abs(distance) / max(span, 1.0));
    return w * w * (3.0 - 2.0 * w);
}

// unsung letters wait a little below their place and climb into it as the sweep reaches them, one soft wave through the word
[[ stitchable ]] float2 lyricRise(float2 position, float4 bounds, float pad, float progress, float drop, float span) {
    // the rise runs a span ahead of the sweep, so a word starts fully down and ends fully up with no jump at either end
    float width = bounds.z - 2.0 * pad;
    float headX = bounds.x + pad - span + (width + span) * progress;
    float passed = clamp((headX - position.x) / max(span, 1.0) + 1.0, 0.0, 1.0);
    float risen = passed * passed * (3.0 - 2.0 * passed);
    return float2(position.x, position.y - drop * (1.0 - risen));
}

// a soft light trailing the sweep, strongest on a held note; it reads each pixel where it is and only adds glow
[[ stitchable ]] half4 lyricBloom(float2 position, SwiftUI::Layer layer, float4 bounds, float pad, float head, float strength, float radius, float lag, float span) {
    half4 base = layer.sample(position);
    if (strength <= 0.001) return base;
    float headX = bounds.x + pad + (bounds.z - 2.0 * pad) * head;
    float bell = bellCurve(position.x - headX + lag, span);
    if (bell <= 0.0) return base;

    half4 glow = half4(0.0);
    for (int ring = 1; ring <= 2; ring++) {
        float r = radius * float(ring) * 0.85;
        for (int i = 0; i < 8; i++) {
            float angle = float(i) * 0.785398 + float(ring) * 0.392699;
            glow += layer.sample(position + float2(cos(angle), sin(angle)) * r);
        }
    }
    glow *= 1.0 / 16.0;
    return base + glow * half(strength * bell);
}

// four soft colour pools from the cover drifting on slow loops, blended by closeness into one smooth field
[[ stitchable ]] half4 ambient(float2 position, half4 color, float2 size, float time, half4 deep, half4 seamLeft, half4 seamRight, half4 accent) {
    float2 uv = position / size;
    float aspect = size.y / max(size.x, 1.0);
    float2 p = float2(uv.x, uv.y * aspect);
    const float w = 6.2831853 / 50.0;
    float t = time;

    float2 a = float2(0.22 + 0.16 * sin(t * w + 0.4), (0.38 + 0.10 * cos(t * w * 2.0)) * aspect);
    float2 b = float2(0.80 + 0.14 * cos(t * w + 1.3), (0.42 + 0.12 * sin(t * w * 2.0 + 0.7)) * aspect);
    float2 c = float2(0.48 + 0.24 * cos(t * w * 3.0 + 2.1), (0.92 + 0.06 * sin(t * w + 1.9)) * aspect);
    float2 d = float2(0.62 + 0.22 * sin(t * w * 2.0 + 3.4), (0.70 + 0.12 * cos(t * w * 3.0 + 0.4)) * aspect);

    float2 da = p - a, db = p - b, dc = p - c, dd = p - d;
    float wa = exp(-dot(da, da) * 3.2);
    float wb = exp(-dot(db, db) * 3.2);
    float wc = exp(-dot(dc, dc) * 2.4);
    float wd = exp(-dot(dd, dd) * 4.0) * 0.8;
    float sum = wa + wb + wc + wd + 0.0001;
    float3 col = (float3(seamLeft.rgb) * wa + float3(seamRight.rgb) * wb + float3(deep.rgb) * wc + float3(accent.rgb) * wd) / sum;

    col *= 1.0 - 0.16 * smoothstep(0.6, 1.0, uv.y);
    float grain = fract(sin(dot(position, float2(12.9898, 78.233))) * 43758.5453);
    col += (grain - 0.5) / 255.0;
    return half4(half3(col), 1.0);
}

// the cover slowly swimming, zoomed past its box so the warp's edges never show
[[ stitchable ]] half4 coverWarp(float2 position, SwiftUI::Layer layer, float2 size, float time, float zoom) {
    float2 centre = size * 0.5;
    float2 p = centre + (position - centre) / zoom;
    float2 uv = p / size;
    float t = time * 0.5;
    float2 warp = float2(
        sin(uv.y * 3.0 + t) * 0.05 + cos(uv.x * 2.0 - t * 0.6) * 0.04,
        cos(uv.x * 3.0 + t * 0.7) * 0.05 + sin(uv.y * 2.5 + t * 0.9) * 0.04
    );
    return layer.sample(clamp(p + warp * size, float2(0.0), size));
}

// one pass whose radius grows row by row, so the sharp end stays sharp and nothing blooms where a faded copy would
[[ stitchable ]] half4 progressiveBlur(float2 position, SwiftUI::Layer layer, float4 bounds, float maxRadius, float from, float to) {
    float row = (position.y - bounds.y) / max(bounds.w, 1.0);
    float t = clamp((row - from) / max(to - from, 0.001), 0.0, 1.0);
    float radius = maxRadius * t * t;
    if (radius < 0.4) return layer.sample(position);

    half4 sum = half4(0.0);
    float total = 0.0;
    for (int i = 0; i < 24; i++) {
        float fi = float(i) + 0.5;
        float r = sqrt(fi / 24.0) * radius;
        float angle = fi * 2.39996323;
        float weight = 1.0 - 0.5 * (r / radius);
        sum += layer.sample(position + float2(cos(angle), sin(angle)) * r) * half(weight);
        total += weight;
    }
    return sum / half(total);
}
