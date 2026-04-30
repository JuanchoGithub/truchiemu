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
  // CRITICAL: We use linear filtering.
  // This is the ONLY way to avoid the jagged "left image" look.
  constexpr sampler s(filter::linear, address::clamp_to_edge);

  float2 uv = in.texCoord;

  // 1. Barrel Distortion
  if (u.barrelAmount > 0.001) {
    float2 centered = uv * 2.0 - 1.0;
    float2 offset = centered * centered;
    centered += centered * (offset.yx * u.barrelAmount);
    uv = centered * 0.5 + 0.5;

    // Fast bounds check
    if (uv.x < 0.0 || uv.x > 1.0 || uv.y < 0.0 || uv.y > 1.0)
      return float4(0, 0, 0, 1);
  }

  // 2. THE SMOOTHING ENGINE (The "Right Image" Fix)
  // To get the right image, we must sample in a way that forces the
  // GPU to interpolate between texels.

  float4 color;

  // We calculate a 'spread' based on the texture size.
  // If the image is jagged, increase the multiplier (e.g., 1.5)
  float spread = 0.0025; // 1 * (0.5 / u.texSizeX);

  // We take 3 samples, but because the sampler is LINEAR,
  // these samples will 'blend' the pixels together smoothly.
  float4 c = tex.sample(s, uv);
  float4 l = tex.sample(s, uv - float2(spread, 0));
  float4 r = tex.sample(s, uv + float2(spread, 0));

  // This blend creates the "soft" look of the right image.
  // We use a higher weight for the center to keep detail,
  // but the 'l' and 'r' provide the smooth bleed.
  color = (c * 0.5) + (l * 0.25) + (r * 0.25);

  // Apply color boost
  color.rgb *= u.colorBoost;

  // 3. SCANLINES (Must be fine-tuned)
  // If scanlines are too thick, it looks jagged.
  // We use in.position.y (screen space) for consistent lines.
  // We use a high-frequency sine wave.
  float scanLine = sin(in.position.y * 1.5) * 0.5 + 0.5;
  color.rgb *= (1.0 - (u.scanlineIntensity * scanLine * 0.3));

  // 4. VERTICAL APERTURE (The "Grill")
  // This creates the vertical texture seen in the right image.
  float grill = step(0.0, sin(in.position.x * 3.14159));
  color.rgb *= (1.0 - (u.scanlineIntensity * 0.2 * grill));

  // 5. PHOSPHOR MASK (Very subtle)
  // On M-series, we want to avoid heavy math here.
  // This adds a tiny bit of "texture" to the pixels.
  float mask = sin(in.position.x * 10.0) * 0.5 + 0.5;
  color.rgb *= mix(float3(1.0), float3(0.9, 0.95, 1.0), mask * 0.1);

  return float4(color.rgb, 1.0);
}