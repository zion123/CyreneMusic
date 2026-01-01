import 'dart:async';
import 'dart:math';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import '../../services/player_service.dart';
import '../../services/lyric_font_service.dart';
import '../../services/lyric_style_service.dart';
import '../../models/lyric_line.dart';

/// 移动端流体云歌词面板 - 由桌面端 PlayerFluidCloudLyricsPanel 复制而来，用于独立适配
class MobilePlayerFluidCloudLyricsPanel extends StatefulWidget {
  final List<LyricLine> lyrics;
  final int currentLyricIndex;
  final bool showTranslation;
  final int visibleLineCount;

  const MobilePlayerFluidCloudLyricsPanel({
    super.key,
    required this.lyrics,
    required this.currentLyricIndex,
    required this.showTranslation,
    this.visibleLineCount = 7,
  });

  @override
  State<MobilePlayerFluidCloudLyricsPanel> createState() => _MobilePlayerFluidCloudLyricsPanelState();
}

class _MobilePlayerFluidCloudLyricsPanelState extends State<MobilePlayerFluidCloudLyricsPanel>
    with TickerProviderStateMixin {
  
  // 核心变量
  final double _lineHeight = 80.0; 
  
  // 滚动/拖拽相关
  double _dragOffset = 0.0;
  bool _isDragging = false;
  Timer? _dragResetTimer;

  // 布局缓存
  final Map<String, double> _heightCache = {};
  double? _lastViewportWidth;
  String? _lastFontFamily;
  bool? _lastShowTranslation;
  
  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    _dragResetTimer?.cancel();
    super.dispose();
  }

  void _onDragStart(DragStartDetails details) {
    setState(() {
      _isDragging = true;
      _dragResetTimer?.cancel();
    });
  }

  void _onDragUpdate(DragUpdateDetails details) {
    setState(() {
      _dragOffset += details.delta.dy;
    });
  }

  void _onDragEnd(DragEndDetails details) {
     _dragResetTimer = Timer(const Duration(milliseconds: 600), () {
       if (mounted) {
         setState(() {
           _isDragging = false;
           _dragOffset = 0.0; 
         });
       }
     });
  }

  @override
  Widget build(BuildContext context) {
    if (widget.lyrics.isEmpty) {
      return _buildNoLyric();
    }

    return AnimatedBuilder(
      animation: LyricStyleService(),
      builder: (context, _) {
        final lyricStyle = LyricStyleService();
        return LayoutBuilder(
          builder: (context, constraints) {
            final viewportHeight = constraints.maxHeight;
            final viewportWidth = constraints.maxWidth;
            
            final centerY = lyricStyle.currentAlignment == LyricAlignment.center 
                ? viewportHeight * 0.5 
                : viewportHeight * 0.25;
            
            final visibleBuffer = 6; 
            final visibleLines = (viewportHeight / _lineHeight).ceil();
            final minIndex = max(0, widget.currentLyricIndex - visibleBuffer - (visibleLines ~/ 2));
            final maxIndex = min(widget.lyrics.length - 1, widget.currentLyricIndex + visibleBuffer + (visibleLines ~/ 2));

            final Map<int, double> heights = {};
            final textMaxWidth = viewportWidth - 40; // horizontal padding 20 * 2
            
            for (int i = minIndex; i <= maxIndex; i++) {
              heights[i] = _measureLyricItemHeight(i, textMaxWidth);
            }

            final Map<int, double> offsets = {};
            offsets[widget.currentLyricIndex] = 0;

            double currentOffset = 0;
            double prevHalfHeight = (heights[widget.currentLyricIndex] ?? _lineHeight) / 2;
            
            for (int i = widget.currentLyricIndex + 1; i <= maxIndex; i++) {
              final h = heights[i] ?? _lineHeight;
              currentOffset += prevHalfHeight + (h / 2); 
              offsets[i] = currentOffset;
              prevHalfHeight = h / 2;
            }

            currentOffset = 0;
            double nextHalfHeight = (heights[widget.currentLyricIndex] ?? _lineHeight) / 2;
            
            for (int i = widget.currentLyricIndex - 1; i >= minIndex; i--) {
              final h = heights[i] ?? _lineHeight;
              currentOffset -= (nextHalfHeight + h / 2);
              offsets[i] = currentOffset;
              nextHalfHeight = h / 2;
            }

            List<Widget> children = [];
            for (int i = minIndex; i <= maxIndex; i++) {
              children.add(_buildLyricItem(i, centerY, offsets[i] ?? 0.0, heights[i] ?? _lineHeight));
            }

            return GestureDetector(
              onVerticalDragStart: _onDragStart,
              onVerticalDragUpdate: _onDragUpdate,
              onVerticalDragEnd: _onDragEnd,
              behavior: HitTestBehavior.translucent, 
              child: Stack(
                fit: StackFit.expand,
                children: children,
              ),
            );
          },
        );
      },
    );
  }

  double _measureLyricItemHeight(int index, double maxWidth) {
    if (index < 0 || index >= widget.lyrics.length) return _lineHeight;
    final lyric = widget.lyrics[index];
    final fontFamily = LyricFontService().currentFontFamily ?? 'Microsoft YaHei';
    
    final cacheKey = '${lyric.startTime.inMilliseconds}_${lyric.text.hashCode}_$maxWidth';
    if (_lastViewportWidth == maxWidth && 
        _lastFontFamily == fontFamily && 
        _lastShowTranslation == widget.showTranslation &&
        _heightCache.containsKey(cacheKey)) {
      return _heightCache[cacheKey]!;
    }

    final fontSize = 28.8; // 32.0 * 0.9

    final textPainter = TextPainter(
      text: TextSpan(
        text: lyric.text,
        style: TextStyle(
          fontFamily: fontFamily,
          fontSize: fontSize,
          fontWeight: FontWeight.w800,
          height: 1.1,
        ),
      ),
      textDirection: TextDirection.ltr,
    );
    textPainter.layout(maxWidth: maxWidth);
    double h = textPainter.height * 1.3 / 1.1;

    if (widget.showTranslation && lyric.translation != null && lyric.translation!.isNotEmpty) {
      final transPainter = TextPainter(
        text: TextSpan(
          text: lyric.translation,
          style: TextStyle(
            fontFamily: fontFamily,
            fontSize: 16.2, // 18 * 0.9
            fontWeight: FontWeight.w600,
            height: 1.0,
          ),
        ),
        textDirection: TextDirection.ltr,
      );
      transPainter.layout(maxWidth: maxWidth);
      h += 8.0;
      h += transPainter.height * 1.4;
    }
    
    h += 24.0; 
    final result = max(h, _lineHeight);
    
    _lastViewportWidth = maxWidth;
    _lastFontFamily = fontFamily;
    _lastShowTranslation = widget.showTranslation;
    _heightCache[cacheKey] = result;
    
    return result;
  }

  Widget _buildLyricItem(int index, double centerYOffset, double relativeOffset, double itemHeight) {
    final activeIndex = widget.currentLyricIndex;
    final diff = index - activeIndex;
    
    final double baseTranslation = relativeOffset;
    final double sineOffset = sin(diff * 0.8) * 20.0;
    
    double targetY = centerYOffset + baseTranslation + sineOffset - (itemHeight / 2);

    if (_isDragging) {
       targetY += _dragOffset;
    }
    
    double targetScale;
    if (diff == 0) {
      targetScale = 1.15;
    } else if (diff.abs() < 3) {
      targetScale = 1.0 - diff.abs() * 0.1;
    } else {
      targetScale = 0.7;
    }

    double targetOpacity;
    if (diff.abs() > 4) {
      targetOpacity = 0.0;
    } else {
      targetOpacity = 1.0 - diff.abs() * 0.2;
    }
    targetOpacity = targetOpacity.clamp(0.0, 1.0).toDouble();

    final int delayMs = (diff.abs() * 50).toInt();

    double targetBlur = 4.0;
    if (diff == 0) targetBlur = 0.0;
    else if (diff.abs() == 1) targetBlur = 1.0;

    final bool isActive = (diff == 0);

    return _ElasticLyricLine(
      key: ValueKey(index),
      text: widget.lyrics[index].text,
      translation: widget.lyrics[index].translation,
      lyric: widget.lyrics[index], 
      lyrics: widget.lyrics,     
      index: index,             
      lineHeight: _lineHeight,
      targetY: targetY,
      targetScale: targetScale,
      targetOpacity: targetOpacity,
      targetBlur: targetBlur,
      isActive: isActive,
      delay: Duration(milliseconds: delayMs),
      isDragging: _isDragging,
      showTranslation: widget.showTranslation,
    );
  }

  Widget _buildNoLyric() {
    return const Center(
      child: Text(
        '暂无歌词',
        style: TextStyle(color: Colors.white54, fontSize: 21.6), // 24 * 0.9
      ),
    );
  }
}

