# WhatsApp Camera Plugin

一个模仿 WhatsApp 相机界面的 Flutter 插件，为用户提供简化的拍照和图片选择体验。

## 🚀 项目简介

这是一个专业的 Flutter 相机插件，集成了以下核心功能：

- **相机拍照** - 支持前后摄像头切换、闪光灯控制
- **图片选择** - 一键打开相册选择多张图片
- **图片预览** - 优雅的图片查看器
- **多选支持** - 可配置单选或多选模式

## 📱 功能特性

### 主要功能

- ✅ 高质量相机拍照
- ✅ 图片库选择（支持多选）
- ✅ 实时相机预览
- ✅ 前后摄像头切换
- ✅ 闪光灯控制
- ✅ 图片自动保存到相册
- ✅ 现代化 UI 设计
- ✅ 权限自动管理

### 技术特性

- 🔧 基于 CameraAwesome 插件，性能优异
- 🔧 支持不同宽高比（4:3, 1:1, 16:9）
- 🔧 自适应屏幕尺寸
- 🔧 优化的内存管理

## 🛠 安装配置

### 1. 添加依赖

在 `pubspec.yaml` 中添加：

```yaml
dependencies:
  whatsapp_camera: ^1.0.0
```

### 2. Android 配置

在 `android/app/src/main/AndroidManifest.xml` 中添加权限：

```xml
<uses-permission android:name="android.permission.CAMERA" />
<uses-permission android:name="android.permission.WRITE_EXTERNAL_STORAGE" />
<uses-permission android:name="android.permission.READ_EXTERNAL_STORAGE" />
<application
  android:requestLegacyExternalStorage="true"
  ...
```

在 `android/app/build.gradle` 中设置：

```gradle
minSdkVersion 21
compileSdkVersion 34
```

### 3. iOS 配置

在 `ios/Runner/Info.plist` 中添加权限描述：

```xml
<key>NSCameraUsageDescription</key>
<string>此应用需要使用相机来拍照</string>
<key>NSPhotoLibraryUsageDescription</key>
<string>此应用需要访问相册来选择图片</string>
```

## 📖 使用方法

### 打开相机拍照

```dart
// 支持多选模式（默认）
List<File>? images = await Navigator.push(
  context,
  MaterialPageRoute(
    builder: (context) => const WhatsappCamera(multiple: true),
  ),
);

// 单选模式
List<File>? image = await Navigator.push(
  context,
  MaterialPageRoute(
    builder: (context) => const WhatsappCamera(multiple: false),
  ),
);

// 处理返回的图片
if (images != null && images.isNotEmpty) {
  for (File imageFile in images) {
    print('选择的图片路径: ${imageFile.path}');
    // 在这里处理您的图片
  }
}
```

### 图片预览

```dart
Navigator.push(
  context,
  MaterialPageRoute(
    builder: (context) => const ViewImage(
      image: 'path/to/image.jpg',
      imageType: ImageType.file,
    ),
  ),
);

// 网络图片预览
Navigator.push(
  context,
  MaterialPageRoute(
    builder: (context) => const ViewImage(
      image: 'https://example.com/image.jpg',
      imageType: ImageType.network,
    ),
  ),
);
```

<p align="center">
<img  src="https://github.com/welitonsousa/whatsapp_camera/blob/main/assets/example.gif?raw=true" width="250" height="500"/>
</p>

<hr>

## Android

add permissions: <br>
<b>file:</b> `/android/app/main/AndroidManifest.xml`

```dart
<uses-permission android:name="android.permission.WRITE_EXTERNAL_STORAGE" />
<uses-permission android:name="android.permission.READ_EXTERNAL_STORAGE" />
<application
  android:requestLegacyExternalStorage="true"
  ...
```

<b>file:</b> `android/app/build.gradle`

```dart
minSdkVersion 21
compileSdkVersion 33
```

## ios

<b>file:</b> `/ios/Runner/Info.plist`

