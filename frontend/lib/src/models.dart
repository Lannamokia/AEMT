enum StreamKind { video, audio, subtitle, attachment, data, unknown }

enum StreamOrigin { input, externalSubtitle }

enum ExportProfile { hardsubMp4, muxMkv }

enum TaskStatus { queued, running, success, failed, cancelled }

enum CompressionMode { generic, episodic }

enum HardwareMode { auto, software, nvenc, qsv, amf }

enum SourceColorClass {
  sdrBt709,
  sdrWideGamut,
  hdrPq,
  hdrHlg,
  dolbyVision,
  unknown,
}

enum FontSourceKind { imported, attachment, system, subsetted }

const Map<String, List<String>> kSupportedRcModes = <String, List<String>>{
  'libx264': <String>['CRF', 'CBR', 'VBR'],
  'libx265': <String>['CRF', 'CBR', 'VBR'],
  'h264_nvenc': <String>['CBR', 'VBR', 'CQP'],
  'hevc_nvenc': <String>['CBR', 'VBR', 'CQP'],
  'h264_qsv': <String>['CBR', 'VBR', 'CQP'],
  'hevc_qsv': <String>['CBR', 'VBR', 'CQP'],
  'h264_amf': <String>['CBR', 'VBR', 'CQP'],
  'hevc_amf': <String>['CBR', 'VBR', 'CQP'],
};

T _enumByName<T extends Enum>(List<T> values, Object? rawValue, T fallback) {
  final String value = (rawValue ?? '').toString();
  for (final T item in values) {
    if (item.name == value) {
      return item;
    }
  }
  return fallback;
}

String _readString(Map<String, dynamic> json, String field, String fallback) {
  if (!json.containsKey(field) || json[field] == null) {
    return fallback;
  }
  final Object? value = json[field];
  if (value is String) {
    return value;
  }
  throw FormatException('字段 $field 类型不匹配');
}

int _readInt(Map<String, dynamic> json, String field, int fallback) {
  if (!json.containsKey(field) || json[field] == null) {
    return fallback;
  }
  final Object? value = json[field];
  if (value is int) {
    return value;
  }
  if (value is num && value.roundToDouble() == value.toDouble()) {
    return value.toInt();
  }
  throw FormatException('字段 $field 类型不匹配');
}

double _readDouble(Map<String, dynamic> json, String field, double fallback) {
  if (!json.containsKey(field) || json[field] == null) {
    return fallback;
  }
  final Object? value = json[field];
  if (value is num) {
    return value.toDouble();
  }
  throw FormatException('字段 $field 类型不匹配');
}

bool _readBool(Map<String, dynamic> json, String field, bool fallback) {
  if (!json.containsKey(field) || json[field] == null) {
    return fallback;
  }
  final Object? value = json[field];
  if (value is bool) {
    return value;
  }
  throw FormatException('字段 $field 类型不匹配');
}

Map<String, dynamic> _readObjectMap(Map<String, dynamic> json, String field) {
  if (!json.containsKey(field) || json[field] == null) {
    return <String, dynamic>{};
  }
  final Object? value = json[field];
  if (value is Map<String, dynamic>) {
    return value;
  }
  if (value is Map) {
    return value.map(
      (dynamic key, dynamic innerValue) => MapEntry(key.toString(), innerValue),
    );
  }
  throw FormatException('字段 $field 类型不匹配');
}

bool _setEquals<T>(Set<T> a, Set<T> b) {
  if (identical(a, b)) {
    return true;
  }
  if (a.length != b.length) {
    return false;
  }
  for (final T value in a) {
    if (!b.contains(value)) {
      return false;
    }
  }
  return true;
}

bool _mapEquals<K, V>(
  Map<K, V> a,
  Map<K, V> b,
  bool Function(V a, V b) valueEquals,
) {
  if (identical(a, b)) {
    return true;
  }
  if (a.length != b.length) {
    return false;
  }
  for (final K key in a.keys) {
    if (!b.containsKey(key) || !valueEquals(a[key] as V, b[key] as V)) {
      return false;
    }
  }
  return true;
}

class NamingTemplateVariable {
  const NamingTemplateVariable({required this.name, required this.description});

  final String name;
  final String description;
}

class EncoderTuningSelection {
  const EncoderTuningSelection({required this.preset, required this.tune});

  final String preset;
  final String tune;

  Map<String, dynamic> toJson() {
    return <String, dynamic>{'preset': preset, 'tune': tune};
  }

  factory EncoderTuningSelection.fromJson(Map<String, dynamic> json) {
    return EncoderTuningSelection(
      preset: (json['preset'] ?? '').toString(),
      tune: (json['tune'] ?? '').toString(),
    );
  }
}

class Version implements Comparable<Version> {
  const Version(this.major, this.minor, this.patch);

  final int major;
  final int minor;
  final int patch;

  static Version? tryParse(String value) {
    final RegExpMatch? match = RegExp(r'(\d+)\.(\d+)\.(\d+)').firstMatch(value);
    if (match == null) {
      return null;
    }
    return Version(
      int.parse(match.group(1)!),
      int.parse(match.group(2)!),
      int.parse(match.group(3)!),
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{'major': major, 'minor': minor, 'patch': patch};
  }

  factory Version.fromJson(Map<String, dynamic> json) {
    return Version(
      _readInt(json, 'major', 0),
      _readInt(json, 'minor', 0),
      _readInt(json, 'patch', 0),
    );
  }

  @override
  int compareTo(Version other) {
    if (major != other.major) {
      return major.compareTo(other.major);
    }
    if (minor != other.minor) {
      return minor.compareTo(other.minor);
    }
    return patch.compareTo(other.patch);
  }

  bool operator >(Version other) => compareTo(other) > 0;

  @override
  String toString() => '$major.$minor.$patch';

  @override
  bool operator ==(Object other) {
    return other is Version &&
        other.major == major &&
        other.minor == minor &&
        other.patch == patch;
  }

  @override
  int get hashCode => Object.hash(major, minor, patch);
}

class AudioStreamConfig {
  const AudioStreamConfig({
    required this.encoder,
    required this.mode,
    required this.bitrate,
    required this.vbrQuality,
    required this.vbrModeOpus,
    required this.sampleRate,
    required this.channelLayout,
    required this.downmixAlgo,
    required this.profile,
    required this.compressionLevel,
    required this.loudnormEnabled,
    required this.loudnormI,
    required this.loudnormTp,
    required this.loudnormLra,
    required this.drcEnabled,
    required this.drcThreshold,
    required this.drcRatio,
    required this.drcAttack,
    required this.drcRelease,
    required this.customFilter,
  });

