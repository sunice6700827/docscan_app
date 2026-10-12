# 拍照扫描 App（DocScan）

一个夸克浏览器「拍照扫描」风格的原生手机 APP。**Flutter 跨平台工程（Android / iOS）**，文字与表格识别在**设备本地离线完成**（Tesseract 本地引擎，**不依赖 Google Play 服务，国产手机可用**），图片不会上传服务器。

## 功能一览

| 模块 | 功能 | 说明 |
|---|---|---|
| 文档扫描 | 拍照/相册 → 自动校正 → 提取文字 | 自动透视校正+增强，本地 OCR 支持中文/英文，可编辑、复制、导出为 txt |
| 表格识别 | 拍照/相册 → 自动校正 → 转成表格 | 按文字坐标自动分行分列，单元格可编辑，导出 CSV（Excel 可开） |
| 证件扫描 | 相册 → 四角矫正 → 保存 | 拖动四个角点对齐证件边缘，透视矫正为正面视图 |
| 图像处理 | 裁剪 / 增强 / 擦除 | 裁剪框拖拽、亮度/对比度/饱和度/锐化实时预览、涂抹擦除（去水印） |
| 多页PDF | 连续拍摄/相册多选 → 合并导出 | 拍摄自动透视校正，自动失败可手动拖四角校正，可排序，合并 A4 PDF，可分享或保存本机 |

## 技术栈

- Flutter (Material 3) + Dart
- `flutter_tesseract_ocr`：Tesseract 本地文字识别（离线、不依赖 Google Play 服务）
- `image`：图像解码、裁剪、增强、透视矫正、自动四角检测、擦除填充（纯 Dart，本地计算）
- `pdf`：多页图片合并导出 PDF
- `file_saver`：保存 PDF 到系统下载/文件目录
- `image_picker` / `share_plus` / `path_provider`

## 环境要求

- Flutter SDK **3.19 或更高**（`flutter --version` 查看）
- Android：Android Studio + JDK 17（构建 APK 用）
- iOS：macOS + Xcode（仅在你用 Mac 时构建 iOS 版）

## 构建步骤（三分钟跑起来）

本工程是**完整可构建的 Flutter 工程**，已包含 `android/`、`ios/` 平台骨架、Gradle 配置与 `lib/` 全部源码，无需再执行 `flutter create`，可直接打包。

**本地打包（需本机装 Flutter + Android Studio）：**
```bash
cd docscan_app
flutter pub get
flutter build apk --release        # Android 安装包（在 build/app/outputs/flutter-apk/）
```

## 一键自动打包 APK（GitHub Actions，无需本机装环境）

工程已附带 `.github/workflows/build_apk.yml`，把本工程推送到 GitHub，云端会自动构建 release APK，可在仓库 **Actions → Build Android APK → 该次运行 → Artifacts** 里下载：

1. 在 GitHub 新建一个仓库（New repository）
2. 本机把工程推到该仓库：
   ```bash
   git init && git add . && git commit -m "init"
   git remote add origin https://github.com/<你的用户名>/<仓库名>.git
   git push -u origin main
   ```
3. 打开仓库 **Actions** 页，等待任务跑完（约 3-5 分钟），点进运行记录，底部 **Artifacts** 处下载 `app-release-apk.zip`，解压即得 `app-release.apk`。

> 也可用 Gitee 码云 + 持续集成，或本地安装 Android Studio 后用 `flutter build apk --release` 直接打包。

## 平台权限配置

**Android**（本工程已附 `android/app/src/main/AndroidManifest.xml`，含以下权限）：
- `CAMERA`：拍照
- `READ_MEDIA_IMAGES` / `READ_EXTERNAL_STORAGE`：相册选图
- `INTERNET`：首次识别中文时需要联网下载 OCR 语言模型（模型下载后离线可用）

**iOS**（本工程已附 `ios/Runner/Info.plist`，含以下说明项）：
- `NSCameraUsageDescription`
- `NSPhotoLibraryUsageDescription`

## 使用说明与已知限制

1. **首次识别中文**：Android 首次运行中文识别会联网下载语言模型（Google Play Services 自动处理），之后离线可用。英文识别不依赖下载。若设备无 Google Play 服务，中文识别可能受限，建议换英文脚本或换有 GMS 的设备。
2. **表格识别**：基于 OCR 文字坐标自动分行分列，适合印刷体表格；手写或线框严重扭曲的表格识别精度有限，识别后可手动编辑单元格。
3. **证件矫正**：采用「手动拖动四角 + 透视矫正」方案（更可靠），透视校正由单应矩阵双线性采样实现，能纠正倾斜拍摄。
4. **擦除（去水印）**：为本地简化版「边缘颜色传播填充」，适合清除浅色水印、局部杂物；对大面积复杂纹理效果有限，专业去水印建议后续接入后端深度学习模型。
5. **识别精度**：与拍摄清晰度、光线强相关，建议贴近、正对拍摄。

## 隐私

所有识别与图像处理均在**设备本地**完成，无任何网络上传。唯一联网行为是首次下载 OCR 语言模型。

## 目录结构

```
docscan_app/
├── pubspec.yaml
├── README.md
├── android/app/src/main/AndroidManifest.xml   # Android 权限
├── ios/Runner/Info.plist                       # iOS 权限说明
└── lib/
    ├── main.dart                 # 入口
    ├── home/home_page.dart       # 主界面（功能宫格）
    ├── services/
    │   ├── pick_helper.dart      # 拍照/相册选图
    │   ├── ocr_service.dart      # ML Kit OCR 封装（真实识别）
    │   ├── image_service.dart    # 裁剪/增强/透视矫正/擦除
    │   └── export_service.dart   # 导出 txt / csv / 分享
    └── features/
        ├── document_scan/        # 文档扫描 + 文字提取
        ├── table_recognize/      # 表格识别
        ├── card_scan/            # 证件扫描
        └── image_process/        # 图像处理（裁剪/增强/擦除）
```
