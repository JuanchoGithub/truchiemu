#include "internal/ShaderTypes.h.metal"
#include <metal_stdlib>
using namespace metal;

// This structure is now 48 bytes (3 * 16 bytes), which is perfectly aligned.
struct CRTUniforms {
  float scanlineIntensity; // 4
  float barrelAmount;      // 4
  float colorBoost;        // 4
  float time;              // 4
  float bleedAmount;       // 4
  float texSizeX;          // 4
  float texSizeY;          // 4
  float padding;           // 4 (Total 32)
};

// --- Helper for Horizontal Bleed ---
float4 getBleedingColor(texture2d<float> tex, sampler s, float2 uv,
                        float2 texSize, float bleedAmount) {
  float dx = 1.0 / texSize.x;

  // Always sample the center purely from the original UV to prevent doubling
  // the main image
  float4 center = tex.sample(s, uv);

  if (bleedAmount <= 0.0)
    return center;

  // Apply NTSC dot crawl jitter ONLY to the surrounding taps for bleeding
  // The frequency `500.0` is an arbitrary choice to simulate phase,
  // you can adjust it for a different "crawl" look, e.g., `uv.y * 300.0`
  float jitterAmount =
      sin(uv.y * 500.0) * 0.25; // 0.25 is a good balance for subtle jitter

  float4 left =
      tex.sample(s, uv - float2(dx + jitterAmount * dx, 0)); // Shift left more
  float4 right =
      tex.sample(s, uv + float2(dx - jitterAmount * dx, 0)); // Shift right less

  // Add more taps for a wider, softer bleed
  float4 left2 = tex.sample(s, uv - float2(dx * 2.0 + jitterAmount * dx, 0));
  float4 right2 = tex.sample(s, uv + float2(dx * 2.0 - jitterAmount * dx, 0));

  // Weighted average for a smoother bleed
  float4 blurred = (left2 * 0.1) + (left * 0.2) + (center * 0.4) +
                   (right * 0.2) + (right2 * 0.1);

  return mix(center, blurred, bleedAmount);
}

vertex VertexOut vertexPassthrough(uint id [[vertex_id]]) {
  float2 positions[4] = {{-1, -1}, {1, -1}, {-1, 1}, {1, 1}};
  float2 uvs[4] = {{0, 1}, {1, 1}, {0, 0}, {1, 0}};
  VertexOut out;
  out.position = float4(positions[id], 0, 1);
  out.texCoord = uvs[id];
  return out;
}

fragment float4 fragmentCRT(VertexOut in [[stage_in]],
                            texture2d<float> tex [[texture(0)]],
                            constant CRTUniforms &u [[buffer(0)]]) {
  constexpr sampler s(filter::nearest, address::clamp_to_edge);
  float2 uv = in.texCoord;
  float2 texSize = float2(u.texSizeX, u.texSizeY);

  // --- CRT barrel distortion ---
  if (u.barrelAmount > 0.001) {
    float2 centered = uv * 2.0 - 1.0;
    float2 offset = centered * centered;
    centered += centered * (offset.yx * u.barrelAmount);
    uv = centered * 0.5 + 0.5;

    if (uv.x < 0.0 || uv.x > 1.0 || uv.y < 0.0 || uv.y > 1.0) {
      return float4(0, 0, 0, 1);
    }
  }

  // 1. RAW PIXEL DATA
  // No manual RGB shifting! The "bleed" will handle the color blending.
  float dx = 1.0 / texSize.x;
  float4 center = tex.sample(s, uv);
  float4 left = tex.sample(s, uv - float2(dx, 0));
  float4 right = tex.sample(s, uv + float2(dx, 0));

  // Simple 3-tap horizontal blend (The "Genesis Blur")
  // This blend is what naturally mixes the dithered colors together.
  // Change the 0.25 to 0.5 to make the bleed stronger.
  float4 color = (left * 0.25) + (center * 0.5) + (right * 0.25);
  color.rgb *= u.colorBoost;

  // -- Horizontal SCANLINES --
  // The 3.5 divison in the sin() controls the thickness of the scanlines
  // (higher = thicker) the 0.3 in the multiplication controls the intensity of
  // the scanlines. The 0.5 in the multiplication controls the brightness of the
  // scanlines.
  float scanLine = sin(in.position.y * 3.14159 / 3.5) * 0.5 + 0.5;
  color.rgb *= (1.0 - (u.scanlineIntensity * scanLine * 0.3));
  // --- Vertical Scanlines / Aperture Grill ---
  // ALTERNATIVE 1 - Adjust the '4.0' to make the grill thinner or wider.
  // float grill = sin(in.position.x * 3.14159 * 0.5) * 0.5 + 0.5;
  // ALTERNATIVE 2- Pixel-snapped vertical grill
  float grill = step(0.5, sin(in.position.x * 3.14159));

  // Apply a subtle darkening to the vertical columns
  color.rgb *= (1.0 - (u.scanlineIntensity * 0.5 * grill));

  // 3. PHOSPHOR MASK (Keep it very subtle so it doesn't look like a colored
  // screen)
  // Change the 0.08 to 0.5 to make the mask stronger.
  int m = int(in.position.x) % 2;
  float3 mask = (m == 0)   ? float3(1.0, 0.95, 0.95)
                : (m == 1) ? float3(0.95, 1.0, 0.95)
                           : float3(0.95, 0.95, 1.0);
  color.rgb *= mix(float3(1.0), mask, 0.5);

  color.a = 1.0;
  return color;
}