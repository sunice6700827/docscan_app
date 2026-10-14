import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' show Offset, Rect;

import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';

/// 图像处理工具（裁剪 / 增强 / 透视校正 / 擦除填充）
///
/// 全部在本地完成，不联网。
class ImageService {
  /// 解码图片文件。
  ///
  /// 必须应用 EXIF 方向：手机竖拍的照片像素常以"横躺 + orientation 标记"
  /// 保存，image 包解码不会自动转正。不处理的话，后续四角检测、透视矫正、
  /// PDF 合成全部基于横躺像素，导致结果歪斜、被裁切、方向错乱。
  static img.Image decode(File file) {
    final bytes = file.readAsBytesSync();
    final decoded = img.decodeImage(bytes);
    if (decoded == null) {
      throw Exception('无法解码图片，格式可能不支持');
    }
    return img.bakeOrientation(decoded);
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

  /// 处理前缩图（线性插值，快）：相机原图常为 4000+ 宽，处理前缩到最长边
  /// maxSide 可大幅降低后续逐像素处理耗时，同时保持足够清晰度
  static img.Image downscaleForProcessing(img.Image src, {int maxSide = 2400}) {
    if (src.width <= maxSide && src.height <= maxSide) return src;
    final scale = maxSide / (src.width > src.height ? src.width : src.height);
    return img.copyResize(
      src,
      width: (src.width * scale).round(),
      height: (src.height * scale).round(),
      interpolation: img.Interpolation.linear,
    );
  }

  /// 把图像像素一次性读入 RGB 数组（getPixel 很慢，读数组快 5~10 倍）
  static Uint8List _toRgb(img.Image src) {
    final w = src.width, h = src.height;
    final buf = Uint8List(w * h * 3);
    var i = 0;
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        final p = src.getPixel(x, y);
        buf[i++] = p.r.toInt();
        buf[i++] = p.g.toInt();
        buf[i++] = p.b.toInt();
      }
    }
    return buf;
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
    double outWidth = 2000,
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

