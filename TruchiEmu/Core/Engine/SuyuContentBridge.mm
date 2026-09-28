// SuyuContentBridge.mm
//
// Uses the installed suyu core's own FileSys classes (via dlopen) to read
// Switch content IDs without booting emulation and without suyu headers.
//
// How it works:
//  - KeyManager singleton storage is initialized through the Itanium guard
//    protocol, then prod.keys are loaded. Same keys the launcher requires.
//  - Files are opened through RealVfsFilesystem, parsed with FileSys::NSP
//    (GetNCAsCollapsed) or FileSys::XCI (GetProgramTitleID).
//  - Only concrete (non-virtual) methods are called, so no class layouts or
//    vtables are needed. Objects live in fixed opaque buffers.
//  - Every symbol is resolved with dlsym. A core update that changes these
//    stable yuzu-lineage APIs fails closed: ensureReady returns NO and all
//    callers fall back to filename/ticket identification.
//
// Proven against real dumps (see dev spike): update/DLC NSP Meta NCA titles,
// program ID lists, and XCI program title IDs all match ticket ground truth.

#import "SuyuContentBridge.h"

#include <dlfcn.h>
#include <memory>
#include <mutex>
#include <cstdio>
#include <string>
#include <string_view>
#include <vector>
#include <filesystem>

// ---- Forward declarations (no suyu headers) ----
namespace FileSys {
struct VfsFile;
struct RealVfsFilesystem;
struct VfsDirectory;
struct NSP;
struct XCI;
struct NCA;
} // namespace FileSys
namespace Core {
namespace Crypto {
struct KeyManager;
} // namespace Crypto
} // namespace Core

using VFile = std::shared_ptr<FileSys::VfsFile>;
using VNca = std::shared_ptr<FileSys::NCA>;

// ---- Exact function types (verified against core symbols + lineage source) ----
using FnKeyManagerC1 = void (*)(Core::Crypto::KeyManager*);
using FnKeyManagerLoad = void (*)(Core::Crypto::KeyManager*, const std::filesystem::path&, bool);
using FnKeyManagerLoaded = bool (*)(const Core::Crypto::KeyManager*);
using FnVfsC1 = void (*)(FileSys::RealVfsFilesystem*);
using FnOpenFile = VFile (*)(FileSys::RealVfsFilesystem*, std::string_view, int);
using FnNspC1 = void (*)(FileSys::NSP*, VFile, unsigned long long, unsigned long);
using FnNspD1 = void (*)(FileSys::NSP*);
using FnNspStatus = int (*)(const FileSys::NSP*);
using FnNspProgIds = std::vector<unsigned long long> (*)(const FileSys::NSP*);
using FnNspCollapsed = std::vector<VNca> (*)(const FileSys::NSP*);
using FnXciC1 = void (*)(FileSys::XCI*, VFile, unsigned long long, unsigned long);
using FnXciD1 = void (*)(FileSys::XCI*);
using FnXciProgId = unsigned long long (*)(const FileSys::XCI*);
using FnNcaStatus = int (*)(const FileSys::NCA*);
using FnNcaType = unsigned (*)(const FileSys::NCA*);
using FnNcaTitleId = unsigned long long (*)(const FileSys::NCA*);

extern "C" int __cxa_guard_acquire(unsigned long long*);
extern "C" void __cxa_guard_release(unsigned long long*);
extern "C" void __cxa_guard_abort(unsigned long long*);

namespace {
// FileSys::OpenMode::Read = 1 << 0 (fs_filesystem.h, stable across lineage).
constexpr int kOpenModeRead = 1;
// NCAContentType::Meta (content_archive.h, stable across lineage).
constexpr unsigned kNcaTypeMeta = 1;

std::string Hex16(unsigned long long v) {
    char buf[17];
    snprintf(buf, sizeof(buf), "%llX", v);
    std::string s(buf);
    return std::string(16 - s.size(), '0') + s;
}
} // namespace

@implementation SuyuContentBridge {
    std::mutex _mutex;
    void *_handle;
    bool _symbolsOK;
    bool _keysOK;
    NSString *_lastFailure;
    // Resolved symbols.
    FnKeyManagerC1 _keyC1;
    FnKeyManagerLoad _keyLoad;
    FnKeyManagerLoaded _keyLoaded;
    FnVfsC1 _vfsC1;
    FnOpenFile _openFile;
    FnNspC1 _nspC1;
    FnNspD1 _nspD1;
    FnNspStatus _nspStatus;
    FnNspProgIds _nspProgIds;
    FnNspCollapsed _nspCollapsed;
    FnXciC1 _xciC1;
    FnXciD1 _xciD1;
    FnXciProgId _xciProgId;
    FnNcaStatus _ncaStatus;
    FnNcaType _ncaType;
    FnNcaTitleId _ncaTitleId;
    Core::Crypto::KeyManager *_keyStorage;
    FileSys::RealVfsFilesystem *_vfs;
    alignas(16) char _vfsBuf[4096];
}

