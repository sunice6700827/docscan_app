import 'dart:io';
import 'dart:ui' show Offset, Size, Rect;

import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;

import '../../services/export_service.dart';
import '../../services/image_service.dart';
import '../../services/pick_helper.dart';

class CardScanPage extends StatefulWidget {
  const CardScanPage({super.key});

  @override
  State<CardScanPage> createState() => _CardScanPageState();
}

class _CardScanPageState extends State<CardScanPage> {
  File? _imageFile;
  Size? _imageSize; // 原始图片尺寸
  List<Offset>? _corners; // 屏幕显示坐标的 4 个角点（TL,TR,BR,BL）
  Rect? _editRect; // 编辑时图片显示区域（供矫正换算像素坐标）
  bool _busy = false;

  static const _cornerColor = Color(0xFF2F6BFF);

  Future<void> _pick() async {
    final file = await PickHelper.pickFromGallery();
    if (file == null || !mounted) return;
    final decoded = ImageService.decode(file);
    setState(() {
      _imageFile = file;
      _imageSize = Size(decoded.width.toDouble(), decoded.height.toDouble());
      _corners = null;
    });
  }

  /// 计算 contain 显示矩形
  Rect _containRect(Size imageSize, Size boxSize) {
    final scale = (boxSize.width / imageSize.width) < (boxSize.height / imageSize.height)
        ? boxSize.width / imageSize.width
        : boxSize.height / imageSize.height;
    final w = imageSize.width * scale;
    final h = imageSize.height * scale;
    return Rect.fromLTWH((boxSize.width - w) / 2, (boxSize.height - h) / 2, w, h);
  }

  Future<void> _correct() async {
    if (_imageFile == null || _corners == null || _busy) return;
    final rect = _editRect;
    if (rect == null) return;
    final scale = rect.width / _imageSize!.width;
    final cornersPx = _corners!.map((p) => Offset((p.dx - rect.left) / scale, (p.dy - rect.top) / scale)).toList();

    setState(() => _busy = true);
    try {
      final decoded = ImageService.decode(_imageFile!);
      final corrected = ImageService.perspectiveCorrect(decoded, cornersPx);
      final file = await ImageService.savePng(corrected, name: 'card');
      if (!mounted) return;
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => CardResultPage(resultFile: file, corrected: corrected),
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('矫正失败：$e')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('证件扫描')),
      body: _imageFile == null ? _buildEmpty() : _buildEditor(),
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
                color: const Color(0xFFFF8A00).withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.badge_outlined, color: Color(0xFFFF8A00), size: 44),
            ),
            const SizedBox(height: 20),
            const Text('选择一张证件或卡片照片',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            const Text('拖动四个角点对齐证件边缘，自动矫正为正面视图并保存',
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

  Widget _buildEditor() {
    return Column(
      children: [
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Container(
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.92),
                borderRadius: BorderRadius.circular(16),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    // 四周留出手柄空间，避免四角按钮跑到屏幕边缘按不到
                    const pad = 28.0;
                    final box = Size(
                      constraints.maxWidth - pad * 2,
                      constraints.maxHeight - pad * 2,
                    );
                    final rect = _containRect(_imageSize!, box).shift(const Offset(pad, pad));
                    _editRect = rect;
                    final corners = _corners ??
                        (() {
                          final c = [
                            rect.topLeft,
                            rect.topRight,
                            rect.bottomRight,
                            rect.bottomLeft,
                          ];
                          WidgetsBinding.instance.addPostFrameCallback((_) {
                            if (mounted) setState(() => _corners = c);
                          });
                          return c;
                        })();
                    return Stack(
                      children: [
                        Positioned(
                          left: pad,
                          top: pad,
                          right: pad,
                          bottom: pad,
                          child: Image.file(
                            _imageFile!,
                            fit: BoxFit.contain,
                            gaplessPlayback: true,
                          ),
                        ),
                        // 角点连线蒙版
                        Positioned.fromRect(
                          rect: rect,
                          child: CustomPaint(painter: _CornerPainter(corners, _cornerColor)),
                        ),
                        for (var i = 0; i < 4; i++)
                          _CornerHandle(
                            position: corners[i],
                            color: _cornerColor,
                            onDrag: (delta) {
                              setState(() {
                                final c = [...corners];
                                c[i] = Offset(
                                  (c[i].dx + delta.dx).clamp(rect.left, rect.right),
                                  (c[i].dy + delta.dy).clamp(rect.top, rect.bottom),
                                );
                                _corners = c;
                              });
                            },
                          ),
                      ],
                    );
                  },
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
                    onPressed: _pick,
                    icon: const Icon(Icons.refresh),
                    label: const Text('重选'),
                    style: OutlinedButton.styleFrom(foregroundColor: Colors.white),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: FilledButton.icon(
                    onPressed: _busy ? null : _correct,
                    icon: const Icon(Icons.crop_free),
                    label: const Text('矫正并保存'),
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

/// 可拖动的角点手柄
class _CornerHandle extends StatelessWidget {
  const _CornerHandle({required this.position, required this.color, required this.onDrag});

  final Offset position;
  final Color color;
  final ValueChanged<Offset> onDrag;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: position.dx - 14,
      top: position.dy - 14,
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onPanUpdate: (d) => onDrag(d.delta),
        child: Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 3),
            boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 6)],
          ),
          child: const Icon(Icons.adjust, color: Colors.white, size: 16),
        ),
      ),
    );
  }
}

/// 绘制四角连线
class _CornerPainter extends CustomPainter {
  _CornerPainter(this.corners, this.color);
  final List<Offset> corners;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (corners.length < 4) return;
    final paint = Paint()
      ..color = color.withOpacity(0.25)
      ..style = PaintingStyle.fill;
    final path = Path()
      ..moveTo(corners[0].dx, corners[0].dy)
      ..lineTo(corners[1].dx, corners[1].dy)
      ..lineTo(corners[2].dx, corners[2].dy)
      ..lineTo(corners[3].dx, corners[3].dy)
      ..close();
    canvas.drawPath(path, paint);
    final line = Paint()
      ..color = color.withOpacity(0.9)
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    canvas.drawPath(path, line);
  }

  @override
  bool shouldRepaint(_CornerPainter old) =>
      old.corners != corners || old.color != color;
}

/// 矫正结果页
class CardResultPage extends StatelessWidget {
  const CardResultPage({super.key, required this.resultFile, required this.corrected});

  final File resultFile;
  final img.Image corrected;

  Future<void> _share(BuildContext context) async {
    await ExportService.shareFile(resultFile, text: '证件扫描结果');
  }

  Future<void> _save(BuildContext context) async {
    final file = await ImageService.savePng(corrected, name: 'card-final');
    if (!context.mounted) return;
    await ExportService.shareFile(file, text: '保存证件扫描结果');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('矫正结果')),
      body: Column(
        children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: Image.file(resultFile, fit: BoxFit.contain),
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
                      onPressed: () => _share(context),
                      icon: const Icon(Icons.ios_share),
                      label: const Text('分享'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: FilledButton.icon(
                      onPressed: () => _save(context),
                      icon: const Icon(Icons.save_alt),
                      label: const Text('保存'),
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
