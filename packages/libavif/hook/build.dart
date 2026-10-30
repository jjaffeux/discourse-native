import 'dart:io';

import 'package:code_assets/code_assets.dart';
import 'package:hooks/hooks.dart';
import 'package:native_toolchain_rust/native_toolchain_rust.dart';

void main(List<String> args) async {
  await build(args, (input, output) async {
    if (!input.config.buildCodeAssets) return;

    _requireBuildTool(
      'meson',
      'libavif builds its vendored dav1d decoder from source with Meson.',
    );
    _requireBuildTool(
      'ninja',
      'libavif builds its vendored dav1d decoder from source with Ninja.',
    );
    final architecture = input.config.code.targetArchitecture;
    if (architecture == Architecture.ia32 || architecture == Architecture.x64) {
      _requireBuildTool(
        'nasm',
        'x86 and x64 dav1d builds require NASM for optimized assembly.',
      );
    }
    await RustBuilder(
      assetName: 'libavif_native',
      cratePath: 'native',
      extraCargoEnvironmentVariables: _cargoEnvironment(input),
    ).run(input: input, output: output);
  });
}

void _requireBuildTool(String executable, String reason) {
  late final ProcessResult result;
  try {
    result = Process.runSync(executable, const ['--version']);
  } on ProcessException {
    throw StateError(
      '$reason Install "$executable" and ensure it is available on PATH.',
    );
  }
  if (result.exitCode != 0) {
    throw StateError(
      '$reason Install "$executable" and ensure it is available on PATH.',
    );
  }
}

Map<String, String> _cargoEnvironment(BuildInput input) {
  final code = input.config.code;
  if (code.targetOS == OS.iOS) {
    return const {'IPHONEOS_DEPLOYMENT_TARGET': '13.0'};
  }
  if (code.targetOS != OS.android) return const {};

  final compiler = code.cCompiler?.compiler;
  if (compiler == null || !compiler.isScheme('file')) {
    throw StateError(
      'Android libavif builds require a file-based NDK C compiler.',
    );
  }
  final ndk = _androidNdkRoot(compiler);
  final toolchain = File.fromUri(
    ndk.uri.resolve('build/cmake/android.toolchain.cmake'),
  );
  if (!toolchain.existsSync()) {
    throw StateError(
      'Android NDK CMake toolchain not found at ${toolchain.path}.',
    );
  }
  return {
    'ANDROID_NDK_ROOT': ndk.path,
    'ANDROID_NDK_HOME': ndk.path,
    'CMAKE_TOOLCHAIN_FILE': toolchain.path,
    'LAVIF_ANDROID_ABI': _androidAbi(code.targetArchitecture),
    'LAVIF_ANDROID_NDK_API': code.android.targetNdkApi.toString(),
  };
}

String _androidAbi(Architecture architecture) {
  if (architecture == Architecture.arm) return 'armeabi-v7a';
  if (architecture == Architecture.arm64) return 'arm64-v8a';
  if (architecture == Architecture.ia32) return 'x86';
  if (architecture == Architecture.x64) return 'x86_64';
  throw UnsupportedError(
    'Android architecture ${architecture.name} is not supported by libavif.',
  );
}

Directory _androidNdkRoot(Uri compiler) {
  var directory = File.fromUri(compiler).parent;
  while (directory.parent.path != directory.path) {
    if (_basename(directory) == 'toolchains') return directory.parent;
    directory = directory.parent;
  }
  throw StateError(
    'Could not derive the Android NDK root from ${compiler.toFilePath()}.',
  );
}

String _basename(Directory directory) =>
    directory.uri.pathSegments.where((segment) => segment.isNotEmpty).last;
