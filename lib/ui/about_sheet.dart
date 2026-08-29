import 'package:flutter/material.dart';

import '../core/fa.dart';

/// Bottom sheet explaining how the app works and platform limitations.
class AboutSheet {
  AboutSheet._();

  static void show(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) {
        return Padding(
          padding: EdgeInsets.fromLTRB(
            20,
            0,
            20,
            MediaQuery.of(context).viewInsets.bottom + 24,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                Strings.aboutTitle,
                style: Theme.of(context)
                    .textTheme
                    .headlineSmall
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              _Section(
                icon: Icons.warning_amber_rounded,
                title: Strings.thresholdLow,
                body: Strings.aboutLow,
              ),
              const SizedBox(height: 14),
              _Section(
                icon: Icons.battery_full,
                title: Strings.thresholdFull,
                body: Strings.aboutFull,
              ),
              const SizedBox(height: 14),
              _Section(
                icon: Icons.info_outline,
                title: 'محدودیت مهم',
                body: Strings.aboutLimitation,
              ),
              const SizedBox(height: 14),
              _Section(
                icon: Icons.android_rounded,
                title: 'اندروید',
                body: Strings.aboutAndroid,
              ),
              const SizedBox(height: 14),
              _Section(
                icon: Icons.apple_rounded,
                title: 'iOS',
                body: Strings.aboutIos,
              ),
              const SizedBox(height: 12),
              Center(
                child: Text(
                  '${Strings.appName} v1.0.0',
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({
    required this.icon,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 24),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 15,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                body,
                style: const TextStyle(fontSize: 13, height: 1.5),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
