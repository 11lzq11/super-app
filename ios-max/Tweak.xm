// SuperApp MAX — 越狱插件骨架（Theos / Logos）
//
// ⚠️ 骨架，未验证：
//   - 需要在越狱设备 + Theos 环境下编译安装；本仓库的 CI 与开发机
//     均未编译过它，也未在任何真机上测试过。
//   - 下面所有系统级操作（偏好读写、文件读写、respring）都是按
//     Theos/Logos 常规写法给出的骨架，具体行为取决于注入目标的
//     运行身份（mobile 还是 root）与越狱类型（Rootful / Rootless）。
//   - 正式使用前必须在测试设备上逐项验证，见 ios-max/README.md。
//
// 设计：
//   SuperApp（Flutter 侧）与本插件之间用两条通道通信：
//   1. Darwin 通知 + 共享 JSON 文件（主通道）：
//      App 把请求写成 /var/mobile/Library/SuperApp/request-<id>.json，
//      再发 Darwin 通知 com.superapp.max.request；
//      插件收到后执行，把结果写成 response-<id>.json，
//      再发通知 com.superapp.max.response，App 读回结果。
//   2. URL Scheme（辅助通道）：superapp-max://<action>?<params>
//      由 SpringBoard 路由到 SuperApp，用于从插件侧唤起 App。
//      Dart 侧的 deep-link 处理尚未实现（后续工作），见 README。
//
// 请求 JSON 格式：
//   {"id": "uuid", "action": "ping|readPref|writePref|readFile|writeFile|listDir|respring|systemInfo", "params": {...}}
// 响应 JSON 格式：
//   {"id": "uuid", "ok": true/false, "result": {...}, "error": "失败原因"}

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <CoreFoundation/CoreFoundation.h>
#import <stdlib.h>
#import <sys/utsname.h>
#import <unistd.h>

#pragma mark - 常量

/// App 与插件共享的目录（需配合 TrollStore 权限或越狱环境才能跨沙盒访问）。
static NSString * const SAMaxSharedDirectory = @"/var/mobile/Library/SuperApp";

/// Darwin 通知名：App → 插件（有新请求）。
static NSString * const SAMaxRequestNotification = @"com.superapp.max.request";

/// Darwin 通知名：插件 → App（有新响应）。
static NSString * const SAMaxResponseNotification = @"com.superapp.max.response";

/// 本插件版本（与 SuperApp 的 iOS MAX 检测约定一致）。
static NSString * const SAMaxTweakVersion = @"0.1.0";

/// 单个文件读写的上限（与 App 侧文件上传 200KB 的限制对齐）。
static const NSUInteger SAMaxMaxFileBytes = 200 * 1024;

#pragma mark - 工具函数

/// 确保共享目录存在；失败返回 NO（调用方应把错误写进响应）。
static BOOL SAMaxEnsureSharedDirectory(void) {
    NSFileManager *fm = [NSFileManager defaultManager];
    BOOL isDir = NO;
    if ([fm fileExistsAtPath:SAMaxSharedDirectory isDirectory:&isDir] && isDir) {
        return YES;
    }
    NSError *error = nil;
    BOOL ok = [fm createDirectoryAtPath:SAMaxSharedDirectory
            withIntermediateDirectories:YES
                             attributes:nil
                                  error:&error];
    if (!ok) {
        NSLog(@"[SuperAppMax] 创建共享目录失败: %@", error);
    }
    return ok;
}

/// 把字典写成 JSON 文件（原子写入，避免 App 读到一半）。
static BOOL SAMaxWriteJSON(NSDictionary *dict, NSString *path) {
    NSError *error = nil;
    NSData *data = [NSJSONSerialization dataWithJSONObject:dict
                                                   options:0
                                                     error:&error];
    if (!data) {
        NSLog(@"[SuperAppMax] JSON 序列化失败: %@", error);
        return NO;
    }
    return [data writeToFile:path options:NSDataWritingAtomic error:&error];
}

/// 只接受 NSString / NSNumber / NSNull 这种能直接进 JSON 的偏好值，
/// 其他类型（NSData、NSArray、NSDictionary）返回其 description，
/// 避免序列化失败。正式版可按需放宽。
static id SAMaxJSONSafeValue(id value) {
    if (value == nil) return [NSNull null];
    if ([value isKindOfClass:[NSString class]] ||
        [value isKindOfClass:[NSNumber class]] ||
        [value isKindOfClass:[NSNull class]]) {
        return value;
    }
    return [value description];
}

#pragma mark - 请求处理