  const AudioStreamConfig.defaultAac()
    : encoder = 'aac',
      mode = 'CBR',
      bitrate = '320k',
      vbrQuality = 3,
      vbrModeOpus = 'on',
      sampleRate = '48000',
      channelLayout = '保持源',
      downmixAlgo = '默认',
      profile = 'aac_low',
      compressionLevel = 5,
      loudnormEnabled = false,
      loudnormI = -16,
      loudnormTp = -1.5,
      loudnormLra = 11,
      drcEnabled = false,
      drcThreshold = -18,
      drcRatio = 3,
      drcAttack = 20,
      drcRelease = 250,
      customFilter = '';

  final String encoder;
  final String mode;
  final String bitrate;
  final int vbrQuality;
  final String vbrModeOpus;
  final String sampleRate;
  final String channelLayout;
  final String downmixAlgo;
  final String profile;
  final int compressionLevel;
  final bool loudnormEnabled;
  final double loudnormI;
  final double loudnormTp;
  final double loudnormLra;
  final bool drcEnabled;
  final double drcThreshold;
  final double drcRatio;
  final double drcAttack;
  final double drcRelease;
  final String customFilter;

  AudioStreamConfig copyWith({
    String? encoder,
    String? mode,
    String? bitrate,
    int? vbrQuality,
    String? vbrModeOpus,
    String? sampleRate,
    String? channelLayout,
    String? downmixAlgo,
    String? profile,
    int? compressionLevel,
    bool? loudnormEnabled,
    double? loudnormI,
    double? loudnormTp,
    double? loudnormLra,
    bool? drcEnabled,
    double? drcThreshold,
    double? drcRatio,
    double? drcAttack,
    double? drcRelease,
    String? customFilter,
  }) {
    return AudioStreamConfig(
      encoder: encoder ?? this.encoder,
      mode: mode ?? this.mode,
      bitrate: bitrate ?? this.bitrate,
      vbrQuality: vbrQuality ?? this.vbrQuality,
      vbrModeOpus: vbrModeOpus ?? this.vbrModeOpus,
      sampleRate: sampleRate ?? this.sampleRate,
      channelLayout: channelLayout ?? this.channelLayout,
      downmixAlgo: downmixAlgo ?? this.downmixAlgo,
      profile: profile ?? this.profile,
      compressionLevel: compressionLevel ?? this.compressionLevel,
      loudnormEnabled: loudnormEnabled ?? this.loudnormEnabled,
      loudnormI: loudnormI ?? this.loudnormI,
      loudnormTp: loudnormTp ?? this.loudnormTp,
      loudnormLra: loudnormLra ?? this.loudnormLra,
      drcEnabled: drcEnabled ?? this.drcEnabled,
      drcThreshold: drcThreshold ?? this.drcThreshold,
      drcRatio: drcRatio ?? this.drcRatio,
      drcAttack: drcAttack ?? this.drcAttack,
      drcRelease: drcRelease ?? this.drcRelease,
      customFilter: customFilter ?? this.customFilter,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'encoder': encoder,
      'mode': mode,
      'bitrate': bitrate,
      'vbrQuality': vbrQuality,
      'vbrModeOpus': vbrModeOpus,
      'sampleRate': sampleRate,
      'channelLayout': channelLayout,
      'downmixAlgo': downmixAlgo,
      'profile': profile,
      'compressionLevel': compressionLevel,
      'loudnormEnabled': loudnormEnabled,
      'loudnormI': loudnormI,
      'loudnormTp': loudnormTp,
      'loudnormLra': loudnormLra,
      'drcEnabled': drcEnabled,
      'drcThreshold': drcThreshold,
      'drcRatio': drcRatio,
      'drcAttack': drcAttack,
      'drcRelease': drcRelease,
      'customFilter': customFilter,
    };
  }

