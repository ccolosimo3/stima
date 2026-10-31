import 'package:flutter/material.dart';

import 'capture_view_data.dart';

class CaptureNoticeView extends StatelessWidget {
  const CaptureNoticeView({super.key, required this.notice});

  final CaptureNotice notice;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final (background, foreground, icon) = switch (notice.tone) {
      CaptureNoticeTone.information => (
        colors.surfaceContainerLowest,
        colors.onSurfaceVariant,
        Icons.info_outline,
      ),
      CaptureNoticeTone.warning => (
        colors.tertiaryContainer,
        colors.onTertiaryContainer,
        Icons.warning_amber_rounded,
      ),
      CaptureNoticeTone.error => (
        colors.errorContainer,
        colors.onErrorContainer,
        Icons.error_outline,
      ),
    };
    return Semantics(
      liveRegion: true,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: foreground, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  notice.message,
                  style: TextStyle(color: foreground, fontSize: 14),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
