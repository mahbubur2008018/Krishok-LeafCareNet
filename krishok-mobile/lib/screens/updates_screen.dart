import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../theme/app_theme.dart';

// ════════════════════════════════════════════════════════════════════════════════
// UPDATES SCREEN — Placeholder
// ════════════════════════════════════════════════════════════════════════════════

class UpdatesScreen extends StatelessWidget {
  const UpdatesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: KrishokColors.background,
      appBar: AppBar(
        backgroundColor: KrishokColors.cardWhite,
        surfaceTintColor: Colors.transparent,
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: KrishokColors.mintGreen,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(LucideIcons.bell,
                  size: 20, color: KrishokColors.primaryGreen),
            ),
            const SizedBox(width: 10),
            const Text(
              'Updates',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 20,
                color: KrishokColors.textDark,
              ),
            ),
          ],
        ),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 40),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 100,
                height: 100,
                decoration: BoxDecoration(
                  color: KrishokColors.mintGreen,
                  borderRadius: BorderRadius.circular(28),
                ),
                child: const Icon(
                  LucideIcons.bell,
                  size: 44,
                  color: KrishokColors.primaryGreen,
                ),
              ),
              const SizedBox(height: 28),
              const Text(
                'Coming Soon',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: KrishokColors.textDark,
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'Stay tuned for crop health alerts,\nweather notifications, and more.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  color: KrishokColors.textMedium,
                  height: 1.6,
                ),
              ),
              const SizedBox(height: 28),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 20, vertical: 12),
                decoration: BoxDecoration(
                  color: KrishokColors.primaryGreen.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Text(
                  'Version 2.0',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: KrishokColors.primaryGreen,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
