import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;

import '../../services/export_service.dart';
import '../../services/image_service.dart';
import '../../services/pick_helper.dart';
import 'crop_page.dart';
import 'enhance_page.dart';
import 'eraser_page.dart';

class ImageProcessPage extends StatefulWidget {
  const ImageProcessPage({super.key});

  @override
  State<ImageProcessPage> createState() => _ImageProcessPageState();
}

class _ImageProcessPageState extends State<ImageProcessPage> {
  img.Image? _image;
  final List<img.Image> _history = [];

  Future<void> _pick() async {
    final file = await PickHelper.pickFromGallery();
    if (file == null || !mounted) return;
    final decoded = ImageService.thumb(ImageService.decode(file), maxSide: 1800);
    setState(() {
      _history.clear();
      _image = decoded;
    });
  }

  void _replace(img.Image next) {
    setState(() {
      if (_image != null) _history.add(_image!);
      if (_history.length > 8) _history.removeAt(0);
      _image = next;
    });
  }

  void _undo() {
    if (_history.isEmpty) return;
    setState(() => _image = _history.removeLast());
  }

  Future<void> _save() async {
    final image = _image;
    if (image == null) return;
    final file = await ImageService.savePng(image, name: 'processed');
    if (!mounted) return;
    await ExportService.shareFile(file, text: '保存处理图片');
  }

  Future<void> _open(Widget page) async {
    final image = _image;
    if (image == null) return;
    final result = await Navigator.of(context).push<img.Image>(
      MaterialPageRoute(builder: (_) => page),
    );
    if (result != null && mounted) _replace(result);
  }

  @override
  Widget build(BuildContext context) {
    final image = _image;
    return Scaffold(
      appBar: AppBar(title: const Text('图像处理')),
      body: image == null ? _buildEmpty() : _buildEditor(image),
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
                color: const Color(0xFFB45BFF).withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.auto_fix_high_outlined, color: Color(0xFFB45BFF), size: 44),
            ),
            const SizedBox(height: 20),
            const Text('选择一张图片开始处理',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            const Text('支持裁剪、亮度/对比度增强、锐化、涂抹擦除',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: Color(0xFF8A9099))),
            const SizedBox(height: 28),
            FilledButton.icon(
              onPressed: _pick,
              icon: const Icon(Icons.photo_library_outlined),
              label: const Text('从相册选择'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEditor(img.Image image) {
    return Column(
      children: [
        Expanded(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.memory(
                  _toBytes(image),
                  fit: BoxFit.contain,
                  gaplessPlayback: true,
                ),
              ),
            ),
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _Tool(icon: Icons.crop, label: '裁剪', onTap: () => _open(CropPage(initial: image))),
                _Tool(icon: Icons.tune, label: '增强', onTap: () => _open(EnhancePage(initial: image))),
                _Tool(icon: Icons.auto_fix_normal, label: '擦除', onTap: () => _open(EraserPage(initial: image))),
                _Tool(icon: Icons.undo, label: '撤销', onTap: _history.isEmpty ? null : _undo),
                _Tool(icon: Icons.save_alt, label: '保存', onTap: _save),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Uint8List _toBytes(img.Image image) => img.encodePng(image);
}

class _Tool extends StatelessWidget {
  const _Tool({required this.icon, required this.label, required this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        child: Column(
          children: [
            Icon(icon, size: 24, color: enabled ? const Color(0xFF1F2329) : const Color(0xFFC0C4CC)),
            const SizedBox(height: 4),
            Text(label,
                style: TextStyle(
                  fontSize: 12,
                  color: enabled ? const Color(0xFF1F2329) : const Color(0xFFC0C4CC),
                )),
          ],
        ),
      ),
    );
  }
}
