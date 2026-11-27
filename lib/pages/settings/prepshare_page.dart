import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../services/desktop/desktop_files_handler.dart';
import '../../services/desktop/desktop_session_tracker.dart';
import '../../services/desktop_log_server_service.dart';
import '../../utils/theme.dart';
import '../../widgets/top_banner_notification.dart';

class _PrepShareCategory {
  final String label;
  final String subtitle;
  final IconData icon;
  final List<String> mimeTypes;

  const _PrepShareCategory({
    required this.label,
    required this.subtitle,
    required this.icon,
    required this.mimeTypes,
  });
}

class PrepSharePage extends StatefulWidget {
  const PrepSharePage({super.key});

  @override
  State<PrepSharePage> createState() => _PrepSharePageState();
}

class _PrepSharePageState extends State<PrepSharePage> {
  static const MethodChannel _nativeChannel =
      MethodChannel('io.github.thelazyindian.tasks/native');

  static const List<_PrepShareCategory> _categories = [
    _PrepShareCategory(
      label: 'PDF & Docs',
      subtitle: 'PDF, Word, Text, Slides',
      icon: Icons.picture_as_pdf_outlined,
      mimeTypes: [
        'application/pdf',
        'text/plain',
        'text/markdown',
        'text/csv',
        'application/msword',
        'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
        'application/vnd.ms-excel',
        'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
        'application/vnd.ms-powerpoint',
        'application/vnd.openxmlformats-officedocument.presentationml.presentation',
      ],
    ),
    _PrepShareCategory(
      label: 'Video (MP4/MKV)',
      subtitle: 'Lectures & recordings',
      icon: Icons.video_file_outlined,
      mimeTypes: ['video/*'],
    ),
    _PrepShareCategory(
      label: 'Audio (MP3/WAV)',
      subtitle: 'Voice notes & tracks',
      icon: Icons.audio_file_outlined,
      mimeTypes: ['audio/*'],
    ),
    _PrepShareCategory(
      label: 'Images',
      subtitle: 'Screenshots & diagrams',
      icon: Icons.image_outlined,
      mimeTypes: ['image/*'],
    ),
    _PrepShareCategory(
      label: 'Any File',
      subtitle: 'ZIP, APK or any format',
      icon: Icons.attach_file_rounded,
      mimeTypes: ['*/*'],
    ),
  ];

  String _targetDeviceId = 'all';
  String _receivedFilter = 'all'; // 'all' | 'media_pdf' | 'docs' | 'other'
  bool _isPicking = false;

  @override
  void initState() {
    super.initState();
    DesktopLogServerService.instance.refreshSharedFiles();
  }

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

  static bool _matchesReceivedFilter(DesktopSharedFile file, String filter) {
    if (filter == 'all') return true;
    final ext = file.extension;
    final mime = file.mimeType.toLowerCase();
    final isDoc = const {'pdf', 'doc', 'docx', 'txt', 'md', 'csv', 'xls', 'xlsx', 'ppt', 'pptx'}.contains(ext);
    final isMediaOrPdf = ext == 'pdf' ||
        mime.startsWith('video/') ||
        mime.startsWith('audio/') ||
        mime.startsWith('image/') ||
        const {'mp4', 'mkv', 'webm', 'mov', 'avi', 'mp3', 'wav', 'm4a', 'flac', 'ogg', 'aac', 'png', 'jpg', 'jpeg', 'webp'}
            .contains(ext);
    if (filter == 'media_pdf') return isMediaOrPdf;
    if (filter == 'docs') return isDoc;
    return !isMediaOrPdf && !isDoc;
  }

  static String _formatTime(int millis) {
    final diff = DateTime.now().difference(DateTime.fromMillisecondsSinceEpoch(millis));
    if (diff.inSeconds < 15) return 'just now';
    if (diff.inMinutes < 1) return '${diff.inSeconds}s ago';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }

