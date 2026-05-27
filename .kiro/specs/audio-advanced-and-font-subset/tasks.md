# Implementation Plan: 音频高级编码、视频码控、字体子集化与色调映射

## Overview

按 design.md 给出的分层（UI → AemtController → services → 外部进程）逐
层落地。先以 `models.dart` 中的纯数据结构与 `detectSourceColorClass`
立稳基础，然后扩展运行时探测（pyftsubset / hasZscale / audioEncoders）
与 `media_parser.dart` 色彩元数据，再实现 `FontAssetService` 的字符索
引、字体匹配、子集化与许可元数据。控制层把新字段并入 `EncodingSettings
Snapshot version=2`，`_TaskPlanner` 顺序加上音频参数、视频码控、色调
映射与字体管线。`_QueueRunner` 把子集化建模为独立 `CommandStep`、接
管取消信号并捕获 zscale 失败。最后才动 `encoding_panel.dart` 的 UI，
追加三个新 Tab 与既有视频 Tab 的码控控件；每个 PBT property 都按
design 中编号独立成子任务，方便逐条追溯。

## Tasks

- [x] 1. 数据模型与序列化（`frontend/lib/src/models.dart`）
  - [x] 1.1 Implement new data models with JSON + value-equality
    - `AudioStreamConfig` with `defaultAac()` factory, `toJson/fromJson`,
      `==`/`hashCode`; lowerCamelCase keys; missing-field defaults; type
      mismatch → `FormatException` containing field name
    - `VideoEncodingConfig` with `defaultsFor(encoderKey)` factory,
      `userOverridden` sentinel, `kSupportedRcModes` constant table
    - `ToneMappingConfig` with `defaultBt709()` factory; `fromJson`
      maps legacy `tonemapMode: 'manual'` → `'on'`; `peak` is `String`
    - `VideoStreamInfo` (color metadata bag) + `SourceColorClass` enum
      `{sdrBt709, sdrWideGamut, hdrPq, hdrHlg, dolbyVision, unknown}`
    - `detectSourceColorClass(VideoStreamInfo)` pure function per Req
      25.4 priority table; never mutates the input
    - `SubtitleCharIndex` (Map<String, Set<int>>) + `FontMatchResult`
      (`matched` / `missing`) value types
    - `SubsetResult { fonts: List<ResolvedFontFile>, renameMap:
      Map<String, String> }`; `renameMap` 键是原 Fontname 的归一化形式
      （大小写不敏感、首尾去空格），值是 8 字符 `[A-Z0-9]` 随机新名
    - 在 `EncodingSettingsSnapshot` v2 schema 中预留
      `bool sourceHanEllipsisFix`（默认 `true`）字段
    - 新增常量 `Vert_Mapping_Table: Map<int, int>`，权威来源为
      AssFontSubset.Core 的 `src/FontConstant.cs#VertMapping`，建议
      落在 `services/font_asset_service_internal/vert_mapping.dart`
    - Extend `MediaInfo` with `VideoStreamInfo? primaryVideo`
    - _Requirements: 6.1, 7.2, 7.3, 8.1, 8.6, 9.1, 9.5, 9.6, 11.8,
      13.6, 13.7, 14.9, 14.10, 22.1, 25.4, 25.5, 25.6, 28.7, 29.8_

  - [x] 1.2 Write property test for `AudioStreamConfig` round-trip
    - **Property 1: AudioStreamConfig JSON round-trip**
    - **Validates: Requirements 9.1, 9.2**

  - [x] 1.3 Write property test for `VideoEncodingConfig` round-trip
    - **Property 2: VideoEncodingConfig JSON round-trip**
    - **Validates: Requirements 9.1, 9.3**

  - [x] 1.4 Write property test for `ToneMappingConfig` round-trip
    - **Property 3: ToneMappingConfig JSON round-trip**
    - **Validates: Requirements 9.1, 9.4**

  - [x] 1.5 Write property test for `detectSourceColorClass`
    - **Property 16: Source color classification is total and pure**
    - **Validates: Requirements 25.4, 25.5, 25.6**

  - [x] 1.6 Write unit tests for `*.fromJson` error paths
    - Type mismatch on `bitrate` / `crf` / `peak` raises
      `FormatException` with field name
    - Legacy `tonemapMode: 'manual'` is mapped to `'on'`
    - _Requirements: 9.5, 9.6, 22.5_

- [x] 2. 运行时探测扩展（`frontend/lib/src/services/runtime_service.dart`）
  - [x] 2.1 Add `pyftsubset` discovery to `RuntimeService`
    - Search order: custom dir → `bin/` and `../bin/` →
      `FONTTOOLS_BIN_DIR` → `PATH`
    - Add `RuntimeToolInfo pyftsubset` (`required=false`) to
      `RuntimeDiagnostics`; append `pyftsubset: 未找到` to
      `startupMessage` when missing; never block startup
    - _Requirements: 13.1, 13.2, 13.3_

  - [x] 2.2 Probe `zscale` availability via `ffmpeg -hide_banner -filters`
    - Parse output, set `RuntimeDiagnostics.hasZscale`
    - On `false` append `当前 ffmpeg 未启用 libzimg，色调映射不可用`
      to `startupMessage`
    - _Requirements: 26.1, 26.2_

  - [x] 2.3 Probe available audio encoders via `ffmpeg -encoders`
    - Filter to `{aac, libfdk_aac, libopus, flac, ac3, eac3}` subset
      and expose as `RuntimeDiagnostics.audioEncoders`
    - _Requirements: 2.8_

  - [x] 2.4 Add `ttx` discovery + fonttools version probe
    - Search order identical to pyftsubset (custom dir → `bin/` /
      `../bin/` → `FONTTOOLS_BIN_DIR` → `PATH`)
    - Add `RuntimeToolInfo ttx` (`required=false`) to
      `RuntimeDiagnostics`; append `ttx: 未找到` to `startupMessage`
      when missing; never block startup
    - When `ttx.path != null`, run `ttx --version`, parse three-segment
      SemVer (e.g. `ttx 4.55.0`), cache as
      `RuntimeDiagnostics.fontToolsVersion: Version?`; parse failure →
      `null` (does not block startup)
    - _Requirements: 13.1, 13.2, 13.3, 13.6, 13.7_

  - [x] 2.5 Write unit tests for runtime discovery parsers
    - Static fixtures for `-filters` and `-encoders` outputs
    - Verify search-path priority via temp directories
    - _Requirements: 2.8, 13.1, 26.1_