+ (instancetype)shared {
    static SuyuContentBridge *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[SuyuContentBridge alloc] init];
    });
    return instance;
}

- (instancetype)init {
    if ((self = [super init])) {
        _vfs = nullptr;
        _keyStorage = nullptr;
    }
    return self;
}

- (BOOL)ready {
    std::lock_guard<std::mutex> lock(_mutex);
    return _symbolsOK && _keysOK && _vfs != nullptr;
}

- (nullable NSString *)lastFailure {
    std::lock_guard<std::mutex> lock(_mutex);
    return _lastFailure;
}

- (void)setFailure:(const char *)reason {
    _lastFailure = reason ? @(reason) : nil;
}

template <typename T>
static T Resolve(void *handle, const char *name) {
    return (T)dlsym(handle, name);
}

- (BOOL)ensureReadyWithCorePath:(NSString *)corePath keysPath:(NSString *)keysPath {
    std::lock_guard<std::mutex> lock(_mutex);
    if (_symbolsOK && _keysOK && _vfs != nullptr) {
        return YES;
    }
    if (!_handle) {
        _handle = dlopen(corePath.UTF8String, RTLD_NOW | RTLD_LOCAL);
        if (!_handle) {
            return NO;
        }
        _keyC1 = Resolve<FnKeyManagerC1>(self->_handle, "_ZN4Core6Crypto10KeyManagerC1Ev");
        _keyLoad = Resolve<FnKeyManagerLoad>(self->_handle, "_ZN4Core6Crypto10KeyManager12LoadFromFileERKNSt3__14__fs10filesystem4pathEb");
        _keyLoaded = Resolve<FnKeyManagerLoaded>(self->_handle, "_ZNK4Core6Crypto10KeyManager13AreKeysLoadedEv");
        _vfsC1 = Resolve<FnVfsC1>(self->_handle, "_ZN7FileSys17RealVfsFilesystemC1Ev");
        _openFile = Resolve<FnOpenFile>(self->_handle, "_ZN7FileSys17RealVfsFilesystem8OpenFileENSt3__117basic_string_viewIcNS1_11char_traitsIcEEEENS_8OpenModeE");
        _nspC1 = Resolve<FnNspC1>(self->_handle, "_ZN7FileSys3NSPC1ENSt3__110shared_ptrINS_7VfsFileEEEym");
        _nspD1 = Resolve<FnNspD1>(self->_handle, "_ZN7FileSys3NSPD1Ev");
        _nspStatus = Resolve<FnNspStatus>(self->_handle, "_ZNK7FileSys3NSP9GetStatusEv");
        _nspProgIds = Resolve<FnNspProgIds>(self->_handle, "_ZNK7FileSys3NSP18GetProgramTitleIDsEv");
        _nspCollapsed = Resolve<FnNspCollapsed>(self->_handle, "_ZNK7FileSys3NSP16GetNCAsCollapsedEv");
        _xciC1 = Resolve<FnXciC1>(self->_handle, "_ZN7FileSys3XCIC1ENSt3__110shared_ptrINS_7VfsFileEEEym");
        _xciD1 = Resolve<FnXciD1>(self->_handle, "_ZN7FileSys3XCID1Ev");
        _xciProgId = Resolve<FnXciProgId>(self->_handle, "_ZNK7FileSys3XCI17GetProgramTitleIDEv");
        _ncaStatus = Resolve<FnNcaStatus>(self->_handle, "_ZNK7FileSys3NCA9GetStatusEv");
        _ncaType = Resolve<FnNcaType>(self->_handle, "_ZNK7FileSys3NCA7GetTypeEv");
        _ncaTitleId = Resolve<FnNcaTitleId>(self->_handle, "_ZNK7FileSys3NCA10GetTitleIdEv");
        _keyStorage = (Core::Crypto::KeyManager *)dlsym(self->_handle, "_ZZN4Core6Crypto10KeyManager8InstanceEvE8instance");
        _symbolsOK = _keyC1 && _keyLoad && _keyLoaded && _vfsC1 && _openFile && _nspC1 &&
                     _nspD1 && _nspStatus && _nspProgIds && _nspCollapsed && _xciC1 && _xciD1 &&
                     _xciProgId && _ncaStatus && _ncaType && _ncaTitleId && _keyStorage;
        if (!_symbolsOK) {
            return NO;
        }
    }
    if (!_keysOK) {
        auto guard = (unsigned long long *)dlsym(_handle, "_ZGVZN4Core6Crypto10KeyManager8InstanceEvE8instance");
        if (!guard || !_keyStorage) {
            return NO;
        }
        @try {
            if (__cxa_guard_acquire(guard)) {
                @try {
                    _keyC1(_keyStorage);
                } @catch (...) {
                    __cxa_guard_abort(guard);
                    throw;
                }
                __cxa_guard_release(guard);
            }
            std::filesystem::path kp(keysPath.UTF8String);
            _keyLoad(_keyStorage, kp, false);
            _keysOK = _keyLoaded(_keyStorage);
        } @catch (...) {
            return NO;
        }
        if (!_keysOK) {
            return NO;
        }
    }
    if (!_vfs) {
        @try {
            _vfs = (FileSys::RealVfsFilesystem *)_vfsBuf;
            _vfsC1(_vfs);
        } @catch (...) {
            _vfs = nullptr;
            return NO;
        }
    }
    return YES;
}

