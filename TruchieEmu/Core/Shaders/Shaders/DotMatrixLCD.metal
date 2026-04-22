#include <metal_stdlib>
#include "internal/ShaderTypes.h.metal"
using namespace metal;

struct DotMatrixLCDUniforms {
    float dotOpacity;        // Usaremos esto para la fuerza de la rejilla LCD
    float metallicIntensity; // Reflejo de la pantalla TFT
    float specularShininess; // Control de Gamma/Saturación
    float colorBoost;        // Brillo general
    float4 sourceSize;
    float4 outputSize;
};

fragment float4 fragmentDotMatrixLCD(VertexOut in [[stage_in]],
                                       texture2d<float> tex [[texture(0)]],
                                       constant DotMatrixLCDUniforms &u [[buffer(0)]]) {
    
    constexpr sampler s(filter::linear, address::clamp_to_edge);
    float2 uv = in.texCoord;
    
    // 1. DIMENSIONES FÍSICAS (GBC 160x144)
    float2 gameRes = float2(160.0, 144.0);
    float2 pixelPos = uv * gameRes;
    float2 snappedGb = floor(pixelPos);
    float2 f = fract(pixelPos);
    
    // 2. CORRECCIÓN DE COLOR GBC (TFT Simulation)
    // El GBC tiene una curva de color extraña: los colores puros son muy brillantes.
    float4 rawColor = tex.sample(s, uv);
    float3 color = rawColor.rgb;
    
    // Simular el "Color Washout" de la pantalla reflectiva
    // Elevamos a potencia para ajustar el gamma y desaturamos levemente
    color = pow(color, 1.2); 
    
    // Matriz de transformación para imitar el gamut del GBC (colores cruzados)
    float3 gbcColor;
    gbcColor.r = dot(color, float3(0.85, 0.10, 0.05));
    gbcColor.g = dot(color, float3(0.05, 0.80, 0.15));
    gbcColor.b = dot(color, float3(0.10, 0.15, 0.75));
    color = mix(color, gbcColor, 0.7); // Mezclamos con el perfil de color

    // 3. REJILLA LCD (Píxeles GBC)
    // En GBC los píxeles son casi cuadrados con una separación mínima
    float2 grid = smoothstep(0.0, 0.08, f) * smoothstep(1.0, 0.92, f);
    float gridVal = grid.x * grid.y;
    
    // Aplicamos la rejilla oscureciendo suavemente los bordes del píxel
    float3 final = color * mix(1.0, gridVal, u.dotOpacity * 0.5);

    // 4. REFLECTIVIDAD TFT (Metallic/Specular)
    // A diferencia del DMG verde, el GBC es como un espejo oscuro cuando está apagado.
    float2 lightPos = float2(0.8, 0.2); // Simulamos una lámpara arriba a la derecha
    float distToLight = length(uv - lightPos);
    
    // Reflejo metálico sutil en el fondo de la celda
    float sheen = sin(uv.x * 10.0 - uv.y * 5.0) * 0.5 + 0.5;
    float glare = exp(-distToLight * 4.0) * u.metallicIntensity;
    
    // Añadimos el "tint" de pantalla apagada (un gris azulado/violeta profundo)
    float3 screenTint = float3(0.08, 0.08, 0.12);
    final = mix(screenTint, final, 0.95);
    
    // Aplicar el brillo y el glare
    final += (glare * 0.15) * float3(0.9, 0.9, 1.0);
    
    // 5. POST-PROCESO FINAL
    // El "specularShininess" lo reusamos para el contraste final
    final = mix(float3(0.5), final, u.specularShininess); 
    
    final *= u.colorBoost;
    
    return float4(saturate(final), 1.0);
}