/// 执行一条请求，返回响应字典（不含 id，调用方补上）。
/// 注意：所有写操作都没有路径/域名白名单——骨架阶段如此，
/// 正式版必须加白名单（见 README“安全注意事项”）。
static NSDictionary *SAMaxHandleRequest(NSDictionary *request) {
    NSString *action = request[@"action"];
    NSDictionary *params = request[@"params"];
    if (![params isKindOfClass:[NSDictionary class]]) params = @{};
    if (![action isKindOfClass:[NSString class]]) {
        return @{@"ok": @NO, @"error": @"缺少 action 字段"};
    }

    // ping：连通性检查，顺带上报当前 uid（0 表示以 root 运行）。
    if ([action isEqualToString:@"ping"]) {
        return @{
            @"ok": @YES,
            @"result": @{
                @"tweak": SAMaxTweakVersion,
                @"uid": @(getuid()),
            },
        };
    }

    // systemInfo：设备型号、系统版本、当前 uid。
    if ([action isEqualToString:@"systemInfo"]) {
        struct utsname uts;
        uname(&uts);
        return @{
            @"ok": @YES,
            @"result": @{
                @"machine": [NSString stringWithUTF8String:uts.machine],
                @"systemVersion": [[UIDevice currentDevice] systemVersion] ?: @"",
                @"uid": @(getuid()),
                @"tweak": SAMaxTweakVersion,
            },
        };
    }

    // readPref：读系统/应用偏好。params: {domain, key}
    // 用 CFPreferencesCopyAppValue（当前用户）。root 拥有的域在
    // mobile 身份下只能读、不能写，写会静默失败，见 writePref。
    if ([action isEqualToString:@"readPref"]) {
        NSString *domain = params[@"domain"];
        NSString *key = params[@"key"];
        if (![domain isKindOfClass:[NSString class]] ||
            ![key isKindOfClass:[NSString class]]) {
            return @{@"ok": @NO, @"error": @"readPref 需要 domain 与 key"};
        }
        id value = CFBridgingRelease(
            CFPreferencesCopyAppValue((CFStringRef)key, (CFStringRef)domain));
        return @{@"ok": @YES, @"result": @{@"value": SAMaxJSONSafeValue(value)}};
    }

    // writePref：写偏好。params: {domain, key, value}
    // ⚠️ 需要写目标域的权限；SpringBoard 以 mobile 身份运行时，
    // root 拥有的系统域写不进去。需要 root 写能力时，应由一个以
    // root 运行的守护进程代写（TODO，未实现）。
    if ([action isEqualToString:@"writePref"]) {
        NSString *domain = params[@"domain"];
        NSString *key = params[@"key"];
        id value = params[@"value"];
        if (![domain isKindOfClass:[NSString class]] ||
            ![key isKindOfClass:[NSString class]] || value == nil) {
            return @{@"ok": @NO, @"error": @"writePref 需要 domain、key 与 value"};
        }
        CFPreferencesSetAppValue((CFStringRef)key, (CFPropertyListRef)value,
                                 (CFStringRef)domain);
        BOOL synced = CFPreferencesAppSynchronize((CFStringRef)domain);
        return @{@"ok": @(synced), @"result": @{@"synced": @(synced)}};
    }

    // readFile：读文件内容（UTF-8 文本，超限拒绝）。params: {path}
    if ([action isEqualToString:@"readFile"]) {
        NSString *path = params[@"path"];
        if (![path isKindOfClass:[NSString class]]) {
            return @{@"ok": @NO, @"error": @"readFile 需要 path"};
        }
        NSError *error = nil;
        NSDictionary *attrs = [[NSFileManager defaultManager]
            attributesOfItemAtPath:path error:&error];
        if (attrs && [attrs fileSize] > SAMaxMaxFileBytes) {
            return @{@"ok": @NO, @"error": @"文件超过 200KB 上限"};
        }
        NSString *content = [NSString stringWithContentsOfFile:path
                                                      encoding:NSUTF8StringEncoding
                                                         error:&error];
        if (!content) {
            return @{@"ok": @NO,
                     @"error": [NSString stringWithFormat:@"读文件失败: %@", error]};
        }
        return @{@"ok": @YES, @"result": @{@"content": content}};
    }

    // writeFile：写文件（UTF-8 文本）。params: {path, content}
    // ⚠️ 骨架未做路径白名单；正式版只允许写白名单内的路径。
    if ([action isEqualToString:@"writeFile"]) {
        NSString *path = params[@"path"];
        NSString *content = params[@"content"];
        if (![path isKindOfClass:[NSString class]] ||
            ![content isKindOfClass:[NSString class]]) {
            return @{@"ok": @NO, @"error": @"writeFile 需要 path 与 content"};
        }
        NSError *error = nil;
        BOOL ok = [content writeToFile:path
                            atomically:YES
                              encoding:NSUTF8StringEncoding
                                 error:&error];
        if (!ok) {
            return @{@"ok": @NO,
                     @"error": [NSString stringWithFormat:@"写文件失败: %@", error]};
        }
        return @{@"ok": @YES, @"result": @{@"path": path}};
    }

    // listDir：列目录。params: {path}
    if ([action isEqualToString:@"listDir"]) {
        NSString *path = params[@"path"];
        if (![path isKindOfClass:[NSString class]]) {
            return @{@"ok": @NO, @"error": @"listDir 需要 path"};
        }
        NSError *error = nil;
        NSArray *names = [[NSFileManager defaultManager]
            contentsOfDirectoryAtPath:path error:&error];
        if (!names) {
            return @{@"ok": @NO,
                     @"error": [NSString stringWithFormat:@"列目录失败: %@", error]};
        }
        return @{@"ok": @YES, @"result": @{@"entries": names}};
    }

    // respring：重启 SpringBoard。
    // ⚠️ 高危操作：只在用户明确确认后调用；且只有以 root 身份运行时
    // 才可靠，mobile 身份下 killall backboardd 可能无权限（TODO：
    // Rootful 下由 root 守护进程代执行；Rootless 下需用 sbreload 等替代，
    // 均未验证）。
    if ([action isEqualToString:@"respring"]) {
        int rc = system("killall -9 backboardd");
        return @{@"ok": @(rc == 0), @"result": @{@"exitCode": @(rc)}};
    }

    return @{@"ok": @NO,
             @"error": [NSString stringWithFormat:@"未知 action：%@", action]};
}

