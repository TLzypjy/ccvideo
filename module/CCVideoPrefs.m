#import "CCVideoPrefs.h"
#include <dlfcn.h>

NSString * const CCVBundleID = @"com.wuba.ccvideo";
NSString * const CCVLibraryRoot = @"/var/mobile/Library/CCVideo";
NSString * const CCVVideoDir = @"/var/mobile/Library/CCVideo/Video";
NSString * const CCVThumbDir = @"/var/mobile/Library/CCVideo/Thumb";

NSString * const CCVKeySelectedVideo = @"selectedVideo";
NSString * const CCVKeyPortraitW = @"portraitW";
NSString * const CCVKeyPortraitH = @"portraitH";
NSString * const CCVKeyLandscapeW = @"landscapeW";
NSString * const CCVKeyLandscapeH = @"landscapeH";
NSString * const CCVKeyAspectFill = @"aspectFill";
NSString * const CCVKeyDisplayMode = @"DisplayMode";
NSString * const CCVKeyMaxModules = @"MaxModules";

NSString * const CCVDarwinSettingsChanged = @"com.wuba.ccvideo/SettingsChanged";
NSString * const CCVDarwinReloadSizes = @"com.opa334.ccsupport/ReloadSizes";

NSUserDefaults *CCVPrefs(void) {
    static NSUserDefaults *prefs = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        prefs = [[NSUserDefaults alloc] initWithSuiteName:CCVBundleID];
    });
    return prefs;
}

// ---------- 调试日志 ----------
void CCVLog(NSString *fmt, ...) {
    va_list args;
    va_start(args, fmt);
    NSString *msg = [[NSString alloc] initWithFormat:fmt arguments:args];
    va_end(args);
    NSLog(@"[CCVideo] %@", msg);

    @try {
        static BOOL ensured = NO;
        if (!ensured) { CCVEnsureDirs(); ensured = YES; }
        NSFileManager *fm = [NSFileManager defaultManager];
        // 日志放 Documents 目录（用户用 Filza 方便查看）
        NSString *logDir = @"/var/mobile/Documents";
        if (![fm fileExistsAtPath:logDir]) [fm createDirectoryAtPath:logDir withIntermediateDirectories:YES attributes:nil error:nil];
        NSString *logPath = [logDir stringByAppendingPathComponent:@"CCVideo_log.txt"];
        NSDictionary *attr = [fm attributesOfItemAtPath:logPath error:nil];
        if ([attr fileSize] > 300 * 1024) [fm removeItemAtPath:logPath error:nil]; // 防无限膨胀
        static NSDateFormatter *df = nil;
        static dispatch_once_t once;
        dispatch_once(&once, ^{
            df = [[NSDateFormatter alloc] init];
            df.dateFormat = @"MM-dd HH:mm:ss.SSS";
        });
        NSString *line = [NSString stringWithFormat:@"[%@][%@] %@\n",
                          [df stringFromDate:[NSDate date]],
                          [NSThread isMainThread] ? @"main" : @"bg", msg];
        NSFileHandle *fh = [NSFileHandle fileHandleForWritingAtPath:logPath];
        if (!fh) {
            [fm createFileAtPath:logPath contents:nil attributes:nil];
            fh = [NSFileHandle fileHandleForWritingAtPath:logPath];
        }
        if (fh) {
            [fh seekToEndOfFile];
            [fh writeData:[line dataUsingEncoding:NSUTF8StringEncoding]];
            [fh closeFile];
        }
    } @catch (NSException *e) {
        NSLog(@"[CCVideo] log write failed: %@", e);
    }
}

void CCVEnsureDirs(void) {
    NSFileManager *fm = [NSFileManager defaultManager];
    for (NSString *path in @[CCVLibraryRoot, CCVVideoDir, CCVThumbDir]) {
        if (![fm fileExistsAtPath:path]) {
            [fm createDirectoryAtPath:path withIntermediateDirectories:YES attributes:nil error:nil];
        }
    }
}

void CCVPostDarwin(NSString *name) {
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
                                         (__bridge CFStringRef)name, NULL, NULL, YES);
}

void CCVPostSizeChange(void) {
    CCVPostDarwin(CCVDarwinSettingsChanged);
    CCVPostDarwin(CCVDarwinReloadSizes);
}

// ---------- 多模块 ----------
NSUInteger CCVMaxModules(void) {
    NSInteger v = [CCVPrefs() integerForKey:CCVKeyMaxModules];
    if (v < 1) v = 1;
    if (v > CCV_MAX_MODULES) v = CCV_MAX_MODULES;
    return (NSUInteger)v;
}

void CCVSetMaxModules(NSUInteger n) {
    if (n < 1) n = 1;
    if (n > CCV_MAX_MODULES) n = CCV_MAX_MODULES;
    [CCVPrefs() setInteger:(NSInteger)n forKey:CCVKeyMaxModules];
    [CCVPrefs() synchronize];
}

NSString *CCVKeyForModule(NSString *baseKey, NSUInteger moduleIndex) {
    if (moduleIndex <= 1) return baseKey; // 模块 1 用原键，兼容旧数据
    return [NSString stringWithFormat:@"%@%lu", baseKey, (unsigned long)moduleIndex];
}

// ---------- jbroot 推导（rootless=/var/jb，roothide=随机 jbroot，通用） ----------
NSString *CCVJBRootForProcess(void) {
    Dl_info info;
    if (dladdr((void *)&CCVJBRootForProcess, &info) && info.dli_fname) {
        NSString *selfPath = [NSString stringWithUTF8String:info.dli_fname];
        for (NSString *marker in @[@"/Library/PreferenceBundles/",
                                   @"/Library/ControlCenter/Bundles/",
                                   @"/Library/MobileSubstrate/DynamicLibraries/"]) {
            NSRange r = [selfPath rangeOfString:marker];
            if (r.location != NSNotFound && r.location > 0) {
                return [selfPath substringToIndex:r.location];
            }
        }
    }
    return @"/var/jb"; // rootless 兜底
}