- [x] 3. 媒体解析器扩展（`frontend/lib/src/services/media_parser.dart`）
  - [x] 3.1 Populate `VideoStreamInfo` from ffprobe
    - Read `color_space / color_primaries / color_transfer /
      color_range / bits_per_raw_sample`
    - Parse `side_data_list` for `Mastering display metadata`,
      `Content light level metadata` (treat `0` as valid),
      `DOVI configuration record` → `dolbyVision=true`
    - Fill `MediaInfo.primaryVideo` for the first video stream;
      missing fields → `'unknown' / 0 / false`
    - _Requirements: 25.1, 25.2, 25.3, 25.5_

  - [x] 3.2 Write unit tests for ffprobe color parsing
    - Use `ffprobe_sample.json` style fixtures for SDR / HDR10 / HLG /
      Dolby Vision / missing-field cases
    - _Requirements: 25.1, 25.2, 25.3, 25.5_

- [x] 4. Checkpoint - models + runtime discovery green
  - Ensure all tests pass, ask the user if questions arise.

- [x] 5. 字体服务：字符索引（`frontend/lib/src/services/font_asset_service.dart`）
  - [x] 5.1 Implement `indexSubtitleCharacters(List<String>)`
    - `.ass`/`.ssa`: parse `[V4+ Styles]` Format/Fontname, resolve
      Dialogue style and `\fn<name>` inline overrides; ignore other
      `{...}` override-tag content
    - `.srt`: bucket all visible chars under `__default__`
    - Other extensions (`.vtt`, `.sub`, unknown): generic text path
      under `__default__`, no ASS-specific parsing
    - Append ASCII printable + `\n\r\t` to every bucket
    - Always append the AppendNecessaryRunes set to every bucket per
      Req 10.5: uppercase Latin + fullwidth (`0xFF21-0xFF3A`),
      lowercase Latin + fullwidth (`0xFF41-0xFF5A`), digits +
      fullwidth (`0xFF10-0xFF19`), plus `0xFF1F` and `0xFF20`
    - Vertical handling per Req 10.7 / 10.8: when ASS Style.Fontname
      starts with `@`, additionally pull in `Vert_Mapping_Table[c]`
      for each codepoint `c` (skip when mapping not defined); strip
      the leading `@` so vertical and horizontal buckets for the same
      underlying TTF/OTF target merge into one bucket
    - Per Req 10.9 ignore ASS Style.Encoding when bucketing — same
      Fontname/Bold/Italic/Weight 4-tuple maps to one bucket
      regardless of Encoding value
    - BOM-aware decoder fallback chain `utf-8 / utf-16-le /
      utf-16-be / gb18030`; on total failure throw
      `Exception("无法解析字幕: <path>: <reason>")` without polluting
      already-built index
    - Caller is responsible for filtering `enabled=false` subtitle
      streams before passing paths in
    - _Requirements: 10.1, 10.2, 10.3, 10.4, 10.5, 10.6, 10.7, 10.8,
      10.9, 11.7_

  - [x] 5.2 Write property test for character-index coverage
    - **Property 9: Subtitle character index covers visible text**
    - **Validates: Requirements 10.2, 10.3, 10.4, 10.5**

  - [x] 5.3 Write unit tests for subtitle-parser error paths
    - Read failure / undecodable bytes raise `Exception` with path,
      partial index untouched
    - _Requirements: 10.6, 20.3_

- [x] 6. 字体服务：sfnt name 表读取与匹配
  - [x] 6.1 Implement minimal sfnt `name`-table reader
    - New helper `services/font_asset_service_internal/sfnt_name_reader.dart`
    - Read NameID 1 (Family) + NameID 4 (Full); `.ttc` treated as
      union of internal faces
    - Pure Dart, no external process
    - _Requirements: 11.1_

  - [x] 6.2 Implement `matchFonts(SubtitleCharIndex, candidates)`
    - Case-insensitive + trimmed key normalization
    - Source priority: source-file attachments > imported sources
      (in import order); ties resolve to earlier index
    - Return `FontMatchResult { matched, missing }`
    - Duplicate detection per Req 11.8: before normalization-matching,
      bucket candidates by `(normalizedFamily, bold, italic, weight,
      trackIndex, maxp.numGlyphs)`; ≥ 2 candidates in one bucket →
      `throw Exception("字体源中存在重复字体: <fileName1>, <fileName2>, ...")`
      (`trackIndex` = `0` for single-file fonts, internal face index
      for `.ttc`; `maxp.numGlyphs` read by `sfnt_name_reader` and
      cached)
    - **Forbid** any MiSans path from candidate set; static guard
      comment + assertion
    - _Requirements: 11.1, 11.2, 11.3, 11.4, 11.8_

  - [x] 6.3 Write property test for font matching
    - **Property 10: Font matching is case-insensitive and source-prioritized**
    - **Validates: Requirements 11.1, 11.3, 11.4, 11.7**

