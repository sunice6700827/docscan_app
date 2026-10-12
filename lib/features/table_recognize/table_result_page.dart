import 'dart:io';

import 'package:flutter/material.dart';

import '../../services/export_service.dart';

class TableResultPage extends StatefulWidget {
  const TableResultPage({super.key, required this.table, required this.imageFile});

  final List<List<String>> table;
  final File imageFile;

  @override
  State<TableResultPage> createState() => _TableResultPageState();
}

class _TableResultPageState extends State<TableResultPage> {
  late final List<List<TextEditingController>> _cells;
  late int _colCount;

  @override
  void initState() {
    super.initState();
    _colCount = widget.table.fold(0, (m, r) => math_max(m, r.length));
    _cells = widget.table
        .map((row) => List.generate(
              _colCount,
              (i) => TextEditingController(text: i < row.length ? row[i] : ''),
            ))
        .toList();
  }

  static int math_max(int a, int b) => a > b ? a : b;

  @override
  void dispose() {
    for (final row in _cells) {
      for (final c in row) {
        c.dispose();
      }
    }
    super.dispose();
  }

  List<List<String>> _snapshot() {
    return _cells
        .map((row) => row.map((c) => c.text.trim()).toList())
        .toList();
  }

  void _addRow() {
    setState(() {
      _cells.add(List.generate(_colCount, (_) => TextEditingController()));
    });
  }

  void _deleteRow(int index) {
    setState(() {
      for (final c in _cells[index]) {
        c.dispose();
      }
      _cells.removeAt(index);
    });
  }

  Future<void> _export() async {
    final file = await ExportService.saveCsv(_snapshot());
    if (!mounted) return;
    await ExportService.shareFile(file, text: '导出识别表格');
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已生成并分享 CSV 文件（可用 Excel 打开）')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('表格识别结果'),
        actions: [
          IconButton(onPressed: _export, icon: const Icon(Icons.ios_share), tooltip: '导出CSV'),
        ],
      ),
      body: Column(
        children: [
          Container(
            margin: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFF00A870).withOpacity(0.08),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                const Icon(Icons.check_circle_outline, size: 18, color: Color(0xFF00A870)),
                const SizedBox(width: 8),
                Text(
                  '识别出 ${_cells.length} 行 × $_colCount 列，点击单元格可编辑',
                  style: const TextStyle(fontSize: 13, color: Color(0xFF00A870)),
                ),
              ],
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.vertical,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.all(12),
                child: _buildTable(),
              ),
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _addRow,
                      icon: const Icon(Icons.add),
                      label: const Text('添加行'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: FilledButton.icon(
                      onPressed: _export,
                      icon: const Icon(Icons.ios_share),
                      label: const Text('导出为 CSV'),
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

  Widget _buildTable() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE4E7EC)),
      ),
      child: Column(
        children: [
          for (var r = 0; r < _cells.length; r++) _buildRow(r),
        ],
      ),
    );
  }

  Widget _buildRow(int rowIndex) {
    return Container(
      decoration: BoxDecoration(
        border: Border(
          bottom: rowIndex == _cells.length - 1
              ? BorderSide.none
              : const BorderSide(color: Color(0xFFE4E7EC)),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 44,
            alignment: Alignment.center,
            decoration: const BoxDecoration(
              color: Color(0xFFF5F6FA),
              border: Border(right: BorderSide(color: Color(0xFFE4E7EC))),
            ),
            child: Text('${rowIndex + 1}', style: const TextStyle(fontSize: 12, color: Color(0xFF8A9099))),
          ),
          for (var c = 0; c < _colCount; c++)
            Container(
              width: 110,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              decoration: BoxDecoration(
                border: c == _colCount - 1
                    ? null
                    : const Border(right: BorderSide(color: Color(0xFFE4E7EC))),
              ),
              child: TextField(
                controller: _cells[rowIndex][c],
                maxLines: null,
                style: const TextStyle(fontSize: 13),
                decoration: const InputDecoration(
                  border: InputBorder.none,
                  isDense: true,
                  contentPadding: EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
          IconButton(
            icon: const Icon(Icons.delete_outline, size: 18, color: Color(0xFFC0C4CC)),
            onPressed: () => _deleteRow(rowIndex),
          ),
        ],
      ),
    );
  }
}
