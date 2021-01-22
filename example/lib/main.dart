import 'package:flutter/material.dart';
import 'dart:async';

import 'dart:io' as io;
import 'package:path_provider/path_provider.dart';
import 'package:file/file.dart';
import 'package:file/local.dart';

import 'package:flutter/services.dart';
import 'package:audio_plugin/audio_plugin.dart';

import 'package:audioplayers/audioplayers.dart';

void main() {
  runApp(MyApp());
}

class MyApp extends StatefulWidget {
  final LocalFileSystem localFileSystem;

  MyApp({localFileSystem})
      : this.localFileSystem = localFileSystem ?? LocalFileSystem();


  @override
  _MyAppState createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  String _platformVersion = 'Unknown';
  AudioPlayer _audioPlayer = AudioPlayer();
  Recording _recording = new Recording();
  bool _isRecording = false;

  TextEditingController _controller = new TextEditingController();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(
          title: const Text('Plugin example app'),
        ),
        body: Column(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: <Widget>[
              new FlatButton(
                onPressed: _isRecording ? null : _start,
                child: new Text("Start"),
                color: Colors.green,
              ),
              new FlatButton(
                onPressed: _isRecording ? null : _stop,
                child: new Text("Stop"),
                color: Colors.red,
              ),
              new FlatButton(
                onPressed: _recording == null ? null : _play,
                child: new Text("Play"),
                color: Colors.amber,
              ),
              new TextField(
                controller: _controller,
                decoration: new InputDecoration(
                  hintText: 'Enter a custom path',
                ),
              ),
              new Text("File path of the record: ${_recording.path}"),
              new Text("Format: ${_recording.audioOutputFormat}"),
              new Text("Extension : ${_recording.extension}"),
              new Text(
                  "Audio recording duration : ${_recording.duration.toString()}")
            ]),
      ),
    );
  }
  int i = 0;
  String fileName = "";
  _start() async {
    ++i;
    if (await AudioPlugin.hasPermissions) {
      fileName = "myfile$i.m4a";
      print("pathToFile=$fileName");
      var isOK = await AudioPlugin.setFileName(fileName);
      if (isOK) {
        await AudioPlugin.startRecording();
        bool isRecording = await AudioPlugin.isRecording;
        setState(() {
          _recording = new Recording(path: fileName);
          _isRecording = isRecording;
        });
      }
    } else {
      Scaffold.of(context).showSnackBar(
          new SnackBar(content: new Text("You must accept permissions")));
    }
  }
  String path = "";
  _stop() async {
    var recording = await AudioPlugin.stopRecording();
    path = recording.path;
    print("Stop recording: $path");
    setState(() {
      _recording = recording;
      _isRecording = false;
    });
    _controller.text = recording.path;
  }

  _play() async {
    if (_audioPlayer.state == AudioPlayerState.PLAYING){
      _audioPlayer.pause();
    } else if (_audioPlayer.state == AudioPlayerState.PAUSED){
      _audioPlayer.resume();
    }else{
      if (fileName.isNotEmpty) {
        io.Directory appDocDirectory = await getApplicationDocumentsDirectory();
        String localPath = "${appDocDirectory.path}/$fileName";
        print("_play= $localPath");
        int result = await _audioPlayer.play(localPath, isLocal: true);
      }
    }
  }
}