  factory AudioStreamConfig.fromJson(Map<String, dynamic> json) {
    const AudioStreamConfig defaults = AudioStreamConfig.defaultAac();
    return AudioStreamConfig(
      encoder: _readString(json, 'encoder', defaults.encoder),
      mode: _readString(json, 'mode', defaults.mode),
      bitrate: _readString(json, 'bitrate', defaults.bitrate),
      vbrQuality: _readInt(json, 'vbrQuality', defaults.vbrQuality),
      vbrModeOpus: _readString(json, 'vbrModeOpus', defaults.vbrModeOpus),
      sampleRate: _readString(json, 'sampleRate', defaults.sampleRate),
      channelLayout: _readString(json, 'channelLayout', defaults.channelLayout),
      downmixAlgo: _readString(json, 'downmixAlgo', defaults.downmixAlgo),
      profile: _readString(json, 'profile', defaults.profile),
      compressionLevel: _readInt(
        json,
        'compressionLevel',
        defaults.compressionLevel,
      ),
      loudnormEnabled: _readBool(
        json,
        'loudnormEnabled',
        defaults.loudnormEnabled,
      ),
      loudnormI: _readDouble(json, 'loudnormI', defaults.loudnormI),
      loudnormTp: _readDouble(json, 'loudnormTp', defaults.loudnormTp),
      loudnormLra: _readDouble(json, 'loudnormLra', defaults.loudnormLra),
      drcEnabled: _readBool(json, 'drcEnabled', defaults.drcEnabled),
      drcThreshold: _readDouble(json, 'drcThreshold', defaults.drcThreshold),
      drcRatio: _readDouble(json, 'drcRatio', defaults.drcRatio),
      drcAttack: _readDouble(json, 'drcAttack', defaults.drcAttack),
      drcRelease: _readDouble(json, 'drcRelease', defaults.drcRelease),
      customFilter: _readString(json, 'customFilter', defaults.customFilter),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is AudioStreamConfig &&
        other.encoder == encoder &&
        other.mode == mode &&
        other.bitrate == bitrate &&
        other.vbrQuality == vbrQuality &&
        other.vbrModeOpus == vbrModeOpus &&
        other.sampleRate == sampleRate &&
        other.channelLayout == channelLayout &&
        other.downmixAlgo == downmixAlgo &&
        other.profile == profile &&
        other.compressionLevel == compressionLevel &&
        other.loudnormEnabled == loudnormEnabled &&
        other.loudnormI == loudnormI &&
        other.loudnormTp == loudnormTp &&
        other.loudnormLra == loudnormLra &&
        other.drcEnabled == drcEnabled &&
        other.drcThreshold == drcThreshold &&
        other.drcRatio == drcRatio &&
        other.drcAttack == drcAttack &&
        other.drcRelease == drcRelease &&
        other.customFilter == customFilter;
  }

  @override
  int get hashCode => Object.hashAll(<Object?>[
    encoder,
    mode,
    bitrate,
    vbrQuality,
    vbrModeOpus,
    sampleRate,
    channelLayout,
    downmixAlgo,
    profile,
    compressionLevel,
    loudnormEnabled,
    loudnormI,
    loudnormTp,
    loudnormLra,
    drcEnabled,
    drcThreshold,
    drcRatio,
    drcAttack,
    drcRelease,
    customFilter,
  ]);
}

class VideoEncodingConfig {
  const VideoEncodingConfig({
    required this.mode,
    required this.userOverridden,
    required this.crf,
    required this.bitrate,
    required this.maxrate,
    required this.minrate,
    required this.bufsize,
    required this.qpI,
    required this.qpP,
    required this.qpB,
  });

  factory VideoEncodingConfig.defaultsFor(String encoderKey) {
    final bool software = encoderKey == 'libx264' || encoderKey == 'libx265';
    return VideoEncodingConfig(
      mode: software ? 'CRF' : 'VBR',
      userOverridden: false,
      crf: 23,
      bitrate: '',
      maxrate: '',
      minrate: '',
      bufsize: '',
      qpI: 23,
      qpP: 25,
      qpB: 28,
    );
  }

  final String mode;
  final bool userOverridden;
  final int crf;
  final String bitrate;
  final String maxrate;
  final String minrate;
  final String bufsize;
  final int qpI;
  final int qpP;
  final int qpB;

  VideoEncodingConfig copyWith({
    String? mode,
    bool? userOverridden,
    int? crf,
    String? bitrate,
    String? maxrate,
    String? minrate,
    String? bufsize,
    int? qpI,
    int? qpP,
    int? qpB,
  }) {
    return VideoEncodingConfig(
      mode: mode ?? this.mode,
      userOverridden: userOverridden ?? this.userOverridden,
      crf: crf ?? this.crf,
      bitrate: bitrate ?? this.bitrate,
      maxrate: maxrate ?? this.maxrate,
      minrate: minrate ?? this.minrate,
      bufsize: bufsize ?? this.bufsize,
      qpI: qpI ?? this.qpI,
      qpP: qpP ?? this.qpP,
      qpB: qpB ?? this.qpB,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'mode': mode,
      'userOverridden': userOverridden,
      'crf': crf,
      'bitrate': bitrate,
      'maxrate': maxrate,
      'minrate': minrate,
      'bufsize': bufsize,
      'qpI': qpI,
      'qpP': qpP,
      'qpB': qpB,
    };
  }

  factory VideoEncodingConfig.fromJson(
    Map<String, dynamic> json, {
    String encoderKey = 'libx264',
  }) {
    final VideoEncodingConfig defaults = VideoEncodingConfig.defaultsFor(
      encoderKey,
    );
    return VideoEncodingConfig(
      mode: _readString(json, 'mode', defaults.mode),
      userOverridden: _readBool(
        json,
        'userOverridden',
        defaults.userOverridden,
      ),
      crf: _readInt(json, 'crf', defaults.crf),
      bitrate: _readString(json, 'bitrate', defaults.bitrate),
      maxrate: _readString(json, 'maxrate', defaults.maxrate),
      minrate: _readString(json, 'minrate', defaults.minrate),
      bufsize: _readString(json, 'bufsize', defaults.bufsize),
      qpI: _readInt(json, 'qpI', defaults.qpI),
      qpP: _readInt(json, 'qpP', defaults.qpP),
      qpB: _readInt(json, 'qpB', defaults.qpB),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is VideoEncodingConfig &&
        other.mode == mode &&
        other.userOverridden == userOverridden &&
        other.crf == crf &&
        other.bitrate == bitrate &&
        other.maxrate == maxrate &&
        other.minrate == minrate &&
        other.bufsize == bufsize &&
        other.qpI == qpI &&
        other.qpP == qpP &&
        other.qpB == qpB;
  }

  @override
  int get hashCode => Object.hash(
    mode,
    userOverridden,
    crf,
    bitrate,
    maxrate,
    minrate,
    bufsize,
    qpI,
    qpP,
    qpB,
  );
}

class ToneMappingConfig {
  const ToneMappingConfig({
    required this.outputPrimaries,
    required this.outputTransfer,
    required this.outputRange,
    required this.tonemapMode,
    required this.tonemapAlgo,
    required this.peak,
    required this.desat,
  });

  const ToneMappingConfig.defaultBt709()
    : outputPrimaries = 'bt709',
      outputTransfer = 'bt709',
      outputRange = 'tv',
      tonemapMode = 'auto',
      tonemapAlgo = 'hable',
      peak = 'auto',
      desat = 0;

