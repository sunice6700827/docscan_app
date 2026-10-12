import 'dart:io';
import 'dart:ui' show Offset, Size, Rect;

import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;

import '../../services/image_service.dart';

/// 手动四角校正页：整张图完整适配屏幕，可双指缩放/拖动，拖动四角对齐文档边缘，透视矫正后返回结果文件
class ManualCorrectPage extends StatefulWidget {
  const ManualCorrectPage({super.key, required this.imageFile});
  final File imageFile;

  @override
  State<ManualCorrectPage> createState() => _ManualCorrectPageState();
}

class _ManualCorrectPageState extends State<ManualCorrectPage> {
  late final img.Image _image;
  late final Size _imageSize;
  Rect? _imgRect; // 图片完整显示在可视区的矩形（视口坐标）
  List<Offset>? _corners; // 四角（视口坐标，位于 _imgRect 内）
  bool _busy = false;
  final TransformationController _transform = TransformationController();

  static const _cornerColor = Color(0xFF2F6BFF);

  @override
  void initState() {
    super.initState();
    _image = ImageService.decode(widget.imageFile);
    _imageSize = Size(_image.width.toDouble(), _image.height.toDouble());
  }

  @override
  void dispose() {
    _transform.dispose();
    super.dispose();
  }

  Rect _containRect(Size box) {
    final scale = (box.width / _imageSize.width) < (box.height / _imageSize.height)
        ? box.width / _imageSize.width
        : box.height / _imageSize.height;
    final w = _imageSize.width * scale;
    final h = _imageSize.height * scale;
    return Rect.fromLTWH((box.width - w) / 2, (box.height - h) / 2, w, h);
  }

  Future<void> _apply() async {
    final r = _imgRect;
    final c = _corners;
    if (r == null || c == null || _busy) return;
    setState(() => _busy = true);
    try {
      // 视口坐标 → 图片像素坐标
      final scale = r.width / _imageSize.width;
      final px = c
          .map((p) => Offset((p.dx - r.left) / scale, (p.dy - r.top) / scale))
          .toList();
      final corrected = ImageService.perspectiveCorrect(_image, px);
      final file = await ImageService.savePng(corrected, name: 'corrected');
      if (mounted) Navigator.of(context).pop(file);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('校正失败：$e')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('透视裁切校正'),
        actions: [
          TextButton(
            onPressed: _busy ? null : _apply,
            child: const Text('应用', style: TextStyle(fontWeight: FontWeight.w600)),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(12),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.92),
            borderRadius: BorderRadius.circular(14),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final viewport = Size(constraints.maxWidth, constraints.maxHeight);
                final imgRect = _containRect(viewport);
                _imgRect = imgRect;
                final corners = _corners ??
                    (() {
                      final c = [
                        imgRect.topLeft,
                        imgRect.topRight,
                        imgRect.bottomRight,
                        imgRect.bottomLeft,
                      ];
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (mounted) setState(() => _corners = c);
                      });
                      return c;
                    })();
                return InteractiveViewer(
                  transformationController: _transform,
                  constrained: false,
                  minScale: 0.3,
                  maxScale: 6,
                  boundaryMargin: const EdgeInsets.all(80),
                  child: SizedBox(
                    width: viewport.width,
                    height: viewport.height,
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Positioned.fromRect(
                          rect: imgRect,
                          child: Image.file(
                            widget.imageFile,
                            fit: BoxFit.fill,
                            gaplessPlayback: true,
                          ),
                        ),
                        Positioned.fill(
                          child: CustomPaint(painter: _CornerPainter(corners, _cornerColor)),
                        ),
                        for (var i = 0; i < 4; i++)
                          _CornerHandle(
                            position: corners[i],
                            color: _cornerColor,
                            onDrag: (delta) {
                              final s = _transform.value.getMaxScaleOnAxis();
                              setState(() {
                                final c = [...corners];
                                c[i] = Offset(
                                  (c[i].dx + delta.dx / s).clamp(0.0, viewport.width),
                                  (c[i].dy + delta.dy / s).clamp(0.0, viewport.height),
                                );
                                _corners = c;
                              });
                            },
                          ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _CornerHandle extends StatelessWidget {
  const _CornerHandle({required this.position, required this.color, required this.onDrag});
  final Offset position;
  final Color color;
  final ValueChanged<Offset> onDrag;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: position.dx - 16,
      top: position.dy - 16,
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onPanUpdate: (d) => onDrag(d.delta),
        child: Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 3),
            boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 6)],
          ),
          child: const Icon(Icons.adjust, color: Colors.white, size: 18),
        ),
      ),
    );
  }
}

class _CornerPainter extends CustomPainter {
  _CornerPainter(this.corners, this.color);
  final List<Offset> corners;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (corners.length < 4) return;
    final fill = Paint()
      ..color = color.withOpacity(0.25)
      ..style = PaintingStyle.fill;
    final path = Path()
      ..moveTo(corners[0].dx, corners[0].dy)
      ..lineTo(corners[1].dx, corners[1].dy)
      ..lineTo(corners[2].dx, corners[2].dy)
      ..lineTo(corners[3].dx, corners[3].dy)
      ..close();
    canvas.drawPath(path, fill);
    final line = Paint()
      ..color = color.withOpacity(0.9)
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke;
    canvas.drawPath(path, line);
  }

  @override
  bool shouldRepaint(_CornerPainter old) => old.corners != corners || old.color != color;
}