- [x] 7. 字体服务：子集化执行
  - [x] 7.1 Implement `subsetFonts(index, matched, workDir, ...)`
    returning `SubsetResult { fonts, renameMap }`
    - Signature additions: `pyftsubsetPath`, `ttxPath`,
      `aemtVersion: String`, `fontToolsVersion: Version?`,
      `sourceHanEllipsisFix: bool`, `cancelSignal: Stream<void>`
    - Per-font TTX_Pipeline three stages, serial inside one font,
      `Pool(4)` across fonts:
      - Stage 1 — `pyftsubset.exe <input> --unicodes-file=<f> ...
        --output-file=<workDir>/subsetted/<base>.subset_tmp_.<ext>`
        with fixed flags: `--no-hinting`, `--retain-gids`,
        `--layout-features=vert,vrtr,vrt2,vkna`, `--name-IDs=*`,
        `--name-languages=*`, `--drop-tables=`; version-conditional
        per Req 14.9: `fontToolsVersion > 4.44.0` → append
        `--no-prune-codepage-ranges`; `> 4.60.0` → append
        `--drop-tables+=BASE`; `null` → append both
      - Stage 2 — `ttx.exe -f -o <base>.ttx <base>.subset_tmp_.<ext>`
      - Stage 2.5 — invoke `ttx_xml_modifier.dart` (in-memory) to
        rename NameID 1/3/4/6, add NameID 0 stamp, strip NULs,
        optional Source Han ellipsis fix
      - Stage 3 — `ttx.exe -f -b <base>.ttx` →
        `<base>.subset.<ext>` (final font)
    - Empty codepoint set still runs the full pipeline → produces a
      structurally valid empty subset (Req 14.4)
    - On any stage failure (pyftsubset / ttx-dump / ttx-rename /
      ttx-compile): `throw Exception` whose message includes
      (a) original font path, (b) stderr tail (last 4KB) or the
      rename-failure reason, (c) literal advice
      `请尝试使用 FontForge 重新生成字体（File - Generate Font），然后用新字体再次子集化。`;
      no cleanup, no retry (Req 18.4 / 18.5 / 28.8)
    - Subscribe to `cancelSignal`; kill the in-flight `pyftsubset`
      OR `ttx` process within 500ms (Req 20.5)
    - Returns `SubsetResult`: `fonts` only contains successful
      subsets, inheriting `fileName` / `mimeType`; `renameMap` maps
      every successfully subset font's normalized original Fontname
      → its 8-char `[A-Z0-9]` Font_Random_Rename written into
      NameID 1/3/4/6 (Req 29.8)
    - _Requirements: 11.8, 14.1, 14.2, 14.3, 14.4, 14.5, 14.6, 14.7,
      14.8, 14.9, 14.10, 18.4, 18.5, 20.4, 20.5, 28.1, 28.2, 28.3,
      28.5, 28.6, 28.8_

  - [x] 7.2 Implement subset-font cmap verification
    - Reuse sfnt reader + minimal `cmap` parser to assert
      `subset.cmap.codepoints ⊇ index[fontname]`
    - Verify on the **final ttx-recompiled** `<base>.subset.<ext>`
      (post Stage 3), not on the `<base>.subset_tmp_.<ext>`
      intermediate, since the rename/GSUB-edit step changes the file
    - Per-font log line `subset OK: ... (n)` or `subset FAIL: ...`;
      verification can be skipped via flag → `子集化校验已跳过`
    - _Requirements: 17.1, 17.2, 17.3, 17.4_

  - [x] 7.3 Implement license sidecar + fsType warning
    - Write `<workDir>/subsetted/LICENSE.txt` per font using NameID 13
      or the placeholder `原字体未提供许可信息，仅做字符子集化处理。`
    - On OS/2 `fsType` bit 1 set, emit
      `字体 <name> 标记为受限嵌入...` warning to log without aborting
    - _Requirements: 18.1, 18.2, 18.3_

  - [x] 7.4 Implement `ttx_xml_modifier.dart` (in-memory TTX edits)
    - New helper
      `services/font_asset_service_internal/ttx_xml_modifier.dart`,
      pure Dart on `package:xml`, no external process
    - Replace text of every `<namerecord nameID="1"|"3"|"4"|"6">`
      element across all platformID/encodingID/languageID
      combinations with the per-font Font_Random_Rename
    - Append one `<namerecord nameID="0" platformID="3" platEncID="1"
      langID="0x409">` whose text is
      `Processed by AEMT v<aemtVersion>; pyFontTools <fontToolsVersion>`
      (use literal `unknown` when `fontToolsVersion == null`)
    - Strip every NUL byte (`\x00`) from the serialized XML text
    - Source Han detection: BEFORE the rename, scan original
      NameID 1/3/4/6 strings for case-sensitive substring
      `Source Han`; mark `isSourceHan`
    - When `isSourceHan && sourceHanEllipsisFix == true`: in
      `<ttFont>/cmap` find the `<map>` whose `code="0x2026"` to read
      `cidEllipsis = map@name`; iterate every
      `<ttFont>/GSUB//Substitution`, remove elements satisfying
      `@in == cidEllipsis && @out.startsWith('cid6')`; preserve every
      `cid5*` substitution
    - When NameID 1/3/4/6 has zero replaceable records → throw the
      same FontForge-advice exception as Req 18.5 (message contains
      original font path); never emit a non-renamed subset font
    - _Requirements: 28.2, 28.3, 28.4, 28.5, 28.6, 28.8_

  - [x] 7.5 Implement Font_Random_Rename generator
    - Co-located with `ttx_xml_modifier.dart` (or a dedicated
      `font_random_name.dart`); pure function exposed as
      `String generateRandomName(Set<String> usedNames)`
    - 8 chars sampled from `[A-Z0-9]` alphabet using `Random.secure()`
      (Windows → `BCryptGenRandom`)
    - Retry on collision against `usedNames` up to 32 attempts; on
      cap reached `throw Exception("无法生成唯一字体随机名（碰撞超过 32 次）")`
    - `usedNames` is initialised by `subsetFonts` per batch and
      shared across fonts → guarantees per-task uniqueness
    - _Requirements: 28.2_

  - [x] 7.6 Write property test for pyftsubset command construction
    - **Property 12: pyftsubset command construction**
    - **Validates: Requirements 14.1, 14.2, 14.3, 18.1**

  - [x] 7.7 Write integration property test for subset round-trip
    - **Property 13: Subsetting preserves required codepoints**
    - **Validates: Requirements 17.1, 17.2**
    - Requires real `pyftsubset.exe` (gated by CI env)

  - [x] 7.8 Write integration test for empty-codepoint subset file
    - **Property 14: Empty codepoint set still yields a valid subset file**
    - **Validates: Requirements 14.4, 14.6**

  - [x] 7.9 Write property test for license sidecar generation
    - **Property 22: License sidecar generation**
    - **Validates: Requirements 18.2, 18.3**

