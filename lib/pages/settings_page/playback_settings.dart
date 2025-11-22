import 'package:flutter/material.dart';
import 'package:fluent_ui/fluent_ui.dart' as fluent_ui;
import '../../widgets/fluent_settings_card.dart';
import '../../services/audio_quality_service.dart';
import '../../models/song_detail.dart';

/// 播放设置组件
class PlaybackSettings extends StatelessWidget {
  const PlaybackSettings({super.key});

  @override
  Widget build(BuildContext context) {
    final isFluent = fluent_ui.FluentTheme.maybeOf(context) != null;

    if (isFluent) {
      return FluentSettingsGroup(
        title: '播放',
        children: [
          FluentSettingsTile(
            icon: Icons.high_quality,
            title: '音质选择',
            subtitle:
                '${AudioQualityService().getQualityName()} - ${AudioQualityService().getQualityDescription()}',
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _showAudioQualityDialogFluent(context),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionTitle(context, '播放'),
        Card(
          child: ListTile(
            leading: const Icon(Icons.high_quality),
            title: const Text('音质选择'),
            subtitle: Text(
                '${AudioQualityService().getQualityName()} - ${AudioQualityService().getQualityDescription()}'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _showAudioQualityDialog(context),
          ),
        ),
      ],
    );
  }

  Widget _buildSectionTitle(BuildContext context, String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12.0, left: 4.0),
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.bold,
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
    );
  }

  void _showAudioQualityDialog(BuildContext context) {
    final currentQuality = AudioQualityService().currentQuality;
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('选择音质'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            RadioListTile<AudioQuality>(
              title: const Text('标准音质'),
              subtitle: const Text('128kbps，节省流量'),
              value: AudioQuality.standard,
              groupValue: currentQuality,
              onChanged: (value) {
                if (value != null) {
                  AudioQualityService().setQuality(value);
                  Navigator.pop(context);
                  final messenger = ScaffoldMessenger.maybeOf(context);
                  if (messenger != null) {
                    messenger.showSnackBar(
                      const SnackBar(
                        content: Text('音质设置已更新'),
                        duration: Duration(seconds: 1),
                      ),
                    );
                  }
                }
              },
            ),
            RadioListTile<AudioQuality>(
              title: const Text('极高音质'),
              subtitle: const Text('320kbps，推荐'),
              value: AudioQuality.exhigh,
              groupValue: currentQuality,
              onChanged: (value) {
                if (value != null) {
                  AudioQualityService().setQuality(value);
                  Navigator.pop(context);
                  final messenger = ScaffoldMessenger.maybeOf(context);
                  if (messenger != null) {
                    messenger.showSnackBar(
                      const SnackBar(
                        content: Text('音质设置已更新'),
                        duration: Duration(seconds: 1),
                      ),
                    );
                  }
                }
              },
            ),
            RadioListTile<AudioQuality>(
              title: const Text('无损音质'),
              subtitle: const Text('FLAC，音质最佳'),
              value: AudioQuality.lossless,
              groupValue: currentQuality,
              onChanged: (value) {
                if (value != null) {
                  AudioQualityService().setQuality(value);
                  Navigator.pop(context);
                  final messenger = ScaffoldMessenger.maybeOf(context);
                  if (messenger != null) {
                    messenger.showSnackBar(
                      const SnackBar(
                        content: Text('音质设置已更新'),
                        duration: Duration(seconds: 1),
                      ),
                    );
                  }
                }
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  void _showAudioQualityDialogFluent(BuildContext context) {
    final currentQuality = AudioQualityService().currentQuality;

    fluent_ui.showDialog(
      context: context,
      builder: (context) {
        return fluent_ui.ContentDialog(
          title: const Text('选择音质'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              fluent_ui.RadioButton(
                content: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: const [Text('标准音质'), Text('128kbps，节省流量')],
                ),
                checked: currentQuality == AudioQuality.standard,
                onChanged: (v) {
                  AudioQualityService().setQuality(AudioQuality.standard);
                  Navigator.pop(context);
                },
              ),
              fluent_ui.RadioButton(
                content: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: const [Text('极高音质'), Text('320kbps，推荐')],
                ),
                checked: currentQuality == AudioQuality.exhigh,
                onChanged: (v) {
                  AudioQualityService().setQuality(AudioQuality.exhigh);
                  Navigator.pop(context);
                },
              ),
              fluent_ui.RadioButton(
                content: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: const [Text('无损音质'), Text('FLAC，音质最佳')],
                ),
                checked: currentQuality == AudioQuality.lossless,
                onChanged: (v) {
                  AudioQualityService().setQuality(AudioQuality.lossless);
                  Navigator.pop(context);
                },
              ),
            ],
          ),
          actions: [
            fluent_ui.Button(
              onPressed: () => Navigator.pop(context),
              child: const Text('关闭'),
            ),
          ],
        );
      },
    );
  }
}