- (nullable NSDictionary *)identifyFileAtPath:(NSString *)path isXCI:(BOOL)isXCI {
    std::lock_guard<std::mutex> lock(_mutex);
    if (!(_symbolsOK && _keysOK && _vfs)) {
        return nil;
    }
    @try {
        std::string_view sv(path.UTF8String);
        VFile file = _openFile(_vfs, sv, kOpenModeRead);
        if (!file) {
            [self setFailure:"open-failed"];
            return nil;
        }
        if (isXCI) {
            alignas(16) char xciBuf[4096] = {};
            FileSys::XCI *xci = (FileSys::XCI *)xciBuf;
            _xciC1(xci, file, 0, 0);
            unsigned long long tid = 0;
            @try {
                tid = _xciProgId(xci);
            } @catch (...) {
                tid = 0;
            }
            _xciD1(xci);
            if (tid == 0) {
                [self setFailure:"xci-no-title"];
                return nil;
            }
            [self setFailure:nullptr];
            return @{
                @"titleID": @(Hex16(tid).c_str()),
                @"programIDs": @[ @(Hex16(tid).c_str()) ],
                @"status": @0,
            };
        } else {
            alignas(16) char nspBuf[4096] = {};
            FileSys::NSP *nsp = (FileSys::NSP *)nspBuf;
            _nspC1(nsp, file, 0, 0);
            int status = 0;
            std::vector<unsigned long long> progIds;
            std::vector<VNca> ncas;
            @try {
                status = _nspStatus(nsp);
                if (status == 0) {
                    progIds = _nspProgIds(nsp);
                    ncas = _nspCollapsed(nsp);
                }
            } @catch (...) {
                status = -1;
            }
            NSString *metaTitle = nil;
            if (status == 0) {
                @try {
                    for (auto &nca : ncas) {
                        if ((_ncaType(nca.get()) & 0xFF) != kNcaTypeMeta) {
                            continue;
                        }
                        if (_ncaStatus(nca.get()) != 0) {
                            continue;
                        }
                        unsigned long long nid = _ncaTitleId(nca.get());
                        if (nid != 0) {
                            metaTitle = @(Hex16(nid).c_str());
                            break;
                        }
                    }
                } @catch (...) {
                    metaTitle = nil;
                }
            }
            _nspD1(nsp);
            if (status != 0) {
                char buf[32];
                snprintf(buf, sizeof(buf), "nsp-status-%d", status);
                [self setFailure:buf];
                return nil;
            }
            NSMutableArray *progStrs = [NSMutableArray array];
            for (auto pid : progIds) {
                [progStrs addObject:@(Hex16(pid).c_str())];
            }
            NSString *primary = metaTitle ?: progStrs.firstObject;
            if (!primary) {
                [self setFailure:"no-program-ids"];
                return nil;
            }
            [self setFailure:nullptr];
            return @{
                @"titleID": primary,
                @"programIDs": progStrs,
                @"status": @(status),
            };
        }
    } @catch (...) {
        [self setFailure:"exception"];
        return nil;
    }
}

@end