  final String outputPrimaries;
  final String outputTransfer;
  final String outputRange;
  final String tonemapMode;
  final String tonemapAlgo;
  final String peak;
  final double desat;

  ToneMappingConfig copyWith({
    String? outputPrimaries,
    String? outputTransfer,
    String? outputRange,
    String? tonemapMode,
    String? tonemapAlgo,
    String? peak,
    double? desat,
  }) {
    return ToneMappingConfig(
      outputPrimaries: outputPrimaries ?? this.outputPrimaries,
      outputTransfer: outputTransfer ?? this.outputTransfer,
      outputRange: outputRange ?? this.outputRange,
      tonemapMode: tonemapMode ?? this.tonemapMode,
      tonemapAlgo: tonemapAlgo ?? this.tonemapAlgo,
      peak: peak ?? this.peak,
      desat: desat ?? this.desat,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'outputPrimaries': outputPrimaries,
      'outputTransfer': outputTransfer,
      'outputRange': outputRange,
      'tonemapMode': tonemapMode,
      'tonemapAlgo': tonemapAlgo,
      'peak': peak,
      'desat': desat,
    };
  }

  factory ToneMappingConfig.fromJson(Map<String, dynamic> json) {
    const ToneMappingConfig defaults = ToneMappingConfig.defaultBt709();
    final String rawMode = _readString(
      json,
      'tonemapMode',
      defaults.tonemapMode,
    );
    return ToneMappingConfig(
      outputPrimaries: _readString(
        json,
        'outputPrimaries',
        defaults.outputPrimaries,
      ),
      outputTransfer: _readString(
        json,
        'outputTransfer',
        defaults.outputTransfer,
      ),
      outputRange: _readString(json, 'outputRange', defaults.outputRange),
      tonemapMode: rawMode == 'manual' ? 'on' : rawMode,
      tonemapAlgo: _readString(json, 'tonemapAlgo', defaults.tonemapAlgo),
      peak: _readString(json, 'peak', defaults.peak),
      desat: _readDouble(json, 'desat', defaults.desat),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is ToneMappingConfig &&
        other.outputPrimaries == outputPrimaries &&
        other.outputTransfer == outputTransfer &&
        other.outputRange == outputRange &&
        other.tonemapMode == tonemapMode &&
        other.tonemapAlgo == tonemapAlgo &&
        other.peak == peak &&
        other.desat == desat;
  }

  @override
  int get hashCode => Object.hash(
    outputPrimaries,
    outputTransfer,
    outputRange,
    tonemapMode,
    tonemapAlgo,
    peak,
    desat,
  );
}

class VideoStreamInfo {
  const VideoStreamInfo({
    this.colorSpace = 'unknown',
    this.colorPrimaries = 'unknown',
    this.colorTransfer = 'unknown',
    this.colorRange = 'unknown',
    this.bitsPerRawSample = 0,
    this.masterDisplay = '',
    this.maxCll = 0,
    this.maxFall = 0,
    this.dolbyVision = false,
  });

  final String colorSpace;
  final String colorPrimaries;
  final String colorTransfer;
  final String colorRange;
  final int bitsPerRawSample;
  final String masterDisplay;
  final num maxCll;
  final num maxFall;
  final bool dolbyVision;

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'colorSpace': colorSpace,
      'colorPrimaries': colorPrimaries,
      'colorTransfer': colorTransfer,
      'colorRange': colorRange,
      'bitsPerRawSample': bitsPerRawSample,
      'masterDisplay': masterDisplay,
      'maxCll': maxCll,
      'maxFall': maxFall,
      'dolbyVision': dolbyVision,
    };
  }

  factory VideoStreamInfo.fromJson(Map<String, dynamic> json) {
    return VideoStreamInfo(
      colorSpace: _readString(json, 'colorSpace', 'unknown'),
      colorPrimaries: _readString(json, 'colorPrimaries', 'unknown'),
      colorTransfer: _readString(json, 'colorTransfer', 'unknown'),
      colorRange: _readString(json, 'colorRange', 'unknown'),
      bitsPerRawSample: _readInt(json, 'bitsPerRawSample', 0),
      masterDisplay: _readString(json, 'masterDisplay', ''),
      maxCll: json['maxCll'] is num ? json['maxCll'] as num : 0,
      maxFall: json['maxFall'] is num ? json['maxFall'] as num : 0,
      dolbyVision: _readBool(json, 'dolbyVision', false),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is VideoStreamInfo &&
        other.colorSpace == colorSpace &&
        other.colorPrimaries == colorPrimaries &&
        other.colorTransfer == colorTransfer &&
        other.colorRange == colorRange &&
        other.bitsPerRawSample == bitsPerRawSample &&
        other.masterDisplay == masterDisplay &&
        other.maxCll == maxCll &&
        other.maxFall == maxFall &&
        other.dolbyVision == dolbyVision;
  }

  @override
  int get hashCode => Object.hash(
    colorSpace,
    colorPrimaries,
    colorTransfer,
    colorRange,
    bitsPerRawSample,
    masterDisplay,
    maxCll,
    maxFall,
    dolbyVision,
  );
}

SourceColorClass detectSourceColorClass(VideoStreamInfo video) {
  final String transfer = video.colorTransfer.toLowerCase();
  final String primaries = video.colorPrimaries.toLowerCase();
  if (video.dolbyVision) {
    return SourceColorClass.dolbyVision;
  }
  if (transfer == 'smpte2084') {
    return SourceColorClass.hdrPq;
  }
  if (transfer == 'arib-std-b67') {
    return SourceColorClass.hdrHlg;
  }
  if (<String>{'bt2020', 'smpte432', 'smpte431'}.contains(primaries) &&
      !<String>{'smpte2084', 'arib-std-b67'}.contains(transfer)) {
    return SourceColorClass.sdrWideGamut;
  }
  if (primaries == 'bt709' ||
      (primaries == 'undefined' && video.bitsPerRawSample <= 8)) {
    return SourceColorClass.sdrBt709;
  }
  return SourceColorClass.unknown;
}

class SubtitleCharIndex {
  const SubtitleCharIndex(this.codepointsByFontname);

