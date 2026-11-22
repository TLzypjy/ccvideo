#import "CCVideoPrefs.h"

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
    return [NSString stringWithFormat:@"%@%@", baseKey, (unsigned long)moduleIndex];
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
