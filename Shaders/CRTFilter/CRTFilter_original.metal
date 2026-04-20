#include <metal_stdlib>
#include "internal/ShaderTypes.h.metal"
using namespace metal;

// MARK: - Vertex shader (shared by all shaders in the default library)
vertex VertexOut vertexPassthrough(uint id [[vertex_id]]) {
    float2 positions[4] = { {-1, -1}, {1, -1}, {-1, 1}, {1, 1} };
    float2 uvs[4]       = { {0, 1},   {1, 1},  {0, 0},  {1, 0} };
    VertexOut out;
    out.position = float4(positions[id], 0, 1);
    out.texCoord = uvs[id];
    return out;
}

// MARK: - CRT + Scanline fragment shader
struct CRTUniforms {
    float scanlineIntensity;  // 0.0 - 1.0: scanline strength (0 = off)
    float barrelAmount;       // 0.0 - 0.5: barrel distortion (0 = off)
    float colorBoost;         // 0.5 - 2.0: brightness multiplier
    float time;               // Frame time for animated effects
};

fragment float4 fragmentCRT(VertexOut in [[stage_in]],
                             texture2d<float> tex [[texture(0)]],
                             constant CRTUniforms &u [[buffer(0)]]) {
    constexpr sampler s(filter::linear, address::clamp_to_edge);
    float2 uv = in.texCoord;

    // --- CRT barrel distortion (enabled when barrelAmount > 0) ---
    if (u.barrelAmount > 0.001) {
        float2 centered = uv * 2.0 - 1.0;
        float2 offset   = centered * centered;
        centered += centered * (offset.yx * u.barrelAmount);
        uv = centered * 0.5 + 0.5;

        if (uv.x < 0.0 || uv.x > 1.0 || uv.y < 0.0 || uv.y > 1.0) {
            return float4(0, 0, 0, 1);
        }
    }

    float4 color = tex.sample(s, uv);
    color.rgb *= u.colorBoost;

    // --- CRT effects (vignette, fringing, phosphor glow) ---
    {
        float2 centered = uv * 2.0 - 1.0;
        // Vignette
        float vig = 1.0 - dot(centered * 0.4, centered * 0.4);
        vig = clamp(pow(vig, 1.5), 0.0, 1.0);
        
        // RGB channel fringing
        float shift = 0.002;
        float r = tex.sample(s, uv + float2(shift, 0)).r;
        float b = tex.sample(s, uv - float2(shift, 0)).b;
        color.r = r;
        color.b = b;

        // Phosphor glow
        float glow = (color.r + color.g + color.b) / 3.0;
        color.rgb += glow * 0.08;

        color.rgb *= vig;
    }

    // --- Phosphor mask ---
    {
        float3 mask = float3(1.0);
        int m = int(in.position.x) % 3;
        if (m == 0)      mask = float3(1.0, 0.75, 0.75);
        else if (m == 1) mask = float3(0.75, 1.0, 0.75);
        else             mask = float3(0.75, 0.75, 1.0);
        color.rgb *= mask;
    }

    // --- Scanlines (enabled when scanlineIntensity > 0) ---
    if (u.scanlineIntensity > 0.001) {
        float scanLine = sin(uv.y * 800.0) * 0.5 + 0.5;
        color.rgb *= 1.0 - u.scanlineIntensity * scanLine;
    }
    
    color.a = 1.0;
    return color;
}