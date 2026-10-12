import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

/// 把多张图片合并导出为一个 PDF（A4 页，图片等比居中）
class PdfMergeService {
  /// 合并多张图片为 PDF，返回生成的 PDF 文件
  static Future<File> mergeToPdf(List<File> images) async {
    if (images.isEmpty) {
      throw Exception('没有可合并的图片');
    }

    final doc = pw.Document();
    for (final file in images) {
      final bytes = file.readAsBytesSync();
      doc.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(16),
          build: (context) => pw.Center(
            child: pw.Image(
              pw.MemoryImage(bytes),
              fit: pw.BoxFit.contain,
            ),
          ),
        ),
      );
    }

    final dir = await getTemporaryDirectory();
    final out = File('${dir.path}/合并文档-${DateTime.now().millisecondsSinceEpoch}.pdf');
    await out.writeAsBytes(await doc.save());
    return out;
  }
}