- [x] 8. 字幕字体名重写（Subset_Rewrite_Ass）
  - [x] 8.1 Implement
    `services/font_asset_service_internal/subset_ass_rewriter.dart`
    - Pure Dart, no external process
    - Inputs: original ASS/SSA path,
      `renameMap: normalizedKey → newName`, output path
      `<workDir>/subtitles/<basename>.<原扩展>`
    - Detect original newline style (CRLF / LF) from raw bytes;
      preserve it on output
    - Decode using the same BOM-aware fallback chain as
      `indexSubtitleCharacters`
    - Rewrite `[V4+ Styles]` / `[V4 Styles]` Style.Fontname column:
      strip optional leading `@`, lowercase + trim → key; if
      `renameMap[key]` exists, replace with
      `(atPrefix ? '@' : '') + renameMap[key]`
    - Rewrite inline `\fn<name>` overrides inside Dialogue `{...}`
      groups using the same key normalization (preserve `@`)
    - Apply `renameMap.keys` longest-match-first so `FZHei` is
      rewritten before `FZ`
    - Inject `; Font Subset: <new> - <old>` comment lines at the
      start of `[Script Info]` (one per renamed font, in renameMap
      iteration order); preserve original comments verbatim
    - Output is UTF-8 with BOM; every byte outside the rewritten
      fields is byte-equal to the original
    - Caller (Task_Planner) must
      `Directory(<workDir>/subtitles).create(recursive: true)`
      before invocation
    - _Requirements: 29.1, 29.2, 29.3, 29.7_

  - [x] 8.2 Write property test for `subset_ass_rewriter`
    - **Property 26: Subset_Rewrite_Ass faithfully applies renameMap**
    - **Validates: Requirements 29.1, 29.2, 29.3, 29.4, 29.5, 29.7**

  - [x] 8.3 Write property test for skip-path semantics
    - **Property 27: Subset_Rewrite_Ass skip-path leaves originals untouched**
    - **Validates: Requirements 13.5, 29.6**

  - [x] 8.4 Write property test for TTX_Pipeline NameID renaming
    - **Property 24: TTX_Pipeline produces a uniquely renamed font**
    - **Validates: Requirements 28.1, 28.2, 18.5**

  - [x] 8.5 Write property test for Source Han ellipsis fix
    - **Property 25: Source Han ellipsis fix removes only cid6* substitutions**
    - **Validates: Requirements 28.3, 28.5, 28.6**

  - [x] 8.6 Write property test for Vert_Mapping_Table + bucket merge
    - **Property 28: Vert_Mapping_Table application is idempotent**
    - **Validates: Requirements 10.7, 10.8, 10.9**

- [x] 9. Checkpoint - font service end-to-end
  - Ensure all tests pass, ask the user if questions arise.

- [x] 10. Snapshot v2（`frontend/lib/src/controller_export_config.dart`）
  - [x] 10.1 Upgrade `EncodingSettingsSnapshot` to `version=2`
    - `toJson` writes `audioStreamConfigs / audioDefaultProfile /
      videoEncodingConfigs / toneMappingConfig / continueOnMissingFont /
      sourceHanEllipsisFix`
    - `fromJson`: `version==1` → fill defaults (incl.
      `sourceHanEllipsisFix=true`) + status message
      `已导入旧版本预设，音频高级参数、视频码控与色调映射沿用默认`;
      `version==2` → full parse with key matching
      `<inputPath>#<streamIndex>`, missing `sourceHanEllipsisFix`
      defaults to `true`; `version>2` →
      `FormatException("不支持的编码参数配置版本: $version")`
    - Update `buildEncodingSettingsSnapshot` /
      `applyEncodingSettingsSnapshot` accordingly
    - _Requirements: 8.1, 8.2, 8.3, 8.4, 8.5, 8.6, 28.7_

  - [x] 10.2 Write property test for v2 snapshot round-trip
    - **Property 4: EncodingSettingsSnapshot v2 round-trip**
    - **Validates: Requirements 8.1, 8.2, 8.6**

  - [x] 10.3 Write unit tests for cross-version import
    - v1 import → defaults + status message
    - v2 import with mismatching `inputPath` → only
      `audioDefaultProfile / videoEncodingConfigs / toneMappingConfig`
      apply; per-stream configs are skipped unless streamIndex matches
    - v3 import → `FormatException`
    - _Requirements: 8.3, 8.4, 8.5_

