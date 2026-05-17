#include <metal_stdlib>
#include "internal/ShaderTypes.h.metal"
using namespace metal;

struct PSPUniforms {
    float dotOpacity;
    float specularShininess;
    float colorBoost;
    float ghostingWeight;
    float physicalDepth;
    uint frameIndex;
    float4 sourceSize;
    float4 outputSize;
    float lightPositionIndex;
    float physicalLineWidth;
    float _pad0;
    float _pad1;
    float3x3 colorGamut;
};

fragment float4 fragmentPSPShader(VertexOut in [[stage_in]],
    texture2d<float> frame0 [[texture(0)]],
    texture2d<float> frame1 [[texture(1)]],
    texture2d<float> frame2 [[texture(2)]],
    constant PSPUniforms &u [[buffer(0)]]) {

    float2 uv = in.texCoord;
    float2 srcRes = u.sourceSize.xy;
    float2 screenRes = u.outputSize.xy;
    float2 scaleRatio = screenRes / srcRes;
    float2 pixelCoord = uv * srcRes;

    // 1. GRID LOGIC (uniform-driven line width)
    float thickness = (u.physicalLineWidth / scaleRatio.x) * 0.5;
    float2 fw = 1.0 / scaleRatio;

    // 2. SAMPLING & COLOR (uniform-driven gamut matrix)
    constexpr sampler s(coord::normalized, address::clamp_to_edge, filter::linear);
    float3 f0 = frame0.sample(s, uv).rgb;
    float3 f1 = frame1.sample(s, uv).rgb;
    float3 f2 = frame2.sample(s, uv).rgb;
    float3 ghostedColor = mix(f0, mix(f1, f2, 0.4), u.ghostingWeight);

    float3 screenColor = (ghostedColor * u.colorGamut) * u.colorBoost;

    // 3. OPTICAL BLEED (10% Opacity Target)
    float luma = dot(screenColor, float3(0.299, 0.587, 0.114));
    float gridAlpha = mix(1.0, 0.10, saturate(luma));

    // 4. THE GRID & SUBSTRATE
    float2 gridUV = abs(fract(pixelCoord) - 0.5);
    float2 gridEdge = 0.5 - thickness;
    float2 gridAA = smoothstep(gridEdge, gridEdge - fw, gridUV);
    float gapMask = gridAA.x * gridAA.y;

    const float3 panelColor = float3(0.10, 0.11, 0.12);
    float2 shadowOffset = (float2(0.5) / scaleRatio) * u.physicalDepth;
    float2 shadowUV = abs(fract(pixelCoord + shadowOffset) - 0.5);
    float2 shadowAA = smoothstep(gridEdge, gridEdge - fw, shadowUV);
    float shadowInt = mix(0.58, 1.0, shadowAA.x * shadowAA.y);
    float3 substrate = panelColor * mix(shadowInt, 1.0, saturate(luma * 1.5));

    // 5. METALLIC REFLECTION PORT
    float2 lightPos;
    int idx = int(u.lightPositionIndex);
    if (idx == 0) lightPos = float2(240.0, 0.0);
    else if (idx == 1) lightPos = float2(0.0, 0.0);
    else if (idx == 2) lightPos = float2(120.0, 0.0);
    else if (idx == 3) lightPos = float2(120.0, 80.0);
    else if (idx == 4) lightPos = float2(0.0, 80.0);
    else if (idx == 5) lightPos = float2(240.0, 80.0);
    else if (idx == 6) lightPos = float2(0.0, 160.0);
    else if (idx == 7) lightPos = float2(120.0, 160.0);
    else lightPos = float2(240.0, 160.0);

    float distToLight = length(pixelCoord - lightPos);

    float wave1 = sin(pixelCoord.x * 5.0 - pixelCoord.y * 2.5);
    float wave2 = sin(pixelCoord.x * 2.1 + pixelCoord.y * 4.8);
    float metallicGrain = (wave1 * wave2) * 0.5 + 0.5;

    float sheen = smoothstep(-150.0, 250.0, pixelCoord.x - pixelCoord.y);
    float glare = smoothstep(180.0, 0.0, distToLight);

    float reflectionMask = 1.0 - (luma * 0.5);
    float3 reflectionColor = float3(0.9, 0.95, 1.0);

    float3 reflectionEffect = (glare * 0.25 + sheen * 0.10 + metallicGrain * 0.02)
        * reflectionColor * reflectionMask * u.specularShininess;

    // 6. FINAL COMPOSITE
    float3 gapColor = mix(screenColor, substrate, gridAlpha);
    float3 activePixel = mix(gapColor, screenColor, gapMask);

    float3 finalRGB = mix(screenColor, activePixel, u.dotOpacity) + reflectionEffect;

    float noise = (fract(sin(dot(uv + float(u.frameIndex%60u)*0.01, float2(12.98, 78.23))) * 43758.54) - 0.5) * 0.002;

    return float4(finalRGB + noise, 1.0);
}