/// 扫描共享目录里的 request-*.json，逐个处理并写回 response-<id>.json，
/// 处理完删除请求文件，最后发响应通知。
static void SAMaxProcessPendingRequests(void) {
    if (!SAMaxEnsureSharedDirectory()) return;
    NSFileManager *fm = [NSFileManager defaultManager];
    NSError *error = nil;
    NSArray *names = [fm contentsOfDirectoryAtPath:SAMaxSharedDirectory
                                               error:&error];
    if (!names) {
        NSLog(@"[SuperAppMax] 列共享目录失败: %@", error);
        return;
    }
    for (NSString *name in names) {
        if (![name hasPrefix:@"request-"] ||
            ![[name pathExtension] isEqualToString:@"json"]) {
            continue;
        }
        NSString *requestPath =
            [SAMaxSharedDirectory stringByAppendingPathComponent:name];
        NSData *data = [NSData dataWithContentsOfFile:requestPath];
        NSDictionary *request = nil;
        if (data) {
            request = [NSJSONSerialization JSONObjectWithData:data
                                                      options:0
                                                        error:NULL];
        }
        NSString *requestId = request[@"id"];
        if (![request isKindOfClass:[NSDictionary class]] ||
            ![requestId isKindOfClass:[NSString class]]) {
            [fm removeItemAtPath:requestPath error:NULL];
            continue;
        }
        NSDictionary *responseBody = SAMaxHandleRequest(request);
        NSMutableDictionary *response = [responseBody mutableCopy];
        response[@"id"] = requestId;
        NSString *responsePath = [SAMaxSharedDirectory
            stringByAppendingPathComponent:
                [NSString stringWithFormat:@"response-%@.json", requestId]];
        if (SAMaxWriteJSON(response, responsePath)) {
            CFNotificationCenterPostNotification(
                CFNotificationCenterGetDarwinNotifyCenter(),
                (CFStringRef)SAMaxResponseNotification, NULL, NULL, true);
        }
        [fm removeItemAtPath:requestPath error:NULL];
    }
}

/// Darwin 通知回调：App 发来新请求时触发。
static void SAMaxRequestCallback(CFNotificationCenterRef center,
                                 void *observer,
                                 CFStringRef name,
                                 const void *object,
                                 CFDictionaryRef userInfo) {
    SAMaxProcessPendingRequests();
}

/// 注册 Darwin 通知监听（重复注册无害，系统会去重）。
static void SAMaxRegisterObserver(void) {
    CFNotificationCenterAddObserver(
        CFNotificationCenterGetDarwinNotifyCenter(),
        NULL,
        SAMaxRequestCallback,
        (CFStringRef)SAMaxRequestNotification,
        NULL,
        CFNotificationSuspensionBehaviorDeliverImmediately);
    // 启动时顺带处理一次，避免通知丢失导致请求一直挂着。
    SAMaxProcessPendingRequests();
    NSLog(@"[SuperAppMax] IPC 监听已注册（%@）", SAMaxRequestNotification);
}

#pragma mark - Hooks（示例）

/// 钩 SpringBoard 的启动回调，在系统桌面就绪后注册 IPC 监听。
/// %ctor 里也会注册一次，双保险；Hook 本身不改 SpringBoard 行为。
%hook SpringBoard
- (void)applicationDidFinishLaunching:(id)application {
    %orig;
    SAMaxRegisterObserver();
}
%end

/// 插件加载入口：注入到 SpringBoard 时执行。
%ctor {
    SAMaxRegisterObserver();
    NSLog(@"[SuperAppMax] tweak %@ 已加载", SAMaxTweakVersion);
}