- [x] 11. AemtController 状态扩展（`frontend/lib/src/controller.dart`）
  - [x] 11.1 Add new fields and named setters
    - `Map<String, AudioStreamConfig> audioStreamConfigs` (keys
      `<inputPath>#<streamIndex>`), `audioDefaultProfile`,
      `Map<String, VideoEncodingConfig> videoEncodingConfigs`,
      `ToneMappingConfig toneMappingConfig`,
      `bool continueOnMissingFont`,
      `bool sourceHanEllipsisFix = true`
    - Setters: `setAudioStreamConfig`, `setAudioDefaultProfile`,
      `setVideoEncodingMode`, `setVideoEncodingField`,
      `setToneMappingConfig`, `setContinueOnMissingFont`,
      `setSourceHanEllipsisFix`, each calls `notifyListeners()`
    - On new media import / new audio stream: initialize via
      `audioDefaultProfile.copyWith()` per stream
    - Implement `reconcileVideoEncodingMode(encoderKey)` per Req 7.3:
      reset `mode` to `defaultsFor(encoderKey).mode` and clear
      `userOverridden` whenever current mode leaves the supported set
    - First-time HDR notice (one-shot via `_hdrToneMappingNoticeShown`):
      append `已自动启用色调映射 (HDR → BT.709)，可在 色调映射 选项卡中查看与覆盖。`
      to `statusMessage` when `Source_Color_Class ∈ {HDR_PQ, HDR_HLG,
      DolbyVision}` and `tonemapMode == auto`
    - _Requirements: 6.1, 6.2, 6.3, 7.3, 8.1, 27.3, 28.4, 28.7_

  - [x] 11.2 Write property test for video RC mode reconciliation
    - **Property 8: Rate-control mode reconciliation**
    - **Validates: Requirements 7.2, 7.3**

  - [x] 11.3 Write property test for one-shot HDR notice
    - **Property 18: First-time HDR notice is one-shot**
    - **Validates: Requirements 27.3**

- [x] 12. _TaskPlanner：音频参数（`frontend/lib/src/controller_task_planner.dart`）
  - [x] 12.1 Implement `_buildAudioStreamArguments(int outIdx, AudioStreamConfig)`
    - Encoder branches per Req 2.2-2.7 matrix; CBR/VBR per Req 3;
      `-ar:N` only when not `保持源`; `-ac:N` / `-channel_layout:N`
      per Req 4 (with `dpl2` pan-matrix downmix)
    - Filter chain order `loudnorm → acompressor → custom`, single
      `-af:N` even with one filter
    - `copy` mode → only `-c:a:N copy`, no `-af`
    - Validate CBR bitrate via `^\d+[kK]$`; on failure throw
      `Exception("码率格式应为如 192k")`
    - Throw `Exception("音频编码器 X 不可用")` when encoder ∉
      `RuntimeDiagnostics.audioEncoders`
    - _Requirements: 2.2, 2.3, 2.4, 2.5, 2.6, 2.7, 2.8, 3.2, 3.3,
      3.4, 3.5, 3.6, 4.1, 4.2, 4.3, 4.4, 4.5, 4.6, 4.7, 5.1, 5.2,
      5.3, 5.4, 5.5, 5.6, 5.7, 6.5_

  - [x] 12.2 Implement `shouldUseLegacyAudioPath(streams, configs)`
    - Returns true iff every stream's config equals
      `AudioStreamConfig.defaultAac()` and `audioDefaultProfile ==
      defaultAac()`; switches to legacy `-c:a aac -b:a 320k -ar 48000`
      output for byte-equivalence with pre-feature command
    - _Requirements: 6.4_

  - [x] 12.3 Write property test for audio command construction
    - **Property 6: Audio command construction**
    - **Validates: Requirements 2.2, 2.3, 2.4, 2.5, 2.6, 2.7, 3.2,
      3.3, 3.4, 3.5, 4.1, 4.2, 4.3, 4.4, 4.5, 4.6, 4.7, 5.1, 5.2,
      5.3, 5.4, 5.5, 5.6, 5.7, 6.5**

- [x] 13. _TaskPlanner：视频码控参数
  - [x] 13.1 Implement `_buildVideoRateControlArguments(sel, cfg)`
    - Per-encoder branches per Req 7.4-7.7 (CRF emits `-crf` only;
      CBR emits `-b:v / -maxrate / -minrate / -bufsize` plus rate
      switch; VBR emits `-b:v` plus per-encoder rate switch + maxrate
      / bufsize; CQP emits per-encoder QP args)
    - Validate `^\d+[kKmM]$` for `bitrate / maxrate`; CRF/QP ∈ [0,51]
    - Defensive throw `当前编码器 X 不支持模式 Y`
    - When `cfg.userOverridden == false` defer to legacy
      `_buildVideoCodecArguments(sel)` for byte-equivalence
    - _Requirements: 7.4, 7.5, 7.6, 7.7, 7.8, 7.9_

  - [x] 13.2 Write property test for video rate-control args
    - **Property 7: Video rate-control command construction**
    - **Validates: Requirements 7.4, 7.5, 7.6, 7.7**

