import 'dart:io';
import 'dart:ui' show Offset, Rect;

import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';

/// 图像处理工具（裁剪 / 增强 / 透视校正 / 擦除填充）
///
/// 全部在本地完成，不联网。
class ImageService {
  /// 解码图片文件
  static img.Image decode(File file) {
    final bytes = file.readAsBytesSync();
    final decoded = img.decodeImage(bytes);
    if (decoded == null) {
      throw Exception('无法解码图片，格式可能不支持');
    }
    return decoded;
  }

  /// 编码并保存到应用临时目录，返回文件路径
  static Future<File> savePng(img.Image image, {String name = 'output'}) async {
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/$name-${DateTime.now().millisecondsSinceEpoch}.png');
    final bytes = img.encodePng(image);
    await file.writeAsBytes(bytes);
    return file;
  }

  // ---------------------------------------------------------------------------
  // 扫描历史：处理后的结果保存到应用文档目录，重新进入可查看/重新识别
  // ---------------------------------------------------------------------------
  static Future<Directory> scanHistoryDir() async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory('${docs.path}/scan_history');
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return dir;
  }

  static Future<File> saveToHistory(img.Image image) async {
    final dir = await scanHistoryDir();
    final file = File('${dir.path}/${DateTime.now().millisecondsSinceEpoch}.png');
    await file.writeAsBytes(img.encodePng(image));
    return file;
  }

  static Future<List<File>> listHistory() async {
    final dir = await scanHistoryDir();
    if (!dir.existsSync()) return [];
    final files = dir
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.png'))
        .toList()
      ..sort((a, b) => b.path.compareTo(a.path)); // 最新在前
    return files;
  }

  /// 按 UI 比例缩小显示用缩略图（限制最长边）
  static img.Image thumb(img.Image src, {int maxSide = 1600}) {
    if (src.width <= maxSide && src.height <= maxSide) return src;
    final scale = maxSide / (src.width > src.height ? src.width : src.height);
    return img.copyResize(
      src,
      width: (src.width * scale).round(),
      height: (src.height * scale).round(),
      interpolation: img.Interpolation.cubic,
    );
  }

  /// 矩形裁剪
  static img.Image crop(img.Image src, Rect box) {
    final x = box.left.round().clamp(0, src.width - 1);
    final y = box.top.round().clamp(0, src.height - 1);
    final w = (box.right.round() - x).clamp(1, src.width - x);
    final h = (box.bottom.round() - y).clamp(1, src.height - y);
    return img.copyCrop(src, x: x, y: y, width: w, height: h);
  }

  // ---------------------------------------------------------------------------
  // 透视校正：将四个角点围成的四边形矫正为正视矩形（证件/文档扫描）
  // ---------------------------------------------------------------------------
  /// corners 顺序：左上、右上、右下、左下（图片像素坐标）
  /// forceA4=true 时输出为 A4 纸张比例（自动按四边形方向选竖版/横版），更适合文档
  static img.Image perspectiveCorrect(
    img.Image src,
    List<Offset> corners, {
    double outWidth = 900,
    double? outHeight,
    bool forceA4 = false,
  }) {
    assert(corners.length == 4, '需要恰好 4 个角点');
    final tl = corners[0], tr = corners[1], br = corners[2], bl = corners[3];
    final quadW = _quadWidth(tl, tr, br, bl);
    final quadH = _quadHeight(tl, tr, br, bl);
    double h;
    if (outHeight != null) {
      h = outHeight;
    } else if (forceA4) {
      final aspect = quadW >= quadH ? 1.41429 : 0.70707; // 横A4 / 竖A4
      h = outWidth / aspect;
    } else {
      h = (outWidth / quadW) * quadH;
    }

    final H = _homographyDstToSrc(
      outW: outWidth,
      outH: h,
      srcTL: tl, srcTR: tr, srcBR: br, srcBL: bl,
    );

    final out = img.Image(width: outWidth.round(), height: h.round());
    for (var y = 0; y < out.height; y++) {
      for (var x = 0; x < out.width; x++) {
        final sx = H[0] * x + H[1] * y + H[2];
        final sy = H[3] * x + H[4] * y + H[5];
        final w = H[6] * x + H[7] * y + H[8];
        final inv = w == 0 ? 0.0 : 1.0 / w;
        final u = sx * inv;
        final v = sy * inv;
        final s = _sample(src, u, v);
        out.setPixelRgb(x, y, s[0], s[1], s[2]);
      }
    }
    return out;
  }

  static double _quadWidth(Offset tl, Offset tr, Offset br, Offset bl) {
    final top = (tr - tl).distance;
    final bottom = (br - bl).distance;
    return (top + bottom) / 2;
  }

  static double _quadHeight(Offset tl, Offset tr, Offset br, Offset bl) {
    final left = (bl - tl).distance;
    final right = (br - tr).distance;
    return (left + right) / 2;
  }

  /// 计算 dst(矩形) -> src(四边形) 的单应矩阵（9 个元素，行优先）
  static List<double> _homographyDstToSrc({
    required double outW,
    required double outH,
    required Offset srcTL,
    required Offset srcTR,
    required Offset srcBR,
    required Offset srcBL,
  }) {
    // DLT：dst 四角 -> src 四角
    final dst = [
      Offset(0, 0), Offset(outW, 0), Offset(outW, outH), Offset(0, outH),
    ];
    final src = [srcTL, srcTR, srcBR, srcBL];

    // 构造 8x8 矩阵 A 与 8x1 向量 b（h33=1）
    final A = List.generate(8, (_) => List<double>.filled(8, 0));
    final b = List<double>.filled(8, 0);
    for (var i = 0; i < 4; i++) {
      final x = dst[i].dx, y = dst[i].dy, u = src[i].dx, v = src[i].dy;
      final r = 2 * i;
      A[r][0] = x; A[r][1] = y; A[r][2] = 1; A[r][3] = 0; A[r][4] = 0; A[r][5] = 0;
      A[r][6] = -u * x; A[r][7] = -u * y; b[r] = u;
      A[r + 1][0] = 0; A[r + 1][1] = 0; A[r + 1][2] = 0;
      A[r + 1][3] = x; A[r + 1][4] = y; A[r + 1][5] = 1;
      A[r + 1][6] = -v * x; A[r + 1][7] = -v * y; b[r + 1] = v;
    }
    final h = _solveLinear(A, b); // h11..h32
    return [
      h[0], h[1], h[2],
      h[3], h[4], h[5],
      h[6], h[7], 1.0,
    ];
  }

  /// 高斯消元解 8x8 线性方程组
  static List<double> _solveLinear(List<List<double>> A, List<double> b) {
    final n = 8;
    final m = List.generate(n, (i) => List<double>.from(A[i])..add(b[i]));
    for (var col = 0; col < n; col++) {
      // 选主元
      var pivot = col;
      for (var r = col + 1; r < n; r++) {
        if (m[r][col].abs() > m[pivot][col].abs()) pivot = r;
      }
      final tmp = m[col]; m[col] = m[pivot]; m[pivot] = tmp;
      final pv = m[col][col];
      if (pv.abs() < 1e-12) continue;
      for (var j = col; j <= n; j++) m[col][j] /= pv;
      for (var r = 0; r < n; r++) {
        if (r == col) continue;
        final f = m[r][col];
        if (f.abs() < 1e-12) continue;
        for (var j = col; j <= n; j++) m[r][j] -= f * m[col][j];
      }
    }
    return List.generate(n, (i) => m[i][n]);
  }

  /// 双线性采样（越界返回最近有效像素）
  static List<int> _sample(img.Image src, double u, double v) {
    var x0 = u.floor().clamp(0, src.width - 1);
    var y0 = v.floor().clamp(0, src.height - 1);
    var x1 = (x0 + 1).clamp(0, src.width - 1);
    var y1 = (y0 + 1).clamp(0, src.height - 1);
    final fx = u - u.floor();
    final fy = v - v.floor();

    final p00 = src.getPixel(x0, y0);
    final p10 = src.getPixel(x1, y0);
    final p01 = src.getPixel(x0, y1);
    final p11 = src.getPixel(x1, y1);

    int lerp(num a, num b, num t) => (a + (b - a) * t).round().clamp(0, 255);
    final r = lerp(lerp(p00.r, p10.r, fx), lerp(p01.r, p11.r, fx), fy);
    final g = lerp(lerp(p00.g, p10.g, fx), lerp(p01.g, p11.g, fx), fy);
    final bl = lerp(lerp(p00.b, p10.b, fx), lerp(p01.b, p11.b, fx), fy);
    return [r, g, bl];
  }

  // ---------------------------------------------------------------------------
  // 增强：亮度 / 对比度 / 饱和度 / 锐化
  // ---------------------------------------------------------------------------
  /// brightness ∈ [-1,1]，contrast ∈ [0,3]，saturation ∈ [0,3]，sharpen ∈ [0,2]
  static img.Image enhance(
    img.Image src, {
    double brightness = 0,
    double contrast = 1,
    double saturation = 1,
    double sharpen = 0,
  }) {
    var out = src.clone();
    final offset = (brightness * 255).round();
    if (offset != 0 || (contrast - 1).abs() > 0.001 || (saturation - 1).abs() > 0.001) {
      out = _colorGrade(out, offset, contrast, saturation);
    }
    if (sharpen > 0.01) {
      out = _sharpen(out, sharpen);
    }
    return out;
  }

  static img.Image _colorGrade(img.Image src, int offset, double contrast, double saturation) {
    final out = img.Image.from(src);
    for (final p in out) {
      var r = p.r, g = p.g, b = p.b;
      // 对比度
      r = (r - 128) * contrast + 128;
      g = (g - 128) * contrast + 128;
      b = (b - 128) * contrast + 128;
      // 饱和度
      final gray = (r * 0.299 + g * 0.587 + b * 0.114);
      r = gray + (r - gray) * saturation;
      g = gray + (g - gray) * saturation;
      b = gray + (b - gray) * saturation;
      // 亮度
      r += offset; g += offset; b += offset;
      p.setRgb(
        r.round().clamp(0, 255),
        g.round().clamp(0, 255),
        b.round().clamp(0, 255),
      );
    }
    return out;
  }

  static img.Image _sharpen(img.Image src, double amount) {
    const kernel = <List<double>>[
      [0, -1, 0],
      [-1, 5, 0],
      [0, 0, 0],
    ];
    final out = img.Image.from(src);
    final w = src.width, h = src.height;
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        var r = 0.0, g = 0.0, b = 0.0;
        for (var ky = 0; ky < 3; ky++) {
          for (var kx = 0; kx < 3; kx++) {
            final px = (x + kx - 1).clamp(0, w - 1);
            final py = (y + ky - 1).clamp(0, h - 1);
            final k = kernel[ky][kx];
            final p = src.getPixel(px, py);
            r += p.r * k; g += p.g * k; b += p.b * k;
          }
        }
        final p0 = src.getPixel(x, y);
        final nr = p0.r + (r - p0.r) * amount;
        final ng = p0.g + (g - p0.g) * amount;
        final nb = p0.b + (b - p0.b) * amount;
        out.setPixelRgb(x, y, nr.round().clamp(0, 255), ng.round().clamp(0, 255), nb.round().clamp(0, 255));
      }
    }
    return out;
  }

  // ---------------------------------------------------------------------------
  // 擦除：基于边缘颜色传播的简化填充（去水印/去杂物）
  // mask：白色(255)=待擦除区域，其余=保留
  // ---------------------------------------------------------------------------
  static img.Image inpaint(img.Image src, img.Image mask) {
    final out = img.Image.from(src);
    final m = img.Image.from(mask);
    final w = src.width, h = src.height;
    final visited = List.generate(h, (_) => List<bool>.filled(w, false));
    final isErase = (x, y) => m.getPixel(x, y).r > 128;

    // 第一轮：待擦除且 8 邻域有保留像素的
    final pending = <(int, int)>[];
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        if (isErase(x, y) && _hasValidNeighbor(x, y, w, h, isErase)) {
          _fillFromNeighbors(out, x, y, w, h, isErase, visited);
          pending.add((x, y));
        }
      }
    }

    // 迭代向内传播
    var guard = 0;
    while (pending.isNotEmpty && guard < 100000) {
      guard += pending.length;
      final next = <(int, int)>[];
      for (final (x, y) in pending) {
        for (final (nx, ny) in _neighbors8(x, y, w, h)) {
          if (isErase(nx, ny) && !visited[ny][nx]) {
            _fillFromNeighbors(out, nx, ny, w, h, isErase, visited);
            next.add((nx, ny));
          }
        }
      }
      pending
        ..clear()
        ..addAll(next);
    }
    return out;
  }

  static bool _hasValidNeighbor(int x, int y, int w, int h, bool Function(int, int) isErase) {
    for (final (nx, ny) in _neighbors8(x, y, w, h)) {
      if (!isErase(nx, ny)) return true;
    }
    return false;
  }

  static void _fillFromNeighbors(
    img.Image out,
    int x,
    int y,
    int w,
    int h,
    bool Function(int, int) isErase,
    List<List<bool>> visited,
  ) {
    var r = 0.0, g = 0.0, b = 0.0, count = 0;
    for (final (nx, ny) in _neighbors8(x, y, w, h)) {
      if (!isErase(nx, ny) || visited[ny][nx]) {
        final p = out.getPixel(nx, ny);
        r += p.r.toDouble(); g += p.g.toDouble(); b += p.b.toDouble();
        count++;
      }
    }
    if (count > 0) {
      out.setPixelRgb(x, y, (r / count).round(), (g / count).round(), (b / count).round());
    }
    visited[y][x] = true;
  }

  static List<(int, int)> _neighbors8(int x, int y, int w, int h) {
    final list = <(int, int)>[];
    for (var dy = -1; dy <= 1; dy++) {
      for (var dx = -1; dx <= 1; dx++) {
        if (dx == 0 && dy == 0) continue;
        final nx = x + dx, ny = y + dy;
        if (nx >= 0 && nx < w && ny >= 0 && ny < h) list.add((nx, ny));
      }
    }
    return list;
  }

  /// 生成空白画布（用于绘制的蒙版）
  static img.Image blank(int width, int height) => img.Image(width: width, height: height);

  // ---------------------------------------------------------------------------
  // 自动检测文档四角（用于拍摄时的自动透视校正）
  // 返回 左上、右上、右下、左下 四个角点（原图坐标）；检测不可靠时返回 null
  // ---------------------------------------------------------------------------
  static List<Offset>? detectDocumentCorners(img.Image src) {
    final small = thumb(src, maxSide: 500);
    final sw = small.width, sh = small.height;

    // 1) 灰度化
    final gray = img.Image.from(small);
    for (final p in gray) {
      final g = (p.r * 0.299 + p.g * 0.587 + p.b * 0.114).round();
      p.setRgb(g, g, g);
    }

    // 2) Otsu 阈值二值化（文档偏亮、背景偏暗）
    final threshold = _otsuThreshold(gray);
    // 3) 收集亮像素（文档区域）
    final pts = <(int, int)>[];
    for (var y = 0; y < sh; y++) {
      for (var x = 0; x < sw; x++) {
        if (gray.getPixel(x, y).r > threshold) pts.add((x, y));
      }
    }
    if (pts.length < sw * sh * 0.02) return null;

    // 4) 质心
    var cx = 0.0, cy = 0.0;
    for (final (x, y) in pts) {
      cx += x; cy += y;
    }
    cx /= pts.length; cy /= pts.length;

    // 5) 相对质心按四象限取最远点，得到 4 个候选角
    final candidates = <Offset>[];
    for (var q = 0; q < 4; q++) {
      var best = const Offset(-1, -1);
      var bestD = -1.0;
      final lo = q * 90.0 * 0.0174533, hi = (q + 1) * 90.0 * 0.0174533;
      for (final (x, y) in pts) {
        final a = _angle(Offset(x.toDouble(), y.toDouble()), Offset(cx, cy));
        if (a < lo || a >= hi) continue;
        final d = (x - cx) * (x - cx) + (y - cy) * (y - cy);
        if (d > bestD) {
          bestD = d;
          best = Offset(x.toDouble(), y.toDouble());
        }
      }
      if (best.dx < 0) return null;
      candidates.add(best);
    }

    // 6) 校验：四边形面积应占一定比例
    final ordered = _orderCorners(candidates);
    if (_quadArea(ordered) < sw * sh * 0.06) return null;

    // 7) 放大回原图坐标
    final scaleX = src.width / sw, scaleY = src.height / sh;
    return ordered.map((p) => Offset(p.dx * scaleX, p.dy * scaleY)).toList();
  }

  static double _angle(Offset p, Offset c) {
    final a = (p - c).direction;
    return a < 0 ? a + 6.283185 : a;
  }

  /// 排序为 左上、右上、右下、左下
  static List<Offset> _orderCorners(List<Offset> c) {
    final byX = [...c]..sort((a, b) => a.dx.compareTo(b.dx));
    final left = byX.sublist(0, 2)..sort((a, b) => a.dy.compareTo(b.dy));
    final right = byX.sublist(2)..sort((a, b) => a.dy.compareTo(b.dy));
    return [left[0], right[0], right[1], left[1]];
  }

  /// 多边形面积（鞋带公式）
  static double _quadArea(List<Offset> q) {
    var sum = 0.0;
    for (var i = 0; i < q.length; i++) {
      final a = q[i], b = q[(i + 1) % q.length];
      sum += a.dx * b.dy - b.dx * a.dy;
    }
    return sum.abs() / 2;
  }

  /// Otsu 最大类间方差法求阈值
  static int _otsuThreshold(img.Image gray) {
    final hist = List<int>.filled(256, 0);
    for (var y = 0; y < gray.height; y++) {
      for (var x = 0; x < gray.width; x++) {
        hist[gray.getPixel(x, y).r.round().clamp(0, 255)]++;
      }
    }
    final total = gray.width * gray.height;
    var sum = 0.0;
    for (var i = 0; i < 256; i++) {
      sum += i * hist[i];
    }
    var sumB = 0.0, wB = 0, maxVar = -1.0, threshold = 127;
    for (var i = 0; i < 256; i++) {
      wB += hist[i];
      if (wB == 0) continue;
      final wF = total - wB;
      if (wF == 0) break;
      sumB += i * hist[i];
      final mB = sumB / wB;
      final mF = (sum - sumB) / wF;
      final between = wB * wF * (mB - mF) * (mB - mF);
      if (between > maxVar) {
        maxVar = between;
        threshold = i;
      }
    }
    return threshold;
  }
}
