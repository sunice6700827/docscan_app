import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/export_service.dart';
import '../../services/ocr_service.dart';

class TextResultPage extends StatefulWidget {
  const TextResultPage({
    super.key,
    required this.document,
    required this.imageFile,
    required this.language,
  });

  final OcrDocument document;
  final File imageFile;
  final OcrLanguage language;

  @override
  State<TextResultPage> createState() => _TextResultPageState();
}

class _TextResultPageState extends State<TextResultPage> {
  late final TextEditingController _controller;
  late int _charCount;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.document.fullText);
    _charCount = _controller.text.replaceAll('\n', '').length;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: _controller.text));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已复制到剪贴板')));
    }
  }

  Future<void> _export() async {
    final file = await ExportService.saveText(_controller.text);
    if (!mounted) return;
    await ExportService.shareFile(file, text: '导出扫描文本');
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已生成并分享文本文件')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('文字提取结果'),
        actions: [
          IconButton(onPressed: _copy, icon: const Icon(Icons.copy_all_outlined), tooltip: '复制'),
          IconButton(onPressed: _export, icon: const Icon(Icons.ios_share), tooltip: '导出/分享'),
        ],
      ),
      body: Column(
        children: [
          Container(
            margin: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFF2F6BFF).withOpacity(0.08),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                const Icon(Icons.check_circle_outline, size: 18, color: Color(0xFF2F6BFF)),
                const SizedBox(width: 8),
                Text(
                  '识别到 ${widget.document.lineCount} 行 · $_charCount 字（${widget.language == OcrLanguage.chinese ? '中文' : '英文'}）',
                  style: const TextStyle(fontSize: 13, color: Color(0xFF2F6BFF)),
                ),
              ],
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: TextField(
                controller: _controller,
                maxLines: null,
                expands: true,
                textAlignVertical: TextAlignVertical.top,
                style: const TextStyle(fontSize: 15, height: 1.6),
                decoration: InputDecoration(
                  filled: true,
                  fillColor: Colors.white,
                  hintText: '识别出的文字（可编辑）',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide.none,
                  ),
                ),
                onChanged: (v) =>
                    setState(() => _charCount = v.replaceAll('\n', '').length),
              ),
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _copy,
                      icon: const Icon(Icons.copy_all_outlined),
                      label: const Text('复制全文'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: FilledButton.icon(
                      onPressed: _export,
                      icon: const Icon(Icons.ios_share),
                      label: const Text('导出为文本'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