  final Map<String, Set<int>> codepointsByFontname;

  bool get isEmpty => codepointsByFontname.isEmpty;

  @override
  bool operator ==(Object other) {
    return other is SubtitleCharIndex &&
        _mapEquals<String, Set<int>>(
          other.codepointsByFontname,
          codepointsByFontname,
          _setEquals<int>,
        );
  }

  @override
  int get hashCode {
    return Object.hashAll(
      codepointsByFontname.entries.map(
        (MapEntry<String, Set<int>> entry) => Object.hash(
          entry.key,
          Object.hashAll(entry.value.toList()..sort()),
        ),
      ),
    );
  }
}

class FontMatchResult {
  const FontMatchResult({required this.matched, required this.missing});

  final Map<String, ResolvedFontFile> matched;
  final Set<String> missing;
}

class SubsetResult {
  const SubsetResult({required this.fonts, required this.renameMap});

  final List<ResolvedFontFile> fonts;
  final Map<String, String> renameMap;
}

class FontSubsetStepPlan {
  const FontSubsetStepPlan({
    required this.originalFont,
    required this.outputFont,
    required this.normalizedKey,
    required this.randomName,
    required this.codepoints,
    required this.pyftsubsetPath,
    required this.ttxPath,
    required this.aemtVersion,
    required this.fontToolsVersion,
    required this.sourceHanEllipsisFix,
    required this.verifyAfterSubset,
    required this.fsTypeRestricted,
    required this.subsetDir,
    required this.codepointsFilePath,
    required this.subsetTempPath,
    required this.ttxXmlPath,
  });

  final ResolvedFontFile originalFont;
  final ResolvedFontFile outputFont;
  final String normalizedKey;
  final String randomName;
  final List<int> codepoints;
  final String pyftsubsetPath;
  final String ttxPath;
  final String aemtVersion;
  final String? fontToolsVersion;
  final bool sourceHanEllipsisFix;
  final bool verifyAfterSubset;
  final bool fsTypeRestricted;
  final String subsetDir;
  final String codepointsFilePath;
  final String subsetTempPath;
  final String ttxXmlPath;

  List<String> get pyftsubsetArguments {
    return <String>[
      originalFont.path,
      '--unicodes-file=$codepointsFilePath',
      '--output-file=$subsetTempPath',
      '--no-hinting',
      '--retain-gids',
      '--layout-features=vert,vrtr,vrt2,vkna',
      '--name-IDs=*',
      '--name-languages=*',
      '--drop-tables=',
      '--font-number=${originalFont.trackIndex}',
      ...fontToolsCompatibilityFlags(fontToolsVersion),
    ];
  }

  List<String> get ttxDumpArguments {
    return <String>['-f', '-o', ttxXmlPath, subsetTempPath];
  }

  List<String> get ttxCompileArguments {
    return <String>['-f', '-b', '-o', outputFont.path, ttxXmlPath];
  }
}

List<String> fontToolsCompatibilityFlags(String? versionText) {
  final Version? version = versionText == null
      ? null
      : Version.tryParse(versionText);
  final List<String> flags = <String>[];
  if (version == null || version > const Version(4, 44, 0)) {
    flags.add('--no-prune-codepage-ranges');
  }
  if (version == null || version > const Version(4, 60, 0)) {
    flags.add('--drop-tables+=BASE');
  }
  return flags;
}

class EncodingSettingsSnapshot {
  const EncodingSettingsSnapshot({
    required this.compressionMode,
    required this.hardwareMode,
    required this.outputFileNameOverride,
    required this.releaseGroup,
    required this.titleOverride,
    required this.seasonNumber,
    required this.episodeNumber,
    required this.sourceLabel,
    required this.episodicNamingTemplate,
    required this.outputResolution,
    required this.outputFps,
    required this.outputDirectory,
    required this.avcBitrate,
    required this.avcMaxrate,
    required this.hevcBitrate,
    required this.hevcMaxrate,
    required this.encoderTunings,
    this.audioStreamConfigs = const <String, AudioStreamConfig>{},
    this.audioDefaultProfile = const AudioStreamConfig.defaultAac(),
    this.videoEncodingConfigs = const <String, VideoEncodingConfig>{},
    this.toneMappingConfig = const ToneMappingConfig.defaultBt709(),
    this.continueOnMissingFont = false,
    this.fontSubsettingEnabled = true,
    this.sourceHanEllipsisFix = true,
    this.importStatusMessage,
  });

  final CompressionMode compressionMode;
  final HardwareMode hardwareMode;
  final String outputFileNameOverride;
  final String releaseGroup;
  final String titleOverride;
  final String seasonNumber;
  final String episodeNumber;
  final String sourceLabel;
  final String episodicNamingTemplate;
  final String outputResolution;
  final String outputFps;
  final String outputDirectory;
  final String avcBitrate;
  final String avcMaxrate;
  final String hevcBitrate;
  final String hevcMaxrate;
  final Map<String, EncoderTuningSelection> encoderTunings;
  final Map<String, AudioStreamConfig> audioStreamConfigs;
  final AudioStreamConfig audioDefaultProfile;
  final Map<String, VideoEncodingConfig> videoEncodingConfigs;
  final ToneMappingConfig toneMappingConfig;
  final bool continueOnMissingFont;
  final bool fontSubsettingEnabled;
  final bool sourceHanEllipsisFix;
  final String? importStatusMessage;

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'type': 'aemt.encoding-settings',
      'version': 2,
      'compressionMode': compressionMode.name,
      'hardwareMode': hardwareMode.name,
      'outputFileNameOverride': outputFileNameOverride,
      'releaseGroup': releaseGroup,
      'titleOverride': titleOverride,
      'seasonNumber': seasonNumber,
      'episodeNumber': episodeNumber,
      'sourceLabel': sourceLabel,
      'episodicNamingTemplate': episodicNamingTemplate,
      'outputResolution': outputResolution,
      'outputFps': outputFps,
      'outputDirectory': outputDirectory,
      'avcBitrate': avcBitrate,
      'avcMaxrate': avcMaxrate,
      'hevcBitrate': hevcBitrate,
      'hevcMaxrate': hevcMaxrate,
      'encoderTunings': encoderTunings.map(
        (String key, EncoderTuningSelection value) =>
            MapEntry(key, value.toJson()),
      ),
      'audioStreamConfigs': audioStreamConfigs.map(
        (String key, AudioStreamConfig value) => MapEntry(key, value.toJson()),
      ),
      'audioDefaultProfile': audioDefaultProfile.toJson(),
      'videoEncodingConfigs': videoEncodingConfigs.map(
        (String key, VideoEncodingConfig value) =>
            MapEntry(key, value.toJson()),
      ),
      'toneMappingConfig': toneMappingConfig.toJson(),
      'continueOnMissingFont': continueOnMissingFont,
      'fontSubsettingEnabled': fontSubsettingEnabled,
      'sourceHanEllipsisFix': sourceHanEllipsisFix,
    };
  }

