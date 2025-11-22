import 'dart:io';
import 'dart:ui';

import 'package:bitsdojo_window/bitsdojo_window.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:cyrene_music/models/toplist.dart';
import 'package:cyrene_music/widgets/track_list_tile.dart';
import 'package:flutter/material.dart';

/// 显示榜单详情
void showToplistDetail(BuildContext context, Toplist toplist) {
  if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
    // 桌面端：从左侧弹出侧边栏
    _showToplistDetailSidebar(context, toplist);
  } else {
    // 移动端：从底部弹出抽屉
    _showToplistDetailBottomSheet(context, toplist);
  }
}

/// 桌面端：从左侧弹出侧边栏（Material Design 3 样式 + 高斯模糊背景）
void _showToplistDetailSidebar(BuildContext context, Toplist toplist) {
  final colorScheme = Theme.of(context).colorScheme;

  showGeneralDialog(
    context: context,
    barrierDismissible: true,
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    barrierColor: Colors.transparent, // 使用透明色，自定义背景
    transitionDuration: const Duration(milliseconds: 300),
    pageBuilder: (context, animation, secondaryAnimation) {
      // M3 标准动画曲线
      final curvedAnimation = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      );

      return Stack(
        children: [
          // 高斯模糊背景层（淡入效果 + 圆角裁剪）
          Padding(
            padding: const EdgeInsets.all(8.0), // 与主窗口外边距一致
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12), // 与主窗口圆角一致
              child: FadeTransition(
                opacity: curvedAnimation,
                child: GestureDetector(
                  onTap: () => Navigator.of(context).pop(), // 点击背景关闭
                  child: BackdropFilter(
                    filter: ImageFilter.blur(
                      sigmaX: 10.0, // 水平模糊强度
                      sigmaY: 10.0, // 垂直模糊强度
                    ),
                    child: Container(
                      color: colorScheme.scrim.withOpacity(0.25), // 半透明遮罩
                    ),
                  ),
                ),
              ),
            ),
          ),
          // Windows 标题栏可拖动区域（覆盖在模糊层上方）
          if (Platform.isWindows)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              height: 48, // 标题栏高度
              child: MoveWindow(
                child: Container(
                  color: Colors.transparent,
                ),
              ),
            ),
          // 侧边栏内容（滑入 + 淡入效果）
          SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(-1.0, 0.0),
              end: Offset.zero,
            ).animate(curvedAnimation),
            child: FadeTransition(
              opacity: curvedAnimation,
              child: Align(
                alignment: Alignment.centerLeft,
                child: Padding(
                  padding: const EdgeInsets.all(8.0), // 与主窗口保持一致的外边距
                  child: Material(
                    elevation: 0,
                    type: MaterialType.card,
                    color: Colors.transparent,
                    child: Container(
                      width: 400,
                      // 减去上下的 padding，避免超出主窗口
                      height: MediaQuery.of(context).size.height - 16,
                      decoration: BoxDecoration(
                        color:
                            colorScheme.surfaceContainerHigh, // M3 标准侧板背景色
                        borderRadius:
                            BorderRadius.circular(12), // 与主窗口圆角保持一致
                        // M3 标准阴影
                        boxShadow: [
                          BoxShadow(
                            color: colorScheme.shadow.withOpacity(0.08),
                            blurRadius: 4,
                            offset: const Offset(2, 0),
                          ),
                          BoxShadow(
                            color: colorScheme.shadow.withOpacity(0.16),
                            blurRadius: 12,
                            offset: const Offset(4, 0),
                          ),
                        ],
                      ),
                      child: ClipRRect(
                        borderRadius:
                            BorderRadius.circular(12), // 裁剪内容，与主窗口一致
                        child: _ToplistDetailContent(toplist: toplist),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      );
    },
    transitionBuilder: (context, animation, secondaryAnimation, child) {
      return child!;
    },
  );
}

/// 移动端：从底部弹出抽屉
void _showToplistDetailBottomSheet(BuildContext context, Toplist toplist) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (context) => DraggableScrollableSheet(
      initialChildSize: 0.9,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              // 拖动指示器
              Container(
                margin: const EdgeInsets.only(top: 12, bottom: 8),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Theme.of(context)
                      .colorScheme
                      .onSurfaceVariant
                      .withOpacity(0.4),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              // 榜单内容
              Expanded(
                child: _ToplistDetailContent(
                    toplist: toplist, scrollController: scrollController),
              ),
            ],
          ),
        );
      },
    ),
  );
}