```dart
<key>NSCameraUsageDescription</key>
<string>Can I use the camera please?</string>
<key>NSPhotoLibraryUsageDescription</key>
<string>Used to demonstrate image picker plugin</string>
```

## 🎯 API 参考

### WhatsappCamera 参数

| 参数       | 类型   | 默认值  | 描述             |
| ---------- | ------ | ------- | ---------------- |
| `multiple` | `bool` | `false` | 是否支持多选图片 |

### ViewImage 参数

| 参数        | 类型        | 必需 | 描述                     |
| ----------- | ----------- | ---- | ------------------------ |
| `image`     | `String`    | ✅   | 图片路径或 URL           |
| `imageType` | `ImageType` | ✅   | 图片类型（file/network） |

### ImageType 枚举

```dart
enum ImageType {
  file,    // 本地文件
  network, // 网络图片
}
```

## 🔧 技术架构

### 核心依赖

- **camerawesome**: 2.0.1 - 高性能相机插件
- **camera**: 0.10.5+9 - Flutter 官方相机包
- **file_picker**: 10.2.1 - 文件选择器
- **permission_handler**: 12.0.0+1 - 权限管理
- **image_gallery_saver**: 2.0.3 - 图片保存到相册

### 项目结构

```
lib/
├── camera/
│   ├── camera_whatsapp.dart  # 主相机组件
│   └── view_image.dart       # 图片查看器
└── whatsapp_camera.dart      # 插件导出文件
```

## ⚠️ 常见问题 & 解决方案

### 1. Flutter 3.32.0+ 构建错误

**问题**: 遇到 `app_plugin_loader.gradle` 相关错误

**解决方案**: 已在最新版本中修复。更新了 Gradle 配置以支持新的插件系统：

- 更新了 `example/android/settings.gradle` 使用新的声明式插件块
- 更新了 `example/android/app/build.gradle` 使用新的插件语法
- 移除了过时的 `apply from` 语句

如果您在现有项目中遇到此问题，请参考示例项目的 Gradle 配置文件。

### 2. 权限被拒绝

**问题**: 应用崩溃或无法访问相机/相册

**解决方案**:

- 确保正确添加了所有必需的权限声明
- 在 Android 6.0+设备上首次使用时会自动请求权限
- 检查设备设置中是否手动禁用了相关权限

### 3. 图片质量问题

**问题**: 拍摄的图片质量不理想

**解决方案**:

- 插件默认使用高质量设置
- 可以通过修改 CameraAwesome 配置来调整画质
- 确保设备有足够的存储空间

## 🚦 版本兼容性

| Flutter 版本  | 插件版本 | 状态        |
| ------------- | -------- | ----------- |
| 3.32.0+       | 1.0.0+   | ✅ 完全支持 |
| 3.16.0-3.31.x | 1.0.0+   | ✅ 支持     |
| 3.0.0-3.15.x  | 1.0.0+   | ⚠️ 部分支持 |
| < 3.0.0       | -        | ❌ 不支持   |

## 📝 更新日志

### v1.0.0 (2024-12-29)

- 🎉 首次发布
- ✅ 修复 Flutter 3.32.0+构建问题
- ✅ 更新 Gradle 配置为新的插件系统
- ✅ 优化相机性能和内存使用
- ✅ 改进文档和示例代码

## 🤝 贡献指南

欢迎提交 Issue 和 Pull Request！

1. Fork 这个仓库
2. 创建您的功能分支 (`git checkout -b feature/AmazingFeature`)
3. 提交您的更改 (`git commit -m 'Add some AmazingFeature'`)
4. 推送到分支 (`git push origin feature/AmazingFeature`)
5. 打开一个 Pull Request

## 📄 许可证

<a target="_blank" href="https://github.com/welitonsousa/whatsapp_camera/blob/main/LICENSE">MIT License</a>

## 👨‍💻 作者

<p align="center">
   由 <a target="_blank" href="https://github.com/welitonsousa"><b>Weliton Sousa</b></a> 用 ❤️ 制作
</p>
