// SpringBoard 侧助手：不 hook 任何方法，仅监听 Darwin 通知。
// 收到 SettingsChanged 后比对 MaxModules 与已装模块 bundle 数：
// 缺少的 CCVideoN.bundle 从 PendingBundles 拷入 ControlCenter/Bundles，然后 exit(0) 注销载入。
#import <Foundation/Foundation.h>
#include <dlfcn.h>
#include <stdlib.h>

// 从 tweak 自身 dylib 加载路径推导 jbroot（rootless=/var/jb，roothide=随机 jbroot，通用）
static NSString *CCVJBRoot(void) {
    Dl_info info;
    if (dladdr((void *)&CCVJBRoot, &info) && info.dli_fname) {
        NSString *selfPath = [NSString stringWithUTF8String:info.dli_fname];
        NSString *marker = @"/Library/MobileSubstrate/DynamicLibraries/";
        NSRange r = [selfPath rangeOfString:marker];
        if (r.location != NSNotFound && r.location > 0) {
            return [selfPath substringToIndex:r.location];
        }
    }
    NSFileManager *fm = [NSFileManager defaultManager];
    if ([fm fileExistsAtPath:@"/var/jb"]) return @"/var/jb"; // rootless 兜底
    return @"/var/jb";
}

static void CCVSBNotifyCallback(CFNotificationCenterRef center, void *observer,
                                CFStringRef name, const void *object, CFDictionaryRef userInfo) {
    dispatch_async(dispatch_get_main_queue(), ^{
        CFPreferencesAppSynchronize((__bridge CFStringRef)@"com.wuba.ccvideo");
        NSUserDefaults *ud = [[NSUserDefaults alloc] initWithSuiteName:@"com.wuba.ccvideo"];
        NSInteger max = [ud integerForKey:@"MaxModules"];
        if (max < 1) max = 1;
        if (max > 8) max = 8;

        NSFileManager *fm = [NSFileManager defaultManager];
        NSString *root = CCVJBRoot();
        NSString *ccDir = [root stringByAppendingPathComponent:@"Library/ControlCenter/Bundles"];
        NSString *pendDir = [root stringByAppendingPathComponent:@"Library/CCVideoPendingBundles"];
        BOOL changed = NO;
        for (int n = 2; n <= max; n++) {
            NSString *bundleName = [NSString stringWithFormat:@"CCVideo%d.bundle", n];
            NSString *dst = [ccDir stringByAppendingPathComponent:bundleName];
            if ([fm fileExistsAtPath:dst]) continue;
            NSString *src = [pendDir stringByAppendingPathComponent:bundleName];
            if (![fm fileExistsAtPath:src]) continue;
            NSError *err = nil;
            if ([fm copyItemAtPath:src toPath:dst error:&err]) {
                changed = YES;
            } else {
                NSLog(@"[CCVideoSBS] copy %@ failed: %@", bundleName, err);
            }
        }
        if (changed) exit(0); // 注销 SpringBoard 载入新模块
    });
}

__attribute__((constructor)) static void CCVideoSBSInit(void) {
    CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(),
                                    NULL,
                                    CCVSBNotifyCallback,
                                    CFSTR("com.wuba.ccvideo/SettingsChanged"),
                                    NULL,
                                    CFNotificationSuspensionBehaviorDeliverImmediately);
    // 启动时同步一次（兜底上次注销前未完成拷贝 / deb 升级后补齐）
    dispatch_async(dispatch_get_main_queue(), ^{
        CFPreferencesAppSynchronize((__bridge CFStringRef)@"com.wuba.ccvideo");
        CCVSBNotifyCallback(NULL, NULL, NULL, NULL, NULL);
    });
}
