
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

  static Future<Recording> startRecording() async {
    var result = await _channel.invokeMethod('startRecording');
    return getRecording(result);
  }

  static Future<Recording> stopRecording() async {
    var result = await _channel.invokeMethod('stopRecording');
    return getRecording(result);
  }

  static Future<bool> setFileName(String fileName) async {
    return await _channel.invokeMethod('setFileName', {"fileName": fileName});
  }

  static Future<bool> get hasPermissions async {
    bool hasPermission = await _channel.invokeMethod('hasPermissions');
    return hasPermission;
  }

  static Future<bool> get isRecording async {
    bool isRecording = await _channel.invokeMethod('isRecording');
    return isRecording;
  }

  /// Ask for current status of recording
  /// Returns the result of current recording status
  /// Metering level, Duration, Status...
  static Future<Recording> current({int channel = 0}) async {
    var result = await _channel.invokeMethod('current', {"channel": channel});
    return getRecording(result);
  }

  static Future<List<String>> audios({int channel = 0}) async {
    var result = await _channel.invokeMethod('audios', {"channel": channel});
    return _fileName(result);
  }

  static List<String> _fileName(result){
    if (result != null){
      var list = List.castFrom(result);
      print("audios: $list");
      if (list != null){
        var names = List<String>();
        for (int i = 0; i < list.length; i++){
          Map<String, Object> response = Map.from(list[i]);
          names.add(response['name']);
        }
        return names;
      }
    }
  }

  static Recording getRecording(result) {
    if (result != null) {
      Map<String, Object> response = Map.from(result);
      Recording recording = new Recording();
      recording.path = response["path"];
      recording.duration = Duration(seconds: response['duration']);
      recording.durationStr = convertDurationToTime(new Duration(seconds: response['duration']));
      recording.metering = new AudioMetering(
          peakPower: response['peakPower'],
          averagePower: response['averagePower'],
          isMeteringEnabled: response['isMeteringEnabled']);
      recording.isRecording = response["isRecording"];
      return recording;
    }else{
      return null;
    }
  }

  static String convertDurationToTime(Duration time){
    String seconds = "00";
    String minutes = "00";
    String hours = "00";
    if (time != null) {
      if (time.inHours < 10){
        hours = "$hours";
      }
      if (time.inMinutes < 10){
        minutes = "$minutes";
      }
      if (time.inSeconds < 10){
        seconds = "$seconds";
      }
    }
    return "$hours:$minutes:$seconds";
  }
}

enum AudioOutputFormat { AAC, WAV }

class Recording {
  // File path
  bool isRecording;

  // File path
  String path;

  // File extension
  String extension;

  // Audio duration in milliseconds
  Duration duration;

  // Audio duration in milliseconds
  String durationStr;
  /// Metering
  AudioMetering metering;

  // Audio output format
  AudioOutputFormat audioOutputFormat;

  Recording({this.duration, this.path, this.audioOutputFormat, this.extension});
}

/// Audio Metering Level - describe the metering level of microphone when recording
class AudioMetering {
  /// Represent peak level of given short duration
  double peakPower;

  /// Represent average level of given short duration
  double averagePower;

  /// Is metering enabled in system
  bool isMeteringEnabled;

  AudioMetering({this.peakPower, this.averagePower, this.isMeteringEnabled});
}