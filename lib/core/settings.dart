import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// root 检测结果（核心壳内部用）。
///
/// 注意：supermax 模块里另有一个同名的 `RootStatus` 类（lib/supermax/root.dart），
/// 为避免重名，这里的枚举叫 [RootCheckStatus]。
enum RootCheckStatus {
  /// 尚未检测。
  unknown,

  /// 已检测到 root。
  rooted,

  /// 未检测到 root。
  notRooted,
}

/// root 检测接口。
///
/// 由 supermax 模块（lib/supermax/root.dart）实现并通过
/// [SettingsService.registerRootChecker] 注册。
/// 核心壳不自己实现 root 检测，只持有这个接口。
abstract class RootChecker {
  /// 执行一次 root 检测，返回结果。
  Future<RootCheckStatus> check();
}

/// Super MAX 控制器接口。
///
/// 由 supermax 模块的 [SuperMaxService] 实现。[SettingsService] 通过
/// [SettingsService.bindSuperMax] 绑定它之后，Super MAX 开关的唯一事实源
/// 就是 SuperMaxService，SettingsService 只做委托转发，避免两边状态漂移。
/// 用接口而不是直接依赖具体类，是为了让 core 层不直接依赖 supermax 模块。
abstract class SuperMaxController extends ChangeNotifier {
  /// Super MAX 是否开启。
  bool get isEnabled;

  /// 是否已检测到 root（缓存的检测结果）。
  bool get isRooted;

  /// 开启 Super MAX（内部先检测 root，未 root 返回 false）。
  Future<bool> enable();

  /// 关闭 Super MAX，立即生效。
  Future<void> disable();

  /// 重新检测 root，返回是否已 root。
  Future<bool> refreshRoot();
}

/// 统一设置服务：主题、Super MAX 开关、root 状态缓存、语言。
///
/// 用 shared_preferences 持久化，通过 Provider 提供给全应用。
/// 语言固定为简体中文。
///
/// Super MAX 开关：绑定 [SuperMaxController] 后，开关状态完全由它决定
/// （[superMaxEnabled] 直接读它的 [SuperMaxController.isEnabled]），
/// 未绑定时才用本地保存的值（兜底）。
class SettingsService extends ChangeNotifier {
  SettingsService._(this._prefs)
      : _themeMode = _themeModeFromString(
          _prefs.getString(_keyThemeMode) ?? 'system',
        ),
        _superMaxEnabled = _prefs.getBool(_keySuperMax) ?? false,
        _rootStatus = _rootStatusFromString(
          _prefs.getString(_keyRootStatus) ?? 'unknown',
        );

  static const String _keyThemeMode = 'theme_mode';
  static const String _keySuperMax = 'supermax_enabled';
  static const String _keyRootStatus = 'root_status';

  final SharedPreferences _prefs;

  /// 检测器：由 supermax 模块注册；未注册时无法检测 root。
  RootChecker? _rootChecker;

  /// 绑定的 Super MAX 控制器（唯一事实源），未绑定时为 null。
  SuperMaxController? _superMax;

  ThemeMode _themeMode;

  /// 未绑定控制器时的本地开关值（兜底）；绑定后以控制器为准。
  bool _superMaxEnabled;
  RootCheckStatus _rootStatus;

  /// 从本地存储加载设置。
  static Future<SettingsService> load() async {
    final prefs = await SharedPreferences.getInstance();
    return SettingsService._(prefs);
  }

  /// 当前主题模式。
  ThemeMode get themeMode => _themeMode;

  /// Super MAX 是否开启（默认 false）。
  ///
  /// 绑定控制器后直接读控制器的状态，否则读本地保存的值。
  bool get superMaxEnabled => _superMax?.isEnabled ?? _superMaxEnabled;

  /// 缓存的 root 检测结果。
  RootCheckStatus get rootStatus => _rootStatus;

  /// 是否检测到 root（Super MAX 可用的前提）。
  bool get isRooted =>
      _superMax?.isRooted ?? _rootStatus == RootCheckStatus.rooted;

