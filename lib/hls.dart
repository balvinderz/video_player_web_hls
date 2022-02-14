@JS()
library hls.js;

import 'dart:html';

import 'package:js/js.dart';

@JS('Hls.isSupported')
external bool isSupported();

@JS()
class Hls {
  external factory Hls(HlsConfig config);

  @JS()
  external void stopLoad();

  @JS()
  external void loadSource(String videoSrc);

  @JS()
  external void attachMedia(VideoElement video);

  @JS()
  external void on(String event, Function callback);

  external HlsConfig config;
}

@JS()
@anonymous
class HlsConfig {
  @JS()
  external Function get xhrSetup;

  external factory HlsConfig({Function xhrSetup});
}

class ErrorData {
  late final String type;
  late final String details;
  late final bool fatal;
  ErrorData(dynamic errorData) {
    type = errorData.type as String;
    details = errorData.details as String;
    fatal = errorData.fatal as bool;
  }
}
