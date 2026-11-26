import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../services/desktop/desktop_files_handler.dart';
import '../../../services/desktop/desktop_session_tracker.dart';
import '../../../services/desktop_log_server_service.dart';
import '../../../utils/theme.dart';
import '../../../widgets/top_banner_notification.dart';

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

class DesktopSharedFilesCard extends StatefulWidget {
  const DesktopSharedFilesCard({super.key});

  @override
  State<DesktopSharedFilesCard> createState() => _DesktopSharedFilesCardState();
}

class _DesktopSharedFilesCardState extends State<DesktopSharedFilesCard> {
  static const MethodChannel _nativeChannel =
      MethodChannel('io.github.thelazyindian.tasks/native');

  bool _isPicking = false;

  static IconData _iconForFile(DesktopSharedFile file) {
    final ext = file.extension;
    final mime = file.mimeType.toLowerCase();
    if (ext == 'pdf' || mime.contains('pdf')) return Icons.picture_as_pdf_outlined;
    if (mime.startsWith('video/') ||
        const {'mp4', 'mkv', 'webm', 'mov', 'avi'}.contains(ext)) {
      return Icons.video_file_outlined;
    }
    if (mime.startsWith('audio/') ||
        const {'mp3', 'wav', 'm4a', 'flac', 'ogg', 'aac'}.contains(ext)) {
      return Icons.audio_file_outlined;
    }
    if (mime.startsWith('image/') ||
        const {'png', 'jpg', 'jpeg', 'webp', 'gif'}.contains(ext)) {
      return Icons.image_outlined;
    }
    return Icons.insert_drive_file_outlined;
  }

  Future<void> _pickAndShareFiles() async {
    if (_isPicking) return;
    setState(() => _isPicking = true);
    try {
      final result =
          await _nativeChannel.invokeMethod<List<dynamic>>('pickFilesToShare');
      if (result == null || result.isEmpty) return;
      int added = 0;
      for (final item in result) {
        if (item is Map) {
          final path = item['path']?.toString();
          final name = item['name']?.toString() ?? 'shared_file';
          if (path != null && path.isNotEmpty) {
            await DesktopLogServerService.instance
                .registerPhoneFile(File(path), name);
            added++;
          }
        }
      }
      if (added > 0 && mounted) {
        TopBanner.show(
          context,
          title: 'Ready for PC',
          message: '$added ${added == 1 ? 'file' : 'files'} shared to Desktop Companion.',
          icon: Icons.upload_file_rounded,
          color: googleGreen,
        );
      }
    } catch (e) {
      if (mounted) {
        TopBanner.show(
          context,
          title: 'File Share Error',
          message: e.toString(),
          icon: Icons.error_outline_rounded,
          color: googleRed,
        );
      }
    } finally {
      if (mounted) setState(() => _isPicking = false);
    }
  }

  Future<void> _openFile(DesktopSharedFile file) async {
    try {
      await _nativeChannel
          .invokeMethod('openSharedFile', {'filePath': file.filePath});
    } catch (e) {
      if (mounted) {
        TopBanner.show(
          context,
          title: 'Could Not Open File',
          message: 'No compatible app found for ${file.name}.',
          icon: Icons.error_outline_rounded,
          color: googleRed,
        );
      }
    }
  }

  Future<void> _saveToDownloads(DesktopSharedFile file) async {
    try {
      final saved = await _nativeChannel.invokeMethod<String>(
        'saveSharedFileToDownloads',
        {'filePath': file.filePath, 'fileName': file.name},
      );
      if (mounted) {
        TopBanner.show(
          context,
          title: 'Saved to Downloads',
          message: saved ?? file.name,
          icon: Icons.download_done_rounded,
          color: googleGreen,
        );
      }
    } catch (e) {
      if (mounted) {
        TopBanner.show(
          context,
          title: 'Save Failed',
          message: e.toString(),
          icon: Icons.error_outline_rounded,
          color: googleRed,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return ValueListenableBuilder<bool>(
      valueListenable: DesktopLogServerService.instance.fileSharingNotifier,
      builder: (context, enabled, _) {
        return ValueListenableBuilder<List<DesktopSharedFile>>(
          valueListenable: DesktopLogServerService.instance.filesNotifier,
          builder: (context, files, _) {
            if (!enabled && files.isEmpty) return const SizedBox.shrink();
            return Container(
              margin: const EdgeInsets.only(top: 12),
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
                          Icons.folder_shared_outlined,
                          color: colors.onPrimaryContainer,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Shared Files',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                color: googleTextPrimary,
                              ),
                            ),
                            Text(
                              '${files.length} ${files.length == 1 ? 'file' : 'files'} • PDF, MP4, MKV, MP3, WAV & any format',
                              style: const TextStyle(
                                fontSize: 11,
                                color: googleTextSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (files.isNotEmpty)
                        TextButton(
                          onPressed: () =>
                              DesktopLogServerService.instance.clearSharedFiles(),
                          style: TextButton.styleFrom(
                            foregroundColor: googleRed,
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                          ),
                          child: const Text('Clear all', style: TextStyle(fontSize: 11)),
                        ),
                    ],
                  ),
                  if (enabled) ...[
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.tonalIcon(
                        onPressed: _isPicking ? null : _pickAndShareFiles,
                        icon: _isPicking
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.upload_file_rounded, size: 18),
                        label: Text(_isPicking
                            ? 'Preparing files...'
                            : 'Send Files from Phone to PC'),
                      ),
                    ),
                  ],
                  if (files.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    for (int i = 0; i < files.length; i++) ...[
                      if (i > 0) const Divider(height: 14, color: googleHairline),
                      _buildFileRow(colors, files[i]),
                    ],
                  ] else if (enabled) ...[
                    const SizedBox(height: 10),
                    const Text(
                      'Pick files above to download on PC, or drop any file in your laptop browser under File share.',
                      style: TextStyle(fontSize: 12, color: googleTextSecondary),
                    ),
                  ],
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildFileRow(ColorScheme colors, DesktopSharedFile file) {
    return Row(
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: colors.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(_iconForFile(file), color: colors.primary, size: 18),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                file.name,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: googleTextPrimary,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 2),
              Text(
                '${file.formatBadge} • ${file.sizeDisplay} • ${file.source == 'pc' ? 'Received from PC' : 'From Phone'}',
                style: const TextStyle(fontSize: 11, color: googleTextSecondary),
              ),
            ],
          ),
        ),
        IconButton(
          icon: Icon(Icons.open_in_new_rounded, size: 19, color: colors.primary),
          tooltip: 'Open file',
          onPressed: () => _openFile(file),
        ),
        if (file.source == 'pc')
          IconButton(
            icon: const Icon(Icons.download_rounded, size: 19, color: googleGreen),
            tooltip: 'Save to Downloads',
            onPressed: () => _saveToDownloads(file),
          ),
        IconButton(
          icon: const Icon(Icons.delete_outline_rounded, size: 19, color: googleRed),
          tooltip: 'Remove file',
          onPressed: () =>
              DesktopLogServerService.instance.removeSharedFile(file.id),
        ),
      ],
    );
  }
}
