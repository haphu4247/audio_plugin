package com.phuhp.audio_plugin

import android.Manifest
import android.app.Activity
import android.content.Context
import android.content.pm.PackageManager
import android.media.AudioFormat
import android.media.AudioRecord
import android.media.MediaRecorder
import android.os.Build
import android.os.Build.VERSION
import android.os.Environment
import android.util.Log
import androidx.annotation.NonNull
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import io.flutter.plugin.common.PluginRegistry.Registrar
import io.flutter.plugin.common.PluginRegistry.RequestPermissionsResultListener
import java.io.*
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.util.*


/** AudioPlugin */

//Stop recording: /app_app_flutter/myfile1.m4a
//_play= /app_flutter/myfile1.m4a
class AudioPlugin: FlutterPlugin, MethodCallHandler, RequestPermissionsResultListener, ActivityAware {
  /// The MethodChannel that will the communication between Flutter and native Android
  ///
  /// This local reference serves to register the plugin with the Flutter Engine and unregister it
  /// when the Flutter Engine is detached from the Activity
  private lateinit var channel : MethodChannel

  private val LOG_NAME = "AndroidAudioRecorder"
  private val PERMISSIONS_REQUEST_RECORD_AUDIO = 200
  private val RECORDER_BPP: Byte = 16 // we use 16bit

//  private val registrar: Registrar? = null
  private var _result: Result? = null
  private var activity: Activity? = null
  private var flutterPluginBinding: FlutterPlugin.FlutterPluginBinding? = null
  private var mSampleRate = 16000 // 16Khz

  private var isRecording = false
  private var output: String = ""
  private var fileName: String = ""

  private var mPeakPower = -120.0
  private var mAveragePower = -120.0
  private var mDataSize: Long = 0

  private var mediaRecorder: MediaRecorder? = null
  private var dir: File? = null
  private var recordingTime: Long = 0
  private var timer = Timer()

  override fun onAttachedToActivity(binding: ActivityPluginBinding) {
    this.activity = binding.activity

    val path = activity?.getDir("flutter", 0)?.absolutePath
    Log.d(LOG_NAME, "path =$path")
    dir = File(path)
    if (!dir!!.exists()) {
      dir?.mkdir()
    }
  }

