import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:math' as math;

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_gallery_saver/image_gallery_saver.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import 'package:image/image.dart' as img;
import 'package:native_device_orientation/native_device_orientation.dart';

class WhatsappCamera extends StatefulWidget {
  /// permission to select multiple images
  final bool multiple;

  /// 是否强制输出 4:3（竖屏 3:4）
  final bool force43;

  /// 当原图比例已匹配时是否直接返回原图，避免重编码
  final bool returnOriginalOnMatch;

  /// 拍照期间是否锁定预览布局方向，防止横屏抖动
  final bool lockLayoutDuringCapture;

  /// 裁剪输出 JPEG 质量
  final int jpegQuality;

  /// 是否输出调试日志
  final bool enableLogs;

  const WhatsappCamera({
    super.key,
    this.multiple = false,
    this.force43 = true,
    this.returnOriginalOnMatch = true,
    this.lockLayoutDuringCapture = true,
    this.jpegQuality = 95,
    this.enableLogs = true,
  });

  @override
  State<WhatsappCamera> createState() => _WhatsappCameraState();
}

// 为了保持兼容性，也导出一个别名
typedef OfficialWhatsappCamera = WhatsappCamera;

class _WhatsappCameraState extends State<WhatsappCamera>
    with WidgetsBindingObserver {
  CameraController? _controller;
  List<CameraDescription>? _cameras;
  int _selectedCameraIdx = 0;
  FlashMode _currentFlashMode = FlashMode.auto;
  bool _isCameraInitialized = false;

  // 聚焦相关状态
  bool _isFocusing = false;
  Offset? _focusPosition;
  Timer? _focusTimer;

  // 曝光调整相关状态
  double _exposureOffset = 0.0;
  double _minExposureOffset = -4.0;
  double _maxExposureOffset = 4.0;
  bool _showExposureSlider = false;

  // 缩放相关状态
  double _currentZoomLevel = 1.0;
  double _minZoomLevel = 1.0;
  double _maxZoomLevel = 10.0;
  double _baseZoomLevel = 1.0; // 用于记录缩放手势开始时的基础缩放值
  bool _isScaling = false; // 标记是否正在进行缩放手势

  // 文件选择
  final List<File> _selectedImages = [];
  // 捕获时锁定的设备方向（用于稳定预览布局，避免横屏拍完瞬间变竖）
  DeviceOrientation? _lockedCaptureOrientation;
  // 防抖：避免连续触发拍照造成状态抖动
  bool _isCapturing = false;
  // 陀螺仪实时方向（用于旋转图标）
  NativeDeviceOrientation _nativeOrientation =
      NativeDeviceOrientation.portraitUp;
  StreamSubscription<NativeDeviceOrientation>? _nativeOrientationSub;

  // 预览容器 key，用于准确计算点击坐标
  final GlobalKey _previewKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initializeCamera();
    // 订阅陀螺仪方向变更
    _nativeOrientationSub = NativeDeviceOrientationCommunicator()
        .onOrientationChanged(useSensor: true)
        .listen((ori) {
      if (!mounted) return;
      setState(() {
        _nativeOrientation = ori;
      });
    });
  }

  @override
  void dispose() {
    // 在退出时统一解除方向锁定，避免残留状态
    try {
      _controller?.unlockCaptureOrientation();
    } catch (_) {}
    _controller?.dispose();
    _focusTimer?.cancel();
    _nativeOrientationSub?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final CameraController? cameraController = _controller;
    if (cameraController == null || !cameraController.value.isInitialized) {
      return;
    }

    if (state == AppLifecycleState.inactive) {
      cameraController.dispose();
    } else if (state == AppLifecycleState.resumed) {
      _initializeCamera();
    }
  }

  /// 初始化相机
  Future<void> _initializeCamera() async {
    try {
      // 获取可用相机
      _cameras = await availableCameras();
      if (_cameras == null || _cameras!.isEmpty) {
        debugPrint('❌ 没有可用的相机');
        return;
      }

      // 初始化相机控制器 - 使用4:3比例
      _controller = CameraController(
        _cameras![_selectedCameraIdx],
        ResolutionPreset.max, // 优先使用传感器原生 4:3，减少后期裁剪
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );

      await _controller!.initialize();

      // 获取曝光范围
      try {
        _minExposureOffset = await _controller!.getMinExposureOffset();
        _maxExposureOffset = await _controller!.getMaxExposureOffset();
        debugPrint(
            '📊 曝光范围: ${_minExposureOffset.toStringAsFixed(1)} 到 ${_maxExposureOffset.toStringAsFixed(1)}');
      } catch (e) {
        debugPrint('⚠️ 获取曝光范围失败: $e，使用默认值');
      }

      // 获取缩放范围
      try {
        _minZoomLevel = await _controller!.getMinZoomLevel();
        _maxZoomLevel = await _controller!.getMaxZoomLevel();
        _currentZoomLevel = _minZoomLevel;
        _baseZoomLevel = _minZoomLevel;
        debugPrint(
            '🔍 缩放范围: ${_minZoomLevel.toStringAsFixed(1)}x 到 ${_maxZoomLevel.toStringAsFixed(1)}x');
      } catch (e) {
        debugPrint('⚠️ 获取缩放范围失败: $e，使用默认值');
      }

      // 输出相机预览信息用于调试
      debugPrint('📷 相机预览信息:');
      debugPrint(
          '   - 原始宽高比: ${_controller!.value.aspectRatio.toStringAsFixed(2)}');
      debugPrint(
          '   - 显示宽高比: ${(1.0 / _controller!.value.aspectRatio).toStringAsFixed(2)}');
      debugPrint('   - 预览尺寸: ${_controller!.value.previewSize}');

      // 相机使用原始比例，但预览和拍摄会强制为4:3
      final double actualRatio = 1.0 / _controller!.value.aspectRatio;
      debugPrint(
          '📱 相机原始比例: ${actualRatio.toStringAsFixed(2)}, 强制显示4:3比例 (1.33)');

      if (mounted) {
        setState(() {
          _isCameraInitialized = true;
        });
        debugPrint('✅ 相机初始化成功');
      }
    } catch (e) {
      debugPrint('❌ 相机初始化失败: $e');
    }
  }

  /// 处理点击聚焦
  Future<void> _handleTapFocus(TapDownDetails details) async {
    // 立即检查多指操作 - 如果是多指，直接返回
    if (_isScaling) return;

    if (_controller == null || !_controller!.value.isInitialized) return;
    if (!mounted) return;

    // 延迟一小段时间检测是否变成多指操作
    await Future.delayed(const Duration(milliseconds: 30));
    if (_isScaling || !mounted) return;

    try {
      await HapticFeedback.lightImpact();

      // 使用预览容器的实际尺寸与 FittedBox(BoxFit.cover) 的裁剪关系计算
      final RenderBox? rb =
          _previewKey.currentContext?.findRenderObject() as RenderBox?;
      if (rb == null) return;

      final Size containerSize = rb.size; // 预览容器的宽高（固定 4:3/3:4）

      // 本地坐标（相对于容器）
      final Offset local = details.localPosition;
      final double xC = local.dx.clamp(0.0, containerSize.width);
      final double yC = local.dy.clamp(0.0, containerSize.height);

      // 相机预览的实际宽高比（child 的宽高比）；横/竖屏取值不同
      final double cameraAspectRatio =
          _controller!.value.aspectRatio; // width/height of camera
      final Orientation deviceOri = MediaQuery.of(context).orientation;
      final double Rp = deviceOri == Orientation.portrait
          ? (1 / cameraAspectRatio)
          : cameraAspectRatio;

      // 容器宽高比（外层 4:3 或 3:4）
      final double Rc = containerSize.width / containerSize.height;

      // 将容器内坐标映射为相机纹理的标准化坐标（考虑 cover 裁剪）
      double u, v;
      if (Rp > Rc) {
        // 子更宽，左右裁剪；高度完全匹配
        final double alpha = Rc / Rp; // Cw / (Ch*Rp)
        u = (xC / containerSize.width) * alpha + (1 - alpha) / 2;
        v = (yC / containerSize.height);
      } else if (Rp < Rc) {
        // 子更窄，上下裁剪；宽度完全匹配
        final double alphaY = Rp / Rc; // Ch / (Cw/Rp)
        u = (xC / containerSize.width);
        v = (yC / containerSize.height) * alphaY + (1 - alphaY) / 2;
      } else {
        // 比例一致，无裁剪
        u = xC / containerSize.width;
        v = yC / containerSize.height;
      }

      double relativeX = u.clamp(0.0, 1.0);
      double relativeY = v.clamp(0.0, 1.0);

      // 确保坐标在有效范围内
      relativeX = relativeX.clamp(0.0, 1.0);
      relativeY = relativeY.clamp(0.0, 1.0);

      // 显示聚焦指示器和曝光滑块
      setState(() {
        _isFocusing = true;
        // 使用全局坐标绘制指示器，避免位置偏移
        _focusPosition = details.globalPosition;
        _showExposureSlider = true;
      });

      // 执行聚焦
      await _controller!.setFocusPoint(Offset(relativeX, relativeY));
      await _controller!.setExposurePoint(Offset(relativeX, relativeY));

      // 聚焦完成的触觉反馈
      await HapticFeedback.selectionClick();

      // 1.5秒后隐藏聚焦指示器和曝光滑块
      _focusTimer?.cancel();
      _focusTimer = Timer(const Duration(milliseconds: 1500), () {
        if (mounted) {
          setState(() {
            _isFocusing = false;
            _focusPosition = null;
            _showExposureSlider = false;
          });
        }
      });
    } catch (e) {
      // 聚焦失败，清理UI状态
      if (mounted) {
        setState(() {
          _isFocusing = false;
          _focusPosition = null;
          _showExposureSlider = false;
        });
      }
    }
  }

  /// 调整曝光补偿
  Future<void> _setExposureOffset(double offset) async {
    if (_controller == null || !_controller!.value.isInitialized) return;

    try {
      // 限制在有效范围内
      final clampedOffset =
          offset.clamp(_minExposureOffset, _maxExposureOffset);

      await _controller!.setExposureOffset(clampedOffset);

      setState(() {
        _exposureOffset = clampedOffset;
      });

      // 曝光调整完成
    } catch (e) {
      // 曝光设置失败，静默处理
    }
  }

  /// 处理曝光滑块拖拽
  void _handleExposurePanUpdate(DragUpdateDetails details) {
    // 重置定时器，保持滑块显示
    _focusTimer?.cancel();
    _focusTimer = Timer(const Duration(milliseconds: 2000), () {
      if (mounted) {
        setState(() {
          _isFocusing = false;
          _focusPosition = null;
          _showExposureSlider = false;
        });
      }
    });

    // 计算新的曝光值 (向上拖拽增加曝光，向下拖拽减少曝光)
    final double sensitivity = 0.02;
    final double deltaY = details.delta.dy;
    final double newOffset = _exposureOffset - (deltaY * sensitivity);

    _setExposureOffset(newOffset);
  }

  /// 处理缩放手势开始
  void _handleScaleStart(ScaleStartDetails details) {
    if (details.pointerCount >= 2) {
      _isScaling = true;
      _baseZoomLevel = _currentZoomLevel;
    }
  }

  /// 处理缩放手势更新
  void _handleScaleUpdate(ScaleUpdateDetails details) {
    if (_controller == null || !_controller!.value.isInitialized) return;
    if (!_isScaling) return;

    final double newZoomLevel =
        (_baseZoomLevel * details.scale).clamp(_minZoomLevel, _maxZoomLevel);

    if ((newZoomLevel - _currentZoomLevel).abs() > 0.1) {
      _setZoomLevel(newZoomLevel);
    }
  }

  /// 处理缩放手势结束
  void _handleScaleEnd(ScaleEndDetails details) {
    _isScaling = false;
  }

  /// 设置缩放级别
  Future<void> _setZoomLevel(double zoomLevel) async {
    if (_controller == null || !_controller!.value.isInitialized) return;

    try {
      await _controller!.setZoomLevel(zoomLevel);
      setState(() {
        _currentZoomLevel = zoomLevel;
      });
    } catch (e) {
      // 缩放设置失败，静默处理
    }
  }

  /// 裁剪图片为4:3比例，保持拍摄方向 (已弃用，保持自然拍摄比例)
  Future<File> _cropImageTo43(File originalFile,
      {DeviceOrientation? deviceOrientation}) async {
    try {
      // 先解码以读取尺寸，但若无需裁剪则直接返回原图，避免任何重编码导致的色偏
      final Uint8List bytes = await originalFile.readAsBytes();
      final img.Image? decoded = img.decodeImage(bytes);
      if (decoded == null) {
        debugPrint('❌ 解码失败，返回原图');
        return originalFile;
      }

      final int rawW = decoded.width;
      final int rawH = decoded.height;
      final bool expectLandscape =
          deviceOrientation == DeviceOrientation.landscapeLeft ||
              deviceOrientation == DeviceOrientation.landscapeRight;
      final double targetRatioWhenExpected =
          expectLandscape ? (4 / 3) : (3 / 4);
      final double currentRatio = rawW / rawH;

      // 若不强制 4:3，或者比例已匹配并允许直接返回，则不做重编码
      if (!widget.force43 ||
          (widget.returnOriginalOnMatch &&
              (currentRatio - targetRatioWhenExpected).abs() < 0.01)) {
        debugPrint('✅ 比例已匹配/不强制裁剪，直接返回原图 ${rawW}x${rawH}');
        return originalFile;
      }

      // 需要裁剪时，才烘焙 EXIF 并做必要旋转
      img.Image baked = img.bakeOrientation(decoded);
      int originalWidth = baked.width;
      int originalHeight = baked.height;
      debugPrint(
          '🧭 方向信息: device=${deviceOrientation?.name ?? 'unknown'}, baked=${originalWidth}x${originalHeight}');

      if (deviceOrientation != null) {
        final bool expectLandscape2 =
            deviceOrientation == DeviceOrientation.landscapeLeft ||
                deviceOrientation == DeviceOrientation.landscapeRight;
        if (expectLandscape2 && originalWidth < originalHeight) {
          final int angle =
              deviceOrientation == DeviceOrientation.landscapeLeft ? -90 : 90;
          baked = img.copyRotate(baked, angle: angle);
          originalWidth = baked.width;
          originalHeight = baked.height;
          debugPrint(
              '🔄 旋转到横屏(${deviceOrientation.name}, angle=$angle): ${originalWidth}x${originalHeight}');
        } else if (!expectLandscape2 && originalWidth > originalHeight) {
          final int angle =
              deviceOrientation == DeviceOrientation.portraitDown ? 180 : -90;
          baked = img.copyRotate(baked, angle: angle);
          originalWidth = baked.width;
          originalHeight = baked.height;
          debugPrint(
              '🔄 旋转到竖屏(${deviceOrientation.name}, angle=$angle): ${originalWidth}x${originalHeight}');
        }
      }

      final bool isLandscape = originalWidth >= originalHeight;
      final double targetRatio = isLandscape ? 4 / 3 : 3 / 4; // width/height

      int cropWidth, cropHeight;
      int offsetX = 0, offsetY = 0;

      if ((originalWidth / originalHeight) > targetRatio) {
        // 太宽，裁左右
        cropHeight = originalHeight;
        cropWidth = (cropHeight * targetRatio).round();
        offsetX = (originalWidth - cropWidth) ~/ 2;
      } else {
        // 太高，裁上下
        cropWidth = originalWidth;
        cropHeight = (cropWidth / targetRatio).round();
        offsetY = (originalHeight - cropHeight) ~/ 2;
      }

      final img.Image cropped = img.copyCrop(
        baked,
        x: offsetX,
        y: offsetY,
        width: cropWidth,
        height: cropHeight,
      );

      final Directory tempDir = await getTemporaryDirectory();
      final String croppedPath = path.join(
        tempDir.path,
        '${DateTime.now().millisecondsSinceEpoch}_${isLandscape ? '4x3' : '3x4'}.jpg',
      );
      final File croppedFile = File(croppedPath);
      await croppedFile
          .writeAsBytes(img.encodeJpg(cropped, quality: widget.jpegQuality));
      debugPrint(
          '✂️ 已裁剪为 ${isLandscape ? '4:3' : '3:4'} 比例: ${cropWidth}x${cropHeight}');
      return croppedFile;
    } catch (e) {
      debugPrint('❌ 图片裁剪失败: $e');
      return originalFile; // 返回原图
    }
  }

  /// 拍照
  Future<void> _takePicture() async {
    if (_controller == null || !_controller!.value.isInitialized) {
      return;
    }
    if (_isCapturing) return;

    try {
      _isCapturing = true;
      await HapticFeedback.mediumImpact();

      // 使用物理传感器获取真实设备方向，避免 UI 方向锁定造成误判
      final NativeDeviceOrientation native =
          await NativeDeviceOrientationCommunicator()
              .orientation(useSensor: true);
      DeviceOrientation captureOrientation;
      switch (native) {
        case NativeDeviceOrientation.landscapeLeft:
          captureOrientation = DeviceOrientation.landscapeLeft;
          break;
        case NativeDeviceOrientation.landscapeRight:
          captureOrientation = DeviceOrientation.landscapeRight;
          break;
        case NativeDeviceOrientation.portraitDown:
          captureOrientation = DeviceOrientation.portraitDown;
          break;
        case NativeDeviceOrientation.portraitUp:
          captureOrientation = DeviceOrientation.portraitUp;
          break;
        default:
          captureOrientation = _controller!.value.deviceOrientation;
      }

      // 拍照（先锁定捕获方向与布局方向，拍完解锁）
      XFile picture;
      try {
        // 使用物理方向锁定相机捕获方向，增强一致性
        await _controller!.lockCaptureOrientation(captureOrientation);
        setState(() {
          _lockedCaptureOrientation = captureOrientation;
        });
      } catch (_) {}
      try {
        picture = await _controller!.takePicture();
      } finally {
        // 不在退出前解除布局方向锁定，避免预览在最后一帧跳变。
        // 也不强制解锁 captureOrientation；控制器将随页面一起销毁。
      }
      final File processed = await _cropImageTo43(
        File(picture.path),
        deviceOrientation: captureOrientation,
      );

      // 保存到相册
      await ImageGallerySaver.saveFile(processed.path);

      _selectedImages.add(processed);
      debugPrint('📸 照片拍摄成功，并已裁剪为 4:3/3:4，方向已纠正');

      // 返回结果
      if (mounted) {
        Navigator.pop(context, _selectedImages);
      }
    } catch (e) {
      debugPrint('❌ 拍照失败: $e');
    } finally {
      _isCapturing = false;
    }
  }

  /// 切换相机
  Future<void> _switchCamera() async {
    if (_cameras == null || _cameras!.length < 2) return;

    try {
      setState(() {
        _isCameraInitialized = false;
      });

      await _controller?.dispose();

      _selectedCameraIdx = (_selectedCameraIdx + 1) % _cameras!.length;

      _controller = CameraController(
        _cameras![_selectedCameraIdx],
        ResolutionPreset.max, // 优先使用传感器原生 4:3，减少后期裁剪
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );

      await _controller!.initialize();

      // 获取新相机的曝光和缩放范围并重置值
      try {
        _minExposureOffset = await _controller!.getMinExposureOffset();
        _maxExposureOffset = await _controller!.getMaxExposureOffset();
        _exposureOffset = 0.0;
        _minZoomLevel = await _controller!.getMinZoomLevel();
        _maxZoomLevel = await _controller!.getMaxZoomLevel();
        _currentZoomLevel = _minZoomLevel;
        _baseZoomLevel = _minZoomLevel;
        debugPrint(
            '🔄 新相机参数 - 曝光: ${_minExposureOffset.toStringAsFixed(1)} ~ ${_maxExposureOffset.toStringAsFixed(1)}, 缩放: ${_minZoomLevel.toStringAsFixed(1)}x ~ ${_maxZoomLevel.toStringAsFixed(1)}x');
      } catch (e) {
        debugPrint('⚠️ 获取新相机参数失败: $e');
      }

      if (mounted) {
        setState(() {
          _isCameraInitialized = true;
        });
      }

      debugPrint('🔄 切换到${_selectedCameraIdx == 0 ? '后置' : '前置'}相机');
    } catch (e) {
      debugPrint('❌ 切换相机失败: $e');
    }
  }

  /// 切换闪光灯模式
  Future<void> _toggleFlashMode() async {
    if (_controller == null || !_controller!.value.isInitialized) return;

    try {
      switch (_currentFlashMode) {
        case FlashMode.off:
          _currentFlashMode = FlashMode.auto;
          break;
        case FlashMode.auto:
          _currentFlashMode = FlashMode.always;
          break;
        case FlashMode.always:
          _currentFlashMode = FlashMode.off;
          break;
        case FlashMode.torch:
          _currentFlashMode = FlashMode.off;
          break;
      }

      await _controller!.setFlashMode(_currentFlashMode);
      setState(() {});

      debugPrint('💡 闪光灯模式: $_currentFlashMode');
    } catch (e) {
      debugPrint('❌ 切换闪光灯失败: $e');
    }
  }

  /// 打开相册
  Future<void> _openGallery() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        allowMultiple: widget.multiple,
        type: FileType.image,
      );

      if (result != null) {
        for (var file in result.files) {
          if (file.path != null) {
            _selectedImages.add(File(file.path!));
          }
        }

        if (_selectedImages.isNotEmpty && mounted) {
          Navigator.pop(context, _selectedImages);
        }
      }
    } catch (e) {
      debugPrint('❌ 打开相册失败: $e');
    }
  }

  /// 获取闪光灯图标
  IconData _getFlashIcon() {
    switch (_currentFlashMode) {
      case FlashMode.off:
        return Icons.flash_off;
      case FlashMode.auto:
        return Icons.flash_auto;
      case FlashMode.always:
        return Icons.flash_on;
      case FlashMode.torch:
        return Icons.flashlight_on;
    }
  }

  double _uiAngle() {
    // 优先使用陀螺仪的实时方向，修正左右横屏方向（反向问题）
    switch (_nativeOrientation) {
      case NativeDeviceOrientation.portraitUp:
        return 0.0;
      case NativeDeviceOrientation.portraitDown:
        return math.pi;
      case NativeDeviceOrientation.landscapeLeft:
        return math.pi / 2; // 修正：左横屏顺时针90°
      case NativeDeviceOrientation.landscapeRight:
        return -math.pi / 2; // 修正：右横屏逆时针90°
      default:
        return 0.0;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_isCameraInitialized || _controller == null) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: CircularProgressIndicator(
            color: Colors.white,
          ),
        ),
      );
    }

    final Size screenSize = MediaQuery.of(context).size;

    // 获取相机的自然宽高比，避免预览变形
    final double cameraAspectRatio = _controller!.value.aspectRatio;
    if (widget.enableLogs) {
      debugPrint('📷 相机自然宽高比: $cameraAspectRatio');
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // 相机预览 - 使用正确的宽高比，避免变形
          Positioned.fill(
            child: Center(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final Orientation orientation =
                      _lockedCaptureOrientation == null
                          ? MediaQuery.of(context).orientation
                          : ((_lockedCaptureOrientation ==
                                      DeviceOrientation.landscapeLeft ||
                                  _lockedCaptureOrientation ==
                                      DeviceOrientation.landscapeRight)
                              ? Orientation.landscape
                              : Orientation.portrait);
                  final double desiredAspect =
                      orientation == Orientation.portrait ? 3 / 4 : 4 / 3;
                  final Size? pv = _controller!.value.previewSize;
                  double childW = pv?.width ?? constraints.maxWidth;
                  double childH = pv?.height ?? constraints.maxWidth / (4 / 3);
                  // 纹理在竖屏时通常是旋转的，交换宽高以匹配屏幕方向
                  if (orientation == Orientation.portrait) {
                    final double tmp = childW;
                    childW = childH;
                    childH = tmp;
                  }

                  return AspectRatio(
                    aspectRatio: desiredAspect,
                    child: GestureDetector(
                      key: _previewKey,
                      onTapDown: _handleTapFocus,
                      onScaleStart: _handleScaleStart,
                      onScaleUpdate: _handleScaleUpdate,
                      onScaleEnd: _handleScaleEnd,
                      child: ClipRect(
                        child: FittedBox(
                          fit: BoxFit.cover,
                          child: SizedBox(
                            width: childW,
                            height: childH,
                            child: CameraPreview(_controller!),
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),

          // 聚焦指示器
          if (_isFocusing && _focusPosition != null)
            Positioned(
              left: _focusPosition!.dx - 40,
              top: _focusPosition!.dy - 40,
              child: TweenAnimationBuilder<double>(
                duration: const Duration(milliseconds: 300),
                tween: Tween(begin: 1.2, end: 1.0),
                builder: (context, scale, child) {
                  return Transform.scale(
                    scale: scale,
                    child: Container(
                      width: 80,
                      height: 80,
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: Colors.white,
                          width: 2,
                        ),
                        shape: BoxShape.rectangle,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Container(
                        margin: const EdgeInsets.all(15),
                        decoration: BoxDecoration(
                          border: Border.all(
                            color: Colors.white,
                            width: 1,
                          ),
                          shape: BoxShape.rectangle,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),

          // 曝光调整滑块
          if (_showExposureSlider && _focusPosition != null)
            Positioned(
              left: (_focusPosition!.dx + 60)
                  .clamp(0, screenSize.width - 70), // 在聚焦框右边60像素处，但不能超出屏幕
              top: (_focusPosition!.dy - 100)
                  .clamp(20, screenSize.height - 220), // 滑块的顶部位置，确保不超出屏幕
              child: TweenAnimationBuilder<double>(
                duration: const Duration(milliseconds: 200),
                tween: Tween(begin: 0.0, end: 1.0),
                builder: (context, opacity, child) {
                  return Opacity(
                    opacity: opacity,
                    child: Container(
                      width: 40,
                      height: 200,
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.6),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: Colors.white.withOpacity(0.3),
                          width: 1,
                        ),
                      ),
                      child: Stack(
                        children: [
                          // 滑块轨道
                          Positioned(
                            left: 17,
                            top: 20,
                            bottom: 20,
                            child: Container(
                              width: 6,
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.3),
                                borderRadius: BorderRadius.circular(3),
                              ),
                            ),
                          ),
                          // 亮度图标（上）
                          Positioned(
                            top: 8,
                            left: 0,
                            right: 0,
                            child: Icon(
                              Icons.wb_sunny,
                              color: Colors.white,
                              size: 18,
                            ),
                          ),
                          // 亮度图标（下）
                          Positioned(
                            bottom: 8,
                            left: 0,
                            right: 0,
                            child: Icon(
                              Icons.brightness_low,
                              color: Colors.white,
                              size: 18,
                            ),
                          ),
                          // 可拖拽的滑块
                          Positioned(
                            left: 12,
                            top: 20 +
                                (160 - 20) *
                                    (1 -
                                        (_exposureOffset - _minExposureOffset) /
                                            (_maxExposureOffset -
                                                _minExposureOffset)),
                            child: GestureDetector(
                              onPanUpdate: _handleExposurePanUpdate,
                              child: Container(
                                width: 16,
                                height: 16,
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: Colors.black.withOpacity(0.2),
                                    width: 1,
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withOpacity(0.3),
                                      blurRadius: 4,
                                      offset: const Offset(0, 2),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          // 曝光值显示
                          Positioned(
                            left: -15,
                            right: -15,
                            top: 20 +
                                (160 - 20) *
                                    (1 -
                                        (_exposureOffset - _minExposureOffset) /
                                            (_maxExposureOffset -
                                                _minExposureOffset)) +
                                20,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.black.withOpacity(0.7),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                _exposureOffset.toStringAsFixed(1),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),

          // 缩放倍数显示
          if (_currentZoomLevel > _minZoomLevel + 0.1) // 当缩放大于最小值时显示
            Positioned(
              top: MediaQuery.of(context).padding.top + 60,
              left: 0,
              right: 0,
              child: Center(
                child: Transform.rotate(
                  angle: (_lockedCaptureOrientation == null)
                      ? 0.0
                      : (_lockedCaptureOrientation ==
                              DeviceOrientation.portraitUp
                          ? 0.0
                          : _lockedCaptureOrientation ==
                                  DeviceOrientation.portraitDown
                              ? math.pi
                              : _lockedCaptureOrientation ==
                                      DeviceOrientation.landscapeLeft
                                  ? -math.pi / 2
                                  : math.pi / 2),
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.6),
                      borderRadius: BorderRadius.circular(15),
                    ),
                    child: Text(
                      '${_currentZoomLevel.toStringAsFixed(1)}x',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ),
              ),
            ),

          // 顶部操作栏
          Positioned(
            top: MediaQuery.of(context).padding.top + 10,
            left: 20,
            right: 20,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // 关闭按钮
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close, color: Colors.white),
                ),
                // 相册按钮
                IconButton(
                  onPressed: _openGallery,
                  icon: AnimatedRotation(
                    turns: _uiAngle() / (2 * math.pi),
                    duration: const Duration(milliseconds: 200),
                    curve: Curves.easeOut,
                    child: const Icon(Icons.photo_library, color: Colors.white),
                  ),
                ),
              ],
            ),
          ),

          // 底部操作栏
          Positioned(
            bottom: 50,
            left: 0,
            right: 0,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                // 闪光灯按钮
                Container(
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.5),
                    shape: BoxShape.circle,
                  ),
                  child: IconButton(
                    onPressed: _toggleFlashMode,
                    icon: AnimatedRotation(
                      turns: _uiAngle() / (2 * math.pi),
                      duration: const Duration(milliseconds: 200),
                      curve: Curves.easeOut,
                      child: Icon(
                        _getFlashIcon(),
                        color: Colors.white,
                        size: 24,
                      ),
                    ),
                  ),
                ),

                // 拍照按钮
                GestureDetector(
                  onTap: _takePicture,
                  child: Container(
                    width: 70,
                    height: 70,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: Colors.white,
                        width: 4,
                      ),
                    ),
                    child: Container(
                      margin: const EdgeInsets.all(4),
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                ),

                // 切换相机按钮
                Container(
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.5),
                    shape: BoxShape.circle,
                  ),
                  child: IconButton(
                    onPressed: _switchCamera,
                    icon: AnimatedRotation(
                      turns: _uiAngle() / (2 * math.pi),
                      duration: const Duration(milliseconds: 200),
                      curve: Curves.easeOut,
                      child: const Icon(
                        Icons.flip_camera_ios,
                        color: Colors.white,
                        size: 24,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
