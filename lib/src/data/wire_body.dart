import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'json_decode.dart';

/// The bytes a parsed model was read from.
///
/// Models carry no encoder, and a second description of the wire format would
/// drift from the parsers. A snapshot therefore keeps what the site sent and
/// reads it back through the same parser. The body rides beside the model it
/// produced rather than inside it, so equality and every existing constructor
/// are untouched and a model built by hand simply has none.
final class WireBody {
  WireBody(this._bytes, {this._encodingName = 'utf-8'});

  WireBody.text(String text) : this(utf8.encode(text));

  WireBody.of(http.Response response)
    : this(
        response.bodyBytes,
        encodingName: jsonResponseEncodingName(response.headers),
      );

  final Uint8List _bytes;
  final String _encodingName;

  int get byteLength => _bytes.length;

  String get text => (Encoding.getByName(_encodingName) ?? utf8).decode(_bytes);

  static final Expando<WireBody> _bodies = Expando<WireBody>('wire body');

  static void attach(Object model, WireBody body) => _bodies[model] = body;

  static WireBody? from(Object model) => _bodies[model];
}
