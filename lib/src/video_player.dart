// Copyright 2013 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';
import 'dart:js_interop';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';
import 'package:http/http.dart' as http;
import 'package:video_player_web_hls/hls.dart';
import 'package:video_player_web_hls/no_script_tag_exception.dart';
import 'package:video_player_web_hls/src/pkg_web_tweaks.dart';
import 'package:web/web.dart' as web;

import 'duration_utils.dart';

// An error code value to error name Map.
// See: https://developer.mozilla.org/en-US/docs/Web/API/MediaError/code
const Map<int, String> _kErrorValueToErrorName = <int, String>{
  1: 'MEDIA_ERR_ABORTED',
  2: 'MEDIA_ERR_NETWORK',
  3: 'MEDIA_ERR_DECODE',
  4: 'MEDIA_ERR_SRC_NOT_SUPPORTED',
};

// An error code value to description Map.
// See: https://developer.mozilla.org/en-US/docs/Web/API/MediaError/code
const Map<int, String> _kErrorValueToErrorDescription = <int, String>{
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

/// Wraps a [html.VideoElement] so its API complies with what is expected by the plugin.
class VideoPlayer {
  /// Create a [VideoPlayer] from a [html.VideoElement] instance.
  VideoPlayer({
    required web.HTMLVideoElement videoElement,
    required this.uri,
    required this.headers,
    @visibleForTesting StreamController<VideoEvent>? eventController,
  })  : _videoElement = videoElement,
        _eventController = eventController ?? StreamController<VideoEvent>();

  final StreamController<VideoEvent> _eventController;
  final web.HTMLVideoElement _videoElement;
  web.EventHandler? _onContextMenu;

  final String uri;
  final Map<String, String> headers;

  bool _isInitialized = false;
  bool _isBuffering = false;
  Hls? _hls;

  /// Returns the [Stream] of [VideoEvent]s from the inner [html.VideoElement].
  Stream<VideoEvent> get events => _eventController.stream;

  /// Initializes the wrapped [html.VideoElement].
  ///
  /// This method sets the required DOM attributes so videos can [play] programmatically,
  /// and attaches listeners to the internal events from the [html.VideoElement]
  /// to react to them / expose them through the [VideoPlayer.events] stream.
  Future<void> initialize() async {
    _videoElement
      ..autoplay = false
      ..controls = false
      ..playsInline = true;

    if (await shouldUseHlsLibrary()) {
      try {
        _hls = Hls(
          HlsConfig(
            xhrSetup:
              (web.XMLHttpRequest xhr, String _) {
                if (headers.isEmpty) {
                  return;
                }

                if (headers.containsKey('useCookies')) {
                  xhr.withCredentials = true;
                }
                headers.forEach((String key, String value) {
                  if (key != 'useCookies') {
                    xhr.setRequestHeader(key, value);
                  }
                });
              }.toJS,
          ),
        );
        _hls!.attachMedia(_videoElement);
        _hls!.on('hlsMediaAttached', ((String _, JSObject __) {
          _hls!.loadSource(uri.toString());
        }.toJS));
        _hls!.on('hlsError', (String _, JSObject data) {
          try {
            final ErrorData _data = ErrorData(data);
            if (_data.fatal) {
              _eventController.addError(PlatformException(
                code: _kErrorValueToErrorName[2]!,
                message: _data.type,
                details: _data.details,
              ));
            }
          } catch (e) {
            debugPrint('Error parsing hlsError: $e');
          }
        }.toJS);
        _videoElement.onCanPlay.listen((dynamic _) {
          _onVideoElementInitialization(_);
          setBuffering(false);
        });
      } catch (e) {
        throw NoScriptTagException();
      }
    } else {
      _videoElement.src = uri.toString();
      final onDurationChange = (web.Event event) {
        if (_videoElement.duration == 0) {
          return;
        }
        _onVideoElementInitialization(event);
      }.toJS;
      _videoElement.addEventListener('durationchange', onDurationChange);
    }

    _videoElement.onCanPlayThrough.listen((dynamic _) {
      setBuffering(false);
    });

    _videoElement.onPlaying.listen((dynamic _) {
      setBuffering(false);
    });

    _videoElement.onWaiting.listen((dynamic _) {
      setBuffering(true);
      _sendBufferingRangesUpdate();
    });

    // The error event fires when some form of error occurs while attempting to load or perform the media.
    _videoElement.onError.listen((web.Event _) {
      setBuffering(false);
      // The Event itself (_) doesn't contain info about the actual error.
      // We need to look at the HTMLMediaElement.error.
      // See: https://developer.mozilla.org/en-US/docs/Web/API/HTMLMediaElement/error
      final web.MediaError error = _videoElement.error!;
      _eventController.addError(PlatformException(
        code: _kErrorValueToErrorName[error.code]!,
        message: error.message != '' ? error.message : _kDefaultErrorMessage,
        details: _kErrorValueToErrorDescription[error.code],
      ));
    });

    _videoElement.onEnded.listen((dynamic _) {
      setBuffering(false);
      _eventController.add(VideoEvent(eventType: VideoEventType.completed));
    });
  }

  /// Attempts to play the video.
  ///
  /// If this method is called programmatically (without user interaction), it
  /// might fail unless the video is completely muted (or it has no Audio tracks).
  ///
  /// When called from some user interaction (a tap on a button), the above
  /// limitation should disappear.
  Future<void> play() {
    return _videoElement.play().toDart.catchError((Object e) {
      // play() attempts to begin playback of the media. It returns
      // a Promise which can get rejected in case of failure to begin
      // playback for any reason, such as permission issues.
      // The rejection handler is called with a DOMException.
      // See: https://developer.mozilla.org/en-US/docs/Web/API/HTMLMediaElement/play
      final web.DOMException exception = e as web.DOMException;
      _eventController.addError(PlatformException(
        code: exception.name,
        message: exception.message,
      ));
      return null;
    }, test: (Object e) => e is web.DOMException);
  }

  /// Pauses the video in the current position.
  void pause() {
    _videoElement.pause();
  }

  /// Controls whether the video should start again after it finishes.
  // ignore: use_setters_to_change_properties
  void setLooping(bool value) {
    _videoElement.loop = value;
  }

  /// Sets the volume at which the media will be played.
  ///
  /// Values must fall between 0 and 1, where 0 is muted and 1 is the loudest.
  ///
  /// When volume is set to 0, the `muted` property is also applied to the
  /// [html.VideoElement]. This is required for auto-play on the web.
  void setVolume(double volume) {
    assert(volume >= 0 && volume <= 1);

    // TODO(ditman): Do we need to expose a "muted" API?
    // https://github.com/flutter/flutter/issues/60721
    _videoElement.muted = !(volume > 0.0);
    _videoElement.volume = volume;
  }

  /// Sets the playback `speed`.
  ///
  /// A `speed` of 1.0 is "normal speed," values lower than 1.0 make the media
  /// play slower than normal, higher values make it play faster.
  ///
  /// `speed` cannot be negative.
  ///
  /// The audio is muted when the fast forward or slow motion is outside a useful
  /// range (for example, Gecko mutes the sound outside the range 0.25 to 4.0).
  ///
  /// The pitch of the audio is corrected by default.
  void setPlaybackSpeed(double speed) {
    assert(speed > 0);

    _videoElement.playbackRate = speed;
  }

  /// Moves the playback head to a new `position`.
  ///
  /// `position` cannot be negative.
  void seekTo(Duration position) {
    assert(!position.isNegative);

    // Don't seek if video is already at target position.
    //
    // This is needed because the core plugin will pause and seek to the end of
    // the video when it finishes, and that causes an infinite loop of `ended`
    // events on the web.
    //
    // See: https://github.com/flutter/flutter/issues/77674
    if (position == _videoElementCurrentTime) {
      return;
    }

    _videoElement.currentTime = position.inMilliseconds.toDouble() / 1000;
  }

  /// Returns the current playback head position as a [Duration].
  Duration getPosition() {
    _sendBufferingRangesUpdate();
    return _videoElementCurrentTime;
  }

  /// Returns the currentTime of the underlying video element.
  Duration get _videoElementCurrentTime {
    return Duration(milliseconds: (_videoElement.currentTime * 1000).round());
  }

  /// Disposes of the current [html.VideoElement].
  void dispose() {
    _videoElement.removeAttribute('src');
    if (_onContextMenu != null) {
      _videoElement.removeEventListener('contextmenu', _onContextMenu);
      _onContextMenu = null;
    }
    _videoElement.load();
    _hls?.stopLoad();
  }

  // Sends an [VideoEventType.initialized] [VideoEvent] with info about the wrapped video.
  void _sendInitialized() {
    final Duration? duration =
        convertNumVideoDurationToPluginDuration(_videoElement.duration);

    final Size? size = _videoElement.videoHeight.isFinite
        ? Size(
            _videoElement.videoWidth.toDouble(),
            _videoElement.videoHeight.toDouble(),
          )
        : null;

    _eventController.add(
      VideoEvent(
        eventType: VideoEventType.initialized,
        duration: duration,
        size: size,
      ),
    );
  }

  /// Caches the current "buffering" state of the video.
  ///
  /// If the current buffering state is different from the previous one
  /// ([_isBuffering]), this dispatches a [VideoEvent].
  @visibleForTesting
  void setBuffering(bool buffering) {
    if (_isBuffering != buffering) {
      _isBuffering = buffering;
      _eventController.add(VideoEvent(
        eventType: _isBuffering
            ? VideoEventType.bufferingStart
            : VideoEventType.bufferingEnd,
      ));
    }
  }

  // Broadcasts the [html.VideoElement.buffered] status through the [events] stream.
  void _sendBufferingRangesUpdate() {
    _eventController.add(VideoEvent(
      buffered: _toDurationRange(_videoElement.buffered),
      eventType: VideoEventType.bufferingUpdate,
    ));
  }

  // Converts from [html.TimeRanges] to our own List<DurationRange>.
  List<DurationRange> _toDurationRange(web.TimeRanges buffered) {
    final List<DurationRange> durationRange = <DurationRange>[];
    for (int i = 0; i < buffered.length; i++) {
      durationRange.add(DurationRange(
        Duration(milliseconds: (buffered.start(i) * 1000).round()),
        Duration(milliseconds: (buffered.end(i) * 1000).round()),
      ));
    }
    return durationRange;
  }

  bool canPlayHlsNatively() {
    bool canPlayHls = false;
    try {
      final String canPlayType = _videoElement.canPlayType('application/vnd.apple.mpegurl');
      canPlayHls =
          canPlayType != '';
    } catch (e) {}
    return canPlayHls;
  }

  Future<bool> shouldUseHlsLibrary() async {
    return isSupported() &&
        (uri.toString().contains('m3u8') || await _testIfM3u8()) &&
        !canPlayHlsNatively();
  }

  Future<bool> _testIfM3u8() async {
    try {
      final Map<String, String> headers = Map<String, String>.of(this.headers);
      if (headers.containsKey('Range') || headers.containsKey('range')) {
        final List<int> range = (headers['Range'] ?? headers['range'])!
            .split('bytes')[1]
            .split('-')
            .map((String e) => int.parse(e))
            .toList();
        range[1] = min(range[0] + 1023, range[1]);
        headers['Range'] = 'bytes=${range[0]}-${range[1]}';
      } else {
        headers['Range'] = 'bytes=0-1023';
      }
      final http.Response response =
          await http.get(Uri.parse(this.uri), headers: headers);
      final String body = response.body;
      if (!body.contains('#EXTM3U')) {
        return false;
      }
      return true;
    } catch (e) {
      return false;
    }
  }

  /// Sets options
  Future<void> setOptions(VideoPlayerWebOptions options) async {
    // In case this method is called multiple times, reset options.
    _resetOptions();

    if (options.controls.enabled) {
      _videoElement.controls = true;
      final String controlsList = options.controls.controlsList;
      if (controlsList.isNotEmpty) {
        _videoElement.controlsList = controlsList.toJS;
      }

      if (!options.controls.allowPictureInPicture) {
        _videoElement.disablePictureInPicture = true.toJS;
      }
    }

    if (!options.allowContextMenu) {
      _onContextMenu = ((web.Event event) => event.preventDefault()).toJS;
      _videoElement.addEventListener('contextmenu', _onContextMenu);
    }

    if (!options.allowRemotePlayback) {
      _videoElement.disableRemotePlayback = true.toJS;
    }
  }

  // Handler to mark (and broadcast) when this player [_isInitialized].
  //
  // (Used as a JS event handler for "canplay" and "loadedmetadata")
  //
  // This function can be called multiple times by different JS Events, but it'll
  // only broadcast an "initialized" event the first time it's called, and ignore
  // the rest of the calls.
  void _onVideoElementInitialization(Object? _) {
    if (!_isInitialized) {
      _isInitialized = true;
      _sendInitialized();
    }
  }

  void _resetOptions() {
    _videoElement.controls = false;
    _videoElement.removeAttribute('controlsList');
    _videoElement.removeAttribute('disablePictureInPicture');
    if (_onContextMenu != null) {
      _videoElement.removeEventListener('contextmenu', _onContextMenu);
      _onContextMenu = null;
    }
    _videoElement.removeAttribute('disableRemotePlayback');
  }
}
