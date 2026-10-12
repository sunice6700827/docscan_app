import 'dart:typed_data';
import 'dart:ui' show Offset, Size, Rect, Matrix4;

import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;

import '../../services/image_service.dart';

/// 透视裁切页：拖动四角框住要裁切的区域（支持双指缩放/拖动），确认后透视拉正并裁掉周围背景
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

  List<Offset>? _corners;
  final TransformationController _transform = TransformationController();
  bool _initDone = false;

  static const _cornerColor = Color(0xFF2F6BFF);

  @override
  void dispose() {
    _transform.dispose();
    super.dispose();
  }

  void _initTransform(Size viewport) {
    if (_initDone) return;
    _initDone = true;
    final scaleX = viewport.width / _imageSize.width;
    final scaleY = viewport.height / _imageSize.height;
    final scale = scaleX < scaleY ? scaleX : scaleY;
    _transform.value = Matrix4.identity()
      ..translate(viewport.width / 2, viewport.height / 2)
      ..scale(scale)
      ..translate(-_imageSize.width / 2, -_imageSize.height / 2);
  }

  void _confirm() {
    final c = _corners;
    if (c == null || _quadArea(c) < _imageSize.width * _imageSize.height * 0.03) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请拖动四个角点框住要裁切的区域')),
      );
      return;
    }
    final cropped = ImageService.perspectiveCorrect(_image, c);
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
                _initTransform(viewport);
                final corners = _corners ??
                    (() {
                      final c = [
                        Offset.zero,
                        Offset(_imageSize.width, 0),
                        Offset(_imageSize.width, _imageSize.height),
                        Offset(0, _imageSize.height),
                      ];
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (mounted) setState(() => _corners = c);
                      });
                      return c;
                    })();
                return Stack(
                  children: [
                    Positioned.fill(
                      child: InteractiveViewer(
                        transformationController: _transform,
                        constrained: false,
                        minScale: 0.05,
                        maxScale: 8,
                        boundaryMargin: const EdgeInsets.all(200),
                        child: SizedBox(
                          width: _imageSize.width,
                          height: _imageSize.height,
                          child: Stack(
                            clipBehavior: Clip.none,
                            children: [
                              Positioned.fill(
                                child: Image.memory(_bytes, fit: BoxFit.fill, gaplessPlayback: true),
                              ),
                              CustomPaint(painter: _CornerPainter(corners, _cornerColor)),
                              for (var i = 0; i < 4; i++)
                                _CornerHandle(
                                  position: corners[i],
                                  color: _cornerColor,
                                  onDrag: (delta) {
                                    final s = _transform.value.getMaxScaleOnAxis();
                                    setState(() {
                                      final c = [...corners];
                                      c[i] = Offset(
                                        (c[i].dx + delta.dx / s).clamp(0.0, _imageSize.width),
                                        (c[i].dy + delta.dy / s).clamp(0.0, _imageSize.height),
                                      );
                                      _corners = c;
                                    });
                                  },
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
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
