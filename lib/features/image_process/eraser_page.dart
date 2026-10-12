import 'dart:typed_data';
import 'dart:ui' show Offset, Size, Rect;

import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;

import '../../services/image_service.dart';

/// 涂抹擦除页：手指涂抹要清除的区域，一键填充（去水印/去杂物）
class EraserPage extends StatefulWidget {
  const EraserPage({super.key, required this.initial});
  final img.Image initial;

  @override
  State<EraserPage> createState() => _EraserPageState();
}

class _EraserPageState extends State<EraserPage> {
  late final img.Image _image = widget.initial;
  late final Uint8List _bytes = img.encodePng(_image);
  late final img.Image _mask = ImageService.blank(_image.width, _image.height);
  late final Size _imageSize = Size(_image.width.toDouble(), _image.height.toDouble());

  final List<Offset> _strokes = []; // 屏幕坐标，用于叠加显示
  Size? _lastBox;
  Rect _imgRect = Rect.zero;
  double _brushPx = 30;

  Rect _containRect(Size box) {
    final scale = (box.width / _imageSize.width) < (box.height / _imageSize.height)
        ? box.width / _imageSize.width
        : box.height / _imageSize.height;
    final w = _imageSize.width * scale;
    final h = _imageSize.height * scale;
    return Rect.fromLTWH((box.width - w) / 2, (box.height - h) / 2, w, h);
  }

  Offset _toPixel(Offset screen) {
    final scale = _imgRect.width / _imageSize.width;
    return Offset((screen.dx - _imgRect.left) / scale, (screen.dy - _imgRect.top) / scale);
  }

  void _paintStroke(Offset screen) {
    final px = _toPixel(screen);
    final radiusPx = (_brushPx * _imageSize.width / _imgRect.width).round().clamp(2, 200);
    for (var dy = -radiusPx; dy <= radiusPx; dy++) {
      for (var dx = -radiusPx; dx <= radiusPx; dx++) {
        if (dx * dx + dy * dy > radiusPx * radiusPx) continue;
        final x = px.dx.round() + dx;
        final y = px.dy.round() + dy;
        if (x >= 0 && x < _image.width && y >= 0 && y < _image.height) {
          _mask.setPixelRgb(x, y, 255, 255, 255);
        }
      }
    }
    setState(() => _strokes.add(screen));
  }

  Future<void> _erase() async {
    if (_strokes.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先涂抹要擦除的区域')),
      );
      return;
    }
    final result = ImageService.inpaint(_image, _mask);
    Navigator.of(context).pop(result);
  }

  void _undoStroke() {
    setState(() {
      if (_strokes.isNotEmpty) _strokes.removeLast();
    });
    // 撤销需重绘蒙版（简化：清空后重放剩余笔画）
    for (var yy = 0; yy < _image.height; yy++) {
      for (var xx = 0; xx < _image.width; xx++) {
        _mask.setPixelRgb(xx, yy, 0, 0, 0);
      }
    }
    final scale = _imgRect.isEmpty ? 1.0 : _imageSize.width / _imgRect.width;
    for (final s in _strokes) {
      final px = _imgRect.isEmpty
          ? s
          : Offset((s.dx - _imgRect.left) * scale, (s.dy - _imgRect.top) * scale);
      final radiusPx = (_brushPx * scale).round().clamp(2, 200);
      _fillCircle(px.dx.round(), px.dy.round(), radiusPx);
    }
  }

  void _fillCircle(int cx, int cy, int radius) {
    for (var dy = -radius; dy <= radius; dy++) {
      for (var dx = -radius; dx <= radius; dx++) {
        if (dx * dx + dy * dy > radius * radius) continue;
        final x = cx + dx, y = cy + dy;
        if (x >= 0 && x < _image.width && y >= 0 && y < _image.height) {
          _mask.setPixelRgb(x, y, 255, 255, 255);
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('涂抹擦除'),
        actions: [
          IconButton(onPressed: _undoStroke, icon: const Icon(Icons.undo), tooltip: '撤销上一笔'),
          TextButton(
            onPressed: _erase,
            child: const Text('擦除', style: TextStyle(fontWeight: FontWeight.w600)),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Container(
                color: const Color(0xFF111418),
                child: ClipRect(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      _lastBox = Size(constraints.maxWidth, constraints.maxHeight);
                      _imgRect = _containRect(_lastBox!);
                      return Stack(
                        children: [
                          Positioned.fromRect(
                            rect: _imgRect,
                            child: Image.memory(_bytes, fit: BoxFit.fill, gaplessPlayback: true),
                          ),
                          Positioned.fill(
                            child: GestureDetector(
                              behavior: HitTestBehavior.translucent,
                              onPanDown: (d) => _paintStroke(d.localPosition),
                              onPanUpdate: (d) => _paintStroke(d.localPosition),
                              child: CustomPaint(painter: _StrokePainter(_strokes)),
                            ),
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
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
              child: Row(
                children: [
                  Expanded(
                    child: Slider(
                      value: _brushPx,
                      min: 10,
                      max: 90,
                      label: '笔刷大小',
                      onChanged: (v) => setState(() => _brushPx = v),
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Icon(Icons.brush, size: 18, color: Color(0xFF8A9099)),
                  const SizedBox(width: 4),
                  Text('${_brushPx.round()}', style: const TextStyle(fontSize: 13)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StrokePainter extends CustomPainter {
  _StrokePainter(this.strokes);
  final List<Offset> strokes;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFFFF3B30).withOpacity(0.45)
      ..style = PaintingStyle.fill;
    for (final p in strokes) {
      canvas.drawCircle(p, 16, paint);
    }
  }

  @override
  bool shouldRepaint(_StrokePainter old) => old.strokes != strokes;
}
