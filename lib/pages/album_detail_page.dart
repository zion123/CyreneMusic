import 'package:cached_network_image/cached_network_image.dart';
import 'package:fluent_ui/fluent_ui.dart' as fluent;
import 'package:flutter/material.dart';
import 'dart:io';
import 'package:flutter_acrylic/flutter_acrylic.dart';
import '../utils/theme_manager.dart';
import '../services/netease_album_service.dart';
import '../models/track.dart';
import '../services/player_service.dart';

class AlbumDetailPage extends StatefulWidget {
  final int albumId;
  final bool embedded;
  const AlbumDetailPage({super.key, required this.albumId, this.embedded = false});

  @override
  State<AlbumDetailPage> createState() => _AlbumDetailPageState();
}

class _AlbumDetailPageState extends State<AlbumDetailPage> {
  Map<String, dynamic>? _data;
  bool _loading = true;
  String? _error;
  bool _useGrid = false; // 歌曲视图模式

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final data = await NeteaseAlbumService().fetchAlbumDetail(widget.albumId);
    if (!mounted) return;
    setState(() {
      _data = data;
      _loading = false;
      if (data == null) _error = '加载失败';
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    if (widget.embedded) {
      return _buildBody();
    }
    final isFluent = fluent.FluentTheme.maybeOf(context) != null;
    if (isFluent) {
      final useWindowEffect =
          Platform.isWindows && ThemeManager().windowEffect != WindowEffect.disabled;
      final body = _buildBody();
      return Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: const Text('专辑详情'),
          backgroundColor: Colors.transparent,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          scrolledUnderElevation: 0,
        ),
        body: useWindowEffect
            ? body
            : Container(
                color: fluent.FluentTheme.of(context).micaBackgroundColor,
                child: body,
              ),
      );
    }
    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        title: const Text('专辑详情'),
        backgroundColor: cs.surface,
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    final isFluent = fluent.FluentTheme.maybeOf(context) != null;
    if (_loading) {
      return Center(child: _buildAdaptiveProgressIndicator(isFluent));
    }
    if (_error != null) return Center(child: Text(_error!));

    final album = _data!['album'] as Map<String, dynamic>? ?? {};
    final songs = (album['songs'] as List<dynamic>? ?? []) as List<dynamic>;
    final coverUrl = (album['coverImgUrl'] ?? '') as String? ?? '';
    final fluentTheme = isFluent ? fluent.FluentTheme.of(context) : null;
    final placeholderColor = isFluent
        ? fluentTheme?.resources?.controlAltFillColorSecondary ??
            Colors.black.withOpacity(0.05)
        : Theme.of(context).colorScheme.surfaceContainerHighest;

    Widget buildCover() {
      if (coverUrl.isEmpty) {
        return Container(
          width: 120,
          height: 120,
          color: placeholderColor,
          child: Icon(
            Icons.album,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        );
      }
      return CachedNetworkImage(
        imageUrl: coverUrl,
        width: 120,
        height: 120,
        fit: BoxFit.cover,
        placeholder: (_, __) => Container(
          width: 120,
          height: 120,
          color: placeholderColor,
          child: Center(
            child: SizedBox(
              width: 20,
              height: 20,
              child: _buildAdaptiveProgressIndicator(isFluent),
            ),
          ),
        ),
        errorWidget: (_, __, ___) => Container(
          width: 120,
          height: 120,
          color: placeholderColor,
          child: Icon(
            Icons.album,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      );
    }

    final headerContent = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: buildCover(),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(album['name']?.toString() ?? '',
                  style:
                      const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              Text(album['artist']?.toString() ?? '',
                  style: const TextStyle(fontSize: 14)),
              const SizedBox(height: 8),
              Text(album['description']?.toString() ?? '',
                  maxLines: 3, overflow: TextOverflow.ellipsis),
            ],
          ),
        ),
      ],
    );

    final header = isFluent
        ? _buildAdaptiveCard(
            isFluent: true,
            padding: const EdgeInsets.all(16),
            child: headerContent,
          )
        : headerContent;

    final iconColor = isFluent
        ? fluentTheme?.resources?.textFillColorSecondary ?? Colors.grey
        : Theme.of(context).colorScheme.onSurfaceVariant;

    final viewToggleRow = Row(
      children: [
        Text('歌曲', style: Theme.of(context).textTheme.titleMedium),
        const Spacer(),
        Icon(Icons.view_list, size: 18, color: iconColor),
        const SizedBox(width: 8),
        isFluent
            ? fluent.ToggleSwitch(
                checked: _useGrid,
                onChanged: (v) => setState(() => _useGrid = v),
                content: Text(_useGrid ? '缩略图' : '列表'),
              )
            : Switch(value: _useGrid, onChanged: (v) => setState(() => _useGrid = v)),
        const SizedBox(width: 8),
        Icon(Icons.grid_view, size: 18, color: iconColor),
      ],
    );

    final children = <Widget>[
      header,
      const SizedBox(height: 16),
      viewToggleRow,
      const SizedBox(height: 8),
    ];

    if (!_useGrid) {
      children.addAll(
        songs.map(
          (s0) => _buildSongListItem(
            context: context,
            song: s0 as Map<String, dynamic>,
            album: album,
            isFluent: isFluent,
            placeholderColor: placeholderColor,
          ),
        ),
      );
    } else {
      children.add(const SizedBox(height: 4));
      children.add(
        _buildSongsGrid(
          context: context,
          songs: songs.cast<Map<String, dynamic>>(),
          album: album,
          isFluent: isFluent,
          placeholderColor: placeholderColor,
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: children,
    );
  }
}