  Future<void> _pickCategoryFiles(
    _PrepShareCategory category,
    List<DesktopConnectedDevice> devices,
  ) async {
    if (_isPicking) return;
    if (!DesktopLogServerService.instance.fileSharingEnabled) {
      await DesktopLogServerService.instance.setFileSharingEnabled(true);
    }

    String targetId = _targetDeviceId;
    String targetLabel = 'All connected PCs';
    if (targetId != 'all') {
      final matched = devices.where((d) => d.id == targetId).firstOrNull;
      if (matched == null) {
        targetId = 'all';
      } else {
        targetLabel = matched.deviceLabel;
      }
    }

    setState(() => _isPicking = true);
    try {
      final result = await _nativeChannel.invokeMethod<List<dynamic>>(
        'pickFilesToShare',
        {'mimeTypes': category.mimeTypes},
      );
      if (result == null || result.isEmpty) return;
      int added = 0;
      for (final item in result) {
        if (item is Map) {
          final path = item['path']?.toString();
          final name = item['name']?.toString() ?? 'shared_file';
          if (path != null && path.isNotEmpty) {
            await DesktopLogServerService.instance.registerPhoneFile(
              File(path),
              name,
              targetDeviceId: targetId,
              targetDeviceLabel: targetLabel,
            );
            added++;
          }
        }
      }
      if (added > 0 && mounted) {
        TopBanner.show(
          context,
          title: 'Ready on PrepShare',
          message:
              '$added ${added == 1 ? 'file' : 'files'} shared to $targetLabel.',
          icon: Icons.upload_file_rounded,
          color: googleGreen,
        );
      }
    } catch (e) {
      if (mounted) {
        TopBanner.show(
          context,
          title: 'PrepShare Error',
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
    } catch (_) {
      if (mounted) {
        TopBanner.show(
          context,
          title: 'Could Not Open File',
          message: 'No compatible app found on this phone for ${file.name}.',
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

  Widget _buildCard({required List<Widget> children}) {
    return Container(
      decoration: BoxDecoration(
        color: googleSurface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: googleHairline),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return ValueListenableBuilder<bool>(
      valueListenable: DesktopLogServerService.instance.fileSharingNotifier,
      builder: (context, enabled, _) {
        return ValueListenableBuilder<List<DesktopConnectedDevice>>(
          valueListenable: DesktopLogServerService.instance.devicesNotifier,
          builder: (context, devices, _) {
            return ValueListenableBuilder<List<DesktopSharedFile>>(
              valueListenable: DesktopLogServerService.instance.filesNotifier,
              builder: (context, allFiles, _) {
                final sentFiles =
                    allFiles.where((f) => f.source == 'phone').toList();
                final receivedFiles =
                    allFiles.where((f) => f.source == 'pc').toList();
                final filteredReceived = receivedFiles
                    .where((f) => _matchesReceivedFilter(f, _receivedFilter))
                    .toList();

                final effectiveTargetId =
                    _targetDeviceId == 'all' || devices.any((d) => d.id == _targetDeviceId)
                        ? _targetDeviceId
                        : 'all';

                return DefaultTabController(
                  length: 2,
                  child: Scaffold(
                    backgroundColor: googleBackground,
                    appBar: AppBar(
                      backgroundColor: googleSurface,
                      surfaceTintColor: Colors.transparent,
                      leading: IconButton(
                        icon: const Icon(Icons.arrow_back_rounded,
                            color: googleTextPrimary),
                        onPressed: () => Navigator.pop(context),
                      ),
                      title: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'PrepShare',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: googleTextPrimary,
                            ),
                          ),
                          Text(
                            enabled
                                ? '${devices.length} connected • Ready to share'
                                : 'Sharing turned off',
                            style: const TextStyle(
                                fontSize: 11, color: googleTextSecondary),
                          ),
                        ],
                      ),
                      actions: [
                        Switch(
                          value: enabled,
                          activeColor: colors.primary,
                          onChanged: (val) => DesktopLogServerService.instance
                              .setFileSharingEnabled(val),
                        ),
                        const SizedBox(width: 8),
                      ],
                      bottom: TabBar(
                        indicatorColor: colors.primary,
                        labelColor: colors.primary,
                        unselectedLabelColor: googleTextSecondary,
                        labelStyle: const TextStyle(
                            fontSize: 13, fontWeight: FontWeight.bold),
                        tabs: [
                          Tab(text: 'Send (${sentFiles.length})'),
                          Tab(text: 'Received (${receivedFiles.length})'),
                        ],
                      ),
                    ),
                    body: Column(
                      children: [
                        if (!enabled)
                          Container(
                            width: double.infinity,
                            margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: colors.primaryContainer.withValues(alpha: 0.45),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: colors.outlineVariant),
                            ),
                            child: Row(
                              children: [
                                Icon(Icons.swap_horiz_rounded,
                                    color: colors.primary, size: 22),
                                const SizedBox(width: 10),
                                const Expanded(
                                  child: Text(
                                    'PrepShare is currently turned off. Turn it on to send or receive files.',
                                    style: TextStyle(
                                        fontSize: 12, color: googleTextPrimary),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                FilledButton.tonal(
                                  onPressed: () => DesktopLogServerService
                                      .instance
                                      .setFileSharingEnabled(true),
                                  child: const Text('Turn on'),
                                ),
                              ],
                            ),
                          ),
                        Expanded(
                          child: TabBarView(
                            children: [
                              _buildSendTab(
                                colors,
                                devices,
                                sentFiles,
                                effectiveTargetId,
                              ),
                              _buildReceivedTab(
                                colors,
                                receivedFiles,
                                filteredReceived,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  Widget _buildSendTab(
    ColorScheme colors,
    List<DesktopConnectedDevice> devices,
    List<DesktopSharedFile> sentFiles,
    String effectiveTargetId,
  ) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // 1. Target Device Selector Card
        _buildCard(
          children: [
            Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: colors.primaryContainer,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(Icons.devices_rounded,
                      color: colors.onPrimaryContainer, size: 20),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Send to device',
                        style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: googleTextPrimary),
                      ),
                      Text(
                        'Choose a paired PC or share with every connected device',
                        style:
                            TextStyle(fontSize: 11, color: googleTextSecondary),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ChoiceChip(
                  avatar: const Icon(Icons.groups_outlined, size: 16),
                  label: const Text('All connected PCs'),
                  selected: effectiveTargetId == 'all',
                  onSelected: (_) => setState(() => _targetDeviceId = 'all'),
                ),
                for (final device in devices)
                  ChoiceChip(
                    avatar: const Icon(Icons.laptop_windows_rounded, size: 16),
                    label: Text('${device.deviceLabel} (${device.ipAddress})'),
                    selected: effectiveTargetId == device.id,
                    onSelected: (_) =>
                        setState(() => _targetDeviceId = device.id),
                  ),
              ],
            ),
            if (devices.isEmpty) ...[
              const SizedBox(height: 8),
              Text(
                DesktopLogServerService.instance.isRunning
                    ? 'Waiting for a browser to pair at ${DesktopLogServerService.instance.serverUrl ?? 'your local URL'}. Files you pick now will wait ready in PrepShare.'
                    : 'Turn on the Desktop Companion server to pair your PC.',
                style: const TextStyle(fontSize: 11, color: googleTextSecondary),
              ),
            ],
          ],
        ),
        const SizedBox(height: 12),

        // 2. Quick Category Picker Chips
        _buildCard(
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Quick Send by Category',
                        style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: googleTextPrimary),
                      ),
                      Text(
                        _isPicking
                            ? 'Preparing files for transfer...'
                            : 'Select multiple files across any format',
                        style: const TextStyle(
                            fontSize: 11, color: googleTextSecondary),
                      ),
                    ],
                  ),
                ),
                if (_isPicking)
                  const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _categories.map((cat) {
                return ActionChip(
                  avatar: Icon(cat.icon, size: 18, color: colors.primary),
                  label: Text(cat.label,
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                  tooltip: cat.subtitle,
                  backgroundColor: colors.surfaceContainerHighest.withValues(alpha: 0.45),
                  side: BorderSide(color: colors.outlineVariant),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                  onPressed: _isPicking
                      ? null
                      : () => _pickCategoryFiles(cat, devices),
                );
              }).toList(),
            ),
          ],
        ),
        const SizedBox(height: 12),

        // 3. Sent / Outgoing Queue
        _buildCard(
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Shared from Phone (${sentFiles.length})',
                    style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: googleTextPrimary),
                  ),
                ),
                if (sentFiles.isNotEmpty)
                  TextButton(
                    onPressed: () =>
                        DesktopLogServerService.instance.clearSentFiles(),
                    style: TextButton.styleFrom(
                      foregroundColor: googleRed,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                    ),
                    child: const Text('Clear sent',
                        style: TextStyle(fontSize: 12)),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            if (sentFiles.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  'Tap any category chip above to pick PDFs, lectures, audio tracks or documents to download on your PC.',
                  style: TextStyle(fontSize: 12, color: googleTextSecondary),
                ),
              )
            else
              for (int i = 0; i < sentFiles.length; i++) ...[
                if (i > 0) const Divider(height: 14, color: googleHairline),
                _buildSentFileRow(colors, sentFiles[i]),
              ],
          ],
        ),
      ],
    );
  }

  Widget _buildSentFileRow(ColorScheme colors, DesktopSharedFile file) {
    return Row(
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: colors.primaryContainer,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(_iconForFile(file),
              color: colors.onPrimaryContainer, size: 20),
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
                    color: googleTextPrimary),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 2),
              Text(
                '${file.formatBadge} • ${file.sizeDisplay} • For: ${file.targetDeviceLabel}',
                style:
                    const TextStyle(fontSize: 11, color: googleTextSecondary),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
        IconButton(
          icon: Icon(Icons.open_in_new_rounded, size: 19, color: colors.primary),
          tooltip: 'Open file',
          onPressed: () => _openFile(file),
        ),
        IconButton(
          icon: const Icon(Icons.delete_outline_rounded,
              size: 19, color: googleRed),
          tooltip: 'Remove file',
          onPressed: () =>
              DesktopLogServerService.instance.removeSharedFile(file.id),
        ),
      ],
    );
  }

