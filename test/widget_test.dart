// 首页冒烟测试：应用能正常启动，首页显示全部模块入口。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:superapp/core/settings.dart';
import 'package:superapp/main.dart';
import 'package:superapp/modules/tools/random_number_page.dart';
import 'package:superapp/modules/tools/stopwatch_page.dart';
import 'package:superapp/modules/tools/text_tools_page.dart';
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
    expect(find.text('秒表与倒计时'), findsOneWidget);
    expect(find.text('随机数'), findsOneWidget);
    expect(find.text('文本工具'), findsOneWidget);
    expect(find.text('AiPlat'), findsOneWidget);
    expect(find.text('WebOS'), findsOneWidget);
    expect(find.text('工具'), findsOneWidget);
    expect(find.text('系统'), findsOneWidget);
  });

  testWidgets('新工具页正常渲染', (WidgetTester tester) async {
    // 秒表与倒计时：分段按钮 + 开始按钮。
    await tester.pumpWidget(
      const MaterialApp(home: StopwatchPage()),
    );
    await tester.pumpAndSettle();
    expect(find.text('秒表与倒计时'), findsOneWidget);
    expect(find.text('开始'), findsOneWidget);

    // 随机数：范围输入 + 生成按钮。
    await tester.pumpWidget(
      const MaterialApp(home: RandomNumberPage()),
    );
    await tester.pumpAndSettle();
    expect(find.text('随机数'), findsOneWidget);
    expect(find.text('生成'), findsOneWidget);
    expect(find.text('掷骰子'), findsOneWidget);

    // 文本工具：字数统计卡片 + 转换按钮。
    await tester.pumpWidget(
      const MaterialApp(home: TextToolsPage()),
    );
    await tester.pumpAndSettle();
    expect(find.text('文本工具'), findsOneWidget);
    expect(find.text('字符'), findsOneWidget);
    expect(find.text('转大写'), findsOneWidget);
  });
}
