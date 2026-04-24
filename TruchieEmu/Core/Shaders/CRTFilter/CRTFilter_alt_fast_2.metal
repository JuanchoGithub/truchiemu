#include "internal/ShaderTypes.h.metal"
#include <metal_stdlib>
using namespace metal;

struct CRTUniforms {
  float scanlineIntensity;
  float barrelAmount;
  float colorBoost;
  float time;
  float bleedAmount;
  float texSizeX;
  float texSizeY;
  float padding;
};

vertex VertexOut vertexPassthrough(uint id [[vertex_id]]) {
  // Using a constant array is fine, but for extreme perf,
  // these can be passed via a vertex buffer.
  const float2 positions[4] = {{-1, -1}, {1, -1}, {-1, 1}, {1, 1}};
  const float2 uvs[4] = {{0, 1}, {1, 1}, {0, 0}, {1, 0}};
  VertexOut out;
  out.position = float4(positions[id], 0, 1);
  out.texCoord = uvs[id];
  return out;
}

fragment float4 fragmentCRT(VertexOut in [[stage_in]],
                            texture2d<float> tex [[texture(0)]],
                            constant CRTUniforms &u [[buffer(0)]]) {
  constexpr sampler s(filter::linear, address::clamp_to_edge);

  float2 uv = in.texCoord;

  // 1. Barrel Distortion (Branchless)
  float2 centered = uv * 2.0 - 1.0;
  float2 offset = centered * centered;
  float2 distortedUV = centered + (centered * (offset.yx * u.barrelAmount));
  distortedUV = distortedUV * 0.5 + 0.5;

  float2 boundsMask =
      step(distortedUV, float2(1.0)) * step(float2(0.0), distortedUV);
  float visibility = boundsMask.x * boundsMask.y;

  // 2. DUAL-PATH SAMPLING (The Secret Sauce)
  // Path A: The "Sharp" path (1 sample) for structure/detail.
  // Path B: The "Bleed" path (3-5 samples) for color softness.

  float4 sharpColor = tex.sample(s, distortedUV);

  // We only use a smaller spread for the bleed to prevent total loss of detail
  float spread = 0.0025;
  float4 bleedColor = tex.sample(s, distortedUV);
  bleedColor += tex.sample(s, distortedUV - float2(spread, 0));
  bleedColor += tex.sample(s, distortedUV + float2(spread, 0));
  bleedColor *= 0.333; // Average them

  // 3. LUMINANCE-BASED BLENDING
  // We calculate the brightness (Luminance) of the sharp image.
  // Standard Rec.709 coefficients for luminance.
  float luminance = dot(sharpColor.rgb, float3(0.2126, 0.7152, 0.0722));

  // We blend the sharp color and the bleed color.
  // To keep it from being "too blurry", we make the bleed more
  // prominent in dark areas and keep it subtle in bright areas.
  // This mimics how phosphors glow/bleed in the dark.
  float3 finalRGB = mix(sharpColor.rgb, bleedColor.rgb, 5 * 0.6);

  // CRITICAL: We re-inject some of the sharp luminance to maintain "edge"
  // This prevents the "smearing" of high-contrast edges.
  finalRGB = mix(finalRGB, sharpColor.rgb, 0.5);
  // Actually, an even better way:
  finalRGB = mix(finalRGB, sharpColor.rgb,
                 luminance); // More luminance = more sharpness

  // 4. APPLY COLOR BOOST
  finalRGB *= u.colorBoost * 2;

  // 5. SCANLINES (Sharper, more surgical)
  // Instead of a heavy sine, we use a very fine-grained adjustment.
  // Using a higher frequency makes them look like "shadow masks" rather than
  // "black bars".
  float scanline = sin(in.position.y * 70) * 0.5 + 0.5;
  finalRGB *= mix(1.0, 1.0 - u.scanlineIntensity, pow(scanline, 3.0));

  // 6. VERTICAL APERTURE (Grill)
  float grill = smoothstep(0.0, 1.0, sin(in.position.x * 3.14159));
  finalRGB *= mix(1.0, 1.0 - (u.scanlineIntensity * 70), grill);

  return float4(finalRGB * visibility, 1.0);
}