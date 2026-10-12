import 'dart:io';
import 'dart:ui' show Offset, Size, Rect, Matrix4;

import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;

import '../../services/image_service.dart';

/// 手动四角校正页：图片可双指缩放/拖动，拖动四角对齐文档边缘，透视矫正后返回结果文件
class ManualCorrectPage extends StatefulWidget {
  const ManualCorrectPage({super.key, required this.imageFile});
  final File imageFile;

  @override
  State<ManualCorrectPage> createState() => _ManualCorrectPageState();
}

class _ManualCorrectPageState extends State<ManualCorrectPage> {
  late final img.Image _image;
  late final Size _imageSize;
  List<Offset>? _corners;
  bool _busy = false;
  final TransformationController _transform = TransformationController();
  bool _initDone = false;

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

  /// 初始把整张图片完整缩放到可视区域并居中
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

  Future<void> _apply() async {
    if (_corners == null || _busy) return;
    setState(() => _busy = true);
    try {
      final corrected = ImageService.perspectiveCorrect(_image, _corners!);
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
                                child: Image.file(
                                  widget.imageFile,
                                  fit: BoxFit.fill,
                                  gaplessPlayback: true,
                                ),
                              ),
                              CustomPaint(painter: _CornerPainter(corners, _cornerColor)),
                              for (var i = 0; i < 4; i++)
                                _CornerHandle(
                                  position: corners[i],
                                  color: _cornerColor,
                                  onDrag: (delta) {
                                    // 屏幕位移换算成图片坐标位移
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
