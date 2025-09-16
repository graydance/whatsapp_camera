import 'dart:async';
import 'dart:io';
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

  /// 是否启用快速拍照模式（跳过图像处理，直接返回原图）
  final bool fastCaptureMode;

  const WhatsappCamera({
    super.key,
    this.multiple = false,
    this.force43 = true,
    this.returnOriginalOnMatch = true,
    this.lockLayoutDuringCapture = true,
    this.jpegQuality = 95,
    this.enableLogs = true,
    this.fastCaptureMode = false,
  });

  /// 快速拍照模式构造函数 - 跳过图像处理，提升拍照速度
  const WhatsappCamera.fastMode({
    Key? key,
    bool multiple = false,
    bool enableLogs = true,
  }) : this(
          key: key,
          multiple: multiple,
          force43: false,
          returnOriginalOnMatch: true,
          lockLayoutDuringCapture: false,
          jpegQuality: 85,
          enableLogs: enableLogs,
          fastCaptureMode: true,
        );

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
  Timer? _exposureUpdateTimer; // 防抖定时器

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
        // 当传感器返回未知状态时，保持上一个有效的方向
        if (ori != NativeDeviceOrientation.unknown) {
          _nativeOrientation = ori;
        }
        // 如果是未知状态(平放)，保持当前方向不变，避免UI跳动
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
    _exposureUpdateTimer?.cancel();
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

    // 提前获取BuildContext相关的数据，避免异步操作后使用
    final Orientation deviceOri = MediaQuery.of(context).orientation;

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
      final double previewAspectRatio = deviceOri == Orientation.portrait
          ? (1 / cameraAspectRatio)
          : cameraAspectRatio;

      // 容器宽高比（外层 4:3 或 3:4）
      final double containerAspectRatio =
          containerSize.width / containerSize.height;

      // 将容器内坐标映射为相机纹理的标准化坐标（考虑 cover 裁剪）
      double u, v;
      if (previewAspectRatio > containerAspectRatio) {
        // 子更宽，左右裁剪；高度完全匹配
        final double alpha = containerAspectRatio /
            previewAspectRatio; // Cw / (Ch*previewAspectRatio)
        u = (xC / containerSize.width) * alpha + (1 - alpha) / 2;
        v = (yC / containerSize.height);
      } else if (previewAspectRatio < containerAspectRatio) {
        // 子更窄，上下裁剪；宽度完全匹配
        final double alphaY = previewAspectRatio /
            containerAspectRatio; // Ch / (Cw/previewAspectRatio)
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

  /// 调整曝光补偿（带防抖）
  Future<void> _setExposureOffset(double offset) async {
    if (_controller == null || !_controller!.value.isInitialized) return;

    // 限制在有效范围内
    final clampedOffset = offset.clamp(_minExposureOffset, _maxExposureOffset);

    // 立即更新UI状态，提供即时反馈
    setState(() {
      _exposureOffset = clampedOffset;
    });

    // 取消之前的定时器
    _exposureUpdateTimer?.cancel();

    // 设置防抖定时器，50ms后更新相机
    _exposureUpdateTimer = Timer(const Duration(milliseconds: 50), () async {
      try {
        await _controller!.setExposureOffset(clampedOffset);
      } catch (e) {
        // 曝光设置失败，静默处理
      }
    });
  }

  /// 立即设置曝光补偿（用于手势结束时）
  Future<void> _setExposureOffsetImmediately(double offset) async {
    if (_controller == null || !_controller!.value.isInitialized) return;

    try {
      // 取消防抖定时器
      _exposureUpdateTimer?.cancel();

      final clampedOffset =
          offset.clamp(_minExposureOffset, _maxExposureOffset);

      // 立即设置
      await _controller!.setExposureOffset(clampedOffset);

      setState(() {
        _exposureOffset = clampedOffset;
      });
    } catch (e) {
      // 曝光设置失败，静默处理
    }
  }

  /// 处理曝光滑块拖拽
  void _handleExposurePanUpdate(DragUpdateDetails details) {
    // 重置定时器，保持滑块显示
    _focusTimer?.cancel();
    _focusTimer = Timer(const Duration(milliseconds: 3000), () {
      if (mounted) {
        setState(() {
          _isFocusing = false;
          _focusPosition = null;
          _showExposureSlider = false;
        });
      }
    });

    // 调整灵敏度，平衡响应速度和精确控制
    // 根据曝光范围动态调整灵敏度
    final double range = _maxExposureOffset - _minExposureOffset;
    final double sensitivity = range / 500.0; // 500像素对应整个范围，进一步降低灵敏度

    final double deltaY = details.delta.dy;
    final double newOffset = _exposureOffset - (deltaY * sensitivity);

    _setExposureOffset(newOffset);
  }

  /// 处理曝光滑块拖拽结束
  void _handleExposurePanEnd(DragEndDetails details) {
    // 手势结束时立即应用最终值，确保设置生效
    _setExposureOffsetImmediately(_exposureOffset);
  }

  /// 处理整个滑块区域的拖拽（更灵敏的操作）
  void _handleExposureSliderPanUpdate(DragUpdateDetails details) {
    // 重置定时器，保持滑块显示
    _focusTimer?.cancel();
    _focusTimer = Timer(const Duration(milliseconds: 3000), () {
      if (mounted) {
        setState(() {
          _isFocusing = false;
          _focusPosition = null;
          _showExposureSlider = false;
        });
      }
    });

    // 基于整个滑块区域计算相对位置
    const double sliderHeight = 160.0; // 滑块有效高度（200-40边距）
    final double range = _maxExposureOffset - _minExposureOffset;

    // 使用更直观的方式：直接基于滑块位置计算曝光值，但降低灵敏度
    final double deltaY = details.delta.dy;
    final double sensitivity =
        range / (sliderHeight * 2.5); // 进一步降低灵敏度，2.5倍的高度对应整个曝光范围

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

  /// 裁剪图片为4:3比例，保持拍摄方向
  Future<File> _cropImageTo43(File originalFile,
      {DeviceOrientation? deviceOrientation}) async {
    try {
      // 快速检查：如果不强制4:3比例，直接返回原图
      if (!widget.force43) {
        if (widget.enableLogs) {
          debugPrint('⚡ 跳过裁剪：未启用force43');
        }
        return originalFile;
      }

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

      // 若比例已匹配并允许直接返回，则不做重编码
      if (widget.returnOriginalOnMatch &&
          (currentRatio - targetRatioWhenExpected).abs() < 0.01) {
        if (widget.enableLogs) {
          debugPrint('⚡ 跳过处理：比例已匹配 ${currentRatio.toStringAsFixed(2)}');
        }
        return originalFile;
      }

      // 需要裁剪时，优化处理流程
      img.Image processed = decoded;

      // 只有在必要时才进行EXIF烘焙（这是最耗时的操作之一）
      // 尝试烘焙EXIF方向信息，失败则使用原图
      try {
        processed = img.bakeOrientation(decoded);
        if (widget.enableLogs) {
          debugPrint('🔄 EXIF烘焙完成');
        }
      } catch (e) {
        // EXIF烘焙失败，使用原图
        processed = decoded;
        if (widget.enableLogs) {
          debugPrint('⚠️ EXIF烘焙跳过');
        }
      }

      int originalWidth = processed.width;
      int originalHeight = processed.height;

      // 简化方向处理逻辑，减少不必要的旋转
      if (deviceOrientation != null && widget.enableLogs) {
        debugPrint(
            '🧭 方向: ${deviceOrientation.name}, 尺寸: ${originalWidth}x$originalHeight');
      }

      // 快速裁剪，不做额外旋转（现代相机通常已经处理好方向）
      final bool isLandscape = originalWidth >= originalHeight;
      final double targetRatio = isLandscape ? 4 / 3 : 3 / 4;

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
        processed,
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

      // 使用较低的质量以加快编码速度（用户可配置）
      final int quality = widget.jpegQuality > 90 ? 85 : widget.jpegQuality;
      await croppedFile.writeAsBytes(img.encodeJpg(cropped, quality: quality));

      if (widget.enableLogs) {
        debugPrint(
            '✂️ 裁剪完成 ${isLandscape ? '4:3' : '3:4'}: ${cropWidth}x$cropHeight');
      }
      return croppedFile;
    } catch (e) {
      debugPrint('❌ 图片裁剪失败: $e');
      return originalFile; // 返回原图
    }
  }

  /// 获取捕获方向（不依赖BuildContext，避免异步问题）
  Future<DeviceOrientation> _getCaptureOrientation() async {
    try {
      final NativeDeviceOrientation native =
          await NativeDeviceOrientationCommunicator()
              .orientation(useSensor: true);

      switch (native) {
        case NativeDeviceOrientation.landscapeLeft:
          return DeviceOrientation.landscapeLeft;
        case NativeDeviceOrientation.landscapeRight:
          return DeviceOrientation.landscapeRight;
        case NativeDeviceOrientation.portraitDown:
          return DeviceOrientation.portraitDown;
        case NativeDeviceOrientation.portraitUp:
          return DeviceOrientation.portraitUp;
        case NativeDeviceOrientation.unknown:
        default:
          // 手机平放或传感器无法确定方向时的容错处理
          debugPrint('⚠️ 传感器方向未知(native=${native.name})，可能是平放状态，使用默认横屏');
          // 按用户要求：如果无法识别横竖屏就默认横屏
          return DeviceOrientation.landscapeLeft;
      }
    } catch (e) {
      // 传感器读取失败时的终极容错
      debugPrint('❌ 传感器读取失败: $e，使用横屏默认方向');
      return DeviceOrientation.landscapeLeft; // 按用户要求默认横屏
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

      // 拍照
      final XFile picture = await _controller!.takePicture();

      File finalFile;
      if (widget.fastCaptureMode) {
        // 快速模式：直接使用原图，跳过所有处理
        finalFile = File(picture.path);
        if (widget.enableLogs) {
          debugPrint('⚡ 快速拍照模式：跳过图像处理，直接返回原图');
        }

        // 快速模式：异步保存，不阻塞返回
        _selectedImages.add(finalFile);
        _saveToGalleryAsync(finalFile);

        // 立即返回
        if (mounted) {
          Navigator.pop(context, _selectedImages);
        }
        return;
      } else {
        // 标准模式：进行方向检测和图像处理
        final DeviceOrientation captureOrientation =
            await _getCaptureOrientation();

        finalFile = await _cropImageTo43(
          File(picture.path),
          deviceOrientation: captureOrientation,
        );

        if (widget.enableLogs) {
          debugPrint('📸 标准拍照模式：已完成图像处理和方向纠正');
        }

        // 标准模式：同步保存到相册
        await ImageGallerySaver.saveFile(finalFile.path);
        _selectedImages.add(finalFile);
      }

      // 标准模式返回结果
      if (mounted) {
        Navigator.pop(context, _selectedImages);
      }
    } catch (e) {
      debugPrint('❌ 拍照失败: $e');
    } finally {
      _isCapturing = false;
    }
  }

  /// 异步保存到相册（不阻塞用户交互）
  void _saveToGalleryAsync(File file) {
    // 使用 Future.microtask 确保异步执行
    Future.microtask(() async {
      try {
        await ImageGallerySaver.saveFile(file.path);
        if (widget.enableLogs) {
          debugPrint('📱 后台保存到相册成功');
        }
      } catch (e) {
        if (widget.enableLogs) {
          debugPrint('⚠️ 后台保存到相册失败: $e');
        }
      }
    });
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

  double _uiAngle(BuildContext context) {
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
      case NativeDeviceOrientation.unknown:
      default:
        // 当方向未知时（平放状态），根据当前屏幕方向决定
        final Orientation currentOrientation =
            MediaQuery.of(context).orientation;
        return currentOrientation == Orientation.landscape ? math.pi / 2 : 0.0;
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
                    child: GestureDetector(
                      onPanUpdate: _handleExposureSliderPanUpdate,
                      onPanEnd: _handleExposurePanEnd,
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
                            const Positioned(
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
                            const Positioned(
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
                              left: 4, // 调整位置使滑块居中 (40-32)/2 = 4
                              top: 20 +
                                  (160 - 20) *
                                      (1 -
                                          (_exposureOffset -
                                                  _minExposureOffset) /
                                              (_maxExposureOffset -
                                                  _minExposureOffset)),
                              child: GestureDetector(
                                onPanUpdate: _handleExposurePanUpdate,
                                onPanEnd: _handleExposurePanEnd,
                                child: Container(
                                  width: 32, // 增大触摸区域
                                  height: 32,
                                  alignment: Alignment.center,
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
                            ),
                            // 曝光值显示
                            Positioned(
                              left: -15,
                              right: -15,
                              top: 20 +
                                  (160 - 20) *
                                      (1 -
                                          (_exposureOffset -
                                                  _minExposureOffset) /
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
                    turns: _uiAngle(context) / (2 * math.pi),
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
                      turns: _uiAngle(context) / (2 * math.pi),
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
                      turns: _uiAngle(context) / (2 * math.pi),
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
