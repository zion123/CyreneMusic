import 'dart:io' show Platform;
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'dart:async';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import '../services/rhythm_service.dart';

/// 动态网格渐变背景组件 (Apple Music 风格重写版)
/// 通过多层随机位移的色块 + 深度高斯模糊实现丝滑液态效果
class MeshGradientBackground extends StatefulWidget {
  final List<Color> colors;
  final double speed;
  final Color backgroundColor;
  final bool animate;
  /// 是否使用模拟节奏（非 Windows 平台自动启用）
  final bool? simulateRhythm;

  const MeshGradientBackground({
    super.key,
    required this.colors,
    this.speed = 0.35,
    this.backgroundColor = Colors.black,
    this.animate = true,
    this.simulateRhythm,
  });

  @override
  State<MeshGradientBackground> createState() => _MeshGradientBackgroundState();
}

class _MeshGradientBackgroundState extends State<MeshGradientBackground>
    with TickerProviderStateMixin {
  late Ticker _ticker;
  double _time = 0.0;
  
  // 用于色彩平滑过渡的控制器
  late AnimationController _colorController;
  List<Color> _previousColors = [];
  List<Color> _currentColors = [];
  List<Color> _targetColors = [];

  // 律动相关
  StreamSubscription? _rhythmSubscription;
  double _bassIntensity = 0.0;
  double _extraTime = 0.0; // 用于根据节奏加速时间

  // 判断是否应该使用模拟节奏
  bool get _shouldSimulateRhythm {
    if (widget.simulateRhythm != null) return widget.simulateRhythm!;
    // 非 Windows 平台自动启用模拟模式
    if (kIsWeb) return true;
    return !Platform.isWindows;
  }

  @override
  void initState() {
    super.initState();
    _currentColors = _ensureMinColors(widget.colors);
    _previousColors = List.from(_currentColors);
    _targetColors = List.from(_currentColors);

    _colorController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    );

    _ticker = createTicker(_onTick);
    if (widget.animate) {
      _ticker.start();
      if (!_shouldSimulateRhythm) {
        _setupRhythmListener();
      }
    }
  }

  void _setupRhythmListener() {
    _rhythmSubscription?.cancel();
    _rhythmSubscription = RhythmService().bandsStream.listen((bands) {
      if (!mounted) return;
      setState(() {
        _bassIntensity = RhythmService().bassIntensity;
      });
    });
    // Windows 平台默认启动捕获
    RhythmService().start();
  }

  List<Color> _ensureMinColors(List<Color> colors) {
    if (colors.isEmpty) return DynamicBackgroundColorExtractor.getDefaultColors();
    List<Color> result = List.from(colors);
    // 补齐到至少 5 个颜色以保证丰富度
    while (result.length < 5) {
      result.add(result[result.length % result.length].withOpacity(0.8));
    }
    return result;
  }

  @override
  void didUpdateWidget(MeshGradientBackground oldWidget) {
    super.didUpdateWidget(oldWidget);
    
    if (!_colorsEqual(oldWidget.colors, widget.colors)) {
      _previousColors = List.from(_currentColors);
      _targetColors = _ensureMinColors(widget.colors);
      _colorController.forward(from: 0.0);
    } else if (widget.colors.isNotEmpty && _currentColors.isEmpty) {
      // 容错处理：如果当前颜色为空但新传入了颜色，强制初始化
      _targetColors = _ensureMinColors(widget.colors);
      _currentColors = List.from(_targetColors);
    }
    
    if (widget.animate != oldWidget.animate) {
      if (widget.animate) {
        _ticker.start();
        _setupRhythmListener();
      } else {
        _ticker.stop();
        _rhythmSubscription?.cancel();
        RhythmService().stop();
      }
    }
  }

  bool _colorsEqual(List<Color> a, List<Color> b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i].toARGB32() != b[i].toARGB32()) return false;
    }
    return true;
  }

  void _onTick(Duration elapsed) {
    if (!mounted) return;
    
    // 模拟节奏模式：使用正弦波生成平滑的强度变化
    if (_shouldSimulateRhythm) {
      final elapsedSeconds = elapsed.inMilliseconds / 1000.0;
      // 多重正弦波叠加，模拟自然的节奏感
      _bassIntensity = 0.25 + 
          0.15 * math.sin(elapsedSeconds * 2.5) + 
          0.10 * math.sin(elapsedSeconds * 1.7 + 0.5) +
          0.08 * math.sin(elapsedSeconds * 4.1 + 1.2);
      _bassIntensity = _bassIntensity.clamp(0.0, 0.8);
    }
    
    // 根据重低音强度增加额外的时间偏移，产生动态加速感
    _extraTime += _bassIntensity * 0.03;
    
    setState(() {
      _time = (elapsed.inMilliseconds / 1000.0 * widget.speed) + _extraTime;
      
      // 更新当前色彩（平滑过渡）
      if (_colorController.isAnimating) {
        final t = Curves.easeInOut.transform(_colorController.value);
        _currentColors = List.generate(_targetColors.length, (i) {
          final startColor = i < _previousColors.length ? _previousColors[i] : _previousColors.last;
          return Color.lerp(startColor, _targetColors[i], t)!;
        });
      }
    });
  }

  @override
  void dispose() {
    _ticker.dispose();
    _colorController.dispose();
    _rhythmSubscription?.cancel();
    // 注意：这里不全局停止 RhythmService，因为可能有多个背景引用，或者全局生命周期管理
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: Stack(
        children: [
          // 核心绘制层
          CustomPaint(
            painter: _MeshGradientPainter(
              colors: _currentColors,
              time: _time,
              backgroundColor: widget.backgroundColor,
              bassIntensity: _bassIntensity, // 传递律动强度
            ),
            size: Size.infinite,
          ),
          // Apple Music 液态感的关键：极高模糊
          Positioned.fill(
            child: BackdropFilter(
              filter: ui.ImageFilter.blur(sigmaX: 100, sigmaY: 100), // 增加模糊半径以显著消除色块边界感
              child: Container(color: Colors.transparent),
            ),
          ),
          // 质感杂色层 (Grain/Noise)
          const Positioned.fill(child: _GrainTexture()),
        ],
      ),
    );
  }
}