  /// 语言固定为简体中文。
  Locale get locale => const Locale('zh', 'CN');

  /// 注册 root 检测器（supermax 模块在接入时调用）。
  void registerRootChecker(RootChecker checker) {
    _rootChecker = checker;
  }

  /// 绑定 Super MAX 控制器（唯一事实源）。
  ///
  /// 绑定后开关状态以控制器为准，并转发它的变化通知，
  /// 让首页徽标、设置页开关等依赖 SettingsService 的 UI 跟着更新。
  void bindSuperMax(SuperMaxController controller) {
    if (_superMax == controller) return;
    _superMax?.removeListener(_onSuperMaxChanged);
    _superMax = controller;
    _superMax!.addListener(_onSuperMaxChanged);
    _superMaxEnabled = controller.isEnabled;
    notifyListeners();
  }

  void _onSuperMaxChanged() {
    notifyListeners();
  }

  /// 设置主题模式并持久化。
  Future<void> setThemeMode(ThemeMode mode) async {
    if (_themeMode == mode) return;
    _themeMode = mode;
    await _prefs.setString(_keyThemeMode, _themeModeToString(mode));
    notifyListeners();
  }

  /// 设置 Super MAX 开关。
  ///
  /// 绑定控制器后委托给它（开启时它内部会检测 root，未 root 返回 false）；
  /// 未绑定时用本地逻辑。返回 true 表示设置已生效。
  Future<bool> setSuperMaxEnabled(bool value) async {
    final controller = _superMax;
    if (controller != null) {
      if (value) {
        if (!isRooted) return false;
        return controller.enable();
      }
      await controller.disable();
      return true;
    }
    if (value && !isRooted) return false;
    if (_superMaxEnabled == value) return true;
    _superMaxEnabled = value;
    await _prefs.setBool(_keySuperMax, value);
    notifyListeners();
    return true;
  }

  /// 刷新 root 检测结果并缓存。
  ///
  /// 绑定控制器时：force 为 false 只同步它缓存的检测结果（不重新检测，
  /// 避免启动时重复弹 su 授权）；force 为 true 才重新检测。
  /// 未绑定时走 [RootChecker] 适配器（兜底）。
  /// 若本次检测不到 root 而 Super MAX 正开着，自动关闭 Super MAX。
  Future<void> refreshRootStatus({bool force = false}) async {
    final controller = _superMax;
    if (controller != null) {
      final rooted = force
          ? await controller.refreshRoot()
          : controller.isRooted;
      _setRootStatus(
        rooted ? RootCheckStatus.rooted : RootCheckStatus.notRooted,
      );
      return;
    }
    final checker = _rootChecker;
    final RootCheckStatus result;
    if (checker == null) {
      result = RootCheckStatus.notRooted;
    } else {
      result = await checker.check();
    }
    _setRootStatus(result);
    if (result != RootCheckStatus.rooted && _superMaxEnabled) {
      _superMaxEnabled = false;
      await _prefs.setBool(_keySuperMax, false);
      notifyListeners();
    }
  }

  void _setRootStatus(RootCheckStatus result) {
    if (_rootStatus == result) return;
    _rootStatus = result;
    _prefs.setString(_keyRootStatus, _rootStatusToString(result));
    notifyListeners();
  }

  static String _themeModeToString(ThemeMode mode) {
    return switch (mode) {
      ThemeMode.light => 'light',
      ThemeMode.dark => 'dark',
      ThemeMode.system => 'system',
    };
  }

  static ThemeMode _themeModeFromString(String value) {
    return switch (value) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => ThemeMode.system,
    };
  }

  static String _rootStatusToString(RootCheckStatus status) {
    return switch (status) {
      RootCheckStatus.rooted => 'rooted',
      RootCheckStatus.notRooted => 'not_rooted',
      RootCheckStatus.unknown => 'unknown',
    };
  }

  static RootCheckStatus _rootStatusFromString(String value) {
    return switch (value) {
      'rooted' => RootCheckStatus.rooted,
      'not_rooted' => RootCheckStatus.notRooted,
      _ => RootCheckStatus.unknown,
    };
  }
}