- [x] 14. _TaskPlanner：色调映射滤镜链
  - [x] 14.1 Implement `_buildToneMappingFilter(v, cfg, hasZscale)`
    - Returns `(filterChain, metadataArgs, logLines)`
    - `hasZscale=false` → empty filter, no axis-derived metadata,
      append `WARN: ffmpeg 未启用 libzimg，色调映射已跳过`
    - `tonemapMode=auto` decision table per Req 22.2-22.6
    - `tonemapMode=on` → force PQ-shaped tonemap chain regardless of
      `class`
    - `tonemapMode=off` → only insert `zscale=...` for axes !=
      `保持源`; full passthrough when all axes `保持源`
    - Suppress `-color_primaries / -color_trc / -colorspace /
      -color_range` for axes that are `保持源`
    - `desat ∈ [0,2]`, `peak == 'auto' || peak > 0`; otherwise throw
      `Exception("色调映射参数非法: <字段>")`
    - _Requirements: 22.2, 22.3, 22.4, 22.5, 22.6, 24.2, 24.3, 24.4,
      24.5, 26.4, 27.2_

  - [x] 14.2 Write property test for tonemap decision table
    - **Property 17: Tone mapping filter chain decision table**
    - **Validates: Requirements 22.2, 22.3, 22.4, 22.5, 22.6, 24.2,
      24.3, 24.4, 24.5, 26.4**

- [x] 15. _TaskPlanner：字体管线接入与 buildTaskPlan 主流程
  - [x] 15.1 Wire font index → match → subset before plan assembly
    - Build `charIndex` from enabled subtitle paths; collect candidate
      fonts as `importedFonts ∪ extractedAttachments` (Font_Source
      only, never MiSans)
    - Compute `FontMatchResult`; on `missing.isNotEmpty &&
      !continueOnMissingFont` throw
      `Exception("未找到字体: <fontname>")`; on `true` append
      `WARN: 字体 <fontname> 缺失` per missing entry
    - Call `subsetFonts(...)` when **both** `pyftsubset` and `ttx`
      are available; the result is `SubsetResult { fonts, renameMap }`
      and `renameMap` is forwarded to the new Subset_Rewrite_Ass step
      (see 15.5)
    - When `pyftsubset` OR `ttx` is missing, log
      `未找到 pyftsubset/ttx，已跳过字体子集化与 ASS 重写`, treat
      `renameMap` as empty, skip Subset_Rewrite_Ass, and pass the
      originals through (Req 13.5, 29.6)
    - When `continueOnMissingFont=true` and every font matched is
      missing → `renameMap` is empty → skip Subset_Rewrite_Ass per
      Req 29.6
    - _Requirements: 11.2, 11.5, 11.6, 12.3, 12.4, 13.5, 13.6, 13.7,
      14.10, 15.5, 20.6, 29.1, 29.6_

  - [x] 15.2 Inject subset fonts into hardsub plan
    - `_buildHardsubPlan` references subset directory via
      `subtitles=...:fontsdir=<workDir>/subsetted`; mask the path as
      `<workDir>/fonts` in `commandPreview`; never injects MiSans
    - When `renameMap` is non-empty, the `subtitles=...` filter
      references the Subset_Rewrite_Ass copy at
      `<workDir>/subtitles/<basename>.<原扩展>` (Req 29.4); on the
      skip-path (`renameMap` empty) it references the original ASS
      verbatim (Req 29.6)
    - _Requirements: 15.1, 15.2, 15.3, 15.4, 15.6, 29.4, 29.6_

  - [x] 15.3 Inject subset fonts into mux plan
    - `_buildMuxPlan` emits `-attach <subset.path>` plus
      `-metadata:s:t:i mimetype=<orig.mimeType>` /
      `filename=<orig.fileName>` per font; empty list when
      `continueOnMissingFont=true` and no matches; never MiSans
    - When `renameMap` is non-empty, the MKV subtitle stream input
      points to the Subset_Rewrite_Ass copy at
      `<workDir>/subtitles/<basename>.<原扩展>`, preserving original
      `language` / `title` metadata (Req 29.5); on the skip-path the
      original ASS path is used (Req 29.6)
    - _Requirements: 16.1, 16.2, 16.3, 16.4, 16.5, 16.6, 29.5, 29.6_

  - [x] 15.4 Add `commandPreview` diagnostic comment lines
    - `# audio:N <encoder>` per enabled audio stream (in order;
      copy → encoder = `copy`)
    - `# video <encoder> rc=<mode>` iff
      `videoEncodingConfigs[encoder].userOverridden == true`
    - `# tonemap source=<class> -> bt709 algo=<algo or none>` iff the
      final filter chain contains `zscale` or `tonemap`
    - _Requirements: 19.4, 19.5, 27.1_

  - [x] 15.5 Wire planner → SubsetAssRewriter call
    - After `subsetFonts` succeeds and BEFORE
      `_buildHardsubPlan` / `_buildMuxPlan`, when `renameMap` is
      non-empty: `Directory(<workDir>/subtitles).create(recursive:
      true)` and call `subset_ass_rewriter.dart` once per enabled
      ASS/SSA path with the shared `renameMap`
    - Output goes to `<workDir>/subtitles/<basename>.<原扩展>`;
      hardsub / mux planners then reference these copies (see 15.2 /
      15.3)
    - On the skip-path (`renameMap` empty) do NOT invoke the
      rewriter and leave `<workDir>/subtitles/` empty so the
      planners fall back to the original ASS paths (Req 29.6)
    - _Requirements: 29.1, 29.2, 29.4, 29.5, 29.7_

  - [x] 15.6 Write property test for missing-font failure policy
    - **Property 11: Missing-font failure policy**
    - **Validates: Requirements 11.5, 11.6, 12.3, 12.4, 15.3, 15.4,
      16.5, 16.6, 20.6**

  - [x] 15.7 Write property test for subset-font pipeline injection
    - **Property 15: Subset-font pipeline injection**
    - **Validates: Requirements 15.1, 15.2, 15.5, 15.6, 16.1, 16.2,
      16.3, 16.4**

  - [x] 15.8 Write property test for diagnostic comment lines
    - **Property 19: Diagnostic comment-line preview**
    - **Validates: Requirements 19.4, 19.5, 27.1**

  - [x] 15.9 Write property test for legacy command equivalence
    - **Property 5: Legacy command equivalence**
    - **Validates: Requirements 6.4, 7.9, 22.2**
    - Compare against golden snapshots in
      `frontend/test/golden/legacy_commands/`

  - [x] 15.10 Write property test for validation rejecting malformed input
    - **Property 20: Validation rejects malformed input**
    - **Validates: Requirements 3.6, 7.8, 20.1, 20.2, 27.2**

