import 'package:video_player/video_player.dart';
import 'package:flutter/material.dart';

void main() {
  runApp(VideoApp());
}

class VideoApp extends StatefulWidget {
  @override
  _VideoAppState createState() => _VideoAppState();
}

class _VideoAppState extends State<VideoApp> {
  VideoPlayerController _controller;

  @override
  void initState() {
    super.initState();
    try {
      // [Video] Working Bunny https://test-streams.mux.dev/x36xhzz/x36xhzz.m3u8
      // [Audio] Working Public BartusZak https://bartuszak-full-public.s3-eu-west-1.amazonaws.com/hls/01-moliere-molier-swietoszek-jak-poczela-sie-komedia-swietoszekTest.m3u8
      // [Audio] Private BartusZak https://zak-dev-app-access-bucket.s3-eu-west-1.amazonaws.com/hls/01-moliere-molier-swietoszek-jak-poczela-sie-komedia-swietoszekTest.m3u8
      final String path =
          "https://zak-dev-app-access-bucket.s3-eu-west-1.amazonaws.com/hls/01-moliere-molier-swietoszek-jak-poczela-sie-komedia-swietoszekTest.m3u8";

      _controller = VideoPlayerController.network(path, httpHeaders: {
        "accessKey": "123",
        "secretKey": "321",
        "region": "eu-west-1"
      })
        ..initialize().then((_) {
          // Ensure the first frame is shown after the video is initialized, even before the play button has been pressed.
          setState(() {});
        });
      _controller.setVolume(0.5);
    } catch (e) {
      print(e);
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Video Demo',
      home: Scaffold(
        body: Center(
          child: _controller.value.isInitialized
              ? AspectRatio(
                  aspectRatio: _controller.value.aspectRatio,
                  child: VideoPlayer(_controller),
                )
              : Container(),
        ),
        floatingActionButton: FloatingActionButton(
          onPressed: () {
            setState(() {
              _controller.value.isPlaying
                  ? _controller.pause()
                  : _controller.play();
            });
          },
          child: Icon(
            _controller.value.isPlaying ? Icons.pause : Icons.play_arrow,
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    super.dispose();
    _controller.dispose();
  }
}