  factory EncodingSettingsSnapshot.fromJson(Map<String, dynamic> json) {
    if ((json['type'] ?? '').toString() != 'aemt.encoding-settings') {
      throw const FormatException('不是 AEMT 编码参数配置文件。');
    }
    final int version = json['version'] is int
        ? json['version'] as int
        : int.tryParse((json['version'] ?? '').toString()) ?? 0;
    if (version < 1 || version > 2) {
      throw FormatException('不支持的编码参数配置版本: $version');
    }
    final Map<String, dynamic> tuningJson = _readObjectMap(
      json,
      'encoderTunings',
    );
    final Map<String, dynamic> audioConfigJson = _readObjectMap(
      json,
      'audioStreamConfigs',
    );
    final Map<String, dynamic> videoConfigJson = _readObjectMap(
      json,
      'videoEncodingConfigs',
    );
    final Map<String, dynamic> toneMappingJson = _readObjectMap(
      json,
      'toneMappingConfig',
    );
    final Map<String, dynamic> audioDefaultJson = _readObjectMap(
      json,
      'audioDefaultProfile',
    );
    return EncodingSettingsSnapshot(
      compressionMode: _enumByName(
        CompressionMode.values,
        json['compressionMode'],
        CompressionMode.generic,
      ),
      hardwareMode: _enumByName(
        HardwareMode.values,
        json['hardwareMode'],
        HardwareMode.auto,
      ),
      outputFileNameOverride: (json['outputFileNameOverride'] ?? '').toString(),
      releaseGroup: (json['releaseGroup'] ?? '').toString(),
      titleOverride: (json['titleOverride'] ?? '').toString(),
      seasonNumber: (json['seasonNumber'] ?? '').toString(),
      episodeNumber: (json['episodeNumber'] ?? '').toString(),
      sourceLabel: (json['sourceLabel'] ?? '').toString(),
      episodicNamingTemplate: (json['episodicNamingTemplate'] ?? '').toString(),
      outputResolution: (json['outputResolution'] ?? '').toString(),
      outputFps: (json['outputFps'] ?? '').toString(),
      outputDirectory: (json['outputDirectory'] ?? '').toString(),
      avcBitrate: (json['avcBitrate'] ?? '').toString(),
      avcMaxrate: (json['avcMaxrate'] ?? '').toString(),
      hevcBitrate: (json['hevcBitrate'] ?? '').toString(),
      hevcMaxrate: (json['hevcMaxrate'] ?? '').toString(),
      encoderTunings: tuningJson.map(
        (String key, dynamic value) => MapEntry(
          key,
          EncoderTuningSelection.fromJson(
            value is Map<String, dynamic>
                ? value
                : (value as Map).map(
                    (dynamic innerKey, dynamic innerValue) =>
                        MapEntry(innerKey.toString(), innerValue),
                  ),
          ),
        ),
      ),
      audioStreamConfigs: audioConfigJson.map(
        (String key, dynamic value) => MapEntry(
          key,
          AudioStreamConfig.fromJson(
            value is Map<String, dynamic>
                ? value
                : (value as Map).map(
                    (dynamic innerKey, dynamic innerValue) =>
                        MapEntry(innerKey.toString(), innerValue),
                  ),
          ),
        ),
      ),
      audioDefaultProfile: audioDefaultJson.isEmpty
          ? const AudioStreamConfig.defaultAac()
          : AudioStreamConfig.fromJson(audioDefaultJson),
      videoEncodingConfigs: videoConfigJson.map(
        (String key, dynamic value) => MapEntry(
          key,
          VideoEncodingConfig.fromJson(
            value is Map<String, dynamic>
                ? value
                : (value as Map).map(
                    (dynamic innerKey, dynamic innerValue) =>
                        MapEntry(innerKey.toString(), innerValue),
                  ),
            encoderKey: key,
          ),
        ),
      ),
      toneMappingConfig: toneMappingJson.isEmpty
          ? const ToneMappingConfig.defaultBt709()
          : ToneMappingConfig.fromJson(toneMappingJson),
      continueOnMissingFont: _readBool(json, 'continueOnMissingFont', false),
      fontSubsettingEnabled: _readBool(json, 'fontSubsettingEnabled', true),
      sourceHanEllipsisFix: _readBool(json, 'sourceHanEllipsisFix', true),
      importStatusMessage: version == 1
          ? '已导入旧版本预设，音频高级参数、视频码控与色调映射沿用默认'
          : null,
    );
  }
}

class RuntimeToolInfo {
  const RuntimeToolInfo({
    required this.name,
    required this.path,
    required this.required,
  });

  final String name;
  final String? path;
  final bool required;