- [x] 16. Checkpoint - planner end-to-end on golden snapshots
  - Ensure all tests pass, ask the user if questions arise.

- [x] 17. _QueueRunner：子集化步骤、取消与错误捕获
  - [x] 17.1 Add `子集化字幕字体` `CommandStep` handling
    - One step per font, the step's execution wraps the three
      TTX_Pipeline sub-commands in order
      (`pyftsubset` → `ttx -f -o` → `ttx -f -b`); the in-memory
      TTX XML edit (Stage 2.5) is NOT a separate sub-process and is
      not counted as a sub-command
    - All three sub-command argv lines (executable absolute path +
      args) are appended to `task.log`, one line each (Req 19.1 /
      19.3)
    - `currentStep` collapses the three sub-commands and displays
      `子集化字幕字体 (i/n)` per Req 19.2
    - Disable ffmpeg `out_time_us` parsing for subset steps only;
      other steps preserve current parsing behavior
    - _Requirements: 19.1, 19.2, 19.3, 19.6_

  - [x] 17.2 Wire cancel signal to `subsetFonts`
    - Forward `stopQueueRequested` as `cancelSignal`; ensure in-flight
      `pyftsubset` is killed within 500ms; mark task
      `TaskStatus.cancelled`
    - _Requirements: 20.5_

  - [x] 17.3 Detect zscale / tonemap stderr failures
    - On stderr containing `Cannot find a matching filter` or
      `zscale: command not found`, mark task failed and append
      `ERROR: 色调映射执行失败，建议检查 ffmpeg 是否启用 libzimg`
    - Append DolbyVision `WARN: 检测到 Dolby Vision...` to task log top
    - Append `INFO: 用户已关闭 HDR 源的色调映射，输出可能偏色` when
      `tonemapMode=off` on HDR source
    - _Requirements: 22.5, 27.4, 27.5_

  - [x] 17.4 Write property test for subset-step progress accounting
    - **Property 21: Subset-step progress accounting**
    - **Validates: Requirements 19.1, 19.2, 19.3, 19.6**

  - [x] 17.5 Write integration test for cancellation
    - **Property 23: Cancellation terminates pyftsubset promptly**
    - **Validates: Requirements 20.5**

- [x] 18. UI: 视频码控扩展（`frontend/lib/src/widgets/encoding_panel.dart`）
  - [x] 18.1 Add `视频码控模式` dropdown into existing
    `高级编码参数（视频）` Tab
    - Candidates dynamically restricted by `Video_Encoder_Family`
      via `kSupportedRcModes`
    - Render mode-specific fields (CRF / CBR / VBR / CQP) and bind
      to `controller.videoEncodingConfigs[encoderKey]`
    - On invalid bitrate, render inline error
      `码率格式应为如 8000k 或 5M`
    - Trigger `controller.reconcileVideoEncodingMode(...)` on
      hardware mode / encoder family changes
    - _Requirements: 7.1, 7.2, 7.3, 7.8_

- [x] 19. UI: 音频参数 Tab（`Audio_Settings_Tab`）
  - [x] 19.1 Add `音频参数` Tab after existing tabs
    - `mediaInfo == null` → `请先导入视频。`; otherwise per-stream
      `ExpansionTile` with header `index / codec / language / title`
    - `enabled=false` streams: red `已禁用` badge, all controls
      disabled but underlying config preserved
    - Encoder dropdown candidates per Req 2.1 with
      `（未探测到）` suffix when missing in `audioEncoders`
    - Per-encoder visibility matrix per Req 2.2-2.7 (incl. opus
      `compression_level` and `vbr` mode, flac `compression_level`)
    - CBR/VBR radio per Req 3; sample-rate / channel-layout /
      downmix-algo per Req 4 (with `dpl2` only when source > 2ch)
    - Filter switches: loudnorm (I/TP/LRA), DRC
      (threshold/ratio/attack/release), custom filter; hidden under
      `copy` but values retained
    - `恢复默认` per stream + `全部恢复默认` global buttons reset
      to `Audio_Default_Profile`
    - _Requirements: 1.1, 1.2, 1.3, 1.4, 1.5, 2.1, 2.2, 2.3, 2.4,
      2.5, 2.6, 2.7, 2.8, 3.1, 3.6, 4.1, 4.4, 4.6, 5.1, 5.3, 5.5,
      5.7, 6.1, 6.2, 6.3_

  - [x] 19.2 Write widget tests for `Audio_Settings_Tab`
    - Empty mediaInfo placeholder
    - Disabled-stream visual state
    - Encoder switch hides/shows correct fields
    - _Requirements: 1.2, 1.4, 2.2, 2.6_