/// 构建榜单详情内容（桌面端和移动端共用 - Material Design 3 样式）
class _ToplistDetailContent extends StatelessWidget {
  final Toplist toplist;
  final ScrollController? scrollController;
  const _ToplistDetailContent({required this.toplist, this.scrollController});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final isDesktop =
        Platform.isWindows || Platform.isMacOS || Platform.isLinux;

    return Column(
      children: [
        // M3 标准头部区域
        Container(
          padding: EdgeInsets.fromLTRB(
            isDesktop ? 24.0 : 16.0, // 桌面端使用更大的左右边距
            isDesktop ? 20.0 : 16.0,
            isDesktop ? 16.0 : 16.0,
            16.0,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 封面 - M3 标准圆角
              Card(
                elevation: 0,
                color: colorScheme.surfaceContainerHighest,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12), // M3 标准圆角
                ),
                clipBehavior: Clip.antiAlias,
                child: CachedNetworkImage(
                  imageUrl: toplist.coverImgUrl,
                  width: isDesktop ? 96 : 80, // 桌面端稍大
                  height: isDesktop ? 96 : 80,
                  fit: BoxFit.cover,
                  placeholder: (context, url) => Container(
                    width: isDesktop ? 96 : 80,
                    height: isDesktop ? 96 : 80,
                    color: colorScheme.surfaceContainerHighest,
                    child: Center(
                      child: SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          color: colorScheme.primary,
                        ),
                      ),
                    ),
                  ),
                  errorWidget: (context, url, error) => Container(
                    width: isDesktop ? 96 : 80,
                    height: isDesktop ? 96 : 80,
                    color: colorScheme.surfaceContainerHighest,
                    child: Icon(
                      Icons.music_note_rounded, // M3 圆角图标
                      size: 40,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              // 信息区域
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 榜单名称 - M3 headline 样式
                    Text(
                      toplist.name,
                      style: textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w600, // M3 标准字重
                        color: colorScheme.onSurface,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 8),
                    // 创建者 - M3 body 样式
                    Row(
                      children: [
                        Icon(
                          Icons.person_rounded,
                          size: 16,
                          color: colorScheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            toplist.creator,
                            style: textTheme.bodyMedium?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    // 歌曲数量 - M3 label 样式
                    Row(
                      children: [
                        Icon(
                          Icons.queue_music_rounded,
                          size: 16,
                          color: colorScheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '共 ${toplist.trackCount} 首歌曲',
                          style: textTheme.labelLarge?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              // 关闭按钮（桌面端显示）- M3 标准图标按钮
              if (isDesktop)
                IconButton(
                  icon: Icon(
                    Icons.close_rounded, // M3 圆角图标
                    color: colorScheme.onSurfaceVariant,
                  ),
                  onPressed: () => Navigator.of(context).pop(),
                  tooltip: '关闭',
                  style: IconButton.styleFrom(
                    backgroundColor: Colors.transparent,
                    hoverColor:
                        colorScheme.onSurface.withOpacity(0.08), // M3 标准悬停效果
                  ),
                ),
            ],
          ),
        ),
        // M3 标准分隔线
        Divider(
          height: 1,
          thickness: 1,
          color: colorScheme.outlineVariant,
        ),
        // 歌曲列表
        Expanded(
          child: ListView.builder(
            controller: scrollController,
            padding: EdgeInsets.only(
              top: 8,
              bottom:
                  MediaQuery.of(context).padding.bottom + 8, // 考虑底部安全区域
            ),
            itemCount: toplist.tracks.length,
            itemBuilder: (context, index) {
              return TrackListTile(
                track: toplist.tracks[index],
                index: index,
              );
            },
          ),
        ),
      ],
    );
  }
}