  bool get available => path != null && path!.isNotEmpty;
}

class RuntimeDiagnostics {
  const RuntimeDiagnostics({
    required this.ffmpeg,
    required this.ffprobe,
    required this.mkvpropedit,
    required this.sevenZip,
    required this.hwaccels,
    required this.videoEncoders,
    this.pyftsubset = const RuntimeToolInfo(
      name: 'pyftsubset',
      path: null,
      required: false,
    ),
    this.ttx = const RuntimeToolInfo(name: 'ttx', path: null, required: false),
    this.fontToolsVersion,
    this.hasZscale = false,
    this.audioEncoders = const <String>{},
  });

  final RuntimeToolInfo ffmpeg;
  final RuntimeToolInfo ffprobe;
  final RuntimeToolInfo mkvpropedit;
  final RuntimeToolInfo sevenZip;
  final RuntimeToolInfo pyftsubset;
  final RuntimeToolInfo ttx;
  final Version? fontToolsVersion;
  final List<String> hwaccels;
  final Set<String> videoEncoders;
  final bool hasZscale;
  final Set<String> audioEncoders;

  List<String> get hardwareVideoEncoderLabels => <String>[
    if (videoEncoders.contains('h264_nvenc')) 'NVENC AVC',
    if (videoEncoders.contains('hevc_nvenc')) 'NVENC HEVC',
    if (videoEncoders.contains('h264_qsv')) 'QSV AVC',
    if (videoEncoders.contains('hevc_qsv')) 'QSV HEVC',
    if (videoEncoders.contains('h264_amf')) 'AMF AVC',
    if (videoEncoders.contains('hevc_amf')) 'AMF HEVC',
  ];

  List<String> get hardwareDecodeLabels => hwaccels
      .map((String item) => item.trim().toLowerCase())
      .where(
        (String item) =>
            item.isNotEmpty && item != 'hardware acceleration methods:',
      )
      .map(
        (String item) => switch (item) {
          'cuda' => 'CUDA',
          'd3d11va' => 'D3D11VA',
          'dxva2' => 'DXVA2',
          'qsv' => 'QSV',
          'amf' => 'AMF',
          'd3d12va' => 'D3D12VA',
          'vaapi' => 'VAAPI',
          'opencl' => 'OpenCL',
          'vulkan' => 'Vulkan',
          _ => item.toUpperCase(),
        },
      )
      .toList();

  bool get hasNvenc =>
      videoEncoders.contains('h264_nvenc') ||
      videoEncoders.contains('hevc_nvenc');

  bool get hasQsv =>
      videoEncoders.contains('h264_qsv') || videoEncoders.contains('hevc_qsv');

  bool get hasAmf =>
      videoEncoders.contains('h264_amf') || videoEncoders.contains('hevc_amf');

  static const empty = RuntimeDiagnostics(
    ffmpeg: RuntimeToolInfo(name: 'ffmpeg', path: null, required: true),
    ffprobe: RuntimeToolInfo(name: 'ffprobe', path: null, required: true),
    mkvpropedit: RuntimeToolInfo(
      name: 'mkvpropedit',
      path: null,
      required: false,
    ),
    sevenZip: RuntimeToolInfo(name: '7z', path: null, required: false),
    pyftsubset: RuntimeToolInfo(
      name: 'pyftsubset',
      path: null,
      required: false,
    ),
    ttx: RuntimeToolInfo(name: 'ttx', path: null, required: false),
    fontToolsVersion: null,
    hwaccels: <String>[],
    videoEncoders: <String>{},
    hasZscale: false,
    audioEncoders: <String>{},
  );
}

class SubtitleBinding {
  const SubtitleBinding({
    required this.key,
    required this.label,
    required this.languageCode,
    required this.regionCode,
    required this.trackName,
    this.filePath,
  });

  final String key;
  final String label;
  final String languageCode;
  final String regionCode;
  final String trackName;
  final String? filePath;

  SubtitleBinding copyWith({
    String? languageCode,
    String? regionCode,
    String? trackName,
    String? filePath,
    bool clearFile = false,
  }) {
    return SubtitleBinding(
      key: key,
      label: label,
      languageCode: languageCode ?? this.languageCode,
      regionCode: regionCode ?? this.regionCode,
      trackName: trackName ?? this.trackName,
      filePath: clearFile ? null : filePath ?? this.filePath,
    );
  }
}

class ChapterEntry {
  const ChapterEntry({
    required this.title,
    required this.start,
    required this.end,
  });

  final String title;
  final Duration start;
  final Duration end;

  ChapterEntry copyWith({String? title, Duration? start, Duration? end}) {
    return ChapterEntry(
      title: title ?? this.title,
      start: start ?? this.start,
      end: end ?? this.end,
    );
  }
}

class MediaStreamEntry {
  const MediaStreamEntry({
    required this.index,
    required this.kind,
    required this.codec,
    required this.title,
    required this.language,
    required this.regionCode,
    required this.enabled,
    required this.isDefault,
    required this.isForced,
    required this.origin,
    required this.sourceLabel,
    this.attachmentFileName,
    this.attachmentMimeType,
    this.externalPath,
    this.videoInfo,
    this.channels = 0,
    this.channelLayout = '',
  });

  final int index;
  final StreamKind kind;
  final String codec;
  final String title;
  final String language;
  final String regionCode;
  final bool enabled;
  final bool isDefault;
  final bool isForced;
  final StreamOrigin origin;
  final String sourceLabel;
  final String? attachmentFileName;
  final String? attachmentMimeType;
  final String? externalPath;
  final VideoStreamInfo? videoInfo;
  final int channels;
  final String channelLayout;

