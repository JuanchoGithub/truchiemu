//
//  SaveDirectoryBridge.h
//  TruchiEmu
//
//  Helper bridge for accessing SaveDirectoryManager from Objective-C++
//

#import <Foundation/Foundation.h>

@interface SaveDirectoryBridge : NSObject

/// Returns the active save directory path for libretro cores (savefiles)
+ (NSString *)libretroSaveDirectoryPath;

/// Returns the active system directory path for libretro cores (BIOS)
+ (NSString *)libretroSystemDirectoryPath;

/// Ensures the directories exist
+ (void)ensureDirectoriesExist;

@end