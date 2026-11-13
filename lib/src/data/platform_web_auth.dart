import 'package:flutter/services.dart';
import 'package:flutter_web_auth_2/flutter_web_auth_2.dart';

import 'user_api_key.dart';

Future<String> launchPlatformWebAuth(String url, String callbackScheme) async {
  try {
    return await FlutterWebAuth2.authenticate(
      url: url,
      callbackUrlScheme: callbackScheme,
    );
  } on PlatformException catch (error, stackTrace) {
    final detail = '${error.code}: ${error.message}';
    if (error.code == 'CANCELED') {
      throw UserApiAuthException(UserApiAuthFailure.cancelled, detail);
    }
    throw UserApiAuthException.caused(
      UserApiAuthFailure.launchFailed,
      detail,
      error,
      stackTrace,
    );
  }
}
