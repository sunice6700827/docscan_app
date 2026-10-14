import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../services/image_service.dart';
import '../../services/ocr_service.dart';
import '../../services/pick_helper.dart';
import 'table_result_page.dart';

/// 基于 OCR 行/元素坐标，将识别结果结构化为二维表格
List<List<String>> structureTable(OcrDocument doc) {
  if (doc.lines.isEmpty) return [];

  // 1) 按垂直位置排序
  final lines = [...doc.lines]..sort((a, b) => a.box.top.compareTo(b.box.top));

  // 估算中位行高，作为聚类阈值
  final heights = lines.map((l) => l.box.height).toList()
    ..sort();
  final medianH = heights.isEmpty ? 0.0 : heights[heights.length ~/ 2];
  final rowThreshold = math.max(6.0, medianH * 0.55);

  // 2) 聚合成视觉行
  final visualRows = <List<OcrLine>>[];
  for (final line in lines) {
    if (visualRows.isEmpty) {
      visualRows.add([line]);
      continue;
    }
    final lastRow = visualRows.last;
    final lastLine = lastRow.last;
    if ((line.box.top - lastLine.box.top) < rowThreshold) {
      lastRow.add(line);
    } else {
      visualRows.add([line]);
    }
  }

  // 3) 每个视觉行内，按水平位置把元素聚成单元格
  final table = <List<String>>[];
  for (final row in visualRows) {
    final allElements = <OcrElement>[];
    for (final l in row) {
      allElements.addAll(l.elements);
    }
    if (allElements.isEmpty) continue;
    allElements.sort((a, b) => a.box.left.compareTo(b.box.left));

    final cellGap = math.max(8.0, _estimateElementWidth(allElements) * 0.6);
    final cells = <String>[];
    var current = allElements.first.text;
    var prevRight = allElements.first.box.right;
    for (var i = 1; i < allElements.length; i++) {
      final e = allElements[i];
      if ((e.box.left - prevRight) > cellGap) {
        cells.add(current);
        current = e.text;
      } else {
        current += e.text;
      }
      prevRight = e.box.right;
    }
    cells.add(current);
    table.add(cells);
  }
  return table;
}

double _estimateElementWidth(List<OcrElement> els) {
  final ws = els.map((e) => e.box.width).toList()..sort();
  if (ws.isEmpty) return 20;
  return ws[ws.length ~/ 2];
}

class TableRecognizePage extends StatefulWidget {
  const TableRecognizePage({super.key});

  @override
  State<TableRecognizePage> createState() => _TableRecognizePageState();
}

class _TableRecognizePageState extends State<TableRecognizePage> {
  File? _imageFile;
  bool _busy = false;

  /// 拍照/选图后自动处理：透视校正 + 轻度增强
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
    setState(() => _imageFile = processed);
  }

  Future<void> _recognize() async {
    final file = _imageFile;
    if (file == null || _busy) return;
    setState(() => _busy = true);

    final ocr = OcrService(language: OcrLanguage.chinese);
    try {
      final doc = await ocr.recognize(file);
      final table = structureTable(doc);
      if (!mounted) return;
      if (table.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('未能识别到表格内容，请换一张更清晰的图片')),
        );
        return;
      }
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => TableResultPage(table: table, imageFile: file),
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('识别失败：$e')));
      }
    } finally {
      ocr.dispose();
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('表格识别')),
      body: _busy
          ? const Center(child: CircularProgressIndicator())
          : (_imageFile == null ? _buildEmpty() : _buildPreview()),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 88,
              height: 88,
              decoration: BoxDecoration(
                color: const Color(0xFF00A870).withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.table_chart_outlined, color: Color(0xFF00A870), size: 44),
            ),
            const SizedBox(height: 20),
            const Text('拍摄或选择一张表格图片',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            const Text('自动识别行列结构，可编辑并导出为 CSV/Excel',
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
        ),
      ),
    );
  }

  Widget _buildPreview() {
    return Column(
      children: [
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Image.file(_imageFile!, fit: BoxFit.contain,
                  width: double.infinity, height: double.infinity),
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
                    icon: const Icon(Icons.table_chart_outlined),
                    label: const Text('识别表格'),
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
            Icon(icon, color: const Color(0xFF00A870), size: 28),
            const SizedBox(height: 8),
            Text(label, style: const TextStyle(fontSize: 14, color: Color(0xFF1F2329))),
          ],
        ),
      ),
    );
  }
}
