import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'core/router.dart';
import 'core/settings.dart';
import 'core/theme.dart';
import 'pages/home_page.dart';
import 'pages/module_placeholder_page.dart';
import 'supermax/root.dart' as root_detect;
import 'supermax/supermax_service.dart';

/// 把 supermax 模块的 [root_detect.RootService] 接到核心壳的
/// [RootChecker] 接口上（适配器，不改 supermax 目录）。
///
/// 这是兜底路径：main() 里 SuperMaxService 绑定后，root 检测走
/// SuperMaxService，不再走这个适配器；只有未绑定时才用它。
class _RootServiceAdapter implements RootChecker {
  _RootServiceAdapter(this._rootService);

  final root_detect.RootService _rootService;

  @override
  Future<RootCheckStatus> check() async {
    final status = await _rootService.detect(force: true);
    return status.isRooted
        ? RootCheckStatus.rooted
        : RootCheckStatus.notRooted;
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Super MAX 是开关的唯一事实源：先初始化它（内部会检测一次 root，
  // 已 root 的手机首次运行可能弹一次 APatch 的 su 授权窗，这是正常的）。
  final superMax = SuperMaxService();
  await superMax.init();
  final settings = await SettingsService.load();
  // 把 Super MAX 绑定为 SettingsService 的事实源，开关不再各管各。
  settings.bindSuperMax(superMax);
  // 兜底的 root 检测器（绑定后一般走不到它）。
  settings.registerRootChecker(
    _RootServiceAdapter(root_detect.RootService()),
  );
  // 同步缓存的 root 状态（不重新检测，避免启动时重复弹 su 授权）。
  await settings.refreshRootStatus();
  runApp(SuperApp(settings: settings, superMax: superMax));
}

/// SuperApp 根组件：提供 SettingsService 与 SuperMaxService，应用主题与路由。
class SuperApp extends StatelessWidget {
  const SuperApp({super.key, required this.settings, required this.superMax});

  final SettingsService settings;
  final SuperMaxService superMax;

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<SettingsService>.value(value: settings),
        ChangeNotifierProvider<SuperMaxService>.value(value: superMax),
      ],
      child: Consumer<SettingsService>(
        builder: (context, settings, _) {
          return MaterialApp(
            title: 'SuperApp',
            debugShowCheckedModeBanner: false,
            theme: AppTheme.light,
            darkTheme: AppTheme.dark,
            themeMode: settings.themeMode,
            locale: settings.locale,
            home: const HomePage(),
            routes: AppRoutes.routes,
            onUnknownRoute: (_) => MaterialPageRoute(
              builder: (_) => const ModulePlaceholderPage(
                title: '页面不存在',
                message: '你要找的页面不存在。',
              ),
            ),
          );
        },
      ),
    );
  }
}
