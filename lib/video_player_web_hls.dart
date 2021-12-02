import 'dart:async';
import 'dart:html';
import 'dart:js';
import 'dart:math';
import 'src/shims/dart_ui.dart' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_web_plugins/flutter_web_plugins.dart';
import 'package:js/js.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';
import 'package:http/http.dart' as http;

import 'hls.dart';
import 'no_script_tag_exception.dart';

// An error code value to error name Map.
// See: https://developer.mozilla.org/en-US/docs/Web/API/MediaError/code
const Map<int, String> _kErrorValueToErrorName = {
  1: 'MEDIA_ERR_ABORTED',
  2: 'MEDIA_ERR_NETWORK',
  3: 'MEDIA_ERR_DECODE',
  4: 'MEDIA_ERR_SRC_NOT_SUPPORTED',
};

// An error code value to description Map.
// See: https://developer.mozilla.org/en-US/docs/Web/API/MediaError/code
const Map<int, String> _kErrorValueToErrorDescription = {
  1: 'The user canceled the fetching of the video.',
  2: 'A network error occurred while fetching the video, despite having previously been available.',
  3: 'An error occurred while trying to decode the video, despite having previously been determined to be usable.',
  4: 'The video has been found to be unsuitable (missing or in a format not supported by your browser).',
  5: 'Could not load manifest'
};

// The default error message, when the error is an empty string
// See: https://developer.mozilla.org/en-US/docs/Web/API/MediaError/message
const String _kDefaultErrorMessage =
    'No further diagnostic information can be determined or provided.';

/// The web implementation of [VideoPlayerPlatform].
///
/// This class implements the `package:video_player` functionality for the web.
class VideoPlayerPluginHls extends VideoPlayerPlatform {
  /// Registers this class as the default instance of [VideoPlayerPlatform].
  static void registerWith(Registrar registrar) {
    VideoPlayerPlatform.instance = VideoPlayerPluginHls();
  }

  Map<int, _VideoPlayer> _videoPlayers = <int, _VideoPlayer>{};

  int _textureCounter = 1;

  /// Headers to send before fetching a url
  /// Add useCookies key to headers if you want to use cookies
  ///
  Map<String, String> headers = {};

  @override
  Future<void> init() async {
    return _disposeAllPlayers();
  }

  @override
  Future<void> dispose(int textureId) async {
    _videoPlayers[textureId]!.dispose();
    _videoPlayers.remove(textureId);
    return null;
  }

  void _disposeAllPlayers() {
    _videoPlayers.values
        .forEach((_VideoPlayer videoPlayer) => videoPlayer.dispose());
    _videoPlayers.clear();
  }

  @override
  Future<int> create(DataSource dataSource) async {
    final int textureId = _textureCounter;
    _textureCounter++;

    late String uri;
    switch (dataSource.sourceType) {
      case DataSourceType.network:
        // Do NOT modify the incoming uri, it can be a Blob, and Safari doesn't
        // like blobs that have changed.
        uri = dataSource.uri ?? "";
        headers = dataSource.httpHeaders;

        break;
      case DataSourceType.asset:
        String assetUrl = dataSource.asset!;
        if (dataSource.package != null && dataSource.package!.isNotEmpty) {
          assetUrl = 'packages/${dataSource.package}/$assetUrl';
        }
        // 'webOnlyAssetManager' is only in the web version of dart:ui
        // ignore: undefined_prefixed_name
        assetUrl = ui.webOnlyAssetManager.getAssetUrl(assetUrl);
        uri = assetUrl;
        break;
      case DataSourceType.file:
        return Future.error(UnimplementedError(
            'web implementation of video_player cannot play local files'));
    }

    final _VideoPlayer player =
        _VideoPlayer(uri: uri, textureId: textureId, headers: headers);

    await player.initialize();

    _videoPlayers[textureId] = player;
    return textureId;
  }

  @override
  Future<void> setLooping(int textureId, bool looping) async {
    return _videoPlayers[textureId]!.setLooping(looping);
  }