class _ElasticLyricLine extends StatefulWidget {
  final String text;
  final String? translation;
  final LyricLine lyric;
  final List<LyricLine> lyrics;
  final int index;
  final double lineHeight;
  
  final double targetY;
  final double targetScale;
  final double targetOpacity;
  final double targetBlur;
  final bool isActive;
  final Duration delay;
  final bool isDragging;
  final bool showTranslation;

  const _ElasticLyricLine({
    Key? key,
    required this.text,
    this.translation,
    required this.lyric,
    required this.lyrics,
    required this.index,
    required this.lineHeight,
    required this.targetY,
    required this.targetScale,
    required this.targetOpacity,
    required this.targetBlur,
    required this.isActive,
    required this.delay,
    required this.isDragging,
    required this.showTranslation,
  }) : super(key: key);

  @override
  State<_ElasticLyricLine> createState() => _ElasticLyricLineState();
}

class _ElasticLyricLineState extends State<_ElasticLyricLine> with TickerProviderStateMixin {
  late double _y;
  late double _scale;
  late double _opacity;
  late double _blur;
  
  AnimationController? _controller;
  Animation<double>? _yAnim;
  Animation<double>? _scaleAnim;
  Animation<double>? _opacityAnim;
  Animation<double>? _blurAnim;
  