  MediaStreamEntry copyWith({
    String? codec,
    String? title,
    String? language,
    String? regionCode,
    bool? enabled,
    bool? isDefault,
    bool? isForced,
    String? sourceLabel,
    String? attachmentFileName,
    String? attachmentMimeType,
    String? externalPath,
    VideoStreamInfo? videoInfo,
    int? channels,
    String? channelLayout,
  }) {
    return MediaStreamEntry(
      index: index,
      kind: kind,
      codec: codec ?? this.codec,
      title: title ?? this.title,
      language: language ?? this.language,
      regionCode: regionCode ?? this.regionCode,
      enabled: enabled ?? this.enabled,
      isDefault: isDefault ?? this.isDefault,
      isForced: isForced ?? this.isForced,
      origin: origin,
      sourceLabel: sourceLabel ?? this.sourceLabel,
      attachmentFileName: attachmentFileName ?? this.attachmentFileName,
      attachmentMimeType: attachmentMimeType ?? this.attachmentMimeType,
      externalPath: externalPath ?? this.externalPath,
      videoInfo: videoInfo ?? this.videoInfo,
      channels: channels ?? this.channels,
      channelLayout: channelLayout ?? this.channelLayout,
    );
  }
}

class MediaInfo {
  const MediaInfo({
    required this.inputPath,
    required this.displayName,
    required this.duration,
    required this.width,
    required this.height,
    required this.fps,
    required this.streams,
    required this.chapters,
    this.primaryVideo,
  });

  final String inputPath;
  final String displayName;
  final Duration duration;
  final int width;
  final int height;
  final double fps;
  final List<MediaStreamEntry> streams;
  final List<ChapterEntry> chapters;
  final VideoStreamInfo? primaryVideo;

  MediaInfo copyWith({
    List<MediaStreamEntry>? streams,
    List<ChapterEntry>? chapters,
    VideoStreamInfo? primaryVideo,
  }) {
    return MediaInfo(
      inputPath: inputPath,
      displayName: displayName,
      duration: duration,
      width: width,
      height: height,
      fps: fps,
      streams: streams ?? this.streams,
      chapters: chapters ?? this.chapters,
      primaryVideo: primaryVideo ?? this.primaryVideo,
    );
  }
}

class EncoderTuning {
  const EncoderTuning({
    required this.key,
    required this.title,
    required this.preset,
    required this.tune,
    required this.presets,
    required this.tunes,
  });

  final String key;
  final String title;
  final String preset;
  final String tune;
  final List<String> presets;
  final List<String> tunes;

  EncoderTuning copyWith({String? preset, String? tune}) {
    return EncoderTuning(
      key: key,
      title: title,
      preset: preset ?? this.preset,
      tune: tune ?? this.tune,
      presets: presets,
      tunes: tunes,
    );
  }
}

class ExportTask {
  const ExportTask({
    required this.id,
    required this.profile,
    required this.bindingKeys,
    required this.label,
    required this.outputPath,
    required this.status,
    required this.progress,
    required this.currentStep,
    required this.commandPreview,
    required this.log,
    this.error,
  });

  final String id;
  final ExportProfile profile;
  final List<String> bindingKeys;
  final String label;
  final String outputPath;
  final TaskStatus status;
  final double progress;
  final String currentStep;
  final String commandPreview;
  final String log;
  final String? error;

  ExportTask copyWith({
    TaskStatus? status,
    double? progress,
    String? currentStep,
    String? commandPreview,
    String? log,
    String? error,
    bool clearError = false,
  }) {
    return ExportTask(
      id: id,
      profile: profile,
      bindingKeys: bindingKeys,
      label: label,
      outputPath: outputPath,
      status: status ?? this.status,
      progress: progress ?? this.progress,
      currentStep: currentStep ?? this.currentStep,
      commandPreview: commandPreview ?? this.commandPreview,
      log: log ?? this.log,
      error: clearError ? null : error ?? this.error,
    );
  }
}

class ResolvedFontFile {
  const ResolvedFontFile({
    required this.path,
    required this.fileName,
    required this.mimeType,
    this.source = FontSourceKind.imported,
    this.importOrder = 0,
    this.trackIndex = 0,
    this.familyNames = const <String>{},
    this.fullNames = const <String>{},
    this.maxpNumGlyphs = 0,
    this.fsType = 0,
    this.bold = false,
    this.italic = false,
    this.weight = 400,
    this.licenseDescription = '',
  });

  final String path;
  final String fileName;
  final String mimeType;
  final FontSourceKind source;
  final int importOrder;
  final int trackIndex;
  final Set<String> familyNames;
  final Set<String> fullNames;
  final int maxpNumGlyphs;
  final int fsType;
  final bool bold;
  final bool italic;
  final int weight;
  final String licenseDescription;

  ResolvedFontFile copyWith({
    String? path,
    String? fileName,
    String? mimeType,
    FontSourceKind? source,
    int? importOrder,
    int? trackIndex,
    Set<String>? familyNames,
    Set<String>? fullNames,
    int? maxpNumGlyphs,
    int? fsType,
    bool? bold,
    bool? italic,
    int? weight,
    String? licenseDescription,
  }) {
    return ResolvedFontFile(
      path: path ?? this.path,
      fileName: fileName ?? this.fileName,
      mimeType: mimeType ?? this.mimeType,
      source: source ?? this.source,
      importOrder: importOrder ?? this.importOrder,
      trackIndex: trackIndex ?? this.trackIndex,
      familyNames: familyNames ?? this.familyNames,
      fullNames: fullNames ?? this.fullNames,
      maxpNumGlyphs: maxpNumGlyphs ?? this.maxpNumGlyphs,
      fsType: fsType ?? this.fsType,
      bold: bold ?? this.bold,
      italic: italic ?? this.italic,
      weight: weight ?? this.weight,
      licenseDescription: licenseDescription ?? this.licenseDescription,
    );
  }
}

class CommandStep {
  const CommandStep({
    required this.executable,
    required this.arguments,
    required this.description,
    this.fontSubsetStep,
  });

  final String executable;
  final List<String> arguments;
  final String description;
  final FontSubsetStepPlan? fontSubsetStep;
}

class TaskPlan {
  const TaskPlan({
    required this.outputPath,
    required this.commandPreview,
    required this.steps,
    required this.workingDirectory,
    required this.expectedDuration,
    this.initialLogLines = const <String>[],
    this.sharedFontPipelineKey,
  });

  final String outputPath;
  final String commandPreview;
  final List<CommandStep> steps;
  final String workingDirectory;
  final Duration expectedDuration;
  final List<String> initialLogLines;
  final String? sharedFontPipelineKey;
}
