// ⚠️ 此文件已弃用 (DEPRECATED)
//
// 由于 camerawesome 包存在聚焦功能问题和类型兼容性问题，
// 我们已改用基于 Flutter 官方 camera 包的实现。
//
// 请使用新的实现：
// import 'package:whatsapp_camera/whatsapp_camera.dart';
//
// 新的 WhatsappCamera 组件提供：
// ✅ 可靠的点击聚焦功能
// ✅ 触觉反馈
// ✅ 完整的类型安全
// ✅ 与所有 Flutter 版本兼容

import 'package:flutter/material.dart';

@Deprecated('此类已弃用，请使用 OfficialWhatsappCamera')
class WhatsappCameraDeprecated extends StatelessWidget {
  final bool multiple;

  const WhatsappCameraDeprecated({super.key, this.multiple = false});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.red,
        title: const Text('已弃用的实现'),
      ),
      body: const Center(
        child: Padding(
          padding: EdgeInsets.all(20),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.warning,
                color: Colors.orange,
                size: 80,
              ),
              SizedBox(height: 20),
              Text(
                '此实现已弃用',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
              SizedBox(height: 10),
              Text(
                '请使用新的 WhatsappCamera 组件',
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 16,
                ),
                textAlign: TextAlign.center,
              ),
              SizedBox(height: 20),
              Text(
                '新版本提供可靠的聚焦功能和更好的兼容性',
                style: TextStyle(
                  color: Colors.white54,
                  fontSize: 14,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