  @override
  Future<void> play(int textureId) async {
    return _videoPlayers[textureId]!.play();
  }

  @override
  Future<void> pause(int textureId) async {
    return _videoPlayers[textureId]!.pause();
  }

  @override
  Future<void> setVolume(int textureId, double volume) async {
    return _videoPlayers[textureId]!.setVolume(volume);
  }

  @override
  Future<void> setPlaybackSpeed(int textureId, double speed) async {
    assert(speed > 0);

    return _videoPlayers[textureId]!.setPlaybackSpeed(speed);
  }

  @override
  Future<void> seekTo(int textureId, Duration position) async {
    return _videoPlayers[textureId]!.seekTo(position);
  }

  @override
  Future<Duration> getPosition(int textureId) async {
    _videoPlayers[textureId]!.sendBufferingUpdate();
    return _videoPlayers[textureId]!.getPosition();
  }

  @override
  Stream<VideoEvent> videoEventsFor(int textureId) {
    return _videoPlayers[textureId]!.eventController.stream;
  }

  @override
  Widget buildView(int textureId) {
    return HtmlElementView(viewType: 'videoPlayer-$textureId');
  }

  /// Sets the audio mode to mix with other sources (ignored)
  @override
  Future<void> setMixWithOthers(bool mixWithOthers) => Future<void>.value();
}

class _VideoPlayer {
  _VideoPlayer(
      {required this.uri, required this.textureId, required this.headers});

  final StreamController<VideoEvent> eventController =
      StreamController<VideoEvent>();

  final String uri;
  final int textureId;
  final Map<String, String> headers;

  late VideoElement videoElement;
  bool isInitialized = false;
  bool isBuffering = false;
  Hls? _hls;

  void setBuffering(bool buffering) {
    if (isBuffering != buffering) {
      isBuffering = buffering;
      eventController.add(VideoEvent(
          eventType: isBuffering
              ? VideoEventType.bufferingStart
              : VideoEventType.bufferingEnd));
    }
  }

  Future<bool> _testIfM3u8() async {
    try {
      final headers = Map.of(this.headers);
      if (headers.containsKey("Range") || headers.containsKey("range")) {
        final range = (headers["Range"] ?? headers["range"])!
            .split("bytes")[1]
            .split("-")
            .map((e) => int.parse(e))
            .toList();
        range[1] = min(range[0]+1023, range[1]);
        headers["Range"] = "bytes=${range[0]}-${range[1]}";
      } else {
        headers["Range"] = "bytes=0-1023";
      }
      final response = await http.get(Uri.parse(uri), headers: headers);
      final body = response.body;
      if (!body.contains("#EXTM3U")) return false;
      return true;
    } catch (e) {
      return false;
    }
  }