class _MeshGradientPainter extends CustomPainter {
  final List<Color> colors;
  final double time;
  final Color backgroundColor;
  final double bassIntensity;

  _MeshGradientPainter({
    required this.colors,
    required this.time,
    required this.backgroundColor,
    required this.bassIntensity,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // 稳定性检查：如果尺寸为 0，跳过绘制以防止 Gradient.radial 抛出异常
    if (size.width <= 0 || size.height <= 0 || colors.isEmpty) return;

    final paint = Paint()..style = PaintingStyle.fill;
    
    // 背景底色
    canvas.drawRect(Offset.zero & size, paint..color = backgroundColor);

    final random = math.Random(42); // 固定种子保证逻辑一致性

    final double shortestSide = size.shortestSide;

    // 绘制 6 个动态流体色彩斑块
    for (int i = 0; i < 6; i++) {
      final color = colors[i % colors.length];
      // 提取核心颜色，强制增加饱和度和明亮度，使画面更"鲜艳明显"
      final hsl = HSLColor.fromColor(color);
      final boostedColor = hsl
          .withSaturation((hsl.saturation + 0.25).clamp(0.6, 1.0))
          .withLightness((hsl.lightness + 0.05).clamp(0.4, 0.8))
          .toColor();
      
      // 为每个斑块生成独特的有机运动轨迹 (使用较大幅度和频率)
      final double xFreq = (0.2 + random.nextDouble() * 0.2);
      final double yFreq = (0.15 + random.nextDouble() * 0.2);
      
      // 锚点分布逻辑：收紧到可视区域内部，避免溢出
      final anchors = [
        const Offset(0.25, 0.25),   // 左上（内收）
        const Offset(0.75, 0.25),   // 右上（内收）
        const Offset(0.25, 0.75),   // 左下（内收）
        const Offset(0.75, 0.75),   // 右下（内收）
        const Offset(0.4, 0.5),     // 中偏左
        const Offset(0.6, 0.5),     // 中偏右
      ];
      final anchor = anchors[i % anchors.length];
      
      // 减小位移幅度（0.18 -> 0.12），避免色块溢出边界
      final centerX = size.width * (anchor.dx + 0.12 * math.sin(time * xFreq + i * 1.5));
      final centerY = size.height * (anchor.dy + 0.12 * math.cos(time * yFreq + i * 2.2));
      
      // 斑块半径：减小基础半径（0.8~1.3 -> 0.5~0.85），确保大部分渐变在可视区域内
      final double baseRadius = shortestSide * (0.5 + random.nextDouble() * 0.35);
      double radius = baseRadius * (1.0 + 0.12 * math.sin(time * 0.2 + i));
      
      // 律动膨胀（降低膨胀系数 0.8 -> 0.5，保持动态但避免溢出）
      radius += baseRadius * bassIntensity * 0.5;
      
      if (radius <= 0.001) radius = 0.001; // 强制正值

      // 提高不透明度，增加"色块厚度感"，使渐变层次更分明
      final gradient = ui.Gradient.radial(
        Offset(centerX, centerY),
        radius,
        [
          boostedColor.withOpacity(0.95), // 中心极高不透明度
          boostedColor.withOpacity(0.5),  // 中间层（稍微提高，增强层次感）
          boostedColor.withOpacity(0.0),  // 边缘淡出
        ],
        const [0.0, 0.6, 1.0], // 调整渐变分布，使颜色更集中在可视区域
      );

      paint.shader = gradient;
      
      // 弹性变形（降低变形幅度 0.2 -> 0.15，避免极端拉伸导致溢出）
      final distortion = bassIntensity * 0.3;
      final canvasScaleX = (1.0 + 0.15 * math.sin(time * 0.15 + i) + distortion);
      final canvasScaleY = (1.0 + 0.15 * math.cos(time * 0.18 + i * 0.5) - distortion);
      
      canvas.save();
      canvas.translate(centerX, centerY);
      canvas.scale(canvasScaleX, canvasScaleY);
      canvas.drawCircle(Offset.zero, radius, paint);
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_MeshGradientPainter oldDelegate) => 
      oldDelegate.time != time || 
      oldDelegate.colors != colors;
}

/// 增加质感的杂色层
class _GrainTexture extends StatelessWidget {
  const _GrainTexture();

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: 0.04, // 非常微弱
      child: CustomPaint(
        painter: _GrainPainter(),
      ),
    );
  }
}

