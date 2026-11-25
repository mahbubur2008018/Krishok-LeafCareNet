import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_state.dart';
import '../theme/app_theme.dart';
import 'splash_screen.dart';
import 'home_navigation.dart';

class DisconnectedScreen extends StatelessWidget {
  const DisconnectedScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: KrishokColors.background,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 40.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Animated pulsing icon container
                Container(
                  width: 120,
                  height: 120,
                  decoration: BoxDecoration(
                    color: KrishokColors.surfaceGray,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: KrishokColors.textLight.withValues(alpha: 0.3),
                      width: 2,
                    ),
                  ),
                  child: const Icon(
                    Icons.wifi_off_rounded,
                    size: 56,
                    color: KrishokColors.textLight,
                  ),
                ),
                const SizedBox(height: 36),
                const Text(
                  'Not Connected',
                  style: TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w700,
                    color: KrishokColors.textDark,
                  ),
                ),
                const SizedBox(height: 14),
                const Text(
                  'Could not reach your ESP32 device.\nCheck your WiFi or update the server URL in Settings.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 15,
                    color: KrishokColors.textMedium,
                    height: 1.6,
                  ),
                ),
                const SizedBox(height: 52),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () {
                      Provider.of<AppState>(context, listen: false)
                          .forceReconnect();
                      Navigator.pushReplacement(
                        context,
                        MaterialPageRoute(builder: (_) => const SplashScreen()),
                      );
                    },
                    icon: const Icon(Icons.refresh_rounded),
                    label: const Text(
                      'Try Again',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: KrishokColors.primaryGreen,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      elevation: 0,
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                TextButton.icon(
                  onPressed: () {
                    Navigator.pushReplacement(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const HomeNavigation(initialIndex: 5),
                      ),
                    );
                  },
                  icon: const Icon(
                    Icons.settings_outlined,
                    size: 18,
                    color: KrishokColors.primaryGreen,
                  ),
                  label: const Text(
                    'Open Settings',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: KrishokColors.primaryGreen,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
