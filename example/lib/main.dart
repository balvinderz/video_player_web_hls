import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

void main() {
  runApp(VideoApp());
}

const hlsUrl =
    'https://demo.unified-streaming.com/k8s/features/stable/video/tears-of-steel/tears-of-steel.mp4/.m3u8';

class VideoApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Video Demo',
      home: Scaffold(
        body: Center(
          child: Builder(
              builder: (context) => Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ElevatedButton(
                          onPressed: () {
                            Navigator.push(
                                context,
                                MaterialPageRoute(
                                    builder: (context) =>
                                        DefaultAspectRatioVideo()));
                          },
                          child: Text('Default AspectRatio')),
                      const SizedBox(height: 16),
                      ElevatedButton(
                          onPressed: () {
                            Navigator.push(
                                context,
                                MaterialPageRoute(
                                    builder: (context) =>
                                        CustomAspectRatioVideo()));
                          },
                          child: Text('Custom AspectRatio'))
                    ],
                  )),
        ),
      ),
    );
  }
}

class DefaultAspectRatioVideo extends StatefulWidget {
  @override
  State createState() => _DefaultAspectRatioVideoState();
}

class _DefaultAspectRatioVideoState extends State<DefaultAspectRatioVideo> {
  late VideoPlayerController _controller;

  @override
  void initState() {
    super.initState();
    try {
      _controller = VideoPlayerController.networkUrl(Uri.parse(hlsUrl))
        ..initialize().then((_) {
          playPause();
        });
    } catch (e) {
      print(e);
    }
  }

  void playPause() => setState(() {
        _controller.value.isPlaying ? _controller.pause() : _controller.play();
      });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Default AspectRatio'),
      ),
      body: Center(
        child: _controller.value.isInitialized
            ? AspectRatio(
                aspectRatio: _controller.value.aspectRatio,
                child: VideoPlayer(_controller),
              )
            : SizedBox(),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: playPause,
        child: Icon(
          _controller.value.isPlaying ? Icons.pause : Icons.play_arrow,
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

class CustomAspectRatioVideo extends StatefulWidget {
  @override
  State createState() => _CustomAspectRatioVideoState();
}

class _CustomAspectRatioVideoState extends State<CustomAspectRatioVideo> {
  late VideoPlayerController _controller;
  double width = 0, height = 0, aspectRatio = 0;

  @override
  void initState() {
    super.initState();
    try {
      width = 800;
      height = 800;
      aspectRatio = height / width;
      _controller = VideoPlayerController.networkUrl(Uri.parse(hlsUrl))
        ..initialize().then((_) {
          // Ensure the first frame is shown after the video is initialized, even before the play button has been pressed.
          playPause();
        });
    } catch (e) {
      print(e);
    }
  }

  void playPause() => setState(() {
        _controller.value.isPlaying ? _controller.pause() : _controller.play();
      });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Custom AspectRatio'),
      ),
      body: Center(
        child: _controller.value.isInitialized
            ? AspectRatio(
                aspectRatio: aspectRatio,
                child: FittedBox(
                  fit: BoxFit.cover,
                  child: SizedBox(
                    width: _controller.value.size.width,
                    height: _controller.value.size.height,
                    child: VideoPlayer(
                      _controller,
                    ),
                  ),
                ),
              )
            : SizedBox(),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: playPause,
        child: Icon(
          _controller.value.isPlaying ? Icons.pause : Icons.play_arrow,
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