  Timer? _delayTimer;

  static const Curve elasticCurve = Cubic(0.34, 1.56, 0.64, 1.0);
  static const Duration animDuration = Duration(milliseconds: 800);
  
  @override
  void initState() {
    super.initState();
    _y = widget.targetY;
    _scale = widget.targetScale;
    _opacity = widget.targetOpacity;
    _blur = widget.targetBlur;
  }

  @override
  void didUpdateWidget(_ElasticLyricLine oldWidget) {
    super.didUpdateWidget(oldWidget);
    const double epsilon = 0.05;
    bool positionChanged = (oldWidget.targetY - widget.targetY).abs() > epsilon;
    bool scaleChanged = (oldWidget.targetScale - widget.targetScale).abs() > 0.001;
    bool opacityChanged = (oldWidget.targetOpacity - widget.targetOpacity).abs() > 0.01;
    bool blurChanged = (oldWidget.targetBlur - widget.targetBlur).abs() > 0.1;
    
    if (positionChanged || scaleChanged || opacityChanged || blurChanged) {
      _startAnimation();
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    _delayTimer?.cancel();
    super.dispose();
  }

  void _startAnimation() {
    _delayTimer?.cancel();
    
    if (widget.isDragging) {
      _controller?.stop();
      setState(() {
        _y = widget.targetY;
        _scale = widget.targetScale;
        _opacity = widget.targetOpacity;
        _blur = widget.targetBlur;
      });
      return;
    }

    void play() {
      _controller?.dispose();
      _controller = AnimationController(
        vsync: this,
        duration: animDuration,
      );

      _yAnim = Tween<double>(begin: _y, end: widget.targetY).animate(
        CurvedAnimation(parent: _controller!, curve: elasticCurve)
      );
      _scaleAnim = Tween<double>(begin: _scale, end: widget.targetScale).animate(
         CurvedAnimation(parent: _controller!, curve: elasticCurve)
      );
      _opacityAnim = Tween<double>(begin: _opacity, end: widget.targetOpacity).animate(
        CurvedAnimation(parent: _controller!, curve: Curves.ease)
      );
      _blurAnim = Tween<double>(begin: _blur, end: widget.targetBlur).animate(
        CurvedAnimation(parent: _controller!, curve: Curves.ease)
      );

      _controller!.addListener(() {
        if (!mounted) return;
        setState(() {
          _y = _yAnim!.value;
          _scale = _scaleAnim!.value;
          _opacity = _opacityAnim!.value;
          _blur = _blurAnim!.value;
        });
      });

      _controller!.forward();
    }

    if (widget.delay == Duration.zero) {
      play();
    } else {
      _delayTimer = Timer(widget.delay, play);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_opacity < 0.01) return const SizedBox();

    return Positioned(
      top: _y,
      left: 0,
      right: 0,
      child: Transform.scale(
        scale: _scale,
        alignment: Alignment.centerLeft,
        child: Opacity(
          opacity: _opacity,
          child: _OptionalBlur(
            blur: _blur,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              alignment: Alignment.centerLeft,
              child: _buildInnerContent(),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildInnerContent() {
    final fontFamily = LyricFontService().currentFontFamily ?? 'Microsoft YaHei';
    final double textFontSize = 28.8; // 32.0 * 0.9

    Color textColor;
    if (widget.isActive) {
      textColor = Colors.white;
    } else {
      textColor = Colors.white.withOpacity(0.3); 
    }
    
    Widget textWidget;
    if (widget.isActive && widget.lyric.hasWordByWord) {
      textWidget = _KaraokeText(
        text: widget.text,
        lyric: widget.lyric,
        lyrics: widget.lyrics,
        index: widget.index,
        originalTextStyle: TextStyle(
             fontFamily: fontFamily,
             fontSize: textFontSize, 
             fontWeight: FontWeight.w800,
             color: Colors.white,
             height: 1.3,
        ),
      );
    } else {
      textWidget = Text(
        widget.text,
        style: TextStyle(
          fontFamily: fontFamily,
          fontSize: textFontSize, 
          fontWeight: FontWeight.w800,
          color: textColor,
          height: 1.3,
        ),
      );
    }
    
    if (widget.showTranslation && widget.translation != null && widget.translation!.isNotEmpty) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          textWidget,
          Padding(
            padding: const EdgeInsets.only(top: 8.0),
            child: Text(
              widget.translation!,
              style: TextStyle(
                fontFamily: fontFamily,
                fontSize: 16.2, // 18 * 0.9
                fontWeight: FontWeight.w600,
                color: Colors.white.withOpacity(0.3),
                height: 1.4,
              ),
            ),
          )
        ],
      );
    }
    
    if (widget.index == 0 && !widget.isDragging) {
       return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
           _CountdownDots(lyrics: widget.lyrics, countdownThreshold: 5.0),
           textWidget, 
        ]
       );
    }

    return textWidget;
  }
}

class _OptionalBlur extends StatelessWidget {
  final double blur;
  final Widget child;

