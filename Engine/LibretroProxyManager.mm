#import "LibretroProxyManager.h"

@interface LibretroProxyManager ()
@property (nonatomic, strong) NSXPCConnection *xpcConnection;
@end

@implementation LibretroProxyManager

+ (instancetype)sharedManager {
    static LibretroProxyManager *sharedManager = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedManager = [[self alloc] init];
    });
    return sharedManager;
}

- (void)setupConnection {
    if (self.xpcConnection) {
        [self.xpcConnection invalidate];
    }
    
    // Connect to the XPC service bundle identifier
    self.xpcConnection = [[NSXPCConnection alloc] initWithServiceName:@"com.truchiemu.runner"];
    
    self.xpcConnection.remoteObjectInterface = [NSXPCInterface interfaceWithProtocol:@protocol(TruchiCoreRunnerProtocol)];
    
    self.xpcConnection.exportedInterface = [NSXPCInterface interfaceWithProtocol:@protocol(TruchiCoreHostProtocol)];
    self.xpcConnection.exportedObject = self;
    
    self.xpcConnection.interruptionHandler = ^{
        NSLog(@"[Proxy] XPC Connection Interrupted");
    };
    
    self.xpcConnection.invalidationHandler = ^{
        NSLog(@"[Proxy] XPC Connection Invalidated - Runner crashed?");
        if (self.failureCallback) {
            self.failureCallback(@"Core Runner Disconnected Unexpectedly");
        }
    };
    
    [self.xpcConnection resume];
}

- (void)launchCore:(NSString *)dylibPath
           romPath:(NSString *)romPath
            coreID:(NSString *)coreID
          systemID:(nullable NSString *)systemID
         shaderDir:(nullable NSString *)shaderDir
             reply:(void(^)(BOOL, NSDictionary * _Nullable))reply {
    
    [self setupConnection];
    
    id<TruchiCoreRunnerProtocol> proxy = [self.xpcConnection remoteObjectProxyWithErrorHandler:^(NSError * _Nonnull error) {
        NSLog(@"[Proxy] XPC Error during launch: %@", error);
        reply(NO, nil);
    }];
    
    [proxy bootCoreWithPath:dylibPath
                   romPath:romPath
                    coreID:coreID
                  systemID:systemID
                 shaderDir:shaderDir
                 withReply:^(BOOL success, NSDictionary * _Nullable avInfo) {
        reply(success, avInfo);
    }];
}

- (void)stopCore {
    if (self.xpcConnection) {
        id<TruchiCoreRunnerProtocol> proxy = [self.xpcConnection remoteObjectProxy];
        [proxy stopWithReply:^{
            [self.xpcConnection invalidate];
            self.xpcConnection = nil;
        }];
    }
}

- (void)setKeyState:(int)retroID pressed:(BOOL)pressed {
    [[self.xpcConnection remoteObjectProxy] setKeyState:retroID pressed:pressed];
}

- (void)serializeStateWithReply:(void(^)(NSData * _Nullable data))reply {
    [[self.xpcConnection remoteObjectProxy] serializeWithReply:reply];
}

- (void)unserializeState:(NSData *)data reply:(void(^)(BOOL success))reply {
    [[self.xpcConnection remoteObjectProxy] unserialize:data withReply:reply];
}

#pragma mark - TruchiCoreHostProtocol

- (void)frameReadyWithSurface:(IOSurface *)surface width:(int)w height:(int)h pitch:(int)p format:(int)f rotation:(int)r {
    if (self.videoCallback) {
        IOSurfaceRef surfaceRef = (__bridge IOSurfaceRef)surface;
        IOSurfaceLock(surfaceRef, kIOSurfaceLockReadOnly, NULL);
        const void *data = IOSurfaceGetBaseAddress(surfaceRef);
        self.videoCallback(data, w, h, p, f);
        IOSurfaceUnlock(surfaceRef, kIOSurfaceLockReadOnly, NULL);
    }
}

- (void)audioSamplesReady:(NSData *)samples {
    if (self.audioCallback) {
        self.audioCallback((const int16_t *)samples.bytes, samples.length / (2 * sizeof(int16_t)));
    }
}

- (void)logMessage:(NSString *)message level:(int)level {
    NSLog(@"[Core:%d] %@", level, message);
}

@end
