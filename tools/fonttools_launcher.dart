import 'dart:io';

Future<int> main(List<String> args) async {
  final File self = File(Platform.resolvedExecutable);
  final Directory root = self.parent.parent;
  final String python = '${root.path}\\python\\python.exe';
  final String executableName = _basenameWithoutExtension(self.path);
  final String? module = switch (executableName.toLowerCase()) {
    'pyftsubset' => 'fontTools.subset',
    'ttx' => 'fontTools.ttx',
    _ => null,
  };

  if (module == null) {
    stderr.writeln('Unsupported FontTools launcher name: $executableName');
    return 64;
  }

  if (!File(python).existsSync()) {
    stderr.writeln('Bundled Python runtime not found: $python');
    return 127;
  }

  final Process process = await Process.start(
    python,
    <String>['-m', module, ...args],
    mode: ProcessStartMode.inheritStdio,
    environment: <String, String>{
      'PYTHONUTF8': '1',
      'PYTHONIOENCODING': 'utf-8',
    },
    includeParentEnvironment: true,
  );
  return process.exitCode;
}

String _basenameWithoutExtension(String path) {
  final int slash = path.lastIndexOf(RegExp(r'[\\/]'));
  final String name = slash < 0 ? path : path.substring(slash + 1);
  final int dot = name.lastIndexOf('.');
  return dot < 0 ? name : name.substring(0, dot);
}