  const _OptionalBlur({required this.blur, required this.child});

  @override
  Widget build(BuildContext context) {
    if (blur < 1.0) return child;
    return ImageFiltered(
      imageFilter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
      child: child,
    );
  }
}

class _KaraokeText extends StatefulWidget {
  final String text;
  final LyricLine lyric;
  final List<LyricLine> lyrics;
  final int index;
  final TextStyle originalTextStyle;

  const _KaraokeText({
    required this.text,
    required this.lyric,
    required this.lyrics,
    required this.index,
    required this.originalTextStyle,
  });

  @override
  State<_KaraokeText> createState() => _KaraokeTextState();
}

class _KaraokeTextState extends State<_KaraokeText> with SingleTickerProviderStateMixin {
  late Ticker _ticker;
  double _lineProgress = 0.0;
  final ValueNotifier<Duration> _positionNotifier = ValueNotifier(Duration.zero);

  double _cachedMaxWidth = 0.0;
  TextStyle? _cachedStyle;
  int _cachedLineCount = 1;
  double _line1Width = 0.0;
  double _line2Width = 0.0;
  double _line1Height = 0.0;
  double _line2Height = 0.0;
  double _line1Ratio = 0.5;

  late Duration _duration;

  @override
  void initState() {
    super.initState();
    _calculateDuration();
    _ticker = createTicker(_onTick);
    _ticker.start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    _positionNotifier.dispose();
    super.dispose();
  }