// ---------- 模块 bundle 同步 ----------
// 需要目录可写：deb 的 postinst 已把 ControlCenter/Bundles chmod 0777
BOOL CCVSyncPendingBundles(NSError *__autoreleasing _Nullable *outError) {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *root = CCVJBRootForProcess();
    NSString *ccDir = [root stringByAppendingPathComponent:@"Library/ControlCenter/Bundles"];
    NSString *pendDir = [root stringByAppendingPathComponent:@"Library/CCVideoPendingBundles"];
    NSUInteger max = CCVMaxModules();
    BOOL changed = NO;
    NSError *firstErr = nil;
    CCVLog(@"syncBundles: root=%@ max=%lu", root, (unsigned long)max);

    // 拷贝缺失的（2..max）
    for (NSUInteger n = 2; n <= max; n++) {
        NSString *name = [NSString stringWithFormat:@"CCVideo%lu.bundle", (unsigned long)n];
        NSString *dst = [ccDir stringByAppendingPathComponent:name];
        NSString *src = [pendDir stringByAppendingPathComponent:name];
        if ([fm fileExistsAtPath:dst]) continue;
        if (![fm fileExistsAtPath:src]) {
            CCVLog(@"syncBundles: 缺源 %@（PendingBundles 里没有）", name);
            continue;
        }
        NSError *e = nil;
        if ([fm copyItemAtPath:src toPath:dst error:&e]) {
            changed = YES;
            CCVLog(@"syncBundles: 已拷入 %@", name);
        } else {
            CCVLog(@"syncBundles: 拷入 %@ 失败: %@", name, e);
            if (!firstErr) firstErr = e;
        }
    }
    // 清理多余的（max+1..8）
    for (NSUInteger n = max + 1; n <= CCV_MAX_MODULES; n++) {
        NSString *name = [NSString stringWithFormat:@"CCVideo%lu.bundle", (unsigned long)n];
        NSString *dst = [ccDir stringByAppendingPathComponent:name];
        if (![fm fileExistsAtPath:dst]) continue;
        NSError *e = nil;
        if ([fm removeItemAtPath:dst error:&e]) {
            changed = YES;
            CCVLog(@"syncBundles: 已移除 %@", name);
        } else {
            CCVLog(@"syncBundles: 移除 %@ 失败: %@", name, e);
            if (!firstErr) firstErr = e;
        }
    }
    CCVLog(@"syncBundles: 完成 changed=%d err=%@", changed, firstErr);
    if (outError) *outError = firstErr;
    return changed;
}

NSInteger CCVDisplayMode(void) {
    NSInteger v;
    id obj = [CCVPrefs() objectForKey:CCVKeyDisplayMode];
    if (obj == nil) {
        // 迁移：旧版"画面填充"（模块1） YES=裁切填满 NO=完整适应
        v = [CCVPrefs() boolForKey:CCVKeyForModule(CCVKeyAspectFill, 1)] ? 0 : 1;
    } else {
        v = [obj integerValue];
    }
    if (v < 0) v = 0;
    if (v > 2) v = 2;
    return v;
}

NSString *CCVSelectedVideoNameForModule(NSUInteger moduleIndex) {
    return [CCVPrefs() stringForKey:CCVKeyForModule(CCVKeySelectedVideo, moduleIndex)] ?: @"";
}

void CCVSetSelectedVideo(NSString *name, NSUInteger moduleIndex) {
    [CCVPrefs() setObject:name forKey:CCVKeyForModule(CCVKeySelectedVideo, moduleIndex)];
    [CCVPrefs() synchronize];
}

NSUInteger CCVSizeForModule(NSString *baseKey, NSUInteger moduleIndex) {
    NSInteger v = [CCVPrefs() integerForKey:CCVKeyForModule(baseKey, moduleIndex)];
    if (v <= 0) v = 2;
    return (NSUInteger)MIN(MAX(v, (NSInteger)1), (NSInteger)4);
}

NSString *CCVSelectedVideoName(void) {
    return [CCVPrefs() stringForKey:CCVKeySelectedVideo] ?: @"";
}

NSArray<NSString *> *CCVVideoFileNames(void) {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSArray *items = [fm contentsOfDirectoryAtPath:CCVVideoDir error:nil] ?: @[];
    NSArray *exts = @[@"mp4", @"mov", @"m4v", @"MP4", @"MOV", @"M4V"];
    NSMutableArray *files = [NSMutableArray array];
    for (NSString *name in items) {
        NSString *ext = name.pathExtension;
        if (ext.length && [exts containsObject:ext]) [files addObject:name];
    }
    [files sortUsingSelector:@selector(localizedCaseInsensitiveCompare:)];
    return files;
}

NSString *CCVVideoPathForName(NSString *name) {
    return [CCVVideoDir stringByAppendingPathComponent:name];
}

NSString *CCVThumbPathForVideoName(NSString *videoName) {
    return [[CCVThumbDir stringByAppendingPathComponent:videoName.stringByDeletingPathExtension] stringByAppendingPathExtension:@"png"];
}

void CCVClampSize(NSUInteger *w, NSUInteger *h) {
    NSUInteger cw = (*w == 0) ? 2 : *w;
    NSUInteger ch = (*h == 0) ? 2 : *h;
    cw = MIN(MAX(cw, (NSUInteger)1), (NSUInteger)4);
    ch = MIN(MAX(ch, (NSUInteger)1), (NSUInteger)4);
    *w = cw;
    *h = ch;
}
