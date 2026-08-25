#include <metal_stdlib>
using namespace metal;

// Glass-orb / fisheye lens refraction for SwiftUI `distortionEffect`.
// `destination` is the layer coordinate (points, top-left origin) provided
// automatically by SwiftUI. `size` is the layer size in points, `offset`
// shifts the lens center (driven by the pointer for a live, cursor-following
// bulge), and `refraction` controls bulge strength (>1 magnifies).
//
// `bubbleWarp` (0..1) and `bubbleAngle` add an asymmetric bulge toward the
// cursor, simulating a bubble being pulled/stretched. This makes the
// magnification field elliptical rather than circular, enhancing the
// organic "air bubble" feel.
//
// The lens acts as a magnifier: every point inside the orb samples the art
// *closer* to the lens center than the destination point (so the orb always
// shows a magnified, warped view — never a flat 1x patch that matches the
// background). Magnification is strongest at the center and eases slightly
// toward the edge for a spherical bulge.
[[ stitchable ]]
float2 glassOrb(float2 destination, float2 size, float2 offset, float refraction,
                float bubbleWarp, float bubbleAngle) {
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

    // Bubble warp: elliptical distortion toward the cursor.
    // Warp stretches the sampling field along the bubbleAngle axis,
    // making the magnification stronger in that direction.
    if (bubbleWarp > 0.0) {
        float2 warpDir = float2(cos(bubbleAngle), sin(bubbleAngle));
        float2 perpDir = float2(-warpDir.y, warpDir.x);

        // Project the vector onto warp and perpendicular axes
        float along = dot(p, warpDir);
        float across = dot(p, perpDir);

        // Stretch the "along" axis, compress "across" slightly for volume conservation
        float warpFactor = 1.0 + bubbleWarp * 0.6;
        float acrossFactor = 1.0 - bubbleWarp * 0.2;

        float2 warpedP = warpDir * (along * warpFactor) + perpDir * (across * acrossFactor);

        // Recompute radius in warped space
        float rWarped = length(warpedP);
        float rnWarped = rWarped / radius;

        // Magnification adapts to warped distance
        mag = refraction * (1.0 - 0.25 * rnWarped);

        // Sample using warped coordinates
        float2 source = center + warpedP / mag;
        return source;
    }

    // Sample inward from the center: source is nearer the center than the
    // destination point, which magnifies the art under the orb.
    float2 source = center + p / mag;
    return source;
}