# AEMT

AEMT 是 `Auto Encoding and Muxing Tool` 的首字母缩写。

AEMT 是一个基于 Flutter Windows 的本地视频压制与封装工具，面向字幕组和本地重编码场景。项目直接调用系统或随包附带的 `ffmpeg`、`ffprobe`、`mkvpropedit` 与 `7z`，不依赖独立后端服务。

## 功能概览

- 导入本地视频并解析视频流、音频流、字幕流、字体附件流与章节信息，并提供抽取源文件路径、流信息、章节信息的功能
- 使用基于 `mpv` 的播放器预览视频，并可加载外挂/源文件中的内封字幕
- 编辑章节名称、章节起止时间
- 导出三种目标产物：简体内嵌、繁体内嵌、简繁内封
- 自动探测 NVENC / QSV / AMF，并按 `NVENC -> QSV -> AMF -> SOFTWARE` 顺序回落
- 支持批量任务列表、任务日志留存、查看单任务 FFmpeg 输出
- 支持分集压制命名模板，可用 `{group}`、`{title}`、`{season}`、`{episode}`、`{source}`、`{profile_tags}`、`{ext}` 等变量自由拼装导出文件名
- 支持导入 / 导出“编码参数”选项卡中的当前配置，便于保存和迁移预设

## 项目结构

- `frontend/`: Flutter Windows 桌面应用主体
- `scripts/`: 开发启动与便携打包脚本
- `MiSans/`: 项目使用的 MiSans 字体资源

## 运行依赖

AEMT 会按以下顺序查找 `ffmpeg.exe` 与 `ffprobe.exe`：

1. 自定义配置路径
2. 运行目录下的 `bin/`
3. `FFMPEG_BIN_DIR`
4. 系统 `PATH`

AEMT 会按以下顺序查找 `mkvpropedit.exe`：

1. 自定义配置路径
2. 运行目录下的 `bin/`
3. `MKVTOOLNIX_BIN_DIR`
4. `C:\Program Files\MKVToolNix\` / `C:\Program Files (x86)\MKVToolNix\`
5. 系统 `PATH`

`mkvpropedit` 是简繁内封 MKV 导出的关键依赖。未安装或未配置时，程序仍可启动，但内封字幕版本无法处理和导出。

AEMT 会按以下顺序查找 `7z.exe`：

1. 自定义配置路径
2. 运行目录下的 `bin/`
3. `C:\Program Files\7-Zip\` / `C:\Program Files (x86)\7-Zip\`
4. 系统 `PATH` 中的 `7z` / `7za` / `7zz`

未安装或未配置 `7z` 时，程序仍可启动，但自定义字体压缩包只能处理 ZIP，无法提取 7z / RAR。

## 开发模式启动

```powershell
.\scripts\start_dev.ps1
```

脚本会自动：

- 设置 `PUB_HOSTED_URL=https://pub.flutter-io.cn`
- 设置 `FLUTTER_STORAGE_BASE_URL=https://storage.flutter-io.cn`
- 以 Windows 桌面调试模式启动 AEMT

## 打包便携版

```powershell
.\scripts\build_portable.ps1
```

默认输出：

- 目录：`dist/AEMT-windows-portable/`
- 压缩包：`dist/AEMT-windows-portable.zip`

打包脚本会执行 Windows release 构建，并把运行时依赖复制到：

- `bin/`: 便携版优先搜索的运行时目录；会先复制项目根目录 `bin/`
- `ffmpeg/`: 会优先使用项目根目录 `ffmpeg/` 下的 `ffmpeg.exe` / `ffprobe.exe` 覆盖便携版 `bin/` 中的同名文件
- `mkvtoolnix`: 打包时会优先从 `MKVTOOLNIX_BIN_DIR`、系统安装目录或 `PATH` 中找到 `mkvpropedit.exe` 并复制其所在目录内容到便携版 `bin/`
- `7z`: 打包时会优先从系统安装目录或 `PATH` 中找到 `7z.exe` / `7za.exe` / `7zz.exe` 并复制其所在目录内容到便携版 `bin/`

## 便携版运行

```powershell
.\dist\AEMT-windows-portable\run_portable.ps1
```

也可以直接运行 `AEMT.exe`。

## 字体版权说明（Font License）

本项目使用小米公司提供的 **MiSans 字体**，该字体已明确允许**免费商用**。

* 字体版权归小米公司所有
* 相关许可协议请查阅：[MiSans 字体知识产权使用许可协议](https://hyperos.mi.com/font-download/MiSans%E5%AD%97%E4%BD%93%E7%9F%A5%E8%AF%86%E4%BA%A7%E6%9D%83%E8%AE%B8%E5%8F%AF%E5%8D%8F%E8%AE%AE.pdf)
* MiSans 官网：[https://hyperos.mi.com/font/](https://hyperos.mi.com/font/)
