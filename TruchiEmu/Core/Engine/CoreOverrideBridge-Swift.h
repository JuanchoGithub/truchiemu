//
//  CoreOverrideBridge-Swift.h
//  TruchiEmu
//
//  Minimal Swift class interface for CoreOverrideBridge to avoid full bridging header

@import Foundation;

@interface CoreOverrideBridge : NSObject

+ (BOOL)hasOverrideForCoreID:(NSString *)coreID optionKey:(NSString *)optionKey;
+ (nullable NSString *)getOverrideForCoreID:(NSString *)coreID optionKey:(NSString *)optionKey;
+ (void)logOverridesForCoreID:(NSString *)coreID;
+ (NSArray<NSString *> *)getOverrideKeysForCoreID:(NSString *)coreID;

@end
