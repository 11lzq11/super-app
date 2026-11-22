import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:superapp/modules/webos/window_manager.dart';

void main() {
  group('WindowManager 摆放约束', () {
    test('openWindow 不带 area 时使用默认偏移', () {
      final wm = WindowManager();
      addTearDown(wm.dispose);
      final w = wm.openWindow(appId: 'notes', title: '记事本');
      expect(w.offset, const Offset(48, 40));
      expect(w.size, const Size(520, 380));
    });

    test('openWindow 带 area 时初始位置与尺寸被夹在区域内', () {
      final wm = WindowManager();
      addTearDown(wm.dispose);
      const area = Size(400, 300);
      final w = wm.openWindow(
        appId: 'notes',
        title: '记事本',
        offset: const Offset(1000, 1000),
        size: const Size(520, 380),
        area: area,
      );
      // 尺寸先被夹到区域大小，位置再被夹到区域内（窗口整体不超区）。
      expect(w.size.width, lessThanOrEqualTo(area.width));
      expect(w.size.height, lessThanOrEqualTo(area.height));
      expect(w.offset.dx, greaterThanOrEqualTo(0));
      expect(w.offset.dy, greaterThanOrEqualTo(0));
      expect(w.offset.dx, lessThanOrEqualTo(area.width - w.size.width));
      expect(w.offset.dy, lessThanOrEqualTo(area.height - w.size.height));
    });

    test('openWindow 默认偏移超出小区域时也被夹住（不会顶到顶栏）', () {
      final wm = WindowManager();
      addTearDown(wm.dispose);
      const area = Size(360, 300);
      final w = wm.openWindow(appId: 'notes', title: '记事本', area: area);
      expect(w.offset.dy, greaterThanOrEqualTo(0));
      expect(w.offset.dy, lessThanOrEqualTo(area.height - w.size.height));
    });

    test('moveWindow 不能把标题栏拖出区域顶部或左侧', () {
      final wm = WindowManager();
      addTearDown(wm.dispose);
      const area = Size(800, 600);
      final w = wm.openWindow(appId: 'notes', title: '记事本', area: area);
      wm.moveWindow(w.id, const Offset(-500, -500), area);
      expect(w.offset.dx, 0);
      expect(w.offset.dy, 0);
      wm.moveWindow(w.id, const Offset(5000, 5000), area);
      expect(w.offset.dx, lessThanOrEqualTo(area.width - 120));
      expect(w.offset.dy, lessThanOrEqualTo(area.height - 48));
    });

    test('resizeWindow 限制在最小尺寸与区域之间', () {
      final wm = WindowManager();
      addTearDown(wm.dispose);
      const area = Size(800, 600);
      final w = wm.openWindow(appId: 'notes', title: '记事本', area: area);
      wm.resizeWindow(w.id, const Offset(-1000, -1000), area);
      expect(w.size, const Size(320, 240));
      wm.resizeWindow(w.id, const Offset(5000, 5000), area);
      expect(w.size.width, lessThanOrEqualTo(area.width));
      expect(w.size.height, lessThanOrEqualTo(area.height));
    });

    test('toggleMaximize 使用传入的 area，还原后回到原位置', () {
      final wm = WindowManager();
      addTearDown(wm.dispose);
      const area = Size(800, 600);
      final w = wm.openWindow(appId: 'notes', title: '记事本', area: area);
      wm.toggleMaximize(w.id, area);
      expect(w.maximized, isTrue);
      expect(w.size, area);
      expect(w.offset, Offset.zero);
      wm.toggleMaximize(w.id, area);
      expect(w.maximized, isFalse);
      expect(w.offset, const Offset(48, 40));
      expect(w.size, const Size(520, 380));
    });
  });
}