  Future<void> initialize() async {
    videoElement = VideoElement()
      ..src = uri
      ..autoplay = false
      ..controls = false
      ..style.border = 'none';

    // Allows Safari iOS to play the video inline
    videoElement.setAttribute('playsinline', 'true');

    // TODO(hterkelsen): Use initialization parameters once they are available
    // ignore: undefined_prefixed_name
    ui.platformViewRegistry.registerViewFactory(
        'videoPlayer-$textureId', (int viewId) => videoElement);
    if (isSupported() && (uri.toString().contains("m3u8") || await _testIfM3u8())) {
      try {
        _hls = new Hls(
          HlsConfig(
            xhrSetup: allowInterop(
              (HttpRequest xhr, url) {
                if (headers.length == 0) return;

                if (headers.containsKey("useCookies")) {
                  xhr.withCredentials = true;
                  headers.remove("useCookies");
                }
                headers.forEach((key, value) {
                  xhr.setRequestHeader(key, value);
                });
              },
            ),
          ),
        );
        _hls!.attachMedia(videoElement);
        // print(hls.config.runtimeType);
        _hls!.on('hlsMediaAttached', allowInterop((_, __) {
          _hls!.loadSource(uri.toString());
        }));
        _hls!.on('hlsError', allowInterop((_, dynamic data) {
          eventController.addError(PlatformException(
            code: _kErrorValueToErrorName[2]!,
            message: _kDefaultErrorMessage,
            details: _kErrorValueToErrorDescription[5],
          ));
        }));
        videoElement.onCanPlay.listen((dynamic _) {
          if (!isInitialized) {
            isInitialized = true;
            sendInitialized();
          }
          setBuffering(false);
        });
      } catch (e) {
        print(e);
        throw NoScriptTagException();
      }
    } else {
      videoElement.src = uri.toString();
      videoElement.addEventListener('loadedmetadata', (_) {
        if (!isInitialized) {
          isInitialized = true;
          sendInitialized();
        }
        setBuffering(false);
      });
    }
    videoElement.onCanPlayThrough.listen((dynamic _) {
      setBuffering(false);
    });

    videoElement.onPlaying.listen((dynamic _) {
      setBuffering(false);
    });

    videoElement.onWaiting.listen((dynamic _) {
      setBuffering(true);
      sendBufferingUpdate();
    });
    // The error event fires when some form of error occurs while attempting to load or perform the media.
    videoElement.onError.listen((Event _) {
      setBuffering(false);
      // The Event itself (_) doesn't contain info about the actual error.
      // We need to look at the HTMLMediaElement.error.
      // See: https://developer.mozilla.org/en-US/docs/Web/API/HTMLMediaElement/error
      MediaError error = videoElement.error!;
      eventController.addError(PlatformException(
        code: _kErrorValueToErrorName[error.code]!,
        message: error.message != '' ? error.message : _kDefaultErrorMessage,
        details: _kErrorValueToErrorDescription[error.code],
      ));
    });

    videoElement.onEnded.listen((dynamic _) {
      setBuffering(false);

      eventController.add(VideoEvent(eventType: VideoEventType.completed));
    });
  }

  void sendBufferingUpdate() {
    eventController.add(VideoEvent(
      buffered: _toDurationRange(videoElement.buffered),
      eventType: VideoEventType.bufferingUpdate,
    ));
  }

  Future<void> play() {
    return videoElement.play().catchError((e) {
      // play() attempts to begin playback of the media. It returns
      // a Promise which can get rejected in case of failure to begin
      // playback for any reason, such as permission issues.
      // The rejection handler is called with a DomException.
      // See: https://developer.mozilla.org/en-US/docs/Web/API/HTMLMediaElement/play
      DomException exception = e;
      eventController.addError(PlatformException(
        code: exception.name,
        message: exception.message,
      ));
    }, test: (e) => e is DomException);
  }

  void pause() {
    videoElement.pause();
  }

  void setLooping(bool value) {
    videoElement.loop = value;
  }

  void setVolume(double value) {
    if (value > 0.0) {
      videoElement.muted = false;
    } else {
      videoElement.muted = true;
    }
    videoElement.volume = value;
  }

  void setPlaybackSpeed(double speed) {
    assert(speed > 0);

    videoElement.playbackRate = speed;
  }

  void seekTo(Duration position) {
    videoElement.currentTime = position.inMilliseconds.toDouble() / 1000;
  }

  Duration getPosition() {
    return Duration(milliseconds: (videoElement.currentTime * 1000).round());
  }

  void sendInitialized() {
    eventController.add(
      VideoEvent(
        eventType: VideoEventType.initialized,
        duration: Duration(
          milliseconds: (videoElement.duration * 1000).round(),
        ),
        size: Size(
          videoElement.videoWidth.toDouble(),
          videoElement.videoHeight.toDouble(),
        ),
      ),
    );
  }

  void dispose() {
    videoElement.removeAttribute('src');
    videoElement.load();
    _hls?.stopLoad();
  }

  List<DurationRange> _toDurationRange(TimeRanges buffered) {
    final List<DurationRange> durationRange = <DurationRange>[];
    for (int i = 0; i < buffered.length; i++) {
      durationRange.add(DurationRange(
        Duration(milliseconds: (buffered.start(i) * 1000).round()),
        Duration(milliseconds: (buffered.end(i) * 1000).round()),
      ));
    }
    return durationRange;
  }
}
