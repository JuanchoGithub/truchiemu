#include <metal_stdlib>
using namespace metal;

// Glass-orb / fisheye lens refraction for SwiftUI `distortionEffect`.
// `destination` is the layer coordinate (points, top-left origin) provided
// automatically by SwiftUI. `size` is the layer size in points, `offset`
// shifts the lens center (driven by the pointer for a live, cursor-following
// bulge), and `refraction` controls bulge strength (>1 magnifies).
//
// The lens acts as a magnifier: every point inside the orb samples the art
// *closer* to the lens center than the destination point (so the orb always
// shows a magnified, warped view — never a flat 1x patch that matches the
// background). Magnification is strongest at the center and eases slightly
// toward the edge for a spherical bulge.
[[ stitchable ]]
float2 glassOrb(float2 destination, float2 size, float2 offset, float refraction) {
    float2 center = size * 0.5 + offset;
    float radius = min(size.x, size.y) * 0.5;

    float2 p = destination - center;
    float r = length(p);

    // Outside the orb: leave the source untouched.
    if (r >= radius) {
        return destination;
    }

    // Normalized radius 0..1. Magnification is highest at the center and eases
    // toward the edge, but always stays > 1 so the orb reads as a glass bubble.
    float rn = r / radius;
    float mag = refraction * (1.0 - 0.25 * rn);

    // Sample inward from the center: source is nearer the center than the
    // destination point, which magnifies the art under the orb.
    float2 source = center + p / mag;
    return source;
}