    final buf = _toRgb(src);
    final sw = src.width, sh = src.height;
    final out = img.Image(width: outWidth.round(), height: h.round());
    for (var y = 0; y < out.height; y++) {
      for (var x = 0; x < out.width; x++) {
        final sx = H[0] * x + H[1] * y + H[2];
        final sy = H[3] * x + H[4] * y + H[5];
        final w = H[6] * x + H[7] * y + H[8];
        final inv = w == 0 ? 0.0 : 1.0 / w;
        final u = sx * inv;
        final v = sy * inv;
        final s = _sampleBuf(buf, sw, sh, u, v);
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

  /// 双线性采样（基于 RGB 数组，越界返回最近有效像素）
  static List<int> _sampleBuf(Uint8List buf, int w, int h, double u, double v) {
    var x0 = u.floor().clamp(0, w - 1).toInt();
    var y0 = v.floor().clamp(0, h - 1).toInt();
    var x1 = (x0 + 1).clamp(0, w - 1).toInt();
    var y1 = (y0 + 1).clamp(0, h - 1).toInt();
    final fx = u - u.floor();
    final fy = v - v.floor();

    final i00 = (y0 * w + x0) * 3;
    final i10 = (y0 * w + x1) * 3;
    final i01 = (y1 * w + x0) * 3;
    final i11 = (y1 * w + x1) * 3;

    int lerp(num a, num b, num t) => (a + (b - a) * t).round().clamp(0, 255);
    final r = lerp(lerp(buf[i00], buf[i10], fx), lerp(buf[i01], buf[i11], fx), fy);
    final g = lerp(lerp(buf[i00 + 1], buf[i10 + 1], fx), lerp(buf[i01 + 1], buf[i11 + 1], fx), fy);
    final bl = lerp(lerp(buf[i00 + 2], buf[i10 + 2], fx), lerp(buf[i01 + 2], buf[i11 + 2], fx), fy);
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

  /// 非锐化掩蔽（unsharp mask）。
  ///
  /// 关键约束：核系数之和必须为 1，平坦区域输出恒等于输入，只增强边缘。
  /// 旧核 [[0,-1,0],[-1,5,0],[0,0,0]] 系数和是 3，纸面等平坦区卷积结果恒为
  /// 3v，输出变成 v*(1+2*amount)——amount=0.5 时亮度翻倍，纸面推到 255 纯白、
  /// 字迹抬灰发虚，这是"过曝、不稳定"的根源之一。
  static img.Image _sharpen(img.Image src, double amount) {
    final buf = _toRgb(src);
    final w = src.width, h = src.height;
    final out = img.Image.from(src);
    final a = amount.clamp(0.0, 1.0); // 上限 1.0，避免振铃与噪点放大
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        final i = (y * w + x) * 3;
        final cr = buf[i], cg = buf[i + 1], cb = buf[i + 2];
        // 8 邻域均值（不含自身）作为局部低频估计
        var lr = 0.0, lg = 0.0, lb = 0.0;
        for (var ky = -1; ky <= 1; ky++) {
          for (var kx = -1; kx <= 1; kx++) {
            if (kx == 0 && ky == 0) continue;
            final px = (x + kx).clamp(0, w - 1);
            final py = (y + ky).clamp(0, h - 1);
            final j = (py * w + px) * 3;
            lr += buf[j]; lg += buf[j + 1]; lb += buf[j + 2];
          }
        }
        lr /= 8.0; lg /= 8.0; lb /= 8.0;
        out.setPixelRgb(
          x, y,
          (cr + (cr - lr) * a).round().clamp(0, 255),
          (cg + (cg - lg) * a).round().clamp(0, 255),
          (cb + (cb - lb) * a).round().clamp(0, 255),
        );
      }
    }
    return out;
  }

  // ---------------------------------------------------------------------------
  // 自适应曝光归一化（扫描文档专用）
  //
  // 取代写死的 brightness/contrast 预设：把画面分块，逐块统计纸面白场与字迹
  // 黑场，块间平滑并与全局统计融合；每块把纸面线性映射到固定目标白点。
  // 无论整页偏亮偏暗，输出纸面亮度都稳定一致；分块统计同时压平一侧阴影、
  // 逆光渐变这类页内光照不均。
  // ---------------------------------------------------------------------------
  static img.Image normalizeForScan(
    img.Image src, {
    double targetWhite = 245,
    double targetInk = 30,
    int tiles = 12,
    double globalWeight = 0.5, // 分块统计向全局统计靠拢的比例（抗噪声）
    double minRange = 18, // 黑白场最小跨度，防止增益爆炸把噪点拉成脏斑
    double minScale = 0.8,
    double maxScale = 3.0,
    double gamma = 1.25, // 中间调压暗：灰字/阴影变黑，纸面(>92%)不动
  }) {
    final w = src.width, h = src.height;
    final buf = _toRgb(src);

    // 1) 在缩图上做分块直方图统计（快），参数作用于全分辨率
    final small = thumb(src, maxSide: 480);
    final sb = _toRgb(small);
    final sw = small.width, sh = small.height;
    final white = List.generate(tiles, (_) => List<double>.filled(tiles, 220));
    final black = List.generate(tiles, (_) => List<double>.filled(tiles, 40));
    final globalHist = List<int>.filled(256, 0);
    for (var ix = 0; ix < tiles; ix++) {
      final x0 = ix * sw ~/ tiles;
      final x1 = (ix + 1) * sw ~/ tiles;
      for (var iy = 0; iy < tiles; iy++) {
        final y0 = iy * sh ~/ tiles;
        final y1 = (iy + 1) * sh ~/ tiles;
        final hist = List<int>.filled(256, 0);
        for (var y = y0; y < y1 && y < sh; y++) {
          for (var x = x0; x < x1 && x < sw; x++) {
            final i = (y * sw + x) * 3;
            final lv =
                (sb[i] * 0.299 + sb[i + 1] * 0.587 + sb[i + 2] * 0.114).round();
            final v = lv < 0 ? 0 : (lv > 255 ? 255 : lv);
            hist[v]++;
            globalHist[v]++;
          }
        }
        var total = (x1 - x0) * (y1 - y0);
        if (total < 1) total = 1;
        white[ix][iy] = _scanPercentile(hist, total, 0.95);
        black[ix][iy] = _scanPercentile(hist, total, 0.02);
      }
    }
    final gWhite = _scanPercentile(globalHist, sw * sh, 0.95);
    final gBlack = _scanPercentile(globalHist, sw * sh, 0.02);

    // 全页黑白场跨度太小（空白纸/无文字画面）：不做自动色阶，原样返回，
    // 否则会把噪声当字迹拉伸，整页拉暗或拉脏。
    if ((gWhite - gBlack) < minRange) return src;

    // 2) 与全局统计融合；弱纹理块（空白纸/纯黑背景）退回全局，避免放大噪点
    for (var ix = 0; ix < tiles; ix++) {
      for (var iy = 0; iy < tiles; iy++) {
        final wv = white[ix][iy] * (1 - globalWeight) + gWhite * globalWeight;
        final bv = black[ix][iy] * (1 - globalWeight) + gBlack * globalWeight;
        if ((wv - bv) < minRange) {
          white[ix][iy] = gWhite;
          black[ix][iy] = gBlack;
        } else {
          white[ix][iy] = wv;
          black[ix][iy] = bv;
        }
      }
    }
    final wSm = _smoothTiles(vals: white, tiles: tiles);
    final bSm = _smoothTiles(vals: black, tiles: tiles);

    // 3) 纸面白平衡（灰世界，增益限幅 ±50%）：纸面=亮度高于全图 p65 的像素。
    // 深色桌面/手机阴影会把均值拉偏，p65 分位判定比固定阈值稳健；
    // 蓝桌布反光这类强偏色需要大修正量，限幅从 ±12% 放宽到 ±50%。
    var pr = 0.0, pg = 0.0, pb = 0.0, pn = 0;
    final paperTh = _scanPercentile(globalHist, sw * sh, 0.65);
    for (var y = 0; y < sh; y++) {
      for (var x = 0; x < sw; x++) {
        final i = (y * sw + x) * 3;
        final lv = sb[i] * 0.299 + sb[i + 1] * 0.587 + sb[i + 2] * 0.114;
        if (lv >= paperTh) {
          pr += sb[i];
          pg += sb[i + 1];
          pb += sb[i + 2];
          pn++;
        }
      }
    }
    double wr = 1, wg = 1, wb = 1;
    if (pn > 24 && pr > 1 && pg > 1 && pb > 1) {
      pr /= pn;
      pg /= pn;
      pb /= pn;
      final gray = (pr + pg + pb) / 3;
      wr = (gray / pr).clamp(0.5, 1.5);
      wg = (gray / pg).clamp(0.5, 1.5);
      wb = (gray / pb).clamp(0.5, 1.5);
    }

    // 4) 逐像素：双线性插值取本处（黑场,白场）→ 线性映射到目标区间 → 中间调压暗
    // gamma 曲线只作用于 0~92% 区间：纸面（映射后接近 targetWhite）保持不动，
    // 灰字迹、纸面阴影被压黑，解决"字迹变淡、阴影发灰"。
    final gammaLut = List<double>.generate(1025, (k) {
      final n = k / 1024.0;
      return n > 0.92 ? n : _pow(n, gamma);
    });
    final out = img.Image(width: w, height: h);
    final tilesLast = (tiles - 1).toDouble();
    for (var y = 0; y < h; y++) {
      var fy = (y + 0.5) * tiles / h - 0.5;
      if (fy < 0) fy = 0;
      if (fy > tilesLast) fy = tilesLast;
      final j0 = fy.floor();
      var j1 = j0 + 1;
      if (j1 > tiles - 1) j1 = tiles - 1;
      final ty = fy - j0;
      for (var x = 0; x < w; x++) {
        var fx = (x + 0.5) * tiles / w - 0.5;
        if (fx < 0) fx = 0;
        if (fx > tilesLast) fx = tilesLast;
        final i0 = fx.floor();
        var i1 = i0 + 1;
        if (i1 > tiles - 1) i1 = tiles - 1;
        final tx = fx - i0;

        final wv = (wSm[i0][j0] * (1 - tx) + wSm[i1][j0] * tx) * (1 - ty) +
            (wSm[i0][j1] * (1 - tx) + wSm[i1][j1] * tx) * ty;
        final bv = (bSm[i0][j0] * (1 - tx) + bSm[i1][j0] * tx) * (1 - ty) +
            (bSm[i0][j1] * (1 - tx) + bSm[i1][j1] * tx) * ty;
        final rng = (wv - bv) < minRange ? minRange : (wv - bv);
        var scale = (targetWhite - targetInk) / rng;
        if (scale < minScale) scale = minScale;
        if (scale > maxScale) scale = maxScale;

        final i = (y * w + x) * 3;
        final r0 = buf[i], g0 = buf[i + 1], b0 = buf[i + 2];
        final l = r0 * 0.299 + g0 * 0.587 + b0 * 0.114;
        var lOut = (l - bv) * scale + targetInk;
        if (lOut < 0) lOut = 0;
        if (lOut > 255) lOut = 255;
        // 查表应用 gamma（1024 级精度，避免逐像素 pow）
        var gi = (lOut * 4.0).round();
        if (gi < 0) gi = 0;
        if (gi > 1024) gi = 1024;
        lOut = gammaLut[gi] * 255.0;
        final f = l > 4.0 ? lOut / l : 1.0;
        final nr = (r0 * wr * f).round();
        final ng = (g0 * wg * f).round();
        final nb = (b0 * wb * f).round();
        out.setPixelRgb(
          x, y,
          nr < 0 ? 0 : (nr > 255 ? 255 : nr),
          ng < 0 ? 0 : (ng > 255 ? 255 : ng),
          nb < 0 ? 0 : (nb > 255 ? 255 : nb),
        );
      }
    }
    return out;
  }

  /// 幂函数（base<=0 时返回 0，避免 NaN）
  static double _pow(double base, double exp) {
    if (base <= 0) return 0;
    return math.pow(base, exp).toDouble();
  }

  /// 3x3 均值平滑分块参数图，消除块间可见接缝
  static List<List<double>> _smoothTiles({
    required List<List<double>> vals,
    required int tiles,
  }) {
    final m = List.generate(tiles, (i) => List<double>.from(vals[i]));
    final o = List.generate(tiles, (_) => List<double>.filled(tiles, 0));
    for (var ix = 0; ix < tiles; ix++) {
      for (var iy = 0; iy < tiles; iy++) {
        var s = 0.0, n = 0;
        for (var dx = -1; dx <= 1; dx++) {
          for (var dy = -1; dy <= 1; dy++) {
            final a = ix + dx, b = iy + dy;
            if (a >= 0 && a < tiles && b >= 0 && b < tiles) {
              s += m[a][b];
              n++;
            }
          }
        }
        o[ix][iy] = s / n;
      }
    }
    return o;
  }

  /// 直方图分位数（p ∈ [0,1]），返回对应灰度值
  static double _scanPercentile(List<int> hist, int total, double p) {
    if (total <= 0) return 0;
    var want = (total * p).ceil();
    if (want < 1) want = 1;
    if (want > total) want = total;
    var acc = 0;
    for (var i = 0; i < 256; i++) {
      acc += hist[i];
      if (acc >= want) return i.toDouble();
    }
    return 255;
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

    // 2) Otsu 阈值二值化；失败时（如手持卡片：背景杂乱、主体占比小，
    // Otsu 容易把背景一起分进来）再用固定亮度阈值重试一次
    var ordered = _quadFromBinary(gray, sw, sh, _otsuThreshold(gray));
    if (ordered == null) {
      ordered = _quadFromBinary(gray, sw, sh, 150);
    }
    if (ordered == null) return null;

    // 放大回原图坐标
    final scaleX = src.width / sw, scaleY = src.height / sh;
    return ordered.map((p) => Offset(p.dx * scaleX, p.dy * scaleY)).toList();
  }

  /// 按给定阈值二值化并提取纸张四边形；检测不可靠时返回 null
  static List<Offset>? _quadFromBinary(img.Image gray, int sw, int sh, int threshold) {
    final bin = List.generate(sh, (_) => List<int>.filled(sw, 0));
    for (var y = 0; y < sh; y++) {
      for (var x = 0; x < sw; x++) {
        bin[y][x] = gray.getPixel(x, y).r > threshold ? 1 : 0;
      }
    }

    // 提取最大的连通亮区域（纸张本体），剔除背景噪声干扰
    final region = _largestBrightRegion(bin, sw, sh);
    if (region.length < sw * sh * 0.02) return null;

    // 求凸包
    final hull = _convexHull(region);
    if (hull.length < 4) return null;

    // 多边形近似（RDP），压出真正的纸张角点
    final eps = _perimeter(hull) * 0.02;
    final approx = _rdp(hull, eps);

    // 取面积最大的 4 角四边形
    final quad = _bestQuad(approx);
    if (quad == null) return null;

    // 排序 + 面积校验
    final ordered = _orderCorners(quad);
    if (_quadArea(ordered) < sw * sh * 0.06) return null;

    // 可靠性校验：特写照片里纸张常超出画面，凸包角点会贴在图像边界上，
    // 此时"检出的四边形"其实是画面本身，拿它做透视矫正会把边缘文字裁掉。
    // 判定不可靠返回 null，流程自动跳过矫正、只做曝光归一化（歪斜交给手动四角）。
    if (!_quadReliable(ordered, sw, sh)) return null;

    return ordered;
  }

  /// 四边形角点可靠性：≥2 个角贴着图像边界，或四边形几乎覆盖整幅画面，
  /// 都说明纸张出框、检测的是画面框而非纸张，不可信。
  static bool _quadReliable(List<Offset> ordered, int w, int h) {
    final marginX = w * 0.02, marginY = h * 0.02;
    var edgeCorners = 0;
    for (final p in ordered) {
      if (p.dx <= marginX || p.dx >= w - marginX || p.dy <= marginY || p.dy >= h - marginY) {
        edgeCorners++;
      }
    }
    if (edgeCorners >= 2) return false;
    if (_quadArea(ordered) > w * h * 0.92) return false;
    return true;
  }

  /// 最大连通亮区域（BFS），返回亮像素点列表
  static List<Offset> _largestBrightRegion(List<List<int>> bin, int w, int h) {
    final visited = List.generate(h, (_) => List<bool>.filled(w, false));
    var best = <Offset>[];
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        if (bin[y][x] == 1 && !visited[y][x]) {
          final stack = <(int, int)>[(x, y)];
          visited[y][x] = true;
          final comp = <Offset>[];
          while (stack.isNotEmpty) {
            final (cx, cy) = stack.removeLast();
            comp.add(Offset(cx.toDouble(), cy.toDouble()));
            for (final (nx, ny) in _neighbors8(cx, cy, w, h)) {
              if (!visited[ny][nx] && bin[ny][nx] == 1) {
                visited[ny][nx] = true;
                stack.add((nx, ny));
              }
            }
          }
          if (comp.length > best.length) best = comp;
        }
      }
    }
    return best;
  }

  /// Andrew 单调链凸包
  static List<Offset> _convexHull(List<Offset> pts) {
    if (pts.length < 3) return pts;
    final p = [...pts]
      ..sort((a, b) => a.dx != b.dx ? a.dx.compareTo(b.dx) : a.dy.compareTo(b.dy));
    List<Offset> build(List<Offset> seq) {
      final h = <Offset>[];
      for (final o in seq) {
        while (h.length >= 2) {
          final a = h[h.length - 2], b = h[h.length - 1];
          final cross =
              (b.dx - a.dx) * (o.dy - a.dy) - (b.dy - a.dy) * (o.dx - a.dx);
          if (cross <= 0) {
            h.removeLast();
          } else {
            break;
          }
        }
        h.add(o);
      }
      return h;
    }
    final lower = build(p);
    final upper = build(p.reversed.toList());
    lower.removeLast();
    upper.removeLast();
    return [...lower, ...upper];
  }

  /// 多边形周长
  static double _perimeter(List<Offset> pts) {
    var sum = 0.0;
    for (var i = 0; i < pts.length; i++) {
      sum += (pts[(i + 1) % pts.length] - pts[i]).distance;
    }
    return sum;
  }

  /// Ramer–Douglas–Peucker 多边形简化
  static List<Offset> _rdp(List<Offset> pts, double eps) {
    if (pts.length <= 2) return pts;
    var dmax = 0.0, index = 0;
    final n = pts.length;
    for (var i = 1; i < n - 1; i++) {
      final d = _perpDistSq(pts[i], pts[0], pts[n - 1]);
      if (d > dmax) {
        index = i;
        dmax = d;
      }
    }
    if (dmax > eps * eps) {
      final left = _rdp(pts.sublist(0, index + 1), eps);
      final right = _rdp(pts.sublist(index), eps);
      return [...left.sublist(0, left.length - 1), ...right];
    }
    return [pts.first, pts.last];
  }

  static double _perpDistSq(Offset p, Offset a, Offset b) {
    final dx = b.dx - a.dx, dy = b.dy - a.dy;
    final lenSq = dx * dx + dy * dy;
    if (lenSq == 0) {
      final qx = p.dx - a.dx, qy = p.dy - a.dy;
      return qx * qx + qy * qy;
    }
    final t = ((p.dx - a.dx) * dx + (p.dy - a.dy) * dy) / lenSq;
    final tc = t.clamp(0.0, 1.0).toDouble();
    final qx = a.dx + tc * dx, qy = a.dy + tc * dy;
    final ux = p.dx - qx, uy = p.dy - qy;
    return ux * ux + uy * uy;
  }

  /// 从近似顶点中取面积最大的 4 角四边形
  static List<Offset>? _bestQuad(List<Offset> pts) {
    if (pts.length < 4) return null;
    if (pts.length == 4) return pts;
    List<Offset>? best;
    var bestArea = -1.0;
    void comb(int start, List<Offset> cur) {
      if (cur.length == 4) {
        final a = _quadArea(cur);
        if (a > bestArea) {
          bestArea = a;
          best = List.of(cur);
        }
        return;
      }
      for (var i = start; i < pts.length; i++) {
        cur.add(pts[i]);
        comb(i + 1, cur);
        cur.removeLast();
      }
    }
    comb(0, []);
    return best;
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
