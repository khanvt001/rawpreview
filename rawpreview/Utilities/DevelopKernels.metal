//
//  DevelopKernels.metal
//  rawpreview
//
//  Core Image kernels for the develop pipeline (built with -fcikernel and
//  loaded by `DevelopKernels`). Colours arrive in the working space, linear
//  Rec.2020; Rec.2020 luminance weights throughout.
//

#include <CoreImage/CoreImage.h>

using namespace metal;

constant float3 luminanceWeights = float3(0.2627, 0.6780, 0.0593);

extern "C" {
namespace coreimage {

/// The RAW base curve, y = xⁿ / (xⁿ + kn), on luminance; chroma ratios kept.
float4 rawBaseCurve(sample_t pixel, float n, float kn) {
    float4 p = unpremultiply(pixel);
    float l = max(dot(p.rgb, luminanceWeights), 0.0);
    float ln = pow(l, n);
    float mapped = ln / (ln + kn);
    float3 c = l > 0.000001 ? p.rgb * (mapped / l) : p.rgb;
    return premultiply(float4(c, p.a));
}

/// Clarity / Texture: luminance detail against a blurred copy, weighted
/// down across strong edges so they don't halo.
float4 lumaDetail(sample_t pixel, sample_t low, float amount) {
    float4 p = unpremultiply(pixel);
    float y = max(dot(p.rgb, luminanceWeights), 0.0);
    float b = max(dot(unpremultiply(low).rgb, luminanceWeights), 0.0);
    float delta = y - b;
    float range = 0.025 + 0.12 * sqrt(y);
    float edgeWeight = exp(-delta * delta / (range * range));
    float target = max(0.0, y + amount * delta * edgeWeight);
    float3 c = y > 0.000001 ? p.rgb * (target / y) : p.rgb;
    return premultiply(float4(c, p.a));
}

/// The darkest channel, gamma-encoded: the haze estimate's input.
float4 darkChannel(sample_t p) {
    float d = pow(max(min(p.r, min(p.g, p.b)), 0.0), 0.4545);
    return float4(d, d, d, 1.0);
}

/// Dehaze through the haze model I = J·t + A·(1 − t), in gamma space.
float4 regionalDehaze(sample_t pixel, sample_t haze, float amount) {
    float4 p = unpremultiply(pixel);
    float3 g = pow(max(p.rgb, float3(0.0)), float3(0.4545));
    float airlight = 0.92;
    float density = clamp(haze.r / airlight, 0.0, 1.0);
    if (amount >= 0.0) {
        float t = max(1.0 - amount * 0.75 * density, 0.45);
        g = max((g - airlight) / t + airlight, float3(0.0));
    } else {
        g = mix(g, float3(airlight), -amount * 0.5 * (0.35 + 0.65 * density));
    }
    return premultiply(float4(pow(g, float3(2.2)), p.a));
}

/// Lightroom's post-crop vignette. frame: centre and half size; shape:
/// roundness, inner and outer distance; tone: signed strength, style
/// (1 highlight priority, 2 colour priority, 3 paint overlay), highlights.
float4 postCropVignette(sampler src, float4 frame, float4 shape, float4 tone, destination dest) {
    float4 p = unpremultiply(src.sample(src.coord()));
    float2 d = (dest.coord() - frame.xy) / frame.zw;
    float r = shape.x;
    float dist;
    if (r >= 0.0) {
        d.x *= mix(1.0, frame.z / frame.w, r);
        dist = length(d);
    } else {
        float e = 2.0 - r * 8.0;
        dist = pow(pow(abs(d.x), e) + pow(abs(d.y), e), 1.0 / e) * 1.41421356;
    }
    float amount = abs(tone.x) * smoothstep(shape.y, shape.z, dist);
    float3 c = p.rgb;
    if (tone.y > 2.5) {
        c = mix(c, float3(tone.x < 0.0 ? 0.0 : 1.0), amount);
    } else if (tone.x < 0.0) {
        float k = 1.0 - amount;
        if (tone.y < 1.5) {
            float l = pow(clamp(dot(c, luminanceWeights), 0.0, 1.0), 0.4545);
            k = mix(k, 1.0, smoothstep(0.45, 1.0, l) * (0.4 + 0.6 * tone.z));
        }
        c *= k;
    } else {
        c = max(c, c + (1.0 - c) * amount);
    }
    return premultiply(float4(c, p.a));
}

/// Monochrome grain, strongest in the midtones; roughness mixes in a
/// coarser noise layer.
float4 filmGrain(sample_t pixel, sample_t fine, sample_t coarse, float amplitude, float roughness) {
    float4 p = unpremultiply(pixel);
    float n = (fine.r - 0.5) * (1.0 - 0.5 * roughness) + (coarse.r - 0.5) * 0.9 * roughness;
    float l = pow(clamp(dot(p.rgb, luminanceWeights), 0.0, 1.0), 0.4545);
    float weight = 0.35 + 2.6 * l * (1.0 - l);
    p.rgb += float3(2.0 * amplitude * weight * n);
    return premultiply(p);
}

}
}
