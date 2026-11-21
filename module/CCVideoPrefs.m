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
