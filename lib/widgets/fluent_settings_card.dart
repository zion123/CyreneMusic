import 'package:fluent_ui/fluent_ui.dart' as fluent_ui;
import 'package:flutter/material.dart';

/// Windows 11 风格的设置分组标题
class FluentSettingsGroup extends StatelessWidget {
  final String title;
  final List<Widget> children;

  const FluentSettingsGroup({
    super.key,
    required this.title,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    final theme = fluent_ui.FluentTheme.of(context);
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 分组标题
        Padding(
          padding: const EdgeInsets.only(bottom: 8.0, left: 4.0),
          child: Text(
            title,
            style: theme.typography.bodyStrong?.copyWith(
              fontSize: 14,
            ),
          ),
        ),
        
        // 每个选项都是独立的卡片
        ...children.map((child) => Padding(
          padding: const EdgeInsets.only(bottom: 4.0),
          child: child,
        )),
      ],
    );
  }
}

/// Windows 11 风格的独立设置卡片（横向长条）
class FluentSettingsTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool enabled;

  const FluentSettingsTile({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    return fluent_ui.Card(
      padding: EdgeInsets.zero,
      child: fluent_ui.ListTile(
        leading: Icon(icon, size: 20),
        title: Text(title),
        subtitle: subtitle != null ? Text(subtitle!) : null,
        trailing: trailing,
        onPressed: enabled ? onTap : null,
      ),
    );
  }
}

/// Windows 11 风格的独立开关卡片（横向长条）
class FluentSwitchTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool>? onChanged;

  const FluentSwitchTile({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    required this.value,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return fluent_ui.Card(
      padding: EdgeInsets.zero,
      child: fluent_ui.ListTile(
        leading: Icon(icon, size: 20),
        title: Text(title),
        subtitle: subtitle != null ? Text(subtitle!) : null,
        trailing: fluent_ui.ToggleSwitch(
          checked: value,
          onChanged: onChanged,
        ),
      ),
    );
  }
}
