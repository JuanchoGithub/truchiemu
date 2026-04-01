#include <metal_stdlib>
#include "internal/ShaderTypes.h.metal"
using namespace metal;

// ============================================================
// Master shader file - includes all fragment shaders
// This ensures all shaders are compiled into a single library
// ============================================================

// ============================================================
// Passthrough Shader
// ============================================================
fragment float4 fragmentPassthrough(VertexOut in [[stage_in]],
                                     texture2d<float> tex [[texture(0)]]) {
    constexpr sampler s(filter::nearest, address::clamp_to_edge, mip_filter::none);
    float4 color = tex.sample(s, in.texCoord);
    color.a = 1.0;
    return color;
}

// ============================================================
// CRT + Scanline fragment shader
// ============================================================
struct CRTUniforms {
    int   crtEnabled;
    int   scanlinesEnabled;
    int   barrelEnabled;
    int   phosphorEnabled;
    float scanlineIntensity;
    float barrelAmount;
    float colorBoost;
    float time;
};

fragment float4 fragmentCRT(VertexOut in [[stage_in]],
                             texture2d<float> tex [[texture(0)]],
                             constant CRTUniforms &u [[buffer(0)]]) {
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
        float vig = 1.0 - dot(centered * 0.4, centered * 0.4);
        vig = clamp(pow(vig, 1.5), 0.0, 1.0);
        
        float shift = 0.002;
        float r = tex.sample(s, uv + float2(shift, 0)).r;
        float b = tex.sample(s, uv - float2(shift, 0)).b;
        color.r = r;
        color.b = b;

        float glow = (color.r + color.g + color.b) / 3.0;
        color.rgb += glow * 0.08;
        color.rgb *= vig;
    }

    if (u.phosphorEnabled) {
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

// ============================================================
// LCD Grid Shader
// ============================================================
struct LCDGridUniforms {
    float gridOpacity;
    float ghostingAmount;
    float gridSize;
    float colorBoost;
    float time;
    float4 SourceSize;
    float4 OutputSize;
};

fragment float4 fragmentLCDGrid(VertexOut in [[stage_in]],
                                 texture2d<float> tex [[texture(0)]],
                                 constant LCDGridUniforms &u [[buffer(0)]]) {
    constexpr sampler s(filter::nearest, address::clamp_to_edge);
    float2 uv = in.texCoord;
    float4 color = tex.sample(s, uv);
    
    if (u.ghostingAmount > 0.0) {
        float ghostUV = 0.002 * u.ghostingAmount;
        float4 ghost1 = tex.sample(s, uv - float2(ghostUV, 0.0));
        float4 ghost2 = tex.sample(s, uv + float2(0.0, ghostUV));
        float4 ghost3 = tex.sample(s, uv - float2(ghostUV, ghostUV));
        color = mix(color, (color + ghost1 + ghost2 + ghost3) / 4.0, u.ghostingAmount);
    }
    
    color.rgb *= u.colorBoost;
    
    if (u.gridOpacity > 0.0) {
        float2 gridUV = in.position.xy / u.gridSize;
        float2 gridCell = fract(gridUV);
        float2 gridLine = smoothstep(0.0, 0.05, gridCell) * smoothstep(1.0, 0.95, gridCell);
        float gridMask = gridLine.x * gridLine.y;
        float3 gridColor = float3(gridMask);
        color.rgb = mix(color.rgb, color.rgb * gridColor, u.gridOpacity);
        float reflection = sin(in.position.y * 0.1) * 0.02;
        color.rgb += reflection;
    }
    
    color.rgb = saturate(color.rgb);
    color.a = 1.0;
    return color;
}

// ============================================================
// Vibrant LCD Shader
// ============================================================
struct VibrantLCDUniforms {
    float saturation;
    float gamma;
    float colorBoost;
    float4 SourceSize;
    float4 OutputSize;
};

fragment float4 fragmentVibrantLCD(VertexOut in [[stage_in]],
                                    texture2d<float> tex [[texture(0)]],
                                    constant VibrantLCDUniforms &u [[buffer(0)]]) {
    constexpr sampler s(filter::linear, address::clamp_to_edge);
    float4 color = tex.sample(s, in.texCoord);
    
    color.rgb *= u.colorBoost;
    
    // Gamma correction
    color.rgb = pow(color.rgb, float3(1.0 / u.gamma));
    
    // Saturation boost
    float gray = dot(color.rgb, float3(0.299, 0.587, 0.114));
    color.rgb = mix(float3(gray), color.rgb, u.saturation);
    
    // LCD pixel grid effect
    float2 px = in.position.xy;
    float2 gridUV = fract(px * 0.5);
    float gridX = step(0.5, gridUV.x);
    float gridY = step(0.5, gridUV.y);
    float grid = gridX * gridY;
    color.rgb *= 0.95 + 0.05 * grid;
    
    color.a = 1.0;
    return color;
}

// ============================================================
// Edge Smoothing Shader
// ============================================================
struct EdgeSmoothUniforms {
    float smoothStrength;
    float colorBoost;
    float4 SourceSize;
    float4 OutputSize;
};

fragment float4 fragmentEdgeSmooth(VertexOut in [[stage_in]],
                                    texture2d<float> tex [[texture(0)]],
                                    constant EdgeSmoothUniforms &u [[buffer(0)]]) {
    constexpr sampler s(filter::linear, address::clamp_to_edge);
    float2 uv = in.texCoord;
    float2 px = u.SourceSize.zw;
    
    float4 c = tex.sample(s, uv);
    float4 t = tex.sample(s, uv + float2(0.0, -px.y));
    float4 b = tex.sample(s, uv + float2(0.0, px.y));
    float4 l = tex.sample(s, uv + float2(-px.x, 0.0));
    float4 r = tex.sample(s, uv + float2(px.x, 0.0));
    
    float tl = length(t.rgb - l.rgb);
    float br = length(b.rgb - r.rgb);
    float tr = length(t.rgb - r.rgb);
    float bl = length(b.rgb - l.rgb);
    
    float minDiff = min(tl, min(br, min(tr, bl)));
    float smoothFactor = smoothstep(0.1, 0.3, minDiff) * u.smoothStrength;
    
    float4 avg = (c + t + b + l + r) * 0.2;
    float4 color = mix(c, avg, smoothFactor);
    
    color.rgb *= u.colorBoost;
    color.a = 1.0;
    return color;
}

// ============================================================
// Composite / VHS Shader
// ============================================================
struct CompositeUniforms {
    float horizontalBlur;
    float verticalBlur;
    float bleedAmount;
    float colorBoost;
    float4 SourceSize;
    float4 OutputSize;
};

fragment float4 fragmentComposite(VertexOut in [[stage_in]],
                                   texture2d<float> tex [[texture(0)]],
                                   constant CompositeUniforms &u [[buffer(0)]]) {
    constexpr sampler s(filter::linear, address::clamp_to_edge);
    float2 uv = in.texCoord;
    float2 px = u.SourceSize.zw;
    
    float4 color = tex.sample(s, uv);
    
    // Horizontal color bleeding
    float hStep = px.x * u.horizontalBlur;
    float4 left = tex.sample(s, uv - float2(hStep, 0.0));
    float4 right = tex.sample(s, uv + float2(hStep, 0.0));
    color = (color * 2.0 + left + right) * 0.25;
    
    // Vertical bleed
    if (u.bleedAmount > 0.0) {
        float vStep = px.y * u.bleedAmount;
        float4 above = tex.sample(s, uv - float2(0.0, vStep));
        float4 below = tex.sample(s, uv + float2(0.0, vStep));
        color.rgb = mix(color.rgb, (color.rgb + above.rgb + below.rgb) / 3.0, u.bleedAmount);
    }
    
    color.rgb *= u.colorBoost;
    color.a = 1.0;
    return color;
}