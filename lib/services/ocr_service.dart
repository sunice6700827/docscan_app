import 'dart:io';
import 'dart:ui' show Rect, Offset;

import 'package:flutter_tesseract_ocr/flutter_tesseract_ocr.dart';

/// 识别语言
enum OcrLanguage { chinese, latin }

/// OCR 元素（最细粒度：单个词 / 字符）
class OcrElement {
  OcrElement({required this.text, required this.box});
  final String text;
  final Rect box;
}

/// OCR 行（含该行所有元素，供表格结构化使用）
class OcrLine {
  OcrLine({
    required this.text,
    required this.box,
    required this.elements,
    this.confidence,
  });
  final String text;
  final Rect box;
  final List<OcrElement> elements;
  final double? confidence;
}

/// 整页 OCR 结果
class OcrDocument {
  OcrDocument({required this.fullText, required this.lines});
  final String fullText;
  final List<OcrLine> lines;

  int get lineCount => lines.length;
}

/// Tesseract 本地 OCR 封装（纯本地离线识别，不依赖 Google Play 服务，国产手机可用）
///
/// 使用方式：
///   final service = OcrService(language: OcrLanguage.chinese);
///   final doc = await service.recognize(File('...'));
///   service.dispose();
class OcrService {
  OcrService({OcrLanguage language = OcrLanguage.chinese})
      : _lang = language == OcrLanguage.chinese ? 'chi_sim' : 'eng';

  final String _lang;

  /// 识别单张图片，返回结构化结果（含文本与行/词坐标）
  Future<OcrDocument> recognize(File imageFile) async {
    // 先尝试 HOCR（含坐标，供表格识别用）
    var hocr = '';
    try {
      hocr = await FlutterTesseractOcr.extractHocr(
        imageFile.path,
        language: _lang,
        args: {'--psm': '6'},
      );
    } catch (_) {}

    final lines = _parseHocr(hocr);
    if (lines.isNotEmpty) {
      final buffer = StringBuffer();
      for (final line in lines) {
        if (buffer.isNotEmpty) buffer.write('\n');
        buffer.write(line.text);
      }
      return OcrDocument(fullText: buffer.toString().trim(), lines: lines);
    }

    // HOCR 解析失败 → 用纯文本兜底，保证能出文字
    var full = '';
    try {
      full = (await FlutterTesseractOcr.extractText(
        imageFile.path,
        language: _lang,
        args: {'--psm': '6'},
      )).trim();
    } catch (_) {}

    if (full.isEmpty) {
      return OcrDocument(fullText: '', lines: const []);
    }
    final fallback = full
        .split('\n')
        .where((s) => s.trim().isNotEmpty)
        .map((s) => OcrLine(text: s.trim(), box: Rect.zero, elements: const []))
        .toList();
    return OcrDocument(fullText: full, lines: fallback);
  }

  /// 解析 HOCR 为行与词坐标
  List<OcrLine> _parseHocr(String hocr) {
    final lines = <OcrLine>[];
    final lineReg = RegExp(
      '<span class=[\'"]ocr_line[\'"][^>]*title=[\'"](?:bbox|bbox_padded) ([\\d]+) ([\\d]+) ([\\d]+) ([\\d]+)[\'"][^>]*>([\\s\\S]*?)</span>',
    );
    final wordReg = RegExp(
      '<span class=[\'"]ocrx_word[\'"][^>]*title=[\'"]bbox ([\\d]+) ([\\d]+) ([\\d]+) ([\\d]+)[\'"][^>]*>(.*?)</span>',
    );
    for (final m in lineReg.allMatches(hocr)) {
      final x1 = int.parse(m.group(1)!);
      final y1 = int.parse(m.group(2)!);
      final x2 = int.parse(m.group(3)!);
      final y2 = int.parse(m.group(4)!);
      final inner = m.group(5)!;
      final elements = <OcrElement>[];
      final textBuf = StringBuffer();
      for (final w in wordReg.allMatches(inner)) {
        final wx1 = int.parse(w.group(1)!);
        final wy1 = int.parse(w.group(2)!);
        final wx2 = int.parse(w.group(3)!);
        final wy2 = int.parse(w.group(4)!);
        final t = _unescape(w.group(5)!);
        elements.add(OcrElement(
          text: t,
          box: Rect.fromLTRB(wx1.toDouble(), wy1.toDouble(), wx2.toDouble(), wy2.toDouble()),
        ));
        if (textBuf.isNotEmpty) textBuf.write(' ');
        textBuf.write(t);
      }
      lines.add(OcrLine(
        text: textBuf.isEmpty ? _innerText(inner) : textBuf.toString(),
        box: Rect.fromLTRB(x1.toDouble(), y1.toDouble(), x2.toDouble(), y2.toDouble()),
        elements: elements,
      ));
    }
    return lines;
  }

  /// 将屏幕坐标点转换为图片像素坐标点
  Offset scalePoint(Offset p, double scaleX, double scaleY) {
    return Offset(p.dx * scaleX, p.dy * scaleY);
  }

  void dispose() {
    // Tesseract 每次识别创建引擎，无需长驻资源释放
  }

  static String _unescape(String s) => s
      .replaceAll('&amp;', '&')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&#39;', "'")
      .replaceAll('&nbsp;', ' ');

  static String _innerText(String inner) =>
      inner.replaceAll(RegExp(r'<[^>]+>'), '').trim();
}