class _GrainPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = Colors.white;
    final random = math.Random();
    
    // 模拟杂色的简单点阵绘制
    // 减小点数以平衡性能
    for (int i = 0; i < 800; i++) {
      final x = random.nextDouble() * size.width;
      final y = random.nextDouble() * size.height;
      canvas.drawRect(Rect.fromLTWH(x, y, 1.2, 1.2), paint);
    }
  }

  @override
  bool shouldRepaint(CustomPainter oldDelegate) => false;
}

class DynamicBackgroundColorExtractor {
  static List<Color> extractColors({
    Color? vibrantColor,
    Color? mutedColor,
    Color? dominantColor,
    Color? lightVibrantColor,
    Color? darkVibrantColor,
    Color? lightMutedColor,
    Color? darkMutedColor,
  }) {
    final List<Color> result = [];
    
    // 候选池：按优先级排序
    final List<Color?> candidates = [
      vibrantColor,
      mutedColor,
      dominantColor,
      darkVibrantColor,
      lightVibrantColor,
      darkMutedColor,
      lightMutedColor,
    ];

    // 1. 基础筛选与去重
    for (final color in candidates) {
      if (color != null && !_isSimilarColor(color, result)) {
        result.add(color);
      }
    }
    
    // 3. 增强逻辑：如果颜色少于 3 个，通过色相旋转生成互补/邻近色，确保背景丰富度
    if (result.length < 3) {
      if (result.isEmpty) {
        result.addAll(getDefaultColors());
      } else {
        final baseColor = result[0];
        final hsl = HSLColor.fromColor(baseColor);
        
        // 如果只有一个颜色，生成三元色 (Triadic) + 更大的明度差异
        if (result.length == 1) {
          // 第二色：色相 +120°，明度略微调暗
          final color2 = hsl
              .withHue((hsl.hue + 120) % 360)
              .withSaturation(math.max(hsl.saturation, 0.55))
              .withLightness((hsl.lightness - 0.15).clamp(0.2, 0.75))
              .toColor();
          // 第三色：色相 +240°，明度略微调亮
          final color3 = hsl
              .withHue((hsl.hue + 240) % 360)
              .withSaturation(math.max(hsl.saturation, 0.55))
              .withLightness((hsl.lightness + 0.15).clamp(0.25, 0.8))
              .toColor();
          result.add(color2);
          result.add(color3);
        } 
        // 如果有两个颜色，生成一个互补色（色相 +180°）
        else if (result.length == 2) {
          final color3 = hsl
              .withHue((hsl.hue + 180) % 360)
              .withSaturation(math.max(hsl.saturation, 0.5))
              .withLightness((hsl.lightness + 0.1).clamp(0.25, 0.75))
              .toColor();
          result.add(color3);
        }
      }
    }
    
    // 4. 最终补齐到 5 个（通过更大的色相偏移和明度变化防止单调）
    int fillIndex = 0;
    while (result.length < 5) {
      final base = result[fillIndex % result.length];
      final hsl = HSLColor.fromColor(base);
      // 交替使用不同的偏移策略
      final hueOffset = (fillIndex % 2 == 0) ? 45.0 : -30.0;
      final lightnessOffset = (fillIndex % 2 == 0) ? 0.18 : -0.12;
      result.add(hsl
          .withHue((hsl.hue + hueOffset) % 360)
          .withLightness((hsl.lightness + lightnessOffset).clamp(0.15, 0.85))
          .toColor());
      fillIndex++;
    }
    
    return result.take(5).toList();
  }
  
