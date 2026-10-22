#include <metal_stdlib>
#include "internal/ShaderTypes.h.metal"
using namespace metal;

// ============================================================
// MorphCRT - Physical CRT Simulation (inspired by PixelFX Morph 4K v4)
// Single-pass: analog path, amplifier blur, dynamic scanlines,
// shadow mask, phosphor glow, curvature, convergence, edge dimming,
// white point / gamut, tube sag (brightness-driven scale).
// ============================================================
struct MorphCRTUniforms {
    float time;
    float4 sourceSize;   // x=w, y=h, z=1/w, w=1/h
    float4 outputSize;   // x=w, y=h, z=1/w, w=1/h

    // Analog path simulation
    float compositeAmount;   // 0..1
    float subcarrierPhase;   // source pixels per subcarrier cycle (pitch)
    float dotCrawl;          // 0..1
    float blendOnly;         // 0..1 (dither blend, no rainbow)

    // Amplifier blur
    float amplifierBlur;     // 0..1

    // Scanlines (dynamic / energy-conserving)
    float scanlineStrength;  // 0..1
    float scanDarkWidth;     // source lines on dark
    float scanBrightWidth;   // source lines on bright

    // Shadow mask
    float maskStrength;      // 0..1
    float maskPitch;         // output pixels per triad
    float maskType;          // 0 aperture, 1 slot, 2 dot

    // Phosphor glow
    float glowStrength;      // 0..1
    float glowSize;          // output pixels
    float glowTint;          // 0..1

    // Edge dimming / vignette
    float edgeDimming;       // 0..1

    // Curvature
    float curvature;         // 0..0.15
    float cornerRadius;      // 0..0.15
    float useCurvature;      // 0/1

    // Convergence
    float convH;             // output pixels
    float convV;
    float cornerConv;        // 0..1
    float useConv;           // 0/1

    // White point / gamut
    float whiteTemp;         // 0=6500K, 1=9300K
    float colorBoost;

    // Tube sag
    float tubeSag;           // 0..1

    // RF channel
    float rfAmount;
    float snowAmount;
    float ghosting;
    float interference;
    float tuningDrift;

    // Y/C comb filter
    float combMode;

    // Beam scan / BFI
    float beamScanMode;
    float persistence;
    float strobeLength;

    // Bezel reflection
    float bezelReflection;

    // Gamut
    float gamutMode;

    // Amplifier overshoot
    float overshoot;

    // PAL / Hanover bars
    float palMode;
    float hanoverBars;         // 0 = PAL delay line on, 1 = off (bars)

    // Bezel frame
    float bezelFrame;

    // Toggles
    float useComposite;
    float useBlur;
    float useScanlines;
    float useMask;
    float useGlow;
    float _pad;
};

// ---------- helpers ----------
static float luminance(float3 c) { return dot(c, float3(0.299, 0.587, 0.114)); }

static float2 curveUV(float2 uv, float curvature) {
    float2 c = uv * 2.0 - 1.0;
    float2 o = c * c;
    c += c * o.yx * curvature;
    return c * 0.5 + 0.5;
}

static bool inBounds(float2 uv, float cornerRadius) {
    if (uv.x < 0.0 || uv.x > 1.0 || uv.y < 0.0 || uv.y > 1.0) return false;
    float2 c = uv * 2.0 - 1.0;
    float2 ac = abs(c);
    float r = cornerRadius * 2.0;
    float2 q = ac - float2(1.0 - r, 1.0 - r);
    if (q.x > 0.0 && q.y > 0.0 && (q.x*q.x + q.y*q.y) > r*r) return false;
    return true;
}

// RGB <-> YIQ
static float3 rgb2yiq(float3 rgb) {
    float y = dot(rgb, float3(0.299, 0.587, 0.114));
    float i = dot(rgb, float3(0.596, -0.274, -0.322));
    float q = dot(rgb, float3(0.211, -0.523, 0.312));
    return float3(y, i, q);
}
static float3 yiq2rgb(float3 yiq) {
    float r = yiq.x + 0.956*yiq.y + 0.621*yiq.z;
    float g = yiq.x - 0.272*yiq.y - 0.647*yiq.z;
    float b = yiq.x - 1.106*yiq.y + 1.703*yiq.z;
    return float3(r, g, b);
}

static float3 sampleBlurred(texture2d<float> tex, sampler s, float2 uvin, float blurAmt, float stepX, float blurPx) {
    if (blurAmt <= 0.0) return tex.sample(s, uvin).rgb;
    // Centre-weighted binomial kernel (1 4 6 4 1). The old kernel gave the
    // centre tap less weight than its neighbours, which smeared the picture.
    float w0 = 0.375; float w1 = 0.25; float w2 = 0.0625;
    float3 acc = tex.sample(s, uvin).rgb * w0;
    acc += tex.sample(s, uvin + float2(stepX*1.0*blurPx, 0)).rgb * w1;
    acc += tex.sample(s, uvin - float2(stepX*1.0*blurPx, 0)).rgb * w1;
    acc += tex.sample(s, uvin + float2(stepX*2.0*blurPx, 0)).rgb * w2;
    acc += tex.sample(s, uvin - float2(stepX*2.0*blurPx, 0)).rgb * w2;
    return acc;
}

// ---------- main ----------
fragment float4 fragmentMorphCRT(VertexOut in [[stage_in]],
                                texture2d<float> tex [[texture(0)]],
                                texture2d<float> tex1 [[texture(1)]],
                                texture2d<float> tex2 [[texture(2)]],
                                texture2d<float> tex3 [[texture(3)]],
                                texture2d<float> tex4 [[texture(4)]],
                                constant MorphCRTUniforms &u [[buffer(0)]]) {
    constexpr sampler s(filter::linear, address::clamp_to_edge);

    float2 uv = in.texCoord;

    // --- Curvature remap ---
    float2 srcUV = uv;
    float cornerR = u.useCurvature > 0.5 ? u.cornerRadius : 0.0;
    float curv = u.useCurvature > 0.5 ? u.curvature : 0.0;
    if (curv > 0.0) {
        srcUV = curveUV(uv, curv);
    }
    // Tube sag: the high-voltage supply droops on bright scenes, so the raster
    // swells. Use a sparse average, not a single pixel, to follow overall APL.
    if (u.tubeSag > 0.0) {
        float avgB = luminance(tex.sample(s, float2(0.50, 0.50)).rgb) * 0.34
                   + luminance(tex.sample(s, float2(0.25, 0.30)).rgb) * 0.17
                   + luminance(tex.sample(s, float2(0.75, 0.30)).rgb) * 0.17
                   + luminance(tex.sample(s, float2(0.25, 0.72)).rgb) * 0.16
                   + luminance(tex.sample(s, float2(0.75, 0.72)).rgb) * 0.16;
        float sagScale = 1.0 + u.tubeSag * 0.03 * avgB;
        srcUV = (srcUV - 0.5) / sagScale + 0.5;
    }
    if (!inBounds(srcUV, cornerR)) {
        // Bezel reflection: reflect edge colors into the bezel area
        float2 clamped = clamp(srcUV, 0.0, 1.0);
        float3 edgeCol = tex.sample(s, clamped).rgb;
        float3 bezelCol = edgeCol * (0.15 + u.bezelReflection * 0.35);
        // distance from edge for falloff
        float2 d = abs(srcUV - clamp(srcUV, 0.0, 1.0));
        float falloff = 1.0 - clamp(length(d) * 4.0, 0.0, 1.0);
        bezelCol *= falloff;
        return float4(bezelCol, 1.0);
    }

    float srcW = u.sourceSize.x;
    float srcH = u.sourceSize.y;
    float outH = u.outputSize.y;

    // --- Convergence offsets (in source UV) ---
    float convScale = 1.0;
    if (u.useConv > 0.5) {
        float2 center = srcUV - 0.5;
        float dist = length(center);
        float cornerFactor = (u.cornerConv) * (dist * dist);
        convScale = 1.0 + cornerFactor;
    }
    float2 convOffset = float2(u.convH / srcW, u.convV / srcH) * convScale;
    float2 uvR = srcUV + (u.useConv > 0.5 ? convOffset : float2(0.0));
    float2 uvB = srcUV - (u.useConv > 0.5 ? convOffset : float2(0.0));
    float2 uvG = srcUV;

    // --- Amplifier blur (horizontal) ---
    float blurAmt = u.useBlur > 0.5 ? u.amplifierBlur : 0.0;
    float blurPx = blurAmt * 2.0; // source pixels
    float stepX = 1.0 / srcW;

    float3 colR = sampleBlurred(tex, s, uvR, blurAmt, stepX, blurPx);
    float3 colG = sampleBlurred(tex, s, uvG, blurAmt, stepX, blurPx);
    float3 colB = sampleBlurred(tex, s, uvB, blurAmt, stepX, blurPx);

    // Reassemble per-channel (convergence): take R from colR, G from colG, B from colB
    float3 color = float3(colR.r, colG.g, colB.b);

    // --- Amplifier overshoot / ringing ---
    if (u.overshoot > 0.0) {
        float3 cL = tex.sample(s, srcUV + float2(-1.0/srcW,0)).rgb;
        float3 cR = tex.sample(s, srcUV + float2(1.0/srcW,0)).rgb;
        float3 edge = color - (cL + cR) * 0.5;
        color += edge * u.overshoot * 0.5;
    }

    // --- Analog path simulation (composite) ---
    float compAmt = (u.useComposite > 0.5) ? clamp(u.compositeAmount, 0.0, 1.0) : 0.0;
    // Blend-only is its own signal type: it must work without the toggle.
    if (u.blendOnly > 0.5) compAmt = 1.0;
    // PAL is a property of the analog path. Enabling it must engage that path,
    // or the toggle would have no visible effect on its own.
    if (u.palMode > 0.5) compAmt = 1.0;
    if (compAmt > 0.0) {
        float2 fragPx = srcUV * float2(srcW, srcH);
        float3 cYIQ = rgb2yiq(color);
        float3 lYIQ = rgb2yiq(tex.sample(s, clamp(srcUV - float2(1.0/srcW, 0.0), 0.0, 1.0)).rgb);
        float3 rYIQ = rgb2yiq(tex.sample(s, clamp(srcUV + float2(1.0/srcW, 0.0), 0.0, 1.0)).rgb);

        // Chroma is low-bandwidth: read it on a coarse (2 source-pixel) grid
        // and average three cells, so dithering blends and colour edges fringe.
        float cell = 2.0 / srcW;
        float qx = (floor(srcUV.x / cell) + 0.5) * cell;
        float3 qC = rgb2yiq(tex.sample(s, float2(qx, srcUV.y)).rgb);
        float3 qL = rgb2yiq(tex.sample(s, float2(qx - cell, srcUV.y)).rgb);
        float3 qR = rgb2yiq(tex.sample(s, float2(qx + cell, srcUV.y)).rgb);
        float2 chromaBase = (qL.yz + 2.0 * qC.yz + qR.yz) * 0.25;

        // Subcarrier Pitch is the console's own pixel-to-subcarrier timing, in
        // source pixels per carrier cycle (NTSC: NES 1.5, Genesis 1.875;
        // PAL: NES/SNES 1.2). The signal must be sampled at 4x the subcarrier,
        // not at the pixel clock; sampling at the pixel clock aliases the
        // carrier and washes the rainbows out.
        bool pal = u.palMode > 0.5;
        // The same console moves its pixels closer to the carrier on PAL
        // (4.43 MHz instead of 3.58 MHz), so the pitch shrinks by that ratio.
        float pitch = clamp(u.subcarrierPhase, 1.15, 3.0) * (pal ? 0.80735 : 1.0);
        float phaseStep = 6.2831853 / pitch;
        float phaseBase = phaseStep * fragPx.x + u.time * 2.0;
        float hanover = clamp(u.hanoverBars, 0.0, 1.0);

        float Y = cYIQ.x;
        float2 chroma = chromaBase;
        if (u.blendOnly > 0.5) {
            // Blend-only: melt dithered detail, no rainbow and no dot crawl.
            Y = (lYIQ.x + cYIQ.x + rYIQ.x) / 3.0;
        } else {
            // Encoder -> decoder. Encode RGB as a real composite signal, then
            // demodulate it against the local carrier. Luma detail near the
            // subcarrier folds down into false colour: this is what produces
            // rainbows on fine stripes, colour fringes on text and dot crawl,
            // and it cancels on flat areas exactly as real composite does.
            //
            // 3 full carrier cycles at 4 samples per cycle. The source is held
            // constant across each pixel (nearest fetch), so the encoder sees
            // the real staircase signal. A whole number of cycles makes the
            // carrier sums cancel exactly, so flat areas stay neutral.
            const int NS = 12;
            float subPx = pitch * 0.25;
            float invN = 1.0 / float(NS);

            // PAL decodes the line above as well: the delay-line decoder
            // averages the two, which cancels the V-switch phase error.
            int lines = pal ? 2 : 1;
            float3 curYIQ = float3(0.0);
            float3 prevYIQ = float3(0.0);
            for (int L = 0; L < 2; L++) {
                if (L >= lines) break;
                float lineIdx = floor(srcUV.y * srcH) - float(L);
                float yy = clamp((lineIdx + 0.5) / srcH, 0.0, 1.0);
                // PAL switches the V axis on every other line.
                float vSign = (pal && fmod(abs(lineIdx), 2.0) > 0.5) ? -1.0 : 1.0;
                // A phase error between the burst and the decoder reference
                // alternates with the V switch. The delay line averages it
                // away; without the line it shows as Hanover bars.
                float decErr = pal ? (hanover * 0.5) : 0.0;
                float phase0 = phaseBase + (lineIdx + 0.5) * 0.05;

                float sumY = 0.0;
                float sumCompCos = 0.0, sumCompSin = 0.0, sumCos = 0.0, sumSin = 0.0;
                for (int j = 0; j < NS; j++) {
                    float off = (float(j) - 5.5) * subPx;
                    float sx = clamp(fragPx.x + off, 0.0, srcW - 1.0);
                    float px = floor(sx) + 0.5;
                    float3 sy = rgb2yiq(tex.sample(s, float2(px / srcW, yy)).rgb);
                    float ph = phase0 + off * phaseStep;
                    float cph = cos(ph);
                    float sph = sin(ph);
                    // Encode: PAL flips the V (Q) sideband on alternate lines.
                    float comp = sy.x + sy.y * cph + vSign * sy.z * sph;
                    float dph = ph + decErr;
                    float cpd = cos(dph);
                    float spd = sin(dph);
                    sumY += sy.x;
                    sumCompCos += comp * cpd;
                    sumCompSin += comp * spd * vSign;
                    sumCos += cpd;
                    sumSin += spd * vSign;
                }
                float yLow = sumY * invN;
                // Demodulate, removing the luma DC contribution so flat areas cancel.
                float I = 2.0 * (sumCompCos * invN - yLow * (sumCos * invN));
                float Q = 2.0 * (sumCompSin * invN - yLow * (sumSin * invN));
                if (L == 0) curYIQ = float3(yLow, I, Q);
                else prevYIQ = float3(yLow, I, Q);
            }

            float2 crossColor = curYIQ.yz - chromaBase;
            chroma = curYIQ.yz;
            if (pal) {
                // Explicit PAL delay line. Hanover Bars at 0 keeps the line on;
                // at 1 the line is off and the raw V-switch error shows.
                float delay = 1.0 - hanover;
                chroma = mix(curYIQ.yz, (curYIQ.yz + prevYIQ.yz) * 0.5, delay);
            }
            Y = curYIQ.x + u.dotCrawl * crossColor.x * 0.5;
        }

        // Layer the analog artifacts onto the CRT-processed picture instead of
        // replacing it. Convergence, amplifier blur and overshoot happen before
        // this point; replacing `color` would silently discard them whenever
        // Composite is on.
        float3 decoded = yiq2rgb(float3(Y, chroma));
        float3 rawCol = tex.sample(s, clamp(srcUV, 0.0, 1.0)).rgb;
        color = clamp(color + (decoded - rawCol) * compAmt, 0.0, 1.0);
    }

    // --- Y/C comb filter (Y/C separation) ---
    // Runs after the analog path so it also affects the decoded chroma: when
    // Composite is on, the decode has already replaced the chroma and a
    // pre-composite comb would be a no-op.
    if (u.combMode > 0.5) {
        float3 yiqC = rgb2yiq(color);
        if (u.combMode < 1.5) {
            // Notch: horizontal chroma lowpass
            float3 cL = tex.sample(s, srcUV + float2(-1.0/srcW, 0)).rgb;
            float3 cR = tex.sample(s, srcUV + float2(1.0/srcW, 0)).rgb;
            float3 yL = rgb2yiq(cL); float3 yR = rgb2yiq(cR);
            float iComb = (yL.y + yiqC.y + yR.y) / 3.0;
            float qComb = (yL.z + yiqC.z + yR.z) / 3.0;
            color = yiq2rgb(float3(yiqC.x, mix(yiqC.y, iComb, 0.6), mix(yiqC.z, qComb, 0.6)));
        } else if (u.combMode < 2.5) {
            // 2-line comb
            float3 cDn = tex.sample(s, srcUV + float2(0, 1.0/srcH)).rgb;
            float3 yDn = rgb2yiq(cDn);
            float iComb = (yiqC.y + yDn.y) * 0.5;
            float qComb = (yiqC.z + yDn.z) * 0.5;
            color = yiq2rgb(float3(yiqC.x, mix(yiqC.y, iComb, 0.7), mix(yiqC.z, qComb, 0.7)));
        } else if (u.combMode < 3.5) {
            // 3-line comb
            float3 cUp = tex.sample(s, srcUV + float2(0, -1.0/srcH)).rgb;
            float3 cDn = tex.sample(s, srcUV + float2(0, 1.0/srcH)).rgb;
            float3 yUp = rgb2yiq(cUp); float3 yDn = rgb2yiq(cDn);
            float iComb = (yUp.y + yiqC.y + yDn.y) / 3.0;
            float qComb = (yUp.z + yiqC.z + yDn.z) / 3.0;
            color = yiq2rgb(float3(yiqC.x, mix(yiqC.y, iComb, 0.7), mix(yiqC.z, qComb, 0.7)));
        } else {
            // Adaptive comb: a 3-line comb on still content, a notch when the
            // picture moves vertically (where a comb would smear).
            float3 cUp = tex.sample(s, srcUV + float2(0, -1.0/srcH)).rgb;
            float3 cDn = tex.sample(s, srcUV + float2(0, 1.0/srcH)).rgb;
            float3 yUp = rgb2yiq(cUp); float3 yDn = rgb2yiq(cDn);
            float motion = abs(yUp.x - yDn.x);
            float still = 1.0 - smoothstep(0.04, 0.14, motion);
            float3 cL = tex.sample(s, srcUV + float2(-1.0/srcW, 0)).rgb;
            float3 cR = tex.sample(s, srcUV + float2( 1.0/srcW, 0)).rgb;
            float3 yL = rgb2yiq(cL); float3 yR = rgb2yiq(cR);
            float iNotch = (yL.y + yiqC.y + yR.y) / 3.0;
            float qNotch = (yL.z + yiqC.z + yR.z) / 3.0;
            float iComb = (yUp.y + yiqC.y + yDn.y) / 3.0;
            float qComb = (yUp.z + yiqC.z + yDn.z) / 3.0;
            color = yiq2rgb(float3(yiqC.x,
                                   mix(iNotch, iComb, still),
                                   mix(qNotch, qComb, still)));
        }
    }

    // --- RF channel (master-gated) ---
    float rfMaster = clamp(u.rfAmount, 0.0, 1.0);
    if (rfMaster > 0.0) {
        if (u.snowAmount > 0.0) {
            float noise = fract(sin(dot(floor(srcUV * float2(srcW, srcH)) + u.time * 60.0,
                                         float2(12.9898, 78.233))) * 43758.5453);
            color += (noise - 0.5) * u.snowAmount * rfMaster * 0.4;
        }
        if (u.ghosting > 0.0) {
            float3 ghost = tex.sample(s, clamp(srcUV + float2(3.0 / srcW, 0.0), 0.0, 1.0)).rgb;
            color = mix(color, color * 0.75 + ghost * 0.5, u.ghosting * rfMaster * 0.6);
        }
        if (u.interference > 0.0) {
            float wave = sin(srcUV.y * srcH * 0.6 + u.time * 5.0) * u.interference * rfMaster;
            color += wave * 0.12;
        }
        if (u.tuningDrift > 0.0) {
            float drift = sin(u.time * 1.3) * u.tuningDrift * rfMaster * 0.01;
            color = mix(color, tex.sample(s, clamp(srcUV + float2(drift, 0.0), 0.0, 1.0)).rgb, 0.25);
        }
    }


    // --- Dynamic, energy-conserving scanlines ---
    // Real beams carry the same energy at any width: dark content forms a thin
    // concentrated line with a deep gap, bright content spreads until it merges
    // with its neighbours. Normalising each beam to unit area keeps a flat field
    // exactly as bright with scanlines as without them.
    if (u.useScanlines > 0.5 && u.scanlineStrength > 0.0) {
        float sy = srcUV.y * srcH;
        float fy = fract(sy);
        float rowY = floor(sy);
        float3 rowColor = tex.sample(s, float2(srcUV.x, (rowY + 0.5) / srcH)).rgb;
        float dist = fy - 0.5;
        // Per-channel beam: each gun follows its own signal level.
        float3 sigma = mix(float3(u.scanDarkWidth), float3(u.scanBrightWidth), rowColor) * 0.5;
        sigma = clamp(sigma, 0.10, 0.5);
        float3 amp = 1.0 / (sigma * 2.506628); // normalise to unit area
        float3 beam = amp * exp(-(dist*dist) / (2.0*sigma*sigma));
        float strength = clamp(u.scanlineStrength, 0.0, 1.0);
        color *= mix(float3(1.0), beam, strength);
    }

    // --- Shadow mask ---
    if (u.useMask > 0.5 && u.maskStrength > 0.0) {
        float pitch = max(u.maskPitch, 3.0);
        float2 pos = in.position.xy;
        float3 maskCol;
        if (u.maskType < 0.5) {
            // Aperture grille: three vertical RGB phosphor stripes.
            float sx = fmod(pos.x, pitch) / pitch;
            float third = 1.0 / 3.0;
            if (sx < third)       maskCol = float3(1.0, 0.18, 0.18);
            else if (sx < 2.0*third) maskCol = float3(0.18, 1.0, 0.18);
            else                  maskCol = float3(0.18, 0.18, 1.0);
            // dark gap between successive triads
            maskCol *= 1.0 - 0.35 * smoothstep(0.94, 1.0, sx);
            // Damper wires: two faint horizontal lines across an aperture grille.
            float wy = fract(in.position.y / max(outH, 1.0));
            float wire = smoothstep(0.0016, 0.0032, abs(wy - 0.33))
                       * smoothstep(0.0016, 0.0032, abs(wy - 0.66));
            maskCol *= mix(1.0, 0.55, (1.0 - wire));
        } else if (u.maskType < 1.5) {
            // Slot mask: staggered RGB slots with dark horizontal gaps.
            float row = floor(pos.y / (pitch * 0.6));
            float stagger = fmod(row, 2.0) * (pitch * 0.5);
            float sx = fmod(pos.x + stagger, pitch) / pitch;
            float third = 1.0 / 3.0;
            if (sx < third)       maskCol = float3(1.0, 0.22, 0.22);
            else if (sx < 2.0*third) maskCol = float3(0.22, 1.0, 0.22);
            else                  maskCol = float3(0.22, 0.22, 1.0);
            float vgap = smoothstep(0.32, 0.5, abs(fract(pos.y / (pitch * 0.6)) - 0.5));
            maskCol *= 1.0 - 0.45 * vgap;
        } else {
            // Dot triad: triangular R/G/B phosphor dots.
            float2 p = fract(pos / pitch);
            float dR = length(p - float2(0.28, 0.30));
            float dG = length(p - float2(0.72, 0.30));
            float dB = length(p - float2(0.50, 0.74));
            float r = smoothstep(0.42, 0.14, dR);
            float g = smoothstep(0.42, 0.14, dG);
            float b = smoothstep(0.42, 0.14, dB);
            maskCol = float3(r, g, b) + 0.07;
        }
        // The mask dims each subpixel; compensate a little so the picture does
        // not lose all its brightness.
        maskCol *= 1.0 + 0.35 * clamp(u.maskStrength, 0.0, 1.0);
        color *= mix(float3(1.0), maskCol, clamp(u.maskStrength, 0.0, 1.0));
    }

    // --- Phosphor glow (energy-conserving) ---
    // Light scatters inside the faceplate glass: it is moved from highlights
    // into their surroundings, never added. Blending toward a normalised blur
    // preserves total light, fills scanline/mask gaps near highlights and lifts
    // the darkness beside them.
    if (u.useGlow > 0.5 && u.glowStrength > 0.0) {
        float gs = u.glowSize;
        float2 stepPx = float2(1.0 / max(srcW, 1.0), 1.0 / max(srcH, 1.0)) * gs;
        float3 glow = float3(0.0);
        float wsum = 0.0;
        for (int gy = -3; gy <= 3; gy++) {
            for (int gx = -3; gx <= 3; gx++) {
                float3 sc = tex.sample(s, clamp(srcUV + float2(gx, gy) * stepPx,
                                                0.0, 1.0)).rgb;
                float w = exp(-(float(gx*gx + gy*gy)) / (2.0 * 1.8 * 1.8));
                glow += sc * w;
                wsum += w;
            }
        }
        glow /= (wsum + 1e-6);
        glow *= mix(float3(0.90, 0.95, 1.10), float3(1.10, 1.00, 0.85), clamp(u.glowTint, 0.0, 1.0));
        // Weight the scatter by local brightness so dark detail stays dark.
        float lb = luminance(color);
        float w = u.glowStrength * (0.18 + 0.82 * smoothstep(0.08, 0.7, lb));
        color = mix(color, glow, clamp(w, 0.0, 1.0));
    }

    // --- Edge dimming / vignette ---
    if (u.edgeDimming > 0.0) {
        float2 c = srcUV * 2.0 - 1.0;
        float vign = 1.0 - u.edgeDimming * (c.x*c.x*0.3 + c.y*c.y*0.5 + (c.x*c.x)*(c.y*c.y)*0.5);
        vign = clamp(vign, 0.5, 1.0);
        color *= vign;
    }

    // --- Bezel frame edge (in-bounds, near border) ---
    if (u.bezelFrame > 0.0) {
        float2 d = abs(srcUV - 0.5) * 2.0;
        float edgeDist = max(d.x, d.y);
        float frame = smoothstep(0.92, 0.98, edgeDist);
        color = mix(color, color * 0.6, frame * u.bezelFrame);
    }

    // --- White point / gamut ---
    float3 wp = color;
    // gamut mode: 0 US/SMPTE-C 6500K, 1 PAL/EBU, 2 Japan 9300K Trinitron, 3 Trinitron, 4 NTSC 1953
    float3x3 gamutMat = float3x3(float3(1,0,0), float3(0,1,0), float3(0,0,1));
    if (u.gamutMode < 0.5) {
        // SMPTE-C
        gamutMat = float3x3(float3(1.05, -0.05, 0.0), float3(-0.02, 1.02, -0.02), float3(0.0, -0.04, 1.06));
    } else if (u.gamutMode < 1.5) {
        // EBU
        gamutMat = float3x3(float3(1.02, 0.0, -0.04), float3(0.0, 1.0, 0.0), float3(-0.02, 0.0, 1.04));
    } else if (u.gamutMode < 2.5) {
        // Japan 9300K
        gamutMat = float3x3(float3(0.95, 0.0, 0.0), float3(0.0, 0.98, 0.0), float3(0.0, 0.0, 1.1));
    } else if (u.gamutMode < 3.5) {
        // Trinitron
        gamutMat = float3x3(float3(1.0, 0.02, -0.02), float3(-0.01, 1.0, 0.0), float3(0.0, -0.01, 1.02));
    } else {
        // NTSC 1953
        gamutMat = float3x3(float3(1.1, -0.05, -0.05), float3(-0.05, 1.05, 0.0), float3(0.0, -0.05, 1.05));
    }
    wp = gamutMat * wp;
    if (u.whiteTemp > 0.5) {
        wp.r *= 0.94; wp.g *= 0.99; wp.b *= 1.08;
    }
    wp *= u.colorBoost;
    color = wp;

    // --- In-bounds bezel reflection (works without curvature) ---
    if (u.bezelReflection > 0.0) {
        float2 d = abs(srcUV - 0.5) * 2.0;
        float edgeDist = max(d.x, d.y);
        float nearEdge = smoothstep(0.7, 0.98, edgeDist);
        float2 reflectUV = clamp(srcUV + (srcUV - 0.5) * 0.05, 0.0, 1.0);
        float3 reflCol = tex.sample(s, reflectUV).rgb;
        color = mix(color, reflCol * 0.4, nearEdge * u.bezelReflection * 0.4);
    }

    // --- Phosphor persistence (temporal glow trail) ---
    // _pad carries the history validity (0 until the temporal ring has filled).
    if (u.useGlow > 0.5 && u._pad > 0.0) {
        float2 tuv = clamp(srcUV, 0.0, 1.0);
        float3 trail = float3(0.0);
        if (tex1.get_width() > 0) trail += tex1.sample(s, tuv).rgb * 0.55;
        if (tex2.get_width() > 0) trail += tex2.sample(s, tuv).rgb * 0.32;
        if (tex3.get_width() > 0) trail += tex3.sample(s, tuv).rgb * 0.18;
        if (tex4.get_width() > 0) trail += tex4.sample(s, tuv).rgb * 0.10;
        // Persistence slider scales the decay trail (0 = no trail, 1 = full ghost).
        color = max(color, trail * (0.8 * clamp(u.persistence, 0.0, 1.0))
                            * clamp(u._pad, 0.0, 1.0));
    }

    // --- Beam scan / BFI (last: the beam scans the finished picture) ---
    if (u.beamScanMode > 0.5) {
        float outY = in.position.y;
        float bandPos = fract(u.time * 2.0) * outH;
        if (u.beamScanMode < 1.5) {
            // Rolling Scan: only a horizontal band is lit, sweeping down the tube.
            float bandHalf = u.persistence * 40.0 + 10.0;
            float dist = abs(outY - bandPos);
            if (dist > outH * 0.5) dist = outH - dist;
            float lit = exp(-(dist*dist)/(2.0*bandHalf*bandHalf));
            color *= mix(0.05, 1.0, lit);
        } else if (u.beamScanMode < 2.5) {
            // Bright Strobe / Variable MPRT: each pixel keeps its own persistence.
            float b = luminance(color);
            float strobe = mix(u.strobeLength, 1.0, b);
            float phase = fract(u.time * 60.0);
            float on = step(phase, strobe);
            color *= mix(0.3, 1.0, on);
        } else {
            // Classic BFI: alternate a fully lit and a fully dark output frame.
            float phase = fract(u.time * 30.0);
            color *= step(phase, 0.5);
        }
    }

    // --- Curvature bounds already handled; final clamp ---
    color = clamp(color, 0.0, 1.0);
    return float4(color, 1.0);
}
