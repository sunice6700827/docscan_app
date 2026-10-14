import 'dart:io';

import 'package:flutter/material.dart';

import '../../services/image_service.dart';
import '../../services/ocr_service.dart';
import '../../services/pick_helper.dart';
import 'text_result_page.dart';

class DocumentScanPage extends StatefulWidget {
  const DocumentScanPage({super.key});

  @override
  State<DocumentScanPage> createState() => _DocumentScanPageState();
}

class _DocumentScanPageState extends State<DocumentScanPage> {
  File? _imageFile;
  bool _busy = false;
  OcrLanguage _language = OcrLanguage.chinese;
  List<File> _history = [];

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    final h = await ImageService.listHistory();
    if (mounted) setState(() => _history = h);
  }

  /// 拍照/选图后自动处理：检测纸张边缘透视校正 + 轻度增强（像夸克拍完自动校正好）
  Future<File> _autoProcess(File file) async {
    try {
      var src = ImageService.decode(file);
      src = ImageService.downscaleForProcessing(src); // 缩到2400宽，显著提速，清晰度足够
      var out = src;
      final corners = ImageService.detectDocumentCorners(src);
      if (corners != null) {
        out = ImageService.perspectiveCorrect(src, corners);
        // 检测到纸张：校正 + 强增强（白纸黑字）
        out = ImageService.enhance(
          out,
          brightness: 0.02,
          contrast: 1.15,
          saturation: 0.95,
          sharpen: 0.5,
        );
      } else {
        // 未检测到纸张：温和增强兜底，避免原图灰暗/带背景（不做过曝的强增强）
        out = ImageService.enhance(
          out,
          brightness: 0.01,
          contrast: 1.08,
          saturation: 0.95,
          sharpen: 0.3,
        );
      }
      return await ImageService.savePng(out, name: 'enhanced');
    } catch (_) {
      return file;
    }
  }

  Future<void> _pick({required bool camera}) async {
    final file = camera ? await PickHelper.takePhoto() : await PickHelper.pickFromGallery();
    if (file == null || !mounted) return;
    final processed = await _autoProcess(file);
    if (!mounted) return;
    setState(() {
      _imageFile = processed;
      _language = OcrLanguage.chinese;
    });
    // 自动存入历史，返回后还能找到
    await ImageService.saveToHistory(ImageService.decode(processed));
    await _loadHistory();
  }

  void _openHistory(File f) {
    setState(() {
      _imageFile = f;
      _language = OcrLanguage.chinese;
    });
  }

  Future<void> _recognize() async {
    final file = _imageFile;
    if (file == null || _busy) return;
    setState(() => _busy = true);

    final service = OcrService(language: _language);
    try {
      final doc = await service.recognize(file);
      if (!mounted) return;
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => TextResultPage(
            document: doc,
            imageFile: file,
            language: _language,
          ),
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('识别失败：$e')),
        );
      }
    } finally {
      service.dispose();
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('文档扫描'),
        actions: [
          PopupMenuButton<OcrLanguage>(
            icon: const Icon(Icons.language),
            tooltip: '识别语言',
            onSelected: (v) => setState(() => _language = v),
            itemBuilder: (_) => [
              for (final lang in OcrLanguage.values)
                PopupMenuItem(
                  value: lang,
                  child: Text(lang == OcrLanguage.chinese ? '中文识别' : '英文识别'),
                ),
            ],
          ),
        ],
      ),
      body: _busy
          ? const Center(child: CircularProgressIndicator())
          : (_imageFile == null ? _buildEmpty() : _buildPreview()),
    );
  }

  Widget _buildEmpty() {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        if (_history.isNotEmpty) ...[
          Row(
            children: [
              const Text('最近扫描', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.delete_outline, size: 20),
                tooltip: '清空历史',
                onPressed: _clearHistory,
              ),
            ],
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 110,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _history.length,
              separatorBuilder: (_, __) => const SizedBox(width: 10),
              itemBuilder: (context, i) {
                final f = _history[i];
                return GestureDetector(
                  onTap: () => _openHistory(f),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: Image.file(f, width: 84, height: 110, fit: BoxFit.cover),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 24),
        ],
        const SizedBox(height: 40),
        Container(
          width: 88,
          height: 88,
          margin: const EdgeInsets.only(bottom: 20),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: const Color(0xFF2F6BFF).withOpacity(0.1),
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.document_scanner_outlined,
              color: Color(0xFF2F6BFF), size: 44),
        ),
        const Text('拍摄或选择一张文档图片',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        const Text('支持中文/英文识别，文字在本地识别，不上传服务器\n扫描结果会自动保存，返回后可在“最近扫描”找到',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: Color(0xFF8A9099))),
        const SizedBox(height: 28),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _ActionButton(
              icon: Icons.photo_camera_outlined,
              label: '拍照',
              onTap: () => _pick(camera: true),
            ),
            const SizedBox(width: 16),
            _ActionButton(
              icon: Icons.photo_library_outlined,
              label: '相册',
              onTap: () => _pick(camera: false),
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _clearHistory() async {
    final dir = await ImageService.scanHistoryDir();
    for (final f in dir.listSync().whereType<File>()) {
      try {
        f.deleteSync();
      } catch (_) {}
    }
    await _loadHistory();
  }

  Widget _buildPreview() {
    return Column(
      children: [
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Container(
                color: Colors.white,
                child: Image.file(
                  _imageFile!,
                  fit: BoxFit.contain,
                  width: double.infinity,
                  height: double.infinity,
                ),
              ),
            ),
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _pick(camera: false),
                    icon: const Icon(Icons.refresh),
                    label: const Text('重选'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: FilledButton.icon(
                    onPressed: _busy ? null : _recognize,
                    icon: const Icon(Icons.text_fields),
                    label: const Text('提取文字'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({required this.icon, required this.label, required this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        width: 116,
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFEDEFF2)),
        ),
        child: Column(
          children: [
            Icon(icon, color: const Color(0xFF2F6BFF), size: 28),
            const SizedBox(height: 8),
            Text(label, style: const TextStyle(fontSize: 14, color: Color(0xFF1F2329))),
          ],
        ),
      ),
    );
  }
}