  override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
    this.activity = binding.activity
  }

  override fun onDetachedFromActivityForConfigChanges() {

  }

  override fun onDetachedFromActivity() {
    this.activity = null
  }

  override fun onAttachedToEngine(@NonNull flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
    this.flutterPluginBinding = flutterPluginBinding
    channel = MethodChannel(flutterPluginBinding.binaryMessenger, "audio_plugin")
    channel.setMethodCallHandler(this)
  }

  override
  fun onRequestPermissionsResult(requestCode: Int, permissions: Array<String?>?, grantResults: IntArray): Boolean {
    val REQUEST_RECORD_AUDIO_PERMISSION = 200
    return when (requestCode) {
      REQUEST_RECORD_AUDIO_PERMISSION -> {
        var granted = true
        Log.d(LOG_NAME, "parsing result")
        for (result in grantResults) {
          if (result != PackageManager.PERMISSION_GRANTED) {
            Log.d(LOG_NAME, "result$result")
            granted = false
          }
        }
        Log.d(LOG_NAME, "onRequestPermissionsResult -$granted")
        if (_result != null) {
          _result!!.success(granted)
        }
        granted
      }
      else -> {
        Log.d(LOG_NAME, "onRequestPermissionsResult - false")
        false
      }
    }
  }

  override fun onMethodCall(@NonNull call: MethodCall, @NonNull result: Result) {

    // Log.d(LOG_NAME, "calling " + call.method);
    _result = result

    when (call.method) {
      "current" -> handleCurrent(call, result)
      "hasPermissions" -> handleHasPermission()
      "startRecording" -> handleStart(call, result)
      "stopRecording" -> handleStop(call, result)
      "isRecording" -> isRecording(call, result)
      "setFileName" -> setFileName(call, result)
      else -> result.notImplemented()
    }
  }

  override fun onDetachedFromEngine(@NonNull binding: FlutterPlugin.FlutterPluginBinding) {
    channel.setMethodCallHandler(null)
  }

  private fun handleHasPermission() {
    if (hasRecordPermission()) {
      Log.d(LOG_NAME, "handleHasPermission true")
      if (_result != null) {
        _result!!.success(true)
      }
    } else {
      Log.d(LOG_NAME, "handleHasPermission false")
      if (VERSION.SDK_INT >= Build.VERSION_CODES.M) {
        this.activity?.let { ActivityCompat.requestPermissions(it, arrayOf(Manifest.permission.RECORD_AUDIO, Manifest.permission.WRITE_EXTERNAL_STORAGE), PERMISSIONS_REQUEST_RECORD_AUDIO) }
      } else {
        this.activity?.let { ActivityCompat.requestPermissions(it, arrayOf(Manifest.permission.RECORD_AUDIO), PERMISSIONS_REQUEST_RECORD_AUDIO) }
      }
    }
  }

  private fun hasRecordPermission(): Boolean {
    // if after [Marshmallow], we need to check permission on runtime
    return if (VERSION.SDK_INT >= Build.VERSION_CODES.M) {
      ( ContextCompat.checkSelfPermission(this.activity!!.baseContext, Manifest.permission.RECORD_AUDIO) == PackageManager.PERMISSION_GRANTED
              && ContextCompat.checkSelfPermission(this.activity!!.baseContext, Manifest.permission.WRITE_EXTERNAL_STORAGE) == PackageManager.PERMISSION_GRANTED)
    } else {
      ContextCompat.checkSelfPermission(this.activity!!.baseContext, Manifest.permission.RECORD_AUDIO) == PackageManager.PERMISSION_GRANTED
    }
  }


  private fun handleInit(fileName: String) {
    resetRecorder()
    try{
      // create a File object for the parent directory
      val recorderDirectory = File(dir?.absolutePath)
      // have the object build the directory structure, if needed.
      recorderDirectory.setReadable(true)
      recorderDirectory.setWritable(true)
      if (!recorderDirectory.exists()) {
        recorderDirectory.mkdirs()
      }
    }catch (e: IOException){
      e.printStackTrace()
    }

    output = dir?.absolutePath + "/${this.fileName}"

    mediaRecorder = MediaRecorder()

    mediaRecorder?.setAudioSource(MediaRecorder.AudioSource.MIC)
    mediaRecorder?.setOutputFormat(MediaRecorder.OutputFormat.MPEG_4)
    mediaRecorder?.setAudioEncoder(MediaRecorder.AudioEncoder.AAC)
    mediaRecorder?.setOutputFile(output)
    mediaRecorder?.prepare()
  }

  private fun handleCurrent(call: MethodCall, result: Result) {
    if mediaRecorder != null {

      // iOS factor : to match iOS power level
      val iOSFactor = 0.25
      mAveragePower = 20 * Math.log(Math.abs(mediaRecorder?.getMaxAmplitude()) / 32768.0) * iOSFactor

      Log.d(LOG_NAME, "getMaxAmplitude: " + mediaRecorder?.getMaxAmplitude() + " average: "+ mAveragePower);

      val currentResult: HashMap<String, Object> = HashMap()
      currentResult.put("duration", getDuration() * 1000)
      currentResult.put("path", if (mStatus === "stopped") mFilePath else getTempFilename())
      currentResult.put("peakPower", mAveragePower)
      currentResult.put("averagePower", mAveragePower)
      currentResult.put("isMeteringEnabled", true)
      currentResult.put("isRecording", isRecording)
      // Log.d(LOG_NAME, currentResult.toString());
      result.success(currentResult)

    }else {
      result.success(null)
    }
  }

  private fun resetRecorder() {
    mPeakPower = -120.0
    mAveragePower = -120.0
    mDataSize = 0
  }

  private fun getDuration(): Int {
    val duration = mDataSize / (mSampleRate * 2 * 1)
    return duration.toInt()
  }

  private fun handleStart(call: MethodCall, result: Result) {
    isRecording = true
    mediaRecorder?.start()
    startTimer()
  }

  private fun startTimer(){
    timer.scheduleAtFixedRate(object : TimerTask() {
      override fun run() {
        recordingTime += 1
        updateDisplay()
      }
    }, 1000, 1000)
  }

  private fun stopTimer(){
    timer.cancel()
  }


  private fun resetTimer() {
    timer.cancel()
    recordingTime = 0
  }

  private fun updateDisplay(){
    val minutes = recordingTime / (60)
    val seconds = recordingTime % 60
    val str = String.format("%d:%02d", minutes, seconds)
    Log.d(LOG_NAME, "updateDisplay: $str")
  }

  private fun handleStop(call: MethodCall, result: Result) {
    this.isRecording = false
    mediaRecorder?.stop()
    mediaRecorder?.release()
    stopTimer()
    resetTimer()

    val initResult = HashMap<String, Any>()
    initResult["duration"] = recordingTime
    initResult["path"] = output
    result.success(initResult)

    mediaRecorder = null
  }

  @Throws(IOException::class)
  private fun WriteWaveFileHeader(out: FileOutputStream, totalAudioLen: Long,
                                  totalDataLen: Long, longSampleRate: Long, channels: Int, byteRate: Long) {
    val header = ByteArray(44)
    header[0] = 'R'.toByte() // RIFF/WAVE header
    header[1] = 'I'.toByte()
    header[2] = 'F'.toByte()
    header[3] = 'F'.toByte()
    header[4] = (totalDataLen and 0xff).toByte()
    header[5] = (totalDataLen shr 8 and 0xff).toByte()
    header[6] = (totalDataLen shr 16 and 0xff).toByte()
    header[7] = (totalDataLen shr 24 and 0xff).toByte()
    header[8] = 'W'.toByte()
    header[9] = 'A'.toByte()
    header[10] = 'V'.toByte()
    header[11] = 'E'.toByte()
    header[12] = 'f'.toByte() // 'fmt ' chunk
    header[13] = 'm'.toByte()
    header[14] = 't'.toByte()
    header[15] = ' '.toByte()
    header[16] = 16 // 4 bytes: size of 'fmt ' chunk
    header[17] = 0
    header[18] = 0
    header[19] = 0
    header[20] = 1 // format = 1
    header[21] = 0
    header[22] = channels.toByte()
    header[23] = 0
    header[24] = (longSampleRate and 0xff).toByte()
    header[25] = (longSampleRate shr 8 and 0xff).toByte()
    header[26] = (longSampleRate shr 16 and 0xff).toByte()
    header[27] = (longSampleRate shr 24 and 0xff).toByte()
    header[28] = (byteRate and 0xff).toByte()
    header[29] = (byteRate shr 8 and 0xff).toByte()
    header[30] = (byteRate shr 16 and 0xff).toByte()
    header[31] = (byteRate shr 24 and 0xff).toByte()
    header[32] = 1.toByte() // block align
    header[33] = 0
    header[34] = RECORDER_BPP // bits per sample
    header[35] = 0
    header[36] = 'd'.toByte()
    header[37] = 'a'.toByte()
    header[38] = 't'.toByte()
    header[39] = 'a'.toByte()
    header[40] = (totalAudioLen and 0xff).toByte()
    header[41] = (totalAudioLen shr 8 and 0xff).toByte()
    header[42] = (totalAudioLen shr 16 and 0xff).toByte()
    header[43] = (totalAudioLen shr 24 and 0xff).toByte()
    out.write(header, 0, 44)
  }


  private fun isRecording(call: MethodCall, result: Result) {
    result.success(isRecording)
  }

  private fun setFileName(call: MethodCall, result: Result) {
    this.fileName = call.argument<Any>("fileName").toString()
    handleInit(this.fileName)
    result.success(true)
  }

}