  void _calculateDuration() {
    if (widget.index < widget.lyrics.length - 1) {
      _duration = widget.lyrics[widget.index + 1].startTime - widget.lyric.startTime;
    } else {
      _duration = const Duration(seconds: 5);
    }
    if (_duration.inMilliseconds == 0) _duration = const Duration(seconds: 3);
  }

  void _onTick(Duration elapsed) {
    if (!mounted) return;
    final currentPos = PlayerService().position;
    _positionNotifier.value = currentPos;

    if (!widget.lyric.hasWordByWord || widget.lyric.words == null) {
      final elapsedFromStart = currentPos - widget.lyric.startTime;
      final newProgress = (elapsedFromStart.inMilliseconds / _duration.inMilliseconds).clamp(0.0, 1.0);

      if ((newProgress - _lineProgress).abs() > 0.005) {
        setState(() {
          _lineProgress = newProgress;
        });
      }
    }
  }
  
  void _updateLayoutCache(BoxConstraints constraints, TextStyle style) {
    if (_cachedMaxWidth == constraints.maxWidth && _cachedStyle == style) return;
    _cachedMaxWidth = constraints.maxWidth;
    _cachedStyle = style;
    
    final textSpan = TextSpan(text: widget.text, style: style);
    final textPainter = TextPainter(
      text: textSpan,
      textDirection: TextDirection.ltr,
    );
    textPainter.layout(maxWidth: constraints.maxWidth);
    
    final metrics = textPainter.computeLineMetrics();
    _cachedLineCount = metrics.length.clamp(1, 2);
    if (metrics.isNotEmpty) {
       _line1Width = metrics[0].width;
       _line1Height = metrics[0].height;
       if (metrics.length > 1) {
           _line2Width = metrics[1].width;
           _line2Height = metrics[1].height;
       }
    }
    
    final totalWidth = _line1Width + _line2Width;
    _line1Ratio = totalWidth > 0 ? _line1Width / totalWidth : 0.5;
    textPainter.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final style = widget.originalTextStyle;
    if (widget.lyric.hasWordByWord && widget.lyric.words != null && widget.lyric.words!.isNotEmpty) {
      return _buildWordByWordEffect(style);
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        _updateLayoutCache(constraints, style);
        return _buildLineGradientEffect(style);
      },
    );
  }
  
  Widget _buildWordByWordEffect(TextStyle style) {
    final words = widget.lyric.words!;
    return Wrap(
      alignment: WrapAlignment.start,
      crossAxisAlignment: WrapCrossAlignment.center,
      runSpacing: 2.0, 
      children: List.generate(words.length, (index) {
        final word = words[index];
        return _WordFillWidget(
          key: ValueKey('${widget.index}_$index'),
          text: word.text,
          word: word,
          style: style,
          positionNotifier: _positionNotifier,
        );
      }),
    );
  }
  
