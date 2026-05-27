# AEMT

AEMT 是 `Auto Encoding and Muxing Tool` 的首字母缩写。

AEMT 是一个基于 Flutter Windows 的本地视频压制与封装工具，面向字幕组和本地重编码场景。项目直接调用系统或随包附带的 `ffmpeg`、`ffprobe`、`mkvpropedit` 与 `7z`，不依赖独立后端服务。

## 功能概览

- 导入本地视频并解析视频流、音频流、字幕流、字体附件流与章节信息，并提供抽取源文件流的功能
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

AEMT 会按以下顺序查找字体子集化工具：

1. `FONTTOOLS_BIN_DIR`
2. 自定义运行时目录
3. 自定义运行时目录下的 `bin/`
4. 自定义运行时可执行文件所在目录
5. 当前运行目录下的 `bin/`
6. 当前运行目录父级下的 `bin/`
7. 系统 `PATH` 中的 `pyftsubset.exe` / `ttx.exe`
8. 系统 `PATH` 中的 `pyftsubset` / `ttx`

字体子集化依赖 Python 版 FontTools 的 `pyftsubset` 与 `ttx`。未找到时程序仍可导出，但会跳过字体子集化与 ASS 字体名改写。

便携版会内置 `bin/pyftsubset.exe`、`bin/ttx.exe` 与 `python/python.exe`。这两个 `bin/` 下的启动器只调用同一便携包根目录里的 `python/python.exe`，不会再搜索用户系统 Python；如需覆盖内置版本，可使用 `FONTTOOLS_BIN_DIR` 或自定义运行时路径。

AEMT 会按以下顺序查找内置字体子集化启动器所需的 Python：

1. 便携包根目录下的 `python/python.exe`

普通开发环境或系统安装的 FontTools 启动器由对应启动器自行决定使用哪个 Python，AEMT 不直接探测系统 Python。

打包脚本会为字体子集化运行时使用：

1. Python embeddable `3.13.9`
2. `fonttools[woff]` `4.63.0`

打包时会先在 `tools/cache/` 缓存下载文件；缓存不存在时从 Python 官网与 pip bootstrap 地址下载。

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
- `python/`: 官方 Windows embeddable Python 运行时；脚本会安装 `fonttools[woff]`，并在 `bin/` 生成 `pyftsubset.exe` / `ttx.exe`，避免依赖用户系统 Python 或全局 pip 包
- `ffmpeg`: 会优先使用项目根目录 `ffmpeg/` 下的 `ffmpeg.exe` / `ffprobe.exe` 与相关 DLL，复制到便携版 `bin/`
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
