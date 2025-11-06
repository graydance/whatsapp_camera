package com.whatsapp_camera

import android.content.Context
import android.hardware.camera2.CameraCharacteristics
import android.hardware.camera2.CameraManager
import android.util.Log
import androidx.annotation.NonNull
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result

/**
 * WhatsappCameraPlugin
 * 
 * Flutter插件,用于检测设备是否有前置摄像头
 * 使用Android Camera2 API进行精确检测
 */
class WhatsappCameraPlugin: FlutterPlugin, MethodCallHandler {
  private lateinit var channel: MethodChannel
  private lateinit var context: Context

  companion object {
    private const val CHANNEL_NAME = "whatsapp_camera/camera_check"
    private const val TAG = "WhatsappCameraPlugin"
  }

  override fun onAttachedToEngine(@NonNull flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
    context = flutterPluginBinding.applicationContext
    channel = MethodChannel(flutterPluginBinding.binaryMessenger, CHANNEL_NAME)
    channel.setMethodCallHandler(this)
    Log.d(TAG, "WhatsappCameraPlugin已注册")
  }

  override fun onMethodCall(@NonNull call: MethodCall, @NonNull result: Result) {
    when (call.method) {
      "hasFrontCamera" -> {
        try {
          val hasFront = checkFrontCamera()
          Log.d(TAG, "检测前置摄像头结果: $hasFront")
          result.success(hasFront)
        } catch (e: Exception) {
          Log.e(TAG, "检测前置摄像头失败: ${e.message}", e)
          result.error("CAMERA_ERROR", "无法检测前置摄像头: ${e.message}", null)
        }
      }
      else -> {
        result.notImplemented()
      }
    }
  }

  override fun onDetachedFromEngine(@NonNull binding: FlutterPlugin.FlutterPluginBinding) {
    channel.setMethodCallHandler(null)
    Log.d(TAG, "WhatsappCameraPlugin已注销")
  }

  /**
   * 检查设备是否有前置摄像头
   * 
   * 使用Camera2 API精确检测:
   * 1. 获取CameraManager服务
   * 2. 遍历所有摄像头ID
   * 3. 检查每个摄像头的LENS_FACING属性
   * 4. 如果找到LENS_FACING_FRONT则返回true
   * 
   * @return true 如果设备有前置摄像头, false 否则
   */
  private fun checkFrontCamera(): Boolean {
    return try {
      val cameraManager = context.getSystemService(Context.CAMERA_SERVICE) as CameraManager
      val cameraIdList = cameraManager.cameraIdList
      
      Log.d(TAG, "检测到${cameraIdList.size}个摄像头设备")
      
      // 遍历所有摄像头,查找前置摄像头
      for (cameraId in cameraIdList) {
        val characteristics = cameraManager.getCameraCharacteristics(cameraId)
        val facing = characteristics.get(CameraCharacteristics.LENS_FACING)
        
        Log.d(TAG, "摄像头ID: $cameraId, 朝向: $facing")
        
        // LENS_FACING_FRONT = 0 表示前置摄像头
        if (facing == CameraCharacteristics.LENS_FACING_FRONT) {
          Log.d(TAG, "找到前置摄像头")
          return true
        }
      }
      
      Log.d(TAG, "未找到前置摄像头")
      false
    } catch (e: Exception) {
      Log.e(TAG, "检测前置摄像头异常: ${e.message}", e)
      // 发生错误时返回false,避免显示无法使用的功能
      false
    }
  }
}