  Widget _buildLineGradientEffect(TextStyle style) {
    if (_cachedLineCount == 1) {
      return RepaintBoundary(
        child: ShaderMask(
          shaderCallback: (bounds) {
            return LinearGradient(
              begin: Alignment.centerLeft, end: Alignment.centerRight,
              colors: const [Colors.white, Color(0x99FFFFFF)],
              stops: [_lineProgress, _lineProgress],
              tileMode: TileMode.clamp,
            ).createShader(bounds);
          },
          blendMode: BlendMode.srcIn,
          child: Text(widget.text, style: style),
        ),
      );
    }
    
    double line1Progress = 0.0; 
    double line2Progress = 0.0;
    
    if (_lineProgress <= _line1Ratio) {
      if (_line1Ratio > 0) line1Progress = _lineProgress / _line1Ratio;
      line2Progress = 0.0;
    } else {
      line1Progress = 1.0;
      if (_line1Ratio < 1.0) line2Progress = (_lineProgress - _line1Ratio) / (1.0 - _line1Ratio);
    }
    
    final dimText = Text(widget.text, style: style.copyWith(color: const Color(0x99FFFFFF)));
    final brightText = Text(widget.text, style: style.copyWith(color: Colors.white));
    
    return RepaintBoundary(
      child: Stack(
        children: [
          dimText,
          ClipRect(
            clipper: _LineClipper(lineIndex: 0, progress: line1Progress, lineHeight: _line1Height, lineWidth: _line1Width),
            child: brightText,
          ),
          if (_cachedLineCount > 1)
            ClipRect(
              clipper: _LineClipper(lineIndex: 1, progress: line2Progress, lineHeight: _line2Height + 10, lineWidth: _line2Width, yOffset: _line1Height),
              child: brightText,
            ),
        ],
      ),
    );
  }
}

class _WordFillWidget extends StatefulWidget {
  final String text;
  final LyricWord word;
  final TextStyle style;
  final ValueNotifier<Duration> positionNotifier;

  const _WordFillWidget({
    Key? key,
    required this.text,
    required this.word,
    required this.style,
    required this.positionNotifier,
  }) : super(key: key);

  @override
  State<_WordFillWidget> createState() => _WordFillWidgetState();
}

class _WordFillWidgetState extends State<_WordFillWidget> with TickerProviderStateMixin {
  late AnimationController _floatController;
  late Animation<double> _floatOffset;
  double _progress = 0.0;
  bool? _isAsciiCached;

  static const double fadeRatio = 0.3;
  static const double maxFloatOffset = -3.0;

  @override
  void initState() {
    super.initState();
    _floatController = AnimationController(vsync: this, duration: const Duration(milliseconds: 500));
    _floatOffset = Tween<double>(begin: 0.0, end: maxFloatOffset).animate(CurvedAnimation(parent: _floatController, curve: Curves.easeOutBack));
    _updateProgress(widget.positionNotifier.value); 
    widget.positionNotifier.addListener(_onPositionUpdate);
    if (_progress >= 0.5) _floatController.value = 1.0;
  }

  void _onPositionUpdate() {
     if (!mounted) return;
     final oldProgress = _progress;
     _updateProgress(widget.positionNotifier.value);
     const double threshold = 0.5;
     if (_progress >= threshold && oldProgress < threshold) {
       _floatController.forward();
     } else if (_progress < threshold && oldProgress >= threshold) {
       _floatController.reverse();
     }
     final isAscii = _isAsciiText();
     final thresholdVal = isAscii ? 0.001 : 0.005;
     if ((oldProgress - _progress).abs() > thresholdVal || (_progress >= 1.0 && oldProgress < 1.0) || (_progress <= 0.0 && oldProgress > 0.0)) {
       setState(() {});
     }
  }

