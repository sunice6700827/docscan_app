import 'dart:io';

import 'package:file_saver/file_saver.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../services/export_service.dart';
import '../../services/image_service.dart';
import '../../services/pdf_merge_service.dart';
import '../../services/pick_helper.dart';
import 'manual_correct_page.dart';

/// 多页拍摄 → 合并导出 PDF
class MultiPagePdfPage extends StatefulWidget {
  const MultiPagePdfPage({super.key});

  @override
  State<MultiPagePdfPage> createState() => _MultiPagePdfPageState();
}

class _MultiPagePdfPageState extends State<MultiPagePdfPage> {
  final List<File> _pages = [];
  bool _busy = false;

  /// 拍摄/选图后自动透视校正 + 增强：检测到可靠文档四角则矫正并提亮增强，否则保留原图
  Future<File> _autoCorrect(File file) async {
    try {
      var decoded = ImageService.decode(file);
      decoded = ImageService.downscaleForProcessing(decoded); // 缩到2400宽，显著提速，清晰度足够
      var out = decoded;
      final corners = ImageService.detectDocumentCorners(decoded);
      if (corners != null) {
        out = ImageService.perspectiveCorrect(decoded, corners);
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
      return await ImageService.savePng(out, name: 'page');
    } catch (_) {
      return file;
    }
  }

  Future<void> _addCamera() async {
    final file = await PickHelper.takePhoto();
    if (file == null || !mounted) return;
    setState(() => _pages.add(file));
    final corrected = await _autoCorrect(file);
    if (mounted) setState(() => _pages[_pages.length - 1] = corrected);
  }

  Future<void> _addGalleryMulti() async {
    final picker = ImagePicker();
    final xs = await picker.pickMultiImage(
      imageQuality: 95,
      maxWidth: 2600,
      maxHeight: 2600,
    );
    if (xs == null || xs.isEmpty) return;
    for (final x in xs) {
      final f = File(x.path);
      final corrected = await _autoCorrect(f);
      if (mounted) setState(() => _pages.add(corrected));
    }
  }

  Future<void> _correctPage(int index) async {
    final file = await Navigator.of(context).push<File>(
      MaterialPageRoute(builder: (_) => ManualCorrectPage(imageFile: _pages[index])),
    );
    if (file != null && mounted) setState(() => _pages[index] = file);
  }

  Future<void> _merge() async {
    if (_pages.isEmpty || _busy) return;
    setState(() => _busy = true);
    try {
      final file = await PdfMergeService.mergeToPdf(_pages);
      if (!mounted) return;
      final action = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text('合并完成（${_pages.length} 页）'),
          content: const Text('PDF 已生成，请选择下一步操作：'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop('save'),
              child: const Text('保存到本机'),
            ),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop('share'),
              child: const Text('分享'),
            ),
          ],
        ),
      );
      if (action == 'share') {
        await ExportService.shareFile(file, text: '分享合并 PDF');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('已生成并分享 PDF（共 ${_pages.length} 页）')),
          );
        }
      } else if (action == 'save') {
        await FileSaver.instance.saveFile(
          name: '拍照扫描文档.pdf',
          bytes: await file.readAsBytes(),
          mimeType: MimeType.pdf,
        );
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('已保存到本机（下载/文件目录），共 ${_pages.length} 页')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('合并失败：$e')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('多页合并 PDF')),
      body: _pages.isEmpty ? _buildEmpty() : _buildList(),
      bottomNavigationBar: _pages.isEmpty ? null : _buildBottomBar(),
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
                color: const Color(0xFF2F6BFF).withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.picture_as_pdf_outlined, color: Color(0xFF2F6BFF), size: 44),
            ),
            const SizedBox(height: 20),
            const Text('连续拍摄或选择多张图片',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            const Text('支持逐页拍摄、相册多选，可拖动调整顺序，合并为一个 PDF',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: Color(0xFF8A9099))),
            const SizedBox(height: 28),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _ActionButton(
                  icon: Icons.photo_camera_outlined,
                  label: '逐页拍摄',
                  onTap: _addCamera,
                ),
                const SizedBox(width: 16),
                _ActionButton(
                  icon: Icons.photo_library_outlined,
                  label: '相册多选',
                  onTap: _addGalleryMulti,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildList() {
    return ReorderableListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: _pages.length,
      onReorder: (oldI, newI) {
        setState(() {
          if (newI > oldI) newI -= 1;
          final item = _pages.removeAt(oldI);
          _pages.insert(newI, item);
        });
      },
      itemBuilder: (context, index) {
        return Padding(
          key: ValueKey(_pages[index].path),
          padding: const EdgeInsets.only(bottom: 8),
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFEDEFF2)),
            ),
            child: ListTile(
              leading: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.file(
                  _pages[index],
                  width: 52,
                  height: 52,
                  fit: BoxFit.cover,
                ),
              ),
              title: Text('第 ${index + 1} 页',
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
              subtitle: const Text('长按拖动可排序 · 点校正图标调整四角',
                  style: TextStyle(fontSize: 12, color: Color(0xFF8A9099))),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(Icons.crop_free, color: Color(0xFF2F6BFF)),
                    tooltip: '手动校正四角',
                    onPressed: () => _correctPage(index),
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete_outline, color: Color(0xFFC0C4CC)),
                    onPressed: () => setState(() => _pages.removeAt(index)),
                  ),
                ],
              ),
              onTap: () => _correctPage(index),
            ),
          ),
        );
      },
    );
  }

  Widget _buildBottomBar() {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _addCamera,
                icon: const Icon(Icons.photo_camera_outlined),
                label: const Text('加页'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              flex: 2,
              child: FilledButton.icon(
                onPressed: _busy ? null : _merge,
                icon: _busy
                    ? const SizedBox(
                        width: 18, height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.picture_as_pdf),
                label: Text(_busy ? '合并中…' : '合并为 PDF（$_len 页）'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  int get _len => _pages.length;
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