  Widget _buildReceivedTab(
    ColorScheme colors,
    List<DesktopSharedFile> receivedFiles,
    List<DesktopSharedFile> filteredReceived,
  ) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Basic filter chips
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (final entry in const {
                'all': 'All',
                'media_pdf': 'Media & PDF',
                'docs': 'Documents',
                'other': 'Other',
              }.entries)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(entry.value),
                    selected: _receivedFilter == entry.key,
                    onSelected: (_) =>
                        setState(() => _receivedFilter = entry.key),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 12),

        _buildCard(
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Received from PC (${filteredReceived.length})',
                    style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: googleTextPrimary),
                  ),
                ),
                if (receivedFiles.isNotEmpty)
                  TextButton.icon(
                    onPressed: () =>
                        DesktopLogServerService.instance.clearReceivedFiles(),
                    icon: const Icon(Icons.clear_all_rounded, size: 16),
                    label: const Text('Clear history',
                        style: TextStyle(fontSize: 12)),
                    style: TextButton.styleFrom(
                      foregroundColor: googleRed,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            if (filteredReceived.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 20),
                child: Column(
                  children: [
                    Icon(Icons.inbox_outlined,
                        size: 36, color: colors.primary.withValues(alpha: 0.6)),
                    const SizedBox(height: 10),
                    Text(
                      receivedFiles.isEmpty
                          ? 'No files received from PC yet'
                          : 'No files match this filter',
                      style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: googleTextPrimary),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Open the PrepShare tab on your laptop browser to send PDFs, videos, audio, or any file.',
                      textAlign: TextAlign.center,
                      style:
                          TextStyle(fontSize: 12, color: googleTextSecondary),
                    ),
                  ],
                ),
              )
            else
              for (int i = 0; i < filteredReceived.length; i++) ...[
                if (i > 0) const Divider(height: 14, color: googleHairline),
                _buildReceivedFileRow(colors, filteredReceived[i]),
              ],
          ],
        ),
      ],
    );
  }

  Widget _buildReceivedFileRow(ColorScheme colors, DesktopSharedFile file) {
    return Row(
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: colors.primaryContainer,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(_iconForFile(file),
              color: colors.onPrimaryContainer, size: 20),
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
                    color: googleTextPrimary),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 2),
              Text(
                '${file.formatBadge} • ${file.sizeDisplay} • ${file.uploadedBy} • ${_formatTime(file.createdAt)}',
                style:
                    const TextStyle(fontSize: 11, color: googleTextSecondary),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
        IconButton(
          icon: Icon(Icons.open_in_new_rounded, size: 19, color: colors.primary),
          tooltip: 'Open with system app',
          onPressed: () => _openFile(file),
        ),
        IconButton(
          icon: const Icon(Icons.download_rounded,
              size: 19, color: googleGreen),
          tooltip: 'Save to Downloads',
          onPressed: () => _saveToDownloads(file),
        ),
        IconButton(
          icon: const Icon(Icons.delete_outline_rounded,
              size: 19, color: googleRed),
          tooltip: 'Delete file',
          onPressed: () =>
              DesktopLogServerService.instance.removeSharedFile(file.id),
        ),
      ],
    );
  }
}
