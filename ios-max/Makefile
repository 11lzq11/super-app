# SuperApp MAX — Theos Makefile（越狱插件骨架）
#
# ⚠️ 未验证：需要在装有 Theos 的 Mac/Linux 上编译，且需要越狱设备测试。
# 本仓库的 CI 与开发机均未编译过它。
#
# 编译：
#   export THEOS=/path/to/theos        # Theos 安装目录
#   make package                        # 生成 .deb
#
# Rootless 越狱（Dopamine / palera1n rootless / XinaA15 等）：
#   make package THEOS_PACKAGE_SCHEME=rootless
#   此时 control 里的 Architecture 应为 iphoneos-arm64，见 README。
#
# 安装：把生成的 .deb 传到手机，用 Sileo/Zebra 安装，或 dpkg -i 安装，
# 然后 respring（Makefile 的 after-install 会自动执行）。

TWEAK_NAME = SuperAppMax

SuperAppMax_FILES = Tweak.xm
SuperAppMax_CFLAGS = -fobjc-arc
SuperAppMax_FRAMEWORKS = Foundation UIKit CoreFoundation

# 目标 iOS 版本：14.0 起；如需支持更低版本自行下调并验证。
TARGET := iphone:clang:latest:14.0
ARCHS = arm64 arm64e

include $(THEOS)/makefiles/common.mk
include $(THEOS_MAKE_PATH)/tweak.mk

after-install::
	install.exec "killall -9 SpringBoard"
