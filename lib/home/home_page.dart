import 'package:flutter/material.dart';

import '../features/card_scan/card_scan_page.dart';
import '../features/document_scan/document_scan_page.dart';
import '../features/document_scan/multi_page_pdf_page.dart';
import '../features/image_process/image_process_page.dart';
import '../features/table_recognize/table_recognize_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  static const _features = <_Feature>[
    _Feature(
      title: '文档扫描',
      subtitle: '拍文档·提取文字',
      icon: Icons.document_scanner_outlined,
      color: Color(0xFF2F6BFF),
      target: DocumentScanPage(),
    ),
    _Feature(
      title: '表格识别',
      subtitle: '拍表格·转成表格',
      icon: Icons.table_chart_outlined,
      color: Color(0xFF00A870),
      target: TableRecognizePage(),
    ),
    _Feature(
      title: '证件扫描',
      subtitle: '卡证校正·归档',
      icon: Icons.badge_outlined,
      color: Color(0xFFFF8A00),
      target: CardScanPage(),
    ),
    _Feature(
      title: '图像处理',
      subtitle: '裁剪·增强·擦除',
      icon: Icons.auto_fix_high_outlined,
      color: Color(0xFFB45BFF),
      target: ImageProcessPage(),
    ),
    _Feature(
      title: '多页PDF',
      subtitle: '连拍合并·存PDF',
      icon: Icons.picture_as_pdf_outlined,
      color: Color(0xFF0080FF),
      target: MultiPagePdfPage(),
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('拍照扫描'),
        automaticallyImplyLeading: false,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildHeader(),
          const SizedBox(height: 16),
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 1.05,
            children: _features
                .map((f) => _FeatureCard(
                      feature: f,
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => f.target),
                      ),
                    ))
                .toList(),
          ),
          const SizedBox(height: 24),
          const _PrivacyNote(),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF2F6BFF), Color(0xFF5B8CFF)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(Icons.center_focus_strong, color: Colors.white, size: 28),
          ),
          const SizedBox(width: 14),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '拍照扫描 · 全能工具',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  '文档 / 表格 / 证件 / 图片处理，一拍即得',
                  style: TextStyle(color: Colors.white70, fontSize: 13),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FeatureCard extends StatelessWidget {
  const _FeatureCard({required this.feature, required this.onTap});

  final _Feature feature;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: feature.color.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(feature.icon, color: feature.color, size: 26),
              ),
              const Spacer(),
              Text(
                feature.title,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF1F2329),
                ),
              ),
              const SizedBox(height: 3),
              Text(
                feature.subtitle,
                style: const TextStyle(fontSize: 12, color: Color(0xFF8A9099)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PrivacyNote extends StatelessWidget {
  const _PrivacyNote();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(horizontal: 4),
      child: Text(
        '提示：文字/表格识别在设备本地完成（Google ML Kit 离线识别），图片不会上传到服务器。',
        style: TextStyle(fontSize: 12, color: Color(0xFF9AA0A8), height: 1.5),
      ),
    );
  }
}

class _Feature {
  const _Feature({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.target,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
  final Widget target;
}
