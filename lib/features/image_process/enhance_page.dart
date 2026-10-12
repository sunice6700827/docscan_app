import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;

import '../../services/image_service.dart';

/// 图像增强页：亮度 / 对比度 / 饱和度 / 锐化实时预览
class EnhancePage extends StatefulWidget {
  const EnhancePage({super.key, required this.initial});
  final img.Image initial;

  @override
  State<EnhancePage> createState() => _EnhancePageState();
}

class _EnhancePageState extends State<EnhancePage> {
  late final img.Image _full = widget.initial;
  late final img.Image _previewSrc = ImageService.thumb(widget.initial, maxSide: 600);

  double _brightness = 0;
  double _contrast = 1;
  double _saturation = 1;
  double _sharpen = 0;
  Uint8List? _previewBytes;

  @override
  void initState() {
    super.initState();
    _rebuildPreview();
  }

  void _rebuildPreview() {
    final out = ImageService.enhance(
      _previewSrc,
      brightness: _brightness,
      contrast: _contrast,
      saturation: _saturation,
      sharpen: _sharpen,
    );
    setState(() => _previewBytes = img.encodeJpg(out, quality: 88));
  }

  void _apply() {
    final out = ImageService.enhance(
      _full,
      brightness: _brightness,
      contrast: _contrast,
      saturation: _saturation,
      sharpen: _sharpen,
    );
    Navigator.of(context).pop(out);
  }

  void _reset() {
    setState(() {
      _brightness = 0;
      _contrast = 1;
      _saturation = 1;
      _sharpen = 0;
    });
    _rebuildPreview();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('图像增强'),
        actions: [
          IconButton(onPressed: _reset, icon: const Icon(Icons.restart_alt), tooltip: '重置'),
          TextButton(
            onPressed: _apply,
            child: const Text('应用', style: TextStyle(fontWeight: FontWeight.w600)),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: _previewBytes == null
                      ? const SizedBox.expand()
                      : Image.memory(_previewBytes!, fit: BoxFit.contain, gaplessPlayback: true),
                ),
              ),
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
              child: Column(
                children: [
                  _Slider(
                    label: '亮度',
                    value: _brightness,
                    min: -0.6, max: 0.6,
                    display: _brightness == 0 ? '0' : '${_brightness > 0 ? '+' : ''}${(_brightness * 100).round()}',
                    onChanged: (v) { _brightness = v; _rebuildPreview(); },
                  ),
                  _Slider(
                    label: '对比度',
                    value: _contrast,
                    min: 0.5, max: 2.0,
                    display: _contrast.toStringAsFixed(1),
                    onChanged: (v) { _contrast = v; _rebuildPreview(); },
                  ),
                  _Slider(
                    label: '饱和度',
                    value: _saturation,
                    min: 0.0, max: 2.0,
                    display: _saturation.toStringAsFixed(1),
                    onChanged: (v) { _saturation = v; _rebuildPreview(); },
                  ),
                  _Slider(
                    label: '锐化',
                    value: _sharpen,
                    min: 0.0, max: 1.5,
                    display: _sharpen == 0 ? '关' : '${(_sharpen * 100).round()}',
                    onChanged: (v) { _sharpen = v; _rebuildPreview(); },
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

class _Slider extends StatelessWidget {
  const _Slider({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.display,
    required this.onChanged,
  });

  final String label;
  final double value;
  final double min;
  final double max;
  final String display;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(width: 56, child: Text(label, style: const TextStyle(fontSize: 14))),
        Expanded(
          child: Slider(
            value: value.clamp(min, max),
            min: min,
            max: max,
            onChanged: onChanged,
          ),
        ),
        SizedBox(
          width: 40,
          child: Text(display, textAlign: TextAlign.right, style: const TextStyle(fontSize: 13)),
        ),
      ],
    );
  }
}
