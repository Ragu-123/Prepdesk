import 'package:flutter/material.dart';
import '../../../services/desktop/desktop_files_handler.dart';
import '../../../services/desktop/desktop_session_tracker.dart';
import '../../../services/desktop_log_server_service.dart';
import '../../../utils/theme.dart';
import '../../../widgets/top_banner_notification.dart';
import '../prepshare_page.dart';

class DesktopConnectedDevicesCard extends StatelessWidget {
  final bool serverRunning;
  final String? serverUrl;

  const DesktopConnectedDevicesCard({
    super.key,
    required this.serverRunning,
    required this.serverUrl,
  });

  static IconData _iconForDevice(String label) {
    final lower = label.toLowerCase();
    if (lower.contains('windows')) return Icons.laptop_windows_rounded;
    if (lower.contains('macos')) return Icons.laptop_mac_rounded;
    if (lower.contains('linux') || lower.contains('chromebook')) {
      return Icons.computer_rounded;
    }
    if (lower.contains('android') || lower.contains('iphone')) {
      return Icons.smartphone_rounded;
    }
    return Icons.devices_other_rounded;
  }

  static String _relativeAge(DateTime time) {
    final diff = DateTime.now().difference(time);
    if (diff.inSeconds < 10) return 'just now';
    if (diff.inSeconds < 60) return '${diff.inSeconds}s ago';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    return '${diff.inHours}h ago';
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return ValueListenableBuilder<List<DesktopConnectedDevice>>(
      valueListenable: DesktopLogServerService.instance.devicesNotifier,
      builder: (context, devices, _) {
        return Container(
          decoration: BoxDecoration(
            color: googleSurface,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: googleHairline),
          ),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: colors.primaryContainer,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      Icons.devices_rounded,
                      color: colors.onPrimaryContainer,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Connected Devices',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: googleTextPrimary,
                          ),
                        ),
                        Text(
                          'Paired laptops and browsers on your network',
                          style: TextStyle(fontSize: 11, color: googleTextSecondary),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: devices.isNotEmpty
                          ? googleGreen.withValues(alpha: 0.12)
                          : const Color(0xFFF1F3F4),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '${devices.length} active',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: devices.isNotEmpty ? googleGreen : googleTextSecondary,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (!serverRunning)
                const Text(
                  'Start the local HTTP server above to accept connections from your PC.',
                  style: TextStyle(fontSize: 12, color: googleTextSecondary),
                )
              else if (devices.isEmpty)
                Text(
                  'Waiting for a browser to pair at ${serverUrl ?? 'the local URL'} with the 6-digit PIN.',
                  style: const TextStyle(fontSize: 12, color: googleTextSecondary),
                )
              else ...[
                for (int i = 0; i < devices.length; i++) ...[
                  if (i > 0) const Divider(height: 14, color: googleHairline),
                  _buildDeviceRow(context, colors, devices[i]),
                ],
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _buildDeviceRow(
    BuildContext context,
    ColorScheme colors,
    DesktopConnectedDevice device,
  ) {
    return Row(
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: colors.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(
            _iconForDevice(device.deviceLabel),
            color: colors.primary,
            size: 18,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                device.deviceLabel,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: googleTextPrimary,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                '${device.ipAddress} • ${device.lastActivity} • ${_relativeAge(device.lastSeenAt)}',
                style: const TextStyle(fontSize: 11, color: googleTextSecondary),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
        IconButton(
          icon: const Icon(Icons.link_off_rounded, size: 20, color: googleRed),
          tooltip: 'Disconnect device',
          onPressed: () async {
            final disconnected =
                await DesktopLogServerService.instance.disconnectDevice(device.id);
            if (disconnected && context.mounted) {
              TopBanner.show(
                context,
                title: 'Device Disconnected',
                message: '${device.deviceLabel} (${device.ipAddress}) was unpaired.',
                icon: Icons.link_off_rounded,
                color: googleTextSecondary,
              );
            }
          },
        ),
      ],
    );
  }
}

class PrepShareEntryTile extends StatelessWidget {
  const PrepShareEntryTile({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return ValueListenableBuilder<bool>(
      valueListenable: DesktopLogServerService.instance.fileSharingNotifier,
      builder: (context, enabled, _) {
        return ValueListenableBuilder<List<DesktopSharedFile>>(
          valueListenable: DesktopLogServerService.instance.filesNotifier,
          builder: (context, files, _) {
            return Container(
              margin: const EdgeInsets.only(top: 12),
              decoration: BoxDecoration(
                color: googleSurface,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: googleHairline),
              ),
              child: Material(
                type: MaterialType.transparency,
                child: ListTile(
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
                  leading: Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: colors.primaryContainer,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      Icons.swap_horiz_rounded,
                      color: colors.onPrimaryContainer,
                      size: 22,
                    ),
                  ),
                  title: Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'PrepShare',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: googleTextPrimary,
                          ),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: enabled
                              ? googleGreen.withValues(alpha: 0.12)
                              : const Color(0xFFF1F3F4),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          enabled
                              ? (files.isEmpty
                                  ? 'READY'
                                  : '${files.length} FILES')
                              : 'OFF',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: enabled ? googleGreen : googleTextSecondary,
                          ),
                        ),
                      ),
                    ],
                  ),
                  subtitle: Text(
                    enabled
                        ? 'Send & receive PDF, MP4, MKV, MP3, WAV or any file'
                        : 'Turn on PrepShare above or tap to configure',
                    style: const TextStyle(
                        fontSize: 12, color: googleTextSecondary),
                  ),
                  trailing: const Icon(Icons.chevron_right_rounded,
                      color: googleTextSecondary, size: 20),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(24)),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute<void>(
                          builder: (_) => const PrepSharePage()),
                    );
                  },
                ),
              ),
            );
          },
        );
      },
    );
  }
}