Widget _buildAdaptiveCard({
  required bool isFluent,
  EdgeInsetsGeometry? margin,
  EdgeInsetsGeometry? padding,
  required Widget child,
}) {
  if (isFluent) {
    return Padding(
      padding: margin ?? EdgeInsets.zero,
      child: fluent.Card(
        padding: padding ?? EdgeInsets.zero,
        child: child,
      ),
    );
  }
  return Card(
    margin: margin,
    child: padding != null ? Padding(padding: padding, child: child) : child,
  );
}

Widget _buildAdaptiveListTile({
  required bool isFluent,
  Widget? leading,
  Widget? title,
  Widget? subtitle,
  Widget? trailing,
  VoidCallback? onPressed,
}) {
  if (isFluent) {
    return fluent.ListTile(
      leading: leading,
      title: title,
      subtitle: subtitle,
      trailing: trailing,
      onPressed: onPressed,
    );
  }
  return ListTile(
    leading: leading,
    title: title,
    subtitle: subtitle,
    trailing: trailing,
    onTap: onPressed,
  );
}

Widget _buildAdaptiveProgressIndicator(bool isFluent) {
  return isFluent
      ? const fluent.ProgressRing()
      : const CircularProgressIndicator();
}

Widget _buildSongListItem({
  required BuildContext context,
  required Map<String, dynamic> song,
  required Map<String, dynamic> album,
  required bool isFluent,
  required Color placeholderColor,
}) {
  final track = Track(
    id: song['id'],
    name: song['name']?.toString() ?? '',
    artists: song['artists']?.toString() ?? '',
    album: song['album']?.toString() ?? (album['name']?.toString() ?? ''),
    picUrl: song['picUrl']?.toString() ?? (album['coverImgUrl']?.toString() ?? ''),
    source: MusicSource.netease,
  );

  final leading = ClipRRect(
    borderRadius: BorderRadius.circular(4),
    child: CachedNetworkImage(
      imageUrl: track.picUrl,
      width: 50,
      height: 50,
      fit: BoxFit.cover,
      placeholder: (_, __) => Container(
        width: 50,
        height: 50,
        color: placeholderColor,
        child: Center(
          child: SizedBox(
            width: 16,
            height: 16,
            child: _buildAdaptiveProgressIndicator(isFluent),
          ),
        ),
      ),
      errorWidget: (_, __, ___) => Container(
        width: 50,
        height: 50,
        color: placeholderColor,
        child: Icon(
          Icons.music_note,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    ),
  );

  final trailing = isFluent
      ? const fluent.Icon(fluent.FluentIcons.play)
      : const Icon(Icons.play_arrow);

  return _buildAdaptiveCard(
    isFluent: isFluent,
    margin: const EdgeInsets.only(bottom: 8),
    padding: EdgeInsets.zero,
    child: _buildAdaptiveListTile(
      isFluent: isFluent,
      leading: leading,
      title: Text(
        track.name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        '${track.artists} • ${track.album}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: trailing,
      onPressed: () => PlayerService().playTrack(track),
    ),
  );
}

Widget _buildSongsGrid({
  required BuildContext context,
  required List<Map<String, dynamic>> songs,
  required Map<String, dynamic> album,
  required bool isFluent,
  required Color placeholderColor,
}) {
  return Wrap(
    spacing: 12,
    runSpacing: 12,
    children: songs.map((song) {
      final track = Track(
        id: song['id'],
        name: song['name']?.toString() ?? '',
        artists: song['artists']?.toString() ?? '',
        album: song['album']?.toString() ?? (album['name']?.toString() ?? ''),
        picUrl: song['picUrl']?.toString() ?? (album['coverImgUrl']?.toString() ?? ''),
        source: MusicSource.netease,
      );

      final trailing = isFluent
          ? const fluent.Icon(fluent.FluentIcons.play)
          : const Icon(Icons.play_arrow);

      final cardContent = Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: CachedNetworkImage(
              imageUrl: track.picUrl,
              width: 80,
              height: 80,
              fit: BoxFit.cover,
              placeholder: (_, __) => Container(
                width: 80,
                height: 80,
                color: placeholderColor,
                child: Center(
                  child: SizedBox(
                    width: 18,
                    height: 18,
                    child: _buildAdaptiveProgressIndicator(isFluent),
                  ),
                ),
              ),
              errorWidget: (_, __, ___) => Container(
                width: 80,
                height: 80,
                color: placeholderColor,
                child: Icon(
                  Icons.music_note,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  track.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 6),
                Text(
                  track.artists,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 6),
                Text(
                  track.album,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          trailing,
        ],
      );

      final card = _buildAdaptiveCard(
        isFluent: isFluent,
        padding: const EdgeInsets.all(10),
        child: cardContent,
      );

      void handleTap() => PlayerService().playTrack(track);

      return ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 260, maxWidth: 440),
        child: isFluent
            ? GestureDetector(onTap: handleTap, child: card)
            : InkWell(
                onTap: handleTap,
                borderRadius: BorderRadius.circular(12),
                child: card,
              ),
      );
    }).toList(),
  );
}
