# CCVideo 视频模块

控制中心视频播放模块（iOS 14+，适配多巴胺无根 / roothide 隐根），基于 [CCSupport](https://github.com/opa334/CCSupport)。

## 功能

- 控制中心显示视频模块，静音循环播放
- 素材库：设置入口（设置 → 控制中心 → 视频模块）网格浏览，PHPicker 免权限导入相册视频，点选、长按删除
- 模块大小可调：竖屏/横屏宽高各 1~4 格滑杆，即时生效无需注销（CCSupport ReloadSizes）
- 画面填充 / 完整显示切换；不可见时自动暂停省电

## 构建

```bash
# 无根（Dopamine rootless）
make clean package FINALPACKAGE=1 THEOS_PACKAGE_SCHEME=rootless
# 隐根（roothide）
make clean package FINALPACKAGE=1 THEOS_PACKAGE_SCHEME=roothide
```

依赖：`com.opa334.ccsupport`（对应源：rootless → https://repo.chariz.com ；roothide → https://repo.roothide.net）。

## 安装

- rootless deb 装多巴胺，roothide deb 装 roothide 引导，装完自动注销 SpringBoard/设置
- 添加模块：设置 → 控制中心 → 自定控制 → 找到「视频模块」
- 视频/缩略图存放：`/var/mobile/Library/CCVideo/`（两个引导通用）

## 已知限制

- 音量条与亮度条位置固定占 1 格，模块默认 2x2（音量/亮度中间大格）
- 视频解码由 SpringBoard 承担，超大 4K 文件可能吃内存；建议导入竖屏 720p 左右