- [x] 20. UI: 字体处理 Tab（`Font_Settings_Tab`）
  - [x] 20.1 Add `字体处理` Tab with two switches
    - `SwitchListTile` "缺失字体时仍继续导出", default false,
      bound to `controller.continueOnMissingFont`
    - Helper line: `默认关闭。开启后字幕字体匹配失败时不再终止任务，
      但成品可能出现字体替换。`
    - Second `SwitchListTile` "思源黑/宋字体省略号居中对齐",
      default `true`, bound to `controller.sourceHanEllipsisFix`
    - Subtitle: `子集化时移除横排省略号的低基线替换规则，使横排
      字幕中省略号居中显示。仅对识别为 Source Han 系列的字体生效。`
    - _Requirements: 12.1, 12.2, 12.5, 12.6, 28.4_

  - [x] 20.2 Write widget tests for `Font_Settings_Tab`
    - Default off / on respectively; toggling persists into snapshot
    - _Requirements: 12.2, 12.5, 28.4_

- [x] 21. UI: 色调映射 Tab（`Tone_Mapping_Tab`）
  - [x] 21.1 Build `Tone_Mapping_Tab` layout
    - `mediaInfo == null` → `请先导入视频。`
    - `源色彩特性` read-only card (9 fields) + colored
      `Source_Color_Class` chip
    - Recommendation card visible only when class !=
      `SDR_BT709`; with `一键采纳` and `我自己来` actions
    - `高级覆盖` ExpansionTile with the 7 controls per Req 24.1;
      tonemap-algo enabled only for `mode=on` or (`auto` + HDR)
    - Inline validation for `desat` / `peak` per Req 27.2
    - When `RuntimeDiagnostics.hasZscale=false`: top warning banner +
      all controls disabled
    - _Requirements: 21.1, 21.2, 21.3, 21.4, 21.5, 23.1, 23.2, 23.3,
      23.4, 24.1, 26.3, 26.5, 27.2_

  - [x] 21.2 Write widget tests for `Tone_Mapping_Tab`
    - HDR source shows recommendation; SDR_BT709 shows passthrough
      hint; zscale-missing banner disables controls
    - _Requirements: 21.4, 23.4, 26.3_

- [x] 22. Final checkpoint - 全部测试通过
  - Ensure all tests pass, ask the user if questions arise.

## Notes

- 任务编号遵循 design.md 中的依赖与关键路径：先模型再 services 再
  controller 再 planner 最后 UI；UI 改动放最后避免 widget 重建影响
  property 测试。
- 所有标 `*` 的子任务为可选，对应 PBT / widget 测试，可在 MVP 阶段
  跳过；核心实现任务必须落地。
- Property 编号与 design.md 的 `Correctness Properties` 段一一对应，
  每条 property 单独成子任务，方便逐条追溯到 requirements 的具体子
  条款。
- Property 5（Legacy command equivalence）依赖
  `frontend/test/golden/legacy_commands/` 目录下的 golden 文件，需在
  动手改 `_TaskPlanner` 之前先快照一份现行命令输出。
- 子集化采用 [AssFontSubset](https://github.com/AmusementClub/AssFontSubset)
  实现路径的 TTX_Pipeline（pyftsubset → ttx -f -o → in-mem 改 NameID
  → ttx -f -b），并由 Subset_Rewrite_Ass 把 Font_Random_Rename 回填进
  ASS/SSA 副本，避免 libass / VSFilter 命中用户系统中同名原版字体。
- 任务 8.x 引入的 P24-P28 是在原 23 条 property 之外新增的 5 条
  property 测试，专门覆盖 TTX_Pipeline、Source Han ellipsis fix、
  Subset_Rewrite_Ass 与 Vert_Mapping_Table 的不变性。
- `ttx` 与 `pyftsubset` 同属 fonttools 包但独立判定可用性；任一缺失
  时整个子集化阶段（含 Font_Random_Rename 与 Subset_Rewrite_Ass）
  跳过，部分集成测试（7.7 / 7.8 / 8.4 / 8.5）需要真实的 `ttx.exe`
  与 `pyftsubset.exe`，会被 CI 环境变量门控。

- 任务隔离：单条任务异常仅影响 `tasks[i]`，`_QueueRunner` 现有 for
  循环会捕获并继续推进，符合 Req 20.1.
- MiSans 兜底在 `_buildHardsubPlan / _buildMuxPlan / matchFonts` 三处
  均显式禁止注入，并通过单元测试 + 静态注释作为机器化 guard。

## Task Dependency Graph

```json
{
  "waves": [
    { "id": 0, "tasks": ["1.1"] },
    { "id": 1, "tasks": ["1.2", "2.1", "3.1", "5.1", "6.1",
      "7.4", "7.5", "10.1"] },
    { "id": 2, "tasks": ["1.3", "2.2", "3.2", "5.2", "6.2", "8.6",
      "10.2", "11.1"] },
    { "id": 3, "tasks": ["1.4", "2.3", "2.4", "5.3", "7.1", "8.1",
      "10.3", "11.2", "11.3", "18.1"] },
    { "id": 4, "tasks": ["1.5", "2.5", "6.3", "7.2", "8.2", "8.3",
      "8.4", "8.5", "13.1", "20.1"] },
    { "id": 5, "tasks": ["1.6", "7.3", "7.6", "12.1", "12.2", "20.2"] },
    { "id": 6, "tasks": ["7.7", "12.3", "14.1"] },
    { "id": 7, "tasks": ["7.8", "13.2", "14.2", "21.1"] },
    { "id": 8, "tasks": ["7.9", "15.1", "19.1", "21.2"] },
    { "id": 9, "tasks": ["15.2", "15.5", "15.6", "17.1", "19.2"] },
    { "id": 10, "tasks": ["15.3", "17.2"] },
    { "id": 11, "tasks": ["15.4", "15.7", "17.3", "17.4"] },
    { "id": 12, "tasks": ["15.8", "17.5"] },
    { "id": 13, "tasks": ["15.9"] },
    { "id": 14, "tasks": ["15.10"] }
  ]
}
```
