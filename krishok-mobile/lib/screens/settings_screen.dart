import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_state.dart';
import '../theme/app_theme.dart';
import '../utils/app_strings.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  late final TextEditingController _urlController;

  @override
  void initState() {
    super.initState();
    final appState = Provider.of<AppState>(context, listen: false);
    _urlController = TextEditingController(text: appState.serverUrl);
  }

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  void _save(BuildContext context) {
    final val = _urlController.text.trim();
    if (val.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        _snack(context.s.enterValidUrl, isError: true),
      );
      return;
    }
    Provider.of<AppState>(context, listen: false).setServerUrl(val);
    ScaffoldMessenger.of(context).showSnackBar(
      _snack(context.s.savedReconnecting),
    );
  }

  SnackBar _snack(String msg, {bool isError = false}) {
    return SnackBar(
      content: Text(msg, style: const TextStyle(fontWeight: FontWeight.w500)),
      backgroundColor:
          isError ? Colors.redAccent : KrishokColors.primaryGreen,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      margin: const EdgeInsets.all(16),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final appState = context.watch<AppState>();

    return Scaffold(
      backgroundColor: KrishokColors.background,
      appBar: AppBar(
        title: Text(context.s.settingsTitle),
        backgroundColor: KrishokColors.cardWhite,
      ),
      body: ListView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.all(20),
        children: [
          // Connection status banner
          _StatusBanner(isConnected: appState.isConnected),
          const SizedBox(height: 24),

          // ESP32 Settings card
          _SettingsSection(
            title: context.s.esp32Device,
            icon: Icons.router_rounded,
            children: [
              Text(
                context.s.serverUrlLabel,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: KrishokColors.textMedium,
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _urlController,
                keyboardType: TextInputType.url,
                style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: KrishokColors.textDark),
                decoration: InputDecoration(
                  hintText: 'http://192.168.4.1',
                  hintStyle:
                      const TextStyle(color: KrishokColors.textLight),
                  filled: true,
                  fillColor: KrishokColors.surfaceGray,
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 14),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide.none,
                  ),
                  prefixIcon: const Icon(Icons.link_rounded,
                      color: KrishokColors.textLight, size: 20),
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () => _save(context),
                  icon: const Icon(Icons.save_rounded, size: 18),
                  label: Text(context.s.saveReconnect),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: KrishokColors.primaryGreen,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                    textStyle: const TextStyle(
                        fontWeight: FontWeight.w600, fontSize: 14),
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),

          // Language card
          _SettingsSection(
            title: context.s.appLanguageTitle,
            icon: Icons.language_rounded,
            children: [
              Text(
                context.s.appLanguageLabel,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: KrishokColors.textMedium,
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _LangButton(
                      label: 'বাংলা',
                      sublabel: 'Bengali',
                      selected: appState.language == 'bn',
                      onTap: () =>
                          Provider.of<AppState>(context, listen: false)
                              .setLanguage('bn'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _LangButton(
                      label: 'English',
                      sublabel: 'ইংরেজি',
                      selected: appState.language == 'en',
                      onTap: () =>
                          Provider.of<AppState>(context, listen: false)
                              .setLanguage('en'),
                    ),
                  ),
                ],
              ),
            ],
          ),

          const SizedBox(height: 16),

          // About card
          _SettingsSection(
            title: context.s.aboutKrishok,
            icon: Icons.eco_rounded,
            children: [
              _InfoRow(label: 'App Name', value: 'Krishok'),
              _InfoRow(label: 'Version', value: '1.0.0-beta'),
              _InfoRow(label: 'Device Protocol', value: 'HTTP/ESP32'),
              _InfoRow(label: 'AI Backend', value: 'Google AI'),
              _InfoRow(label: 'Weather API', value: 'Open-Meteo (Free)'),
            ],
          ),

          const SizedBox(height: 24),
          Center(
            child: Text(
              context.s.madeForFarmers,
              style: const TextStyle(
                fontSize: 12,
                color: KrishokColors.textLight,
                fontStyle: FontStyle.italic,
              ),
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

class _StatusBanner extends StatelessWidget {
  final bool isConnected;
  const _StatusBanner({required this.isConnected});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      decoration: BoxDecoration(
        color: isConnected
            ? KrishokColors.mintGreen
            : Colors.red.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isConnected
              ? KrishokColors.primaryGreen.withValues(alpha: 0.3)
              : Colors.red.withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        children: [
          Icon(
            isConnected
                ? Icons.check_circle_rounded
                : Icons.error_outline_rounded,
            color: isConnected ? KrishokColors.primaryGreen : Colors.red,
            size: 22,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isConnected ? context.s.deviceConnected : context.s.deviceNotConnected,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: isConnected
                        ? KrishokColors.primaryGreen
                        : Colors.red,
                  ),
                ),
                Text(
                  isConnected ? context.s.esp32Online : context.s.checkWifi,
                  style: const TextStyle(
                    fontSize: 12,
                    color: KrishokColors.textMedium,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SettingsSection extends StatelessWidget {
  final String title;
  final IconData icon;
  final List<Widget> children;

  const _SettingsSection({
    required this.title,
    required this.icon,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: KrishokColors.cardWhite,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: KrishokColors.primaryGreen, size: 18),
              const SizedBox(width: 8),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: KrishokColors.textDark,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Divider(height: 1),
          const SizedBox(height: 16),
          ...children,
        ],
      ),
    );
  }
}

class _LangButton extends StatelessWidget {
  final String label;
  final String sublabel;
  final bool selected;
  final VoidCallback onTap;

  const _LangButton({
    required this.label,
    required this.sublabel,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: selected
              ? KrishokColors.mintGreen
              : KrishokColors.surfaceGray,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected
                ? KrishokColors.primaryGreen
                : Colors.transparent,
            width: 1.5,
          ),
        ),
        child: Column(
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: selected
                    ? KrishokColors.primaryGreen
                    : KrishokColors.textDark,
              ),
            ),
            Text(
              sublabel,
              style: const TextStyle(
                fontSize: 11,
                color: KrishokColors.textLight,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;

  const _InfoRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 13,
              color: KrishokColors.textMedium,
              fontWeight: FontWeight.w500,
            ),
          ),
          Text(
            value,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: KrishokColors.textDark,
            ),
          ),
        ],
      ),
    );
  }
}

