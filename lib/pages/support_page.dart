import 'dart:io';
import 'package:flutter/material.dart';
import 'package:fluent_ui/fluent_ui.dart' as fluent_ui;

import 'settings_page/donate_settings.dart';
import 'settings_page/sponsor_wall.dart';
import '../utils/theme_manager.dart';

class SupportPage extends StatelessWidget {
  const SupportPage({super.key});

  @override
  Widget build(BuildContext context) {
    final isFluentUI = Platform.isWindows && ThemeManager().isFluentFramework;

    if (isFluentUI) {
      return fluent_ui.ScaffoldPage.scrollable(
        padding: const EdgeInsets.all(24.0),
        header: const fluent_ui.PageHeader(
          title: Text('支持'),
        ),
        children: const [
          DonateSettings(),
          SizedBox(height: 16),
          SponsorWall(),
          SizedBox(height: 40),
        ],
      );
    }

    final colorScheme = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: colorScheme.surface,
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            floating: true,
            snap: true,
            backgroundColor: colorScheme.surface,
            title: Text(
              '支持',
              style: TextStyle(
                color: colorScheme.onSurface,
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.all(24.0),
            sliver: SliverList(
              delegate: SliverChildListDelegate(const [
                DonateSettings(),
                SizedBox(height: 24),
                SponsorWall(),
                SizedBox(height: 40),
              ]),
            ),
          ),
        ],
      ),
    );
  }
}
