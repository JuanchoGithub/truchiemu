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
  constexpr sampler s(filter::linear, address::clamp_to_edge);

  // --- [ MASTER FEATURE FLAGS - ALL RESTORED ] ---
  const bool USE_BARREL_DISTORT   = true;
  const bool USE_SCANLINES        = true;
  const bool USE_DITHER_BLEED     = true;
  const bool USE_CHROMA_SHIFT     = true;
  const bool USE_BEAM_BLOOM       = true; 
  const bool USE_RADIAL_SOFT      = true; 
  const bool USE_WHITE_BALANCE    = true; 
  const bool USE_VIGNETTE         = true;
  const bool USE_FLICKER          = true;
  const bool USE_BEZEL_REFLECTION = true;
  const bool USE_CORNER_ROUNDING  = true;

  // --- [ ANALOG PARAMETERS ] ---
  const float BLOOM_STRENGTH     = 1.3;
  const float CORNER_ROUNDING_V  = 0.04; 
  const float3 TINT_D65          = float3(0.96, 1.04, 0.95);
  const float JITTER_FREQ        = 60.0;
  const float JITTER_AMOUNT      = 0.00015;
  const float CHROMA_SHIFT_VAL   = 0.0012;
  const float VIG_STRENGTH       = 0.45;
  const float VIG_POWER          = 1.5;
  const float FLICKER_STR        = 0.005;
  const float GLOW_SOURCE_PIXELS = 32.0;
  const float GLOW_INTENSITY     = 0.35;

  // --- [ 1. GEOMETRY ENGINE ] ---
  float2 screenUV = in.texCoord;
  float2 centered = (screenUV - float2(0.5, 0.52)) * 2.0;
  centered.x *= 1.06; 
  centered.y *= 1.08; 

  // --- [ 2. BARREL DISTORTION ] ---
  float2 distortedUV = screenUV;
  if (USE_BARREL_DISTORT) {
    float2 offset = centered * centered;
    distortedUV = centered + (centered * (offset.yx * u.barrelAmount));
    distortedUV = distortedUV * 0.5 + 0.5;
  }

  // --- [ 3. VERTICAL ZOOM ] ---
  float vTrim = 8.0 / 240.0;
  float2 sampleUV = distortedUV;
  sampleUV.y = mix(vTrim, 1.0 - vTrim, distortedUV.y);

  // --- [ 4. JITTER ] ---
  float2 outputRes = float2(4096, 2160);
  float jitter = sin(in.position.y * 0.1 + u.time * JITTER_FREQ) * JITTER_AMOUNT;
  sampleUV.x += floor(jitter * outputRes.x) / outputRes.x;

  // --- [ 5. COLOR SAMPLING ] ---
  float dist = length(centered);
  float pixelShift = floor((CHROMA_SHIFT_VAL * dist) * outputRes.x) / outputRes.x;
  
  float4 sharpColor;
  if (USE_RADIAL_SOFT) {
    // Optimization: using (dist*dist*dist) instead of pow(dist, 3.0)
    float blurAmount = (dist * dist * dist) * 0.0008;
    sharpColor.g = (tex.sample(s, sampleUV).g + tex.sample(s, sampleUV + float2(blurAmount)).g) * 0.5;
    sharpColor.r = tex.sample(s, sampleUV + float2(pixelShift, 0)).r;
    sharpColor.b = tex.sample(s, sampleUV - float2(pixelShift, 0)).b;
  } else {
    sharpColor.g = tex.sample(s, sampleUV).g;
    sharpColor.r = tex.sample(s, sampleUV + (USE_CHROMA_SHIFT ? float2(pixelShift, 0) : 0)).r;
    sharpColor.b = tex.sample(s, sampleUV - (USE_CHROMA_SHIFT ? float2(pixelShift, 0) : 0)).b;
  }
  sharpColor.a = 1.0;

  // --- [ 6. DITHER BLEED ] ---
  float2 sourceRes = float2(u.texSizeX, u.texSizeY);
  float3 bleedResult = sharpColor.rgb;
  if (USE_DITHER_BLEED) {
    float spread = 1.0 / u.texSizeX;
    bleedResult = (sharpColor.rgb + tex.sample(s, sampleUV - float2(spread, 0)).rgb + tex.sample(s, sampleUV + float2(spread, 0)).rgb) * 0.333;
  }

  // --- [ 7. MIXING ] ---
  float luma = dot(sharpColor.rgb, float3(0.2126, 0.7152, 0.0722));
  float3 finalRGB = mix(sharpColor.rgb, bleedResult, 3.0);
  finalRGB = mix(finalRGB, sharpColor.rgb, 0.5 + (luma * 0.5));

  // --- [ 8. ANALOG FINISHING ] ---
  finalRGB *= u.colorBoost * 1.1;
  if (USE_WHITE_BALANCE) finalRGB *= TINT_D65;
  if (USE_VIGNETTE) finalRGB *= clamp(1.0 - dot(centered * VIG_STRENGTH, centered * VIG_STRENGTH), 0.0, 1.0);
  if (USE_FLICKER) finalRGB *= (sin(u.time * 60.0) * FLICKER_STR) + (1.0 - FLICKER_STR);

  // --- [ 9. SCANLINES ] ---
  if (USE_SCANLINES) {
    float scanline = sin(in.position.y * 70.0) * 0.5 + 0.5;
    float intensity = u.scanlineIntensity;
    if (USE_BEAM_BLOOM) {
       float l1 = dot(tex.sample(s, sampleUV + (1.5/sourceRes)).rgb, float3(0.2126, 0.7152, 0.0722));
       intensity = mix(u.scanlineIntensity, 0.0, saturate(l1 * BLOOM_STRENGTH));
    }
    // Optimization: p*p*p instead of pow(p, 3.0)
    float scanPow = scanline * scanline * scanline;
    finalRGB *= mix(1.0, 1.0 - intensity, scanPow);
  }
  finalRGB *= mix(1.0, 1.0, smoothstep(0.0, 1.0, sin(in.position.x * 3.14159)));

  // --- [ 11. MASKING (Performance version) ] ---
  float2 maskEdge = abs(distortedUV - 0.5) * 2.0;
  float2 m2 = maskEdge * maskEdge;
  float2 m4 = m2 * m2;
  float2 m8 = m4 * m4;
  float cornerMask = (m8.x * m4.x) + (m8.y * m4.y); 
  
  float tubeVisibility = 1.0 - smoothstep(1.0, 1.0 + CORNER_ROUNDING_V, cornerMask);
  if (distortedUV.x < 0.0 || distortedUV.x > 1.0 || distortedUV.y < 0.0 || distortedUV.y > 1.0) tubeVisibility = 0.0;

  float3 screenOutput = finalRGB * tubeVisibility;

  // --- [ 12. BEZEL REFLECTION ] ---
  if (USE_BEZEL_REFLECTION) {
    float splay = GLOW_SOURCE_PIXELS / u.texSizeX;
    float bezelWeight = (1.0 - tubeVisibility) * (1.0 - smoothstep(1.0, 1.0 + splay, max(maskEdge.x, maskEdge.y)));
    if (bezelWeight > 0.001) {
      float2 mirrorUV = 1.0 - abs(1.0 - abs(sampleUV)); 
      screenOutput += tex.sample(s, mix(mirrorUV, sampleUV, 0.08)).rgb * u.colorBoost * bezelWeight * GLOW_INTENSITY;
    }
  }

  return float4(saturate(screenOutput), 1.0);
}