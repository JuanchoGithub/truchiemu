#import <Foundation/Foundation.h>

// Swift-facing wrapper around the ported famidec RF decoder + the
// NtscRfEncoder ("digital -> RF") stage. Pure C++/ObjC++ (no Metal); it
// outputs a decoded RGBA8 buffer (640x480) that the caller uploads to a
// Metal texture. Pipeline: encoder (RGBA8 -> NTSC/RF IQ) -> DC blocker ->
// NCO mixer -> 4.3 MHz LPF -> envelope detector -> NtscDecoder -> 640x480.
@interface RfDecoderBridge : NSObject

// (Re)configure for a source frame size. Recreates the encoder/decoder when
// the size changes so the subcarrier phase and AGC state reset cleanly.
- (void)configureWithWidth:(int)srcW height:(int)srcH;

// RF realism + color knobs pulled each frame from the shader uniforms.
// colorMode: 1 = color, 0 = gray. tuningHz folds into the carrier offset.
// instability: 0..1 master amount for the auto "bad reception" events
// (dropouts, vertical-hold roll, random bump glitches).
- (void)setSignalStrength:(float)signalStrength
                      snow:(float)snow
                  tuningHz:(float)tuningHz
                  ghosting:(float)ghosting
                saturation:(float)saturation
                   hueDeg:(float)hueDeg
                 colorMode:(int)colorMode
               instability:(float)instability;

// Convert `data` (libretro pixel layout) -> RGBA8 -> encode RF -> front-end
// -> decode. `decodedRGBA` is valid until the next call.
- (void)processFrame:(const void*)data
               width:(int)w
              height:(int)h
               pitch:(int)pitch
                 bpp:(int)bpp
               format:(int)format;

- (nullable const uint8_t*)decodedRGBA;
- (int)decodedWidth;
- (int)decodedHeight;

- (void)reset;

@end
