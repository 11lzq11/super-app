// 首页冒烟测试：应用能正常启动，首页显示全部模块入口。
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:superapp/core/settings.dart';
import 'package:superapp/main.dart';
import 'package:superapp/supermax/supermax_service.dart';

void main() {
  testWidgets('首页正常显示模块入口', (WidgetTester tester) async {
    // 用足够高的视口，让 ListView 里的所有分区都完成构建。
    tester.view.physicalSize = const Size(800, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    SharedPreferences.setMockInitialValues({});
    final settings = await SettingsService.load();
    final superMax = SuperMaxService();
    await tester.pumpWidget(SuperApp(settings: settings, superMax: superMax));
    await tester.pumpAndSettle();

    expect(find.text('SuperApp'), findsOneWidget);
    expect(find.text('科学计算器'), findsOneWidget);
    expect(find.text('单位转换'), findsOneWidget);
    expect(find.text('函数绘制'), findsOneWidget);
    expect(find.text('密码生成器'), findsOneWidget);
    expect(find.text('JSON 格式化'), findsOneWidget);
    expect(find.text('二维码生成'), findsOneWidget);
    expect(find.text('AiPlat'), findsOneWidget);
    expect(find.text('WebOS'), findsOneWidget);
    expect(find.text('工具'), findsOneWidget);
    expect(find.text('系统'), findsOneWidget);
  });
}
