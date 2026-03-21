#include <metal_stdlib>
using namespace metal;

// MARK: - Uniforms
struct Uniforms {
    int   crtEnabled;
    int   scanlinesEnabled;
    int   barrelEnabled;
    int   phosphorEnabled;
    float scanlineIntensity;
    float barrelAmount;
    float colorBoost;
    float time;
};

// MARK: - Passthrough vertex shader
struct VertexOut {
    float4 position [[position]];
    float2 texCoord;
};

vertex VertexOut vertexPassthrough(uint id [[vertex_id]]) {
    // Full-screen quad
    float2 positions[4] = { {-1, -1}, {1, -1}, {-1, 1}, {1, 1} };
    float2 uvs[4]       = { {0, 1},   {1, 1},  {0, 0},  {1, 0} };
    VertexOut out;
    out.position = float4(positions[id], 0, 1);
    out.texCoord = uvs[id];
    return out;
}

// MARK: - CRT + Scanline fragment shader
fragment float4 fragmentCRT(VertexOut in [[stage_in]],
                             texture2d<float> tex [[texture(0)]],
                             constant Uniforms &u [[buffer(0)]]) {
    constexpr sampler s(filter::linear, address::clamp_to_edge);
    float2 uv = in.texCoord;

    // --- CRT barrel distortion ---
    if (u.barrelEnabled) {
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

    if (u.crtEnabled) {
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

    if (u.phosphorEnabled) {
        // Use screen-space pixel coordinates for a perfectly aligned phosphor mask
        float3 mask = float3(1.0);
        int m = int(in.position.x) % 3;
        if (m == 0)      mask = float3(1.0, 0.75, 0.75);
        else if (m == 1) mask = float3(0.75, 1.0, 0.75);
        else             mask = float3(0.75, 0.75, 1.0);
        color.rgb *= mask;
    }

    if (u.scanlinesEnabled) {
        float scanLine = sin(uv.y * 800.0) * 0.5 + 0.5;
        color.rgb *= 1.0 - u.scanlineIntensity * scanLine;
    }
    
    color.a = 1.0;
    return color;
}
