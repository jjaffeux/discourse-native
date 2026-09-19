import 'package:code_assets/code_assets.dart';
import 'package:hooks/hooks.dart';
import 'package:native_toolchain_c/native_toolchain_c.dart';

void main(List<String> arguments) async {
  await build(arguments, (input, output) async {
    if (!input.config.buildCodeAssets) return;
    final os = input.config.code.targetOS;
    await CBuilder.library(
      name: 'discourse_cooking',
      assetName: 'src/native_runtime.dart',
      sources: [
        'native/cooking_runtime.c',
        'vendor/quickjs/quickjs.c',
        'vendor/quickjs/dtoa.c',
        'vendor/quickjs/libregexp.c',
        'vendor/quickjs/libunicode.c',
      ],
      includes: ['vendor/quickjs'],
      defines: {'_GNU_SOURCE': null, 'QUICKJS_NG_BUILD': null},
      std: 'c11',
      libraries: os == OS.windows ? [] : ['m'],
    ).run(input: input, output: output);
  });
}
