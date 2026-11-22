// Super MAX 工具箱命令库的单元测试：纯 Dart 逻辑，不需要设备。
import 'package:flutter_test/flutter_test.dart';
import 'package:superapp/supermax/toolbox_commands.dart';

void main() {
  group('shellQuote', () {
    test('普通路径加单引号', () {
      expect(shellQuote('/data/data/com.example'), "'/data/data/com.example'");
    });

    test('单引号被转义', () {
      expect(shellQuote("a'b"), "'a'\\''b'");
    });
  });

  group('包名与域名校验', () {
    test('合法包名', () {
      expect(isValidPackageName('com.example.app'), isTrue);
      expect(isValidPackageName('com.example'), isTrue);
    });

    test('非法包名', () {
      expect(isValidPackageName('example'), isFalse);
      expect(isValidPackageName('com.example.app; rm -rf /'), isFalse);
      expect(isValidPackageName(''), isFalse);
    });

    test('合法域名', () {
      expect(isValidDomain('doubleclick.net'), isTrue);
      expect(isValidDomain('ad.example.com'), isTrue);
    });

    test('非法域名', () {
      expect(isValidDomain('facebook.com/tr'), isFalse);
      expect(isValidDomain('not a domain'), isFalse);
      expect(isValidDomain(''), isFalse);
    });
  });

  group('settings 命令', () {
    test('settingsPut 生成正确命令', () {
      final cmd = settingsPut('system', 'screen_brightness', '10');
      expect(cmd.command, "settings put system screen_brightness '10'");
      expect(cmd.description, contains('屏幕亮度'));
    });

    test('settingsGet / settingsDelete', () {
      expect(settingsGet('global', 'low_power').command,
          'settings get global low_power');
      expect(settingsDelete('secure', 'foo').command,
          'settings delete secure foo');
    });

    test('parseSettingsList 解析键值对', () {
      const output = '''
screen_brightness=10
font_scale=1.15
weird line without equals
key_with_equals=a=b=c

''';
      final map = parseSettingsList(output);
      expect(map['screen_brightness'], '10');
      expect(map['font_scale'], '1.15');
      expect(map['key_with_equals'], 'a=b=c');
      expect(map.length, 3);
    });
  });

  group('AI 命令解析', () {
    test('正常 JSON：亮度 + 蓝牙', () {
      const text = '''
{"commands": [
  {"action": "settings_put", "table": "system", "key": "screen_brightness", "value": "10"},
  {"action": "settings_put", "table": "system", "key": "screen_brightness_mode", "value": "0"},
  {"action": "svc", "service": "bluetooth", "state": "disable"}
]}
''';
      final result = parseAiCommandList(text);
      expect(result.success, isTrue);
      expect(result.commands.length, 3);
      expect(result.commands[0].command,
          "settings put system screen_brightness '10'");
      expect(result.commands[2].command, 'svc bluetooth disable');
      expect(result.ignored, isEmpty);
    });

    test('```json 代码块包裹能解析', () {
      const text = '''
```json
{"commands": [{"action": "night", "value": "yes"}]}
```
''';
      final result = parseAiCommandList(text);
      expect(result.commands.length, 1);
      expect(result.commands.first.command, 'cmd uimode night yes');
    });

    test('前后多余文字不影响解析', () {
      const text = '好的，这是命令：{"commands": [{"action": "svc", "service": "wifi", "state": "enable"}]} 请确认。';
      final result = parseAiCommandList(text);
      expect(result.commands.length, 1);
      expect(result.commands.first.command, 'svc wifi enable');
    });

    test('非法 action 被忽略并记录', () {
      const text =
          '{"commands": [{"action": "rm", "path": "/"}, {"action": "svc", "service": "wifi", "state": "enable"}]}';
      final result = parseAiCommandList(text);
      expect(result.commands.length, 1);
      expect(result.ignored.length, 1);
    });

    test('非法表名 / 键名被忽略', () {
      const text = '{"commands": ['
          '{"action": "settings_put", "table": "evil", "key": "x", "value": "1"},'
          '{"action": "settings_put", "table": "system", "key": "bad-key!", "value": "1"},'
          '{"action": "settings_put", "table": "global", "key": "zen_mode", "value": "1"}]}';
      final result = parseAiCommandList(text);
      expect(result.commands.length, 1);
      expect(result.commands.first.command, "settings put global zen_mode '1'");
      expect(result.ignored.length, 2);
    });

    test('wm / input 动作', () {
      const text = '{"commands": ['
          '{"action": "wm", "size": "1080x2400"},'
          '{"action": "input", "keycode": 26}]}';
      final result = parseAiCommandList(text);
      expect(result.commands.length, 2);
      expect(result.commands[0].command, 'wm size 1080x2400');
      expect(result.commands[1].command, 'input keyevent 26');
    });

    test('wm 非法尺寸被忽略', () {
      const text =
          '{"commands": [{"action": "wm", "size": "abc"}, {"action": "wm", "density": "420"}]}';
      final result = parseAiCommandList(text);
      expect(result.commands.length, 1);
      expect(result.commands.first.command, 'wm density 420');
    });

    test('不是 JSON 时返回 error', () {
      final result = parseAiCommandList('今天天气不错');
      expect(result.success, isFalse);
      expect(result.error, isNotNull);
      expect(result.commands, isEmpty);
    });

    test('空 commands 列表合法', () {
      final result = parseAiCommandList('{"commands": []}');
      expect(result.success, isTrue);
      expect(result.commands, isEmpty);
    });

    test('commands 不是列表时返回 error', () {
      final result = parseAiCommandList('{"commands": "none"}');
      expect(result.success, isFalse);
    });
  });

  group('pm 命令与解析', () {
    test('pm 命令构建', () {
      expect(pmDisable('com.example.app').command,
          'pm disable-user --user 0 com.example.app');
      expect(pmEnable('com.example.app').command, 'pm enable com.example.app');
      expect(pmUninstall('com.example.app').command,
          'pm uninstall --user 0 com.example.app');
      expect(pmClear('com.example.app').command, 'pm clear com.example.app');
      expect(pmForceStop('com.example.app').command,
          'am force-stop com.example.app');
    });

    test('非法包名抛错', () {
      expect(() => pmDisable('bad name'), throwsArgumentError);
    });

    test('parsePmPackages', () {
      const output = '''
package:com.example.app
package:com.other
some other line
package:invalid
''';
      expect(
        parsePmPackages(output),
        ['com.example.app', 'com.other'],
      );
    });

    test('parsePmPath', () {
      expect(
        parsePmPath('package:/data/app/com.example/base.apk\n'),
        '/data/app/com.example/base.apk',
      );
      expect(parsePmPath(''), isNull);
    });
  });

  group('ls 解析', () {
    test('目录、文件、软链接', () {
      const output = '''
total 12
drwxr-xr-x  4 root root 4096 Jan  1 00:00 subdir
-rw-r--r--  1 root root 1234 Jan  1 00:00 file.txt
lrwxrwxrwx  1 root root   12 Jan  1 00:00 link -> /target/path
''';
      final entries = parseLsLa(output);
      expect(entries.length, 3);
      // 目录排前面。
      expect(entries[0].name, 'subdir');
      expect(entries[0].isDirectory, isTrue);
      expect(entries[1].name, 'file.txt');
      expect(entries[1].isDirectory, isFalse);
      expect(entries[1].size, 1234);
      expect(entries[2].name, 'link');
      expect(entries[2].isSymlink, isTrue);
      expect(entries[2].linkTarget, '/target/path');
    });

    test('带空格的文件名', () {
      const output =
          '-rw-r--r--  1 root root 10 Jan  1 00:00 my file name.txt\n';
      final entries = parseLsLa(output);
      expect(entries.length, 1);
      expect(entries.first.name, 'my file name.txt');
    });

    test('大小标签', () {
      const entry = RootFileEntry(
        name: 'x',
        isDirectory: false,
        isSymlink: false,
        size: 1536,
        permissions: '-rw-r--r--',
      );
      expect(entry.sizeLabel, '1.5 KB');
    });
  });

  group('性能调节', () {
    test('governorSet 生成循环命令', () {
      final cmd = governorSet('powersave');
      expect(cmd.command, contains('for c in /sys/devices/system/cpu/cpu[0-9]*'));
      expect(cmd.command, contains('echo powersave'));
      expect(cmd.description, contains('powersave'));
    });

    test('非法调速器名抛错', () {
      expect(() => governorSet('a; rm -rf /'), throwsArgumentError);
    });

    test('刷新率命令与范围校验', () {
      expect(refreshRateSet(120, peak: true).command,
          'settings put system peak_refresh_rate 120');
      expect(refreshRateSet(60, peak: false).command,
          'settings put system min_refresh_rate 60');
      expect(() => refreshRateSet(10, peak: true), throwsArgumentError);
      expect(() => refreshRateSet(300, peak: true), throwsArgumentError);
    });

    test('省电模式命令', () {
      expect(powerSaveSet(true).command, 'settings put global low_power 1');
      expect(powerSaveSet(false).command, 'settings put global low_power 0');
    });
  });

  group('广告屏蔽', () {
    test('hostsApply 生成逐条检查命令', () {
      final cmd = hostsApply(hostsSystemPath, ['a.com', 'b.com']);
      expect(cmd.command, contains('for d in a.com b.com'));
      expect(cmd.command, contains('0.0.0.0'));
      expect(cmd.command, contains(hostsSystemPath));
    });

    test('非法域名被过滤', () {
      final cmd = hostsApply(hostsSystemPath, ['a.com', 'bad domain']);
      expect(cmd.command, contains('a.com'));
      expect(cmd.command, isNot(contains('bad domain')));
    });

    test('没有有效域名时抛错', () {
      expect(() => hostsApply(hostsSystemPath, ['bad domain']),
          throwsArgumentError);
    });

    test('备份与恢复命令', () {
      expect(hostsBackup(hostsSystemPath).command,
          contains("cp '/system/etc/hosts' '/sdcard/SuperApp/hosts.bak'"));
      expect(hostsRestore(hostsSystemPath).command,
          contains("cp '/sdcard/SuperApp/hosts.bak' '/system/etc/hosts'"));
    });
  });

  group('应用备份', () {
    test('备份命令包含正确路径', () {
      final apk = backupApk('com.example.app', '/data/app/x/base.apk');
      expect(apk.command,
          contains("cp '/data/app/x/base.apk' '/sdcard/SuperApp/backup/com.example.app/base.apk'"));
      final data = backupData('com.example.app');
      expect(data.command,
          contains("tar -czf '/sdcard/SuperApp/backup/com.example.app/data.tar.gz' -C /data/data com.example.app"));
    });

    test('恢复数据命令含解压、改属主、恢复标签', () {
      final cmd = restoreData('com.example.app', '10123');
      expect(cmd.command, contains('tar -xzf'));
      expect(cmd.command, contains('chown -R 10123:10123'));
      expect(cmd.command, contains('restorecon -R'));
    });

    test('parseDumpsysUserId', () {
      const output = '''
Packages:
  Package [com.example.app] (abc123):
    userId=10123 gids=[3003]
''';
      expect(parseDumpsysUserId(output), '10123');
      expect(parseDumpsysUserId('no userid here'), isNull);
    });
  });

  group('开机自启解析', () {
    test('组件行格式', () {
      const output = '''
Receiver #0:
  com.example/.BootReceiver
Receiver #1:
  com.other/.receiver.StartReceiver
''';
      final list = parseBootReceivers(output);
      expect(list.length, 2);
      expect(list[0].packageName, 'com.example');
      expect(list[0].componentName, '.BootReceiver');
      expect(list[0].fullName, 'com.example/.BootReceiver');
    });

    test('键值行格式', () {
      const output = '''
Receiver #0:
  packageName=com.example
  name=.BootReceiver
''';
      final list = parseBootReceivers(output);
      expect(list.length, 1);
      expect(list.first.fullName, 'com.example/.BootReceiver');
    });

    test('去重', () {
      const output = '''
  com.example/.BootReceiver
  com.example/.BootReceiver
''';
      expect(parseBootReceivers(output).length, 1);
    });

    test('bootReceiverSet 命令', () {
      const receiver = BootReceiver(
        packageName: 'com.example',
        componentName: '.BootReceiver',
      );
      expect(bootReceiverSet(receiver, false).command,
          'pm disable com.example/.BootReceiver');
      expect(bootReceiverSet(receiver, true).command,
          'pm enable com.example/.BootReceiver');
    });
  });

  group('文件删除与文本判断', () {
    test('rmCommand 目录用 rm -rf', () {
      expect(rmCommand('/data/x', isDirectory: true).command,
          "rm -rf '/data/x'");
      expect(rmCommand('/data/x.txt', isDirectory: false).command,
          "rm '/data/x.txt'");
    });

    test('isTextFile 按后缀判断', () {
      expect(isTextFile('a.txt'), isTrue);
      expect(isTextFile('a.log'), isTrue);
      expect(isTextFile('a.apk'), isFalse);
      expect(isTextFile('a.so'), isFalse);
    });
  });
}