  @override
  void didUpdateWidget(_WordFillWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.positionNotifier != widget.positionNotifier) {
      oldWidget.positionNotifier.removeListener(_onPositionUpdate);
      widget.positionNotifier.addListener(_onPositionUpdate);
    }
    _updateProgress(widget.positionNotifier.value);
    if (_progress >= 0.5) { if (!_floatController.isAnimating && _floatController.value < 1.0) _floatController.forward(); } 
    else { if (!_floatController.isAnimating && _floatController.value > 0.0) _floatController.reverse(); }
  }

  void _updateProgress(Duration currentPos) {
    if (currentPos < widget.word.startTime) _progress = 0.0;
    else if (currentPos >= widget.word.endTime) _progress = 1.0;
    else {
      final wordDuration = widget.word.duration.inMilliseconds;
      _progress = (wordDuration <= 0) ? 1.0 : (currentPos - widget.word.startTime).inMilliseconds / wordDuration;
    }
    _progress = _progress.clamp(0.0, 1.0);
  }

  @override
  void dispose() {
    widget.positionNotifier.removeListener(_onPositionUpdate);
    _floatController.dispose();
    super.dispose();
  }

  bool _isAsciiText() {
    if (_isAsciiCached != null) return _isAsciiCached!;
    if (widget.text.isEmpty) return _isAsciiCached = false;
    int asciiCount = 0;
    for (final char in widget.text.runes) {
      if ((char >= 65 && char <= 90) || (char >= 97 && char <= 122)) asciiCount++;
    }
    return _isAsciiCached = asciiCount > widget.text.length / 2;
  }

  @override
  Widget build(BuildContext context) {
    final useLetterAnimation = _isAsciiText() && widget.text.length > 1;
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _floatOffset,
        builder: (context, child) => Transform.translate(offset: Offset(0, useLetterAnimation ? 0.0 : _floatOffset.value), child: child),
        child: _buildInner(),
      ),
    );
  }

  Widget _buildInner() {
    if (_isAsciiText() && widget.text.length > 1) return _buildLetterByLetterEffect();
    return _buildWholeWordEffect();
  }
  
  Widget _buildWholeWordEffect() {
    List<Color> colors; List<double> stops;
    if (_progress <= 0.0) { colors = [const Color(0x99FFFFFF), const Color(0x99FFFFFF)]; stops = [0.0, 1.0]; }
    else if (_progress >= 1.0) { colors = [Colors.white, Colors.white]; stops = [0.0, 1.0]; }
    else {
      const double glowW = 0.05;
      colors = [Colors.white.withOpacity(0.9), Colors.white, Colors.white, const Color(0x99FFFFFF), const Color(0x99FFFFFF)];
      stops = [0.0, (_progress - glowW).clamp(0.0, 1.0), _progress, (_progress + fadeRatio).clamp(0.0, 1.0), 1.0];
    }
    return ShaderMask(
      shaderCallback: (bounds) => LinearGradient(colors: colors, stops: stops).createShader(bounds),
      blendMode: BlendMode.srcIn,
      child: Padding(padding: const EdgeInsets.symmetric(vertical: 3.0), child: Text(widget.text, style: widget.style.copyWith(color: Colors.white))),
    );
  }

  Widget _buildLetterByLetterEffect() {
    final letters = widget.text.split('');
    const double rippleW = 1.2; const double maxLetterFloat = -4.0;
    return Row(
      mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic,
      children: List.generate(letters.length, (index) {
        final baseW = 1.0 / letters.length;
        final fStart = index * baseW; final fEnd = (index + 1) * baseW;
        final fProgress = ((_progress - fStart) / (fEnd - fStart)).clamp(0.0, 1.0);
        double lOffset = 0.0;
        if (_progress >= fEnd) lOffset = maxLetterFloat;
        else if (_progress > max(0.001, fStart - (baseW * rippleW))) {
           lOffset = Curves.easeOut.transform(((_progress - max(0.001, fStart - (baseW * rippleW))) / (fEnd - max(0.001, fStart - (baseW * rippleW)))).clamp(0.0, 1.0)) * maxLetterFloat;
        }
        List<Color> colors; List<double> stops;
        if (fProgress <= 0.0) { colors = [const Color(0x99FFFFFF), const Color(0x99FFFFFF)]; stops = [0.0, 1.0]; }
        else if (fProgress >= 1.0) { colors = [Colors.white, Colors.white]; stops = [0.0, 1.0]; }
        else {
          const double gW = 0.15;
          colors = [Colors.white.withOpacity(0.9), Colors.white, Colors.white, const Color(0x99FFFFFF), const Color(0x99FFFFFF)];
          stops = [0.0, (fProgress - gW).clamp(0.0, 1.0), fProgress, (fProgress + fadeRatio).clamp(0.0, 1.0), 1.0];
        }
        return Transform.translate(
          offset: Offset(0, lOffset),
          child: ShaderMask(
            shaderCallback: (bounds) => LinearGradient(colors: colors, stops: stops).createShader(bounds),
            blendMode: BlendMode.srcIn,
            child: Padding(padding: const EdgeInsets.symmetric(vertical: 4.0), child: Text(letters[index], style: widget.style.copyWith(color: Colors.white))),
          ),
        );
      }),
    );
  }
}

