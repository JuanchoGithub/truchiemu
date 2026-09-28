#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// Talks to the user's installed suyu core (dlopen, no emulation boot) and
// asks its own FileSys classes for content IDs. Every method degrades to
// nil/NO when the core is missing, outdated, or a file cannot be parsed.
// Thread-safe. Never touches the main thread requirements of callers,
// but callers should still prefer background queues (file I/O + AES).
@interface SuyuContentBridge : NSObject

+ (instancetype)shared;

// Loads the core dylib and prod.keys. Idempotent. Safe to call repeatedly.
- (BOOL)ensureReadyWithCorePath:(NSString *)corePath keysPath:(NSString *)keysPath;

@property (nonatomic, readonly, getter=isReady) BOOL ready;

// Identify one file. isXCI selects the XCI vs NSP parser.
// Returns nil on any failure. Otherwise:
//   @"titleID"    - 16-hex-digit NSString (primary: first Meta NCA for NSP,
//                    program title for XCI)
//   @"programIDs" - NSArray<NSString *> of program title IDs (NSP, may be empty)
//   @"status"     - NSNumber int (Loader::ResultStatus, 0 = success)
- (nullable NSDictionary *)identifyFileAtPath:(NSString *)path isXCI:(BOOL)isXCI;

@end

NS_ASSUME_NONNULL_END
