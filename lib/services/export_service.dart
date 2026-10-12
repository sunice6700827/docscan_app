import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

/// 导出与分享工具
class ExportService {
  static Future<Directory> _dir() async {
    return getTemporaryDirectory();
  }

  static Future<File> saveText(String text, {String name = '扫描文本'}) async {
    final dir = await _dir();
    final file = File('${dir.path}/$name-${DateTime.now().millisecondsSinceEpoch}.txt');
    await file.writeAsString(text);
    return file;
  }

  /// rows：表格二维数据，导出为 CSV（UTF-8 with BOM，Excel 可直接打开）
  static Future<File> saveCsv(List<List<String>> rows, {String name = '识别表格'}) async {
    final buffer = StringBuffer('\uFEFF'); // BOM
    for (final row in rows) {
      buffer.writeln(row.map(_escapeCell).join(','));
    }
    final dir = await _dir();
    final file = File('${dir.path}/$name-${DateTime.now().millisecondsSinceEpoch}.csv');
    await file.writeAsString(buffer.toString());
    return file;
  }

  static String _escapeCell(String cell) {
    if (cell.contains(',') || cell.contains('"') || cell.contains('\n')) {
      return '"${cell.replaceAll('"', '""')}"';
    }
    return cell;
  }

  static Future<void> shareFile(File file, {String? text}) async {
    await Share.shareXFiles([XFile(file.path)], text: text);
  }
}