  /// 色彩相似度判定 (基于 HSL 颜色空间)
  /// 使用色相、饱和度、明度三个维度综合判断，比 RGB 欧几里得距离更符合人眼感知
  static bool _isSimilarColor(Color color, List<Color> existingColors) {
    final hsl = HSLColor.fromColor(color);
    
    for (final existing in existingColors) {
      final existingHsl = HSLColor.fromColor(existing);
      
      // 计算色相差（考虑色环的循环特性，0° 和 360° 是同一个颜色）
      double hueDiff = (hsl.hue - existingHsl.hue).abs();
      if (hueDiff > 180) hueDiff = 360 - hueDiff;
      
      // 明度差
      final lightnessDiff = (hsl.lightness - existingHsl.lightness).abs();
      
      // 饱和度差
      final saturationDiff = (hsl.saturation - existingHsl.saturation).abs();
      
      // 判定规则：
      // - 色相差 < 25° 且 明度差 < 0.12 且 饱和度差 < 0.2 => 认为相似
      // - 任一维度超出阈值则认为不同
      if (hueDiff < 25 && lightnessDiff < 0.12 && saturationDiff < 0.2) {
        return true;
      }
    }
    return false;
  }

  static Color _adjustBrightness(Color color, double amount) {
    final hsl = HSLColor.fromColor(color);
    return hsl.withLightness((hsl.lightness + amount).clamp(0.0, 1.0)).toColor();
  }

  static List<Color> getDefaultColors() => const [
    Color(0xFF60A5FA), Color(0xFF1E3A5F), Color(0xFF3B82F6),
    Color(0xFF6366F1), Color(0xFF1E1B4B),
  ];
}
