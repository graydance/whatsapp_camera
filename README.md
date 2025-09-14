# whatsapp_camera

<p>
📷 一个功能完整的相机包，提供WhatsApp风格的拍照体验，包含可靠的点击聚焦功能
</p>
<p>
✨ 现在使用Flutter官方camera包，确保最佳的兼容性和稳定性；默认拍摄比例固定为 4:3（竖屏为 3:4）
</p>
<p>
🎯 特色：完美的点击聚焦 + 触觉反馈 + 相册集成
</p>

## ⚠️ 重要更新

**v2.0.0**: 我们已从`camerawesome`迁移到 Flutter 官方`camera`包，以解决聚焦功能问题。新版本提供：

- ✅ **可靠的点击聚焦**: 真正有效的相机聚焦功能
- ✅ **触觉反馈**: 点击时的震动反馈
- ✅ **完美兼容**: 支持所有 Flutter 版本
- ✅ **API 不变**: 现有代码无需修改

### how to use

Open camera:

```dart
List<File>? res = await Navigator.push(
  context, MaterialPageRoute(
    builder: (context) => const WhatsappCamera(),
  ),
);
```

### ✨ 核心功能特性

- 🎯 **完美聚焦** - 点击屏幕任意位置实现精准聚焦，真正有效！
- ☀️ **智能亮度调整** - iOS 风格的曝光补偿滑块，聚焦时右侧显示亮度调节滑块
- 🔍 **两指缩放** - 支持两指捏合缩放，实时显示缩放倍数，完全仿照 iOS 相机体验
- 📱 **无变形预览** - 预览固定为 4:3（竖屏为 3:4），与最终成片一致，无变形
- 📸 **固定 4:3 拍照** - 成片自动裁剪为 4:3（竖屏 3:4），同时保持横/竖方向
- 🖼️ **相册集成** - 无缝访问设备相册选择照片
- 🔄 **双摄像头** - 前后摄像头自由切换
- 💡 **智能闪光灯** - 自动/开启/关闭/手电筒模式
- 📳 **触觉反馈** - 点击时的震动反馈，提升用户体验
- 🎨 **视觉反馈** - 专业的聚焦指示器动画
- 💾 **自动保存** - 拍摄的照片自动保存到相册

### 使用说明 (Usage Instructions)

**点击聚焦功能：**

- 在相机预览界面点击任意位置进行**像素级精准聚焦**
- **重新设计坐标系统**：基于 AspectRatio 组件的实际布局行为，确保点击位置和聚焦位置完全一致
- **多指检测优化**：30ms 延迟检测机制，彻底避免双指缩放时误触发聚焦
- 智能区域检测：只在实际预览区域内响应点击，自动忽略黑边区域
- **简化算法**：移除复杂的安全区域计算，直接基于屏幕坐标和预览布局
- 会出现白色聚焦框动画指示聚焦位置
- 聚焦框会在 1.5 秒后自动消失
- 触觉反馈：点击时有轻微震动反馈，提升用户体验
- 兼容现代设备的连续自动聚焦系统
- 支持实时调试信息输出，方便开发者排查问题

**亮度调整功能：**

- 点击聚焦时，聚焦框右侧自动显示亮度调整滑块
- iOS 原生相机风格的垂直滑块设计，支持上下拖拽调节亮度
- 滑块顶部显示太阳图标（增加亮度），底部显示月亮图标（降低亮度）
- 实时显示当前曝光补偿数值，范围通常为 -4.0 到 +4.0
- 拖拽滑块时自动延长显示时间，确保调整体验流畅
- 切换摄像头时自动重置曝光值，适配不同摄像头的特性

**两指缩放功能：**

- 支持标准的两指捏合手势进行缩放，与 iOS 原生相机体验完全一致
- **智能手势识别**：只有两指及以上手势才激活缩放，避免误触
- **双重防护机制**：Scale 事件标记 + TapDown 延迟检测，确保多指操作时绝不触发聚焦
- 实时显示当前缩放倍数，缩放范围通常为 1.0x 到 10.0x
- 缩放倍数大于 1.0x 时，屏幕上方自动显示缩放指示器
- 切换摄像头时自动重置缩放级别，适配不同摄像头的缩放能力
- 缩放操作流畅顺滑，无延迟感
- 手势结束时自动清理状态，确保下次操作正常

**预览和拍摄一致性：**

- **固定显示比例**：预览固定为 4:3（竖屏为 3:4），避免任何拉伸变形
- **所见即所得**：预览与成片比例一致。横屏拍摄输出横向 4:3，竖屏拍摄输出竖向 3:4
- 使用 AspectRatio + 居中裁切，预览区域可能出现黑边（与 iOS 相机类似）
- **方向正确**：自动烘焙 EXIF 方向，确保相册中显示方向与拍摄时一致
- **高质量拍摄**：使用 veryHigh 分辨率，先拍原图后高质量裁剪为 4:3/3:4

### 技术特性 (Technical Features)

**🏗️ 技术架构：**

- 📦 **Flutter 官方 camera**: 使用官方维护的 camera 包，确保长期稳定性
- 🎯 **真实聚焦 API**: 调用`setFocusPoint`和`setExposurePoint`实现真正聚焦
- ☀️ **专业曝光控制**: 使用`setExposureOffset`API 实现精准的曝光补偿调整
- 🔍 **智能缩放系统**: 使用`setZoomLevel`API 实现平滑缩放，支持多指手势识别和状态管理
- 🎨 **iOS 风格 UI**: 完全仿照 iOS 原生相机的亮度调节滑块和缩放指示器设计
- 📱 **智能预览适配**: 使用相机原生比例显示预览，确保画面无变形，聚焦位置像素级准确
- 🔧 **开发友好**: 详细的控制台日志输出，包含分辨率、宽高比、缩放范围等调试信息
- ⚡ **高性能**: veryHigh 分辨率 + JPEG 格式，最佳画质和兼容性
- 💫 **用户体验**: 视觉动画 + 触觉震动 + 流畅交互 + 多点触控，媲美原生应用
- 🛡️ **类型安全**: 完整的类型检查，避免运行时错误
- 🔄 **向后兼容**: API 保持不变，现有代码无需修改

<br>

Open image:

```dart
Navigator.push(
  context, MaterialPageRoute(
    builder: (context) => const ViewImage(
      image: 'https://...',
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

<a target="_blank" href="https://github.com/welitonsousa/whatsapp_camera/blob/main/LICENSE">LICENSE</a>

<br>
<br>
<p align="center">
   Feito com ❤️ by <a target="_blank" href="https://github.com/welitonsousa"><b>Weliton Sousa</b></a>
</p>
