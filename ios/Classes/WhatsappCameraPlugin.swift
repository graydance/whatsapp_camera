import AVFoundation
import Flutter
import UIKit

/// WhatsappCameraPlugin
///
/// Flutter插件,用于检测设备是否有前置摄像头
/// 使用AVFoundation框架进行精确检测
public class WhatsappCameraPlugin: NSObject, FlutterPlugin {
    private static let channelName = "whatsapp_camera/camera_check"

    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(
            name: channelName, binaryMessenger: registrar.messenger())
        let instance = WhatsappCameraPlugin()
        registrar.addMethodCallDelegate(instance, channel: channel)
        print("WhatsappCameraPlugin已注册")
    }

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "hasFrontCamera":
            checkFrontCamera(result: result)
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    /**
     * 检查设备是否有前置摄像头
     *
     * 使用AVFoundation精确检测:
     * 1. 使用AVCaptureDevice.DiscoverySession查询所有视频设备
     * 2. 检查是否存在position为.front的设备
     * 3. 返回检测结果
     *
     * @param result Flutter结果回调
     */
    private func checkFrontCamera(result: FlutterResult) {
        do {
            // 获取所有视频设备
            let devices = AVCaptureDevice.DiscoverySession(
                deviceTypes: [.builtInWideAngleCamera],
                mediaType: .video,
                position: .unspecified
            ).devices

            print("检测到\(devices.count)个摄像头设备")

            // 检查是否有前置摄像头
            let hasFront = devices.contains { device in
                let isFront = device.position == .front
                if isFront {
                    print("找到前置摄像头: \(device.localizedName)")
                }
                return isFront
            }

            print("检测前置摄像头结果: \(hasFront)")
            result(hasFront)
        } catch {
            print("检测前置摄像头失败: \(error.localizedDescription)")
            // 发生错误时返回false,避免显示无法使用的功能
            result(false)
        }
    }
}
