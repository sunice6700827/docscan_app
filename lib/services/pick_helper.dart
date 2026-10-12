import 'dart:io';

import 'package:image_picker/image_picker.dart';

/// 拍照 / 相册选图工具（内部基于 image_picker，权限自动处理）
class PickHelper {
  /// 从系统相册选择一张图片
  static Future<File?> pickFromGallery() async {
    final picker = ImagePicker();
    final x = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 95,
      maxWidth: 2600,
      maxHeight: 2600,
    );
    if (x == null) return null;
    return File(x.path);
  }

  /// 调用相机拍摄一张图片
  static Future<File?> takePhoto() async {
    final picker = ImagePicker();
    final x = await picker.pickImage(
      source: ImageSource.camera,
      imageQuality: 95,
      maxWidth: 2600,
      maxHeight: 2600,
    );
    if (x == null) return null;
    return File(x.path);
  }
}
