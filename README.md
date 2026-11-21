# SuperApp

一个 Flutter 全平台超级应用，整合许多常用功能，实用为主。

## 功能

| 模块 | 说明 |
| --- | --- |
| 科学计算器 | 表达式计算、三角/对数/阶乘、DEG/RAD、历史记录 |
| 单位转换 | 长度、质量、温度、体积、面积、速度、时间、数据、压力、能量、功率、角度、货币（离线汇率） |
| 函数绘制 | y=f(x) 多函数同屏、缩放/平移、零点标注 |
| AiPlat | OpenAI 兼容接口聊天（DeepSeek / OpenAI 等），流式输出、图片/文件上传、多会话 |
| WebOS | 应用内桌面操作系统：窗口管理、内置应用、HTML 应用（localhost 运行）、应用市场、应用工坊、应用互联 |
| 小工具 | 密码生成器、JSON 格式化、二维码生成 |
| Super MAX | root 模式（默认关闭）：AI 操作手机、WebOS 读写真实文件、root shell、应用管理 |

## Super MAX

默认关闭，在设置里手动开启。开启需要 root（folkpatch / APatch 等），
开启前会检测 root，所有 root 操作执行前都需要用户确认。

## 平台

Android / iOS / Windows / macOS / Linux（不做 Web 版）。

CI（GitHub Actions）自动构建全平台产物，见 Actions 页。

## 开发

```sh
flutter pub get
flutter analyze
flutter test
flutter run
```

## 许可

私有项目，暂未开源。
