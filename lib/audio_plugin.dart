
import 'dart:async';

import 'package:flutter/services.dart';

export 'audio_plugin.dart';

class AudioPlugin {
  static const MethodChannel _channel = const MethodChannel('audio_plugin');
  //
  // static Future<String> get platformVersion async {
  //   final String version = await _channel.invokeMethod('getPlatformVersion');
  //   return version;
  // }

  static Future startRecording() async {
    return _channel.invokeMethod('startRecording');
  }

  static Future<Recording> stopRecording() async {
    Map<String, Object> response =
    Map.from(await _channel.invokeMethod('stopRecording'));
    print("stopRecording: duration=${response['duration']}, path=${response['path']}");
    Recording recording = new Recording(
        duration: new Duration(milliseconds: response['duration']),
        path: response['path']);
    return recording;
  }

  static Future<bool> setFileName(String fileName) async {
      return _channel.invokeMethod('setFileName', {"fileName": fileName});
  }

  static Future<bool> get hasPermissions async {
    bool hasPermission = await _channel.invokeMethod('hasPermissions');
    return hasPermission;
  }

  static Future<bool> get isRecording async {
    bool isRecording = await _channel.invokeMethod('isRecording');
    return isRecording;
  }
}

enum AudioOutputFormat { AAC, WAV }

class Recording {
  // File path
  String path;
  // File extension
  String extension;
  // Audio duration in milliseconds
  Duration duration;
  // Audio output format
  AudioOutputFormat audioOutputFormat;

  Recording({this.duration, this.path, this.audioOutputFormat, this.extension});
}
