#ifndef ShaderTypes_h
#define ShaderTypes_h

#include <metal_stdlib>
using namespace metal;

// MARK: - Common Structures (shared across all shaders)

struct VertexOut {
    float4 position [[position]];
    float2 texCoord;
};

#endif /* ShaderTypes_h */