import 'dart:typed_data';
import 'dart:ui' show Offset, Size, Rect;

import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;

import '../../services/image_service.dart';

/// 透视裁切页：整张图完整适配屏幕，拖动四角框住要裁切的区域（支持双指缩放），确认后透视拉正并裁掉周围背景
class CropPage extends StatefulWidget {
  const CropPage({super.key, required this.initial});
  final img.Image initial;

  @override
  State<CropPage> createState() => _CropPageState();
}

class _CropPageState extends State<CropPage> {
  late final img.Image _image = widget.initial;
  late final Uint8List _bytes = img.encodePng(_image);
  late final Size _imageSize = Size(_image.width.toDouble(), _image.height.toDouble());

  Rect? _imgRect;
  List<Offset>? _corners;
  final TransformationController _transform = TransformationController();

  static const _cornerColor = Color(0xFF2F6BFF);

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

  void _confirm() {
    final r = _imgRect;
    final c = _corners;
    if (r == null || c == null || _quadArea(c) < r.width * r.height * 0.03) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请拖动四个角点框住要裁切的区域')),
      );
      return;
    }
    // 视口坐标 → 图片像素坐标
    final scale = r.width / _imageSize.width;
    final px = c
        .map((p) => Offset((p.dx - r.left) / scale, (p.dy - r.top) / scale))
        .toList();
    final cropped = ImageService.perspectiveCorrect(_image, px);
    Navigator.of(context).pop(cropped);
  }

  double _quadArea(List<Offset> q) {
    var sum = 0.0;
    for (var i = 0; i < q.length; i++) {
      final a = q[i], b = q[(i + 1) % q.length];
      sum += a.dx * b.dy - b.dx * a.dy;
    }
    return sum.abs() / 2;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('透视裁切'),
        actions: [
          TextButton(onPressed: _confirm, child: const Text('完成', style: TextStyle(fontWeight: FontWeight.w600))),
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
                          child: Image.memory(_bytes, fit: BoxFit.fill, gaplessPlayback: true),
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