class _LineClipper extends CustomClipper<Rect> {
  final int lineIndex; final double progress; final double lineHeight; final double lineWidth; final double yOffset;
  _LineClipper({required this.lineIndex, required this.progress, required this.lineHeight, required this.lineWidth, this.yOffset = 0.0});
  @override Rect getClip(Size size) => Rect.fromLTWH(0, yOffset, lineWidth * progress, lineHeight);
  @override bool shouldReclip(_LineClipper oldClipper) => oldClipper.progress != progress;
}

class _CountdownDots extends StatefulWidget {
  final List<LyricLine> lyrics; final double countdownThreshold;
  const _CountdownDots({required this.lyrics, required this.countdownThreshold});
  @override State<_CountdownDots> createState() => _CountdownDotsState();
}

class _CountdownDotsState extends State<_CountdownDots> with TickerProviderStateMixin {
  late Ticker _ticker; double _progress = 0.0; bool _isVisible = false; bool _wasVisible = false;
  late AnimationController _appearController; late Animation<double> _appearAnimation;
  @override
  void initState() {
    super.initState();
    _appearController = AnimationController(duration: const Duration(milliseconds: 400), vsync: this);
    _appearAnimation = CurvedAnimation(parent: _appearController, curve: Curves.easeOutBack, reverseCurve: Curves.easeInBack);
    _ticker = createTicker(_onTick); _ticker.start();
  }
  @override void dispose() { _ticker.dispose(); _appearController.dispose(); super.dispose(); }
  void _onTick(Duration elapsed) {
    if (widget.lyrics.isEmpty) return;
    final timeUntilFirstLyric = (widget.lyrics.first.startTime - PlayerService().position).inMilliseconds / 1000.0;
    final shouldShow = PlayerService().isPlaying && PlayerService().position.inMilliseconds > 0 && timeUntilFirstLyric > 0 && timeUntilFirstLyric <= widget.countdownThreshold;
    if (shouldShow) {
      if (!_wasVisible) { _wasVisible = true; _appearController.forward(); }
      setState(() { _isVisible = true; _progress = (1.0 - (timeUntilFirstLyric / widget.countdownThreshold)).clamp(0.0, 1.0); });
    } else if (_isVisible || _wasVisible) {
      if (_wasVisible) { _wasVisible = false; _appearController.reverse(); }
      setState(() { _isVisible = false; _progress = 0.0; });
    }
  }
  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _appearAnimation,
      builder: (context, child) {
        if (_appearAnimation.value <= 0.01 && !_isVisible) return const SizedBox.shrink();
        return Row(mainAxisSize: MainAxisSize.min, children: List.generate(3, (index) {
          final dotP = ((_progress - index/3) / (1/3)).clamp(0.0, 1.0);
          final appearS = ((_appearAnimation.value - index*0.15) / (1.0 - index*0.15)).clamp(0.0, 1.0);
          return Padding(padding: const EdgeInsets.only(right: 16.0), child: Transform.scale(scale: _easeOutBack(appearS), child: _CountdownDot(size: 12.0, fillProgress: dotP, appearProgress: appearS)));
        }));
      },
    );
  }
  double _easeOutBack(double t) { const c1 = 1.70158; const c3 = c1 + 1; return (t<=0) ? 0 : (t>=1) ? 1 : 1 + c3 * pow(t - 1, 3) + c1 * pow(t - 1, 2); }
}

class _CountdownDot extends StatelessWidget {
  final double size; final double fillProgress; final double appearProgress;
  const _CountdownDot({required this.size, required this.fillProgress, required this.appearProgress});
  @override
  Widget build(BuildContext context) {
    return Container(
      width: size, height: size, decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: Colors.white.withOpacity(0.4 + 0.2*appearProgress), width: 1.5)),
      child: Center(child: Container(width: (size-4)*pow(fillProgress, 0.25), height: (size-4)*pow(fillProgress, 0.25), decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.white.withOpacity(0.9)))),
    );
  }
}
