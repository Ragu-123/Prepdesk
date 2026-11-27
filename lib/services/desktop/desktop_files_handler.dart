import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import '../../data/database_service.dart';
import 'desktop_session_tracker.dart';

class DesktopSharedFile {
  final String id;
  final String name;
  final String filePath;
  final int sizeBytes;
  final String mimeType;
  final String source; // 'phone' | 'pc'
  final String uploadedBy;
  final String targetDeviceId; // 'all' or connected device id
  final String targetDeviceLabel;
  final int createdAt;

  const DesktopSharedFile({
    required this.id,
    required this.name,
    required this.filePath,
    required this.sizeBytes,
    required this.mimeType,
    required this.source,
    required this.uploadedBy,
    this.targetDeviceId = 'all',
    this.targetDeviceLabel = 'All connected PCs',
    required this.createdAt,
  });

  String get extension {
    final dot = name.lastIndexOf('.');
    if (dot < 0 || dot == name.length - 1) return '';
    return name.substring(dot + 1).toLowerCase();
  }

  String get formatBadge {
    final ext = extension;
    if (ext.isEmpty) return 'FILE';
    return ext.toUpperCase();
  }

  String get sizeDisplay {
    if (sizeBytes < 1024) return '$sizeBytes B';
    if (sizeBytes < 1024 * 1024) {
      return '${(sizeBytes / 1024).toStringAsFixed(1)} KB';
    }
    if (sizeBytes < 1024 * 1024 * 1024) {
      return '${(sizeBytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(sizeBytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  bool isVisibleToDevice(String? deviceId) {
    if (source != 'phone' || targetDeviceId == 'all' || targetDeviceId.isEmpty) {
      return true;
    }
    return deviceId != null && deviceId == targetDeviceId;
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'size_bytes': sizeBytes,
      'size_display': sizeDisplay,
      'mime_type': mimeType,
      'extension': extension,
      'source': source,
      'uploaded_by': uploadedBy,
      'target_device_id': targetDeviceId,
      'target_device_label': targetDeviceLabel,
      'created_at': createdAt,
    };
  }

  Map<String, dynamic> toManifestEntry() {
    return {
      'id': id,
      'name': name,
      'stored_name': File(filePath).uri.pathSegments.last,
      'size_bytes': sizeBytes,
      'mime_type': mimeType,
      'source': source,
      'uploaded_by': uploadedBy,
      'target_device_id': targetDeviceId,
      'target_device_label': targetDeviceLabel,
      'created_at': createdAt,
    };
  }
}

class _ActiveChunkUpload {
  final String uploadId;
  final String finalName;
  final File tempFile;
  final File targetFile;
  final int expectedSize;
  final String mimeType;
  final String uploadedBy;
  final String sessionToken;
  RandomAccessFile? _raf;
  Future<void> _writeLock = Future<void>.value();
  final Map<int, int> _chunkLengths = <int, int>{};

  _ActiveChunkUpload({
    required this.uploadId,
    required this.finalName,
    required this.tempFile,
    required this.targetFile,
    required this.expectedSize,
    required this.mimeType,
    required this.uploadedBy,
    required this.sessionToken,
    required RandomAccessFile raf,
  }) : _raf = raf;

  int get receivedBytes => _chunkLengths.values.fold(0, (a, b) => a + b);

  Future<void> writeChunk(int offset, Uint8List bytes) {
    final completer = Completer<void>();
    _writeLock = _writeLock.then((_) async {
      final raf = _raf;
      if (raf == null) throw StateError('Upload handle closed');
      await raf.setPosition(offset);
      await raf.writeFrom(bytes);
      _chunkLengths[offset] = bytes.length;
    }).then((_) {
      completer.complete();
    }).catchError((Object e, StackTrace st) {
      completer.completeError(e, st);
    });
    return completer.future;
  }

  Future<void> closeHandle() async {
    try {
      await _writeLock;
    } catch (_) {}
    try {
      await _raf?.flush();
    } catch (_) {}
    try {
      await _raf?.close();
    } catch (_) {}
    _raf = null;
  }
}

class DesktopFilesHandler {
  static const int maxUploadBytes = 4 * 1024 * 1024 * 1024; // 4 GB cap
  static const MethodChannel _nativeChannel =
      MethodChannel('io.github.thelazyindian.tasks/native');

  final DesktopSessionTracker sessionTracker;
  final VoidCallback? onFilesChanged;

  final ValueNotifier<List<DesktopSharedFile>> filesNotifier =
      ValueNotifier<List<DesktopSharedFile>>(const []);

  final Map<String, _ActiveChunkUpload> _chunkUploads =
      <String, _ActiveChunkUpload>{};
  Directory? _overrideDirectory;
  bool _loaded = false;

  DesktopFilesHandler({
    required this.sessionTracker,
    this.onFilesChanged,
    Directory? storageDirectory,
  }) : _overrideDirectory = storageDirectory;

  static const Map<String, String> _mimeMap = {
    'pdf': 'application/pdf',
    'mp4': 'video/mp4',
    'm4v': 'video/mp4',
    'mkv': 'video/x-matroska',
    'webm': 'video/webm',
    'mov': 'video/quicktime',
    'avi': 'video/x-msvideo',
    'mp3': 'audio/mpeg',
    'wav': 'audio/wav',
    'm4a': 'audio/mp4',
    'aac': 'audio/aac',
    'ogg': 'audio/ogg',
    'flac': 'audio/flac',
    'opus': 'audio/opus',
    'png': 'image/png',
    'jpg': 'image/jpeg',
    'jpeg': 'image/jpeg',
    'webp': 'image/webp',
    'gif': 'image/gif',
    'svg': 'image/svg+xml',
    'txt': 'text/plain; charset=utf-8',
    'md': 'text/markdown; charset=utf-8',
    'csv': 'text/csv; charset=utf-8',
    'json': 'application/json; charset=utf-8',
    'zip': 'application/zip',
    '7z': 'application/x-7z-compressed',
    'rar': 'application/vnd.rar',
    'apk': 'application/vnd.android.package-archive',
    'doc': 'application/msword',
    'docx': 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
    'xls': 'application/vnd.ms-excel',
    'xlsx': 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    'ppt': 'application/vnd.ms-powerpoint',
    'pptx': 'application/vnd.openxmlformats-officedocument.presentationml.presentation',
  };

  static String resolveMimeType(String fileName) {
    final dot = fileName.lastIndexOf('.');
    if (dot < 0 || dot == fileName.length - 1) {
      return 'application/octet-stream';
    }
    final ext = fileName.substring(dot + 1).toLowerCase();
    return _mimeMap[ext] ?? 'application/octet-stream';
  }

  static String sanitizeFileName(String rawName) {
    var decoded = rawName;
    try {
      decoded = Uri.decodeComponent(rawName);
    } catch (_) {}
    final base = decoded
        .replaceAll('\\', '/')
        .split('/')
        .last
        .replaceAll(RegExp(r'[\x00-\x1F\x7F<>:"|?*]'), '_')
        .trim();
    if (base.isEmpty || base == '.' || base == '..') {
      return 'shared_file_${DateTime.now().millisecondsSinceEpoch}';
    }
    return base.length > 180 ? base.substring(base.length - 180) : base;
  }

  Future<Directory> getStorageDir() async {
    if (_overrideDirectory != null) {
      if (!await _overrideDirectory!.exists()) {
        await _overrideDirectory!.create(recursive: true);
      }
      return _overrideDirectory!;
    }
    try {
      final nativePath =
          await _nativeChannel.invokeMethod<String>('getSharedFilesDir');
      if (nativePath != null && nativePath.isNotEmpty) {
        final dir = Directory(nativePath);
        if (!await dir.exists()) await dir.create(recursive: true);
        _overrideDirectory = dir;
        return dir;
      }
    } catch (_) {}
    final supportDir = await getApplicationSupportDirectory();
    final dir = Directory('${supportDir.path}${Platform.pathSeparator}shared_files');
    if (!await dir.exists()) await dir.create(recursive: true);
    _overrideDirectory = dir;
    return dir;
  }

  Future<File> _manifestFile() async {
    final dir = await getStorageDir();
    return File('${dir.path}${Platform.pathSeparator}.manifest.json');
  }

  Future<void> refreshFiles() async {
    final dir = await getStorageDir();
    final manifestFile = await _manifestFile();
    final Map<String, Map<String, dynamic>> metaByStored = {};
    if (await manifestFile.exists()) {
      try {
        final decoded = jsonDecode(await manifestFile.readAsString());
        if (decoded is List) {
          for (final item in decoded) {
            if (item is Map<String, dynamic>) {
              final stored = item['stored_name']?.toString();
              if (stored != null && stored.isNotEmpty) {
                metaByStored[stored] = item;
              }
            }
          }
        }
      } catch (_) {}
    }

    final List<DesktopSharedFile> results = [];
    final entries = await dir.list().toList();
    bool manifestDirty = false;
    final seenStored = <String>{};

    for (final entity in entries) {
      if (entity is! File) continue;
      final storedName = entity.uri.pathSegments.last;
      if (storedName.startsWith('.')) continue; // skip .manifest.json & .part_*
      seenStored.add(storedName);
      final stat = await entity.stat();
      final meta = metaByStored[storedName];
      if (meta == null) manifestDirty = true;

      final displayName = meta?['name']?.toString() ?? storedName;
      final id = meta?['id']?.toString() ?? _generateId();
      results.add(DesktopSharedFile(
        id: id,
        name: displayName,
        filePath: entity.path,
        sizeBytes: stat.size,
        mimeType: meta?['mime_type']?.toString() ?? resolveMimeType(displayName),
        source: meta?['source']?.toString() ?? 'phone',
        uploadedBy: meta?['uploaded_by']?.toString() ?? 'This device',
        targetDeviceId: meta?['target_device_id']?.toString() ?? 'all',
        targetDeviceLabel:
            meta?['target_device_label']?.toString() ?? 'All connected PCs',
        createdAt: (meta?['created_at'] as num?)?.toInt() ??
            stat.modified.millisecondsSinceEpoch,
      ));
    }

    if (metaByStored.keys.any((k) => !seenStored.contains(k))) {
      manifestDirty = true;
    }

    results.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    filesNotifier.value = List.unmodifiable(results);
    _loaded = true;

    if (manifestDirty) {
      await _writeManifest(results);
    }
  }

  Future<void> _writeManifest(List<DesktopSharedFile> files) async {
    try {
      final f = await _manifestFile();
      await f.writeAsString(
        jsonEncode(files.map((e) => e.toManifestEntry()).toList()),
        flush: true,
      );
    } catch (_) {}
  }

  String _generateId() {
    final rand = Random.secure();
    final bytes = List<int>.generate(8, (_) => rand.nextInt(256));
    return 'f_${bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join()}';
  }

  Future<File> _uniqueTargetFile(Directory dir, String cleanName) async {
    final dot = cleanName.lastIndexOf('.');
    final base = dot > 0 ? cleanName.substring(0, dot) : cleanName;
    final ext = dot > 0 ? cleanName.substring(dot) : '';

    var candidate = File('${dir.path}${Platform.pathSeparator}$cleanName');
    int suffix = 1;
    while (await candidate.exists()) {
      candidate = File(
          '${dir.path}${Platform.pathSeparator}$base ($suffix)$ext');
      suffix++;
    }
    return candidate;
  }

  Future<DesktopSharedFile> registerStoredFile({
    required File file,
    required String displayName,
    required String source,
    required String uploadedBy,
    String targetDeviceId = 'all',
    String targetDeviceLabel = 'All connected PCs',
  }) async {
    if (!_loaded) await refreshFiles();
    final stat = await file.stat();
    final entry = DesktopSharedFile(
      id: _generateId(),
      name: displayName,
      filePath: file.path,
      sizeBytes: stat.size,
      mimeType: resolveMimeType(displayName),
      source: source,
      uploadedBy: uploadedBy,
      targetDeviceId: targetDeviceId,
      targetDeviceLabel: targetDeviceLabel,
      createdAt: DateTime.now().millisecondsSinceEpoch,
    );
    final updated = [entry, ...filesNotifier.value.where((f) => f.filePath != file.path)];
    filesNotifier.value = List.unmodifiable(updated);
    await _writeManifest(updated);
    onFilesChanged?.call();
    return entry;
  }

  Future<void> removeFileById(String id) async {
    if (!_loaded) await refreshFiles();
    final target = filesNotifier.value.where((f) => f.id == id).firstOrNull;
    if (target == null) return;
    try {
      final f = File(target.filePath);
      if (await f.exists()) await f.delete();
    } catch (_) {}
    final updated = filesNotifier.value.where((f) => f.id != id).toList();
    filesNotifier.value = List.unmodifiable(updated);
    await _writeManifest(updated);
    onFilesChanged?.call();
  }

  Future<void> clearBySource(String source) async {
    if (!_loaded) await refreshFiles();
    final toRemove = filesNotifier.value.where((f) => f.source == source).toList();
    for (final item in toRemove) {
      try {
        final f = File(item.filePath);
        if (await f.exists()) await f.delete();
      } catch (_) {}
    }
    final remaining = filesNotifier.value.where((f) => f.source != source).toList();
    filesNotifier.value = List.unmodifiable(remaining);
    await _writeManifest(remaining);
    onFilesChanged?.call();
  }

  Future<void> clearAll() async {
    await abortAllChunkUploads();
    final dir = await getStorageDir();
    await for (final entity in dir.list()) {
      if (entity is File) {
        try {
          await entity.delete();
        } catch (_) {}
      }
    }
    filesNotifier.value = const [];
    onFilesChanged?.call();
  }

  Future<void> abortAllChunkUploads({String? onlySessionToken}) async {
    final ids = _chunkUploads.entries
        .where((e) => onlySessionToken == null || e.value.sessionToken == onlySessionToken)
        .map((e) => e.key)
        .toList();
    for (final id in ids) {
      final upload = _chunkUploads.remove(id);
      if (upload != null) {
        await upload.closeHandle();
        try {
          if (await upload.tempFile.exists()) await upload.tempFile.delete();
        } catch (_) {}
      }
    }
  }

  // --- HTTP Route Handlers ---

  Future<void> handleListFiles(HttpRequest request, {String? token}) async {
    try {
      if (!_loaded) await refreshFiles();
      sessionTracker.recordActivity(token, 'Browsing PrepShare');
      final caller = sessionTracker.deviceForToken(token);
      final visible = filesNotifier.value
          .where((f) => f.isVisibleToDevice(caller?.id))
          .map((f) => f.toMap())
          .toList();
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode({
        'success': true,
        'viewer_device_id': caller?.id,
        'viewer_device_label': caller?.deviceLabel,
        'files': visible,
      }));
    } catch (e) {
      request.response.statusCode = HttpStatus.internalServerError;
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode({'error': e.toString()}));
    } finally {
      await request.response.close();
    }
  }

  Future<void> handleSingleUpload(HttpRequest request, {String? token}) async {
    File? tempFile;
    IOSink? sink;
    try {
      final rawName = request.headers.value('x-file-name') ??
          request.uri.queryParameters['filename'] ??
          'file_${DateTime.now().millisecondsSinceEpoch}';
      final cleanName = sanitizeFileName(rawName);
      final contentLength = request.headers.contentLength;
      if (contentLength > maxUploadBytes) {
        request.response.statusCode = HttpStatus.requestEntityTooLarge;
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode({'error': 'File exceeds 4 GB limit'}));
        await request.response.close();
        return;
      }

      final dir = await getStorageDir();
      final targetFile = await _uniqueTargetFile(dir, cleanName);
      final tempName = '.part_${DateTime.now().millisecondsSinceEpoch}_${Random().nextInt(99999)}';
      tempFile = File('${dir.path}${Platform.pathSeparator}$tempName');
      sink = tempFile.openWrite(mode: FileMode.writeOnly);

      int totalWritten = 0;
      await for (final chunk in request) {
        totalWritten += chunk.length;
        if (totalWritten > maxUploadBytes) {
          throw Exception('File exceeds maximum allowed transfer size.');
        }
        sink.add(chunk);
      }
      await sink.flush();
      await sink.close();
      sink = null;

      await tempFile.rename(targetFile.path);
      tempFile = null;

      final device = sessionTracker.deviceForToken(token);
      final uploadedBy = device?.deviceLabel ?? 'Desktop Browser';
      sessionTracker.recordActivity(token, 'Sent ${targetFile.uri.pathSegments.last}');

      final shared = await registerStoredFile(
        file: targetFile,
        displayName: targetFile.uri.pathSegments.last,
        source: 'pc',
        uploadedBy: uploadedBy,
      );

      try {
        await DatabaseService.instance.addInAppNotification(
          title: 'File Received from PC',
          message: '${shared.name} (${shared.sizeDisplay})',
          type: 'FILE_SHARE',
        );
      } catch (_) {}

      request.response.statusCode = HttpStatus.created;
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode({
        'success': true,
        'file': shared.toMap(),
      }));
    } catch (e) {
      try {
        await sink?.close();
      } catch (_) {}
      try {
        if (tempFile != null && await tempFile.exists()) await tempFile.delete();
      } catch (_) {}
      request.response.statusCode = HttpStatus.badRequest;
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode({'error': e.toString()}));
    } finally {
      await request.response.close();
    }
  }

  Future<void> handleChunkInit(HttpRequest request, {String? token}) async {
    try {
      final body = await utf8.decodeStream(request);
      final json = jsonDecode(body) as Map<String, dynamic>;
      final rawName = json['name']?.toString() ?? 'upload.bin';
      final cleanName = sanitizeFileName(rawName);
      final expectedSize = (json['size'] as num?)?.toInt() ?? 0;
      if (expectedSize <= 0 || expectedSize > maxUploadBytes) {
        request.response.statusCode = HttpStatus.badRequest;
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode({'error': 'Invalid file size'}));
        await request.response.close();
        return;
      }

      final dir = await getStorageDir();
      final targetFile = await _uniqueTargetFile(dir, cleanName);
      final uploadId = _generateId();
      final tempFile = File('${dir.path}${Platform.pathSeparator}.part_$uploadId');
      final raf = await tempFile.open(mode: FileMode.writeOnly);
      await raf.truncate(expectedSize);

      final device = sessionTracker.deviceForToken(token);
      final upload = _ActiveChunkUpload(
        uploadId: uploadId,
        finalName: targetFile.uri.pathSegments.last,
        tempFile: tempFile,
        targetFile: targetFile,
        expectedSize: expectedSize,
        mimeType: resolveMimeType(targetFile.uri.pathSegments.last),
        uploadedBy: device?.deviceLabel ?? 'Desktop Browser',
        sessionToken: token ?? '',
        raf: raf,
      );
      _chunkUploads[uploadId] = upload;
      sessionTracker.recordActivity(token, 'Sending ${upload.finalName}');

      request.response.statusCode = HttpStatus.ok;
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode({
        'success': true,
        'upload_id': uploadId,
        'final_name': upload.finalName,
      }));
    } catch (e) {
      request.response.statusCode = HttpStatus.badRequest;
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode({'error': e.toString()}));
    } finally {
      await request.response.close();
    }
  }

  Future<void> handleChunkWrite(HttpRequest request, {String? token}) async {
    try {
      final uploadId = request.uri.queryParameters['upload_id'] ?? '';
      final offset = int.tryParse(request.uri.queryParameters['offset'] ?? '') ?? -1;
      final upload = _chunkUploads[uploadId];
      if (upload == null || offset < 0) {
        request.response.statusCode = HttpStatus.notFound;
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode({'error': 'Upload session not found'}));
        await request.response.close();
        return;
      }

      final builder = BytesBuilder(copy: false);
      await for (final chunk in request) {
        if (builder.length + chunk.length > 16 * 1024 * 1024) {
          throw Exception('Chunk exceeds 16 MB ceiling');
        }
        builder.add(chunk);
      }
      final bytes = builder.takeBytes();
      if (offset + bytes.length > upload.expectedSize) {
        throw Exception('Chunk exceeds declared file length');
      }

      await upload.writeChunk(offset, bytes);

      request.response.statusCode = HttpStatus.ok;
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode({
        'success': true,
        'received': bytes.length,
      }));
    } catch (e) {
      request.response.statusCode = HttpStatus.badRequest;
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode({'error': e.toString()}));
    } finally {
      await request.response.close();
    }
  }

  Future<void> handleChunkComplete(HttpRequest request, {String? token}) async {
    try {
      final body = await utf8.decodeStream(request);
      final json = jsonDecode(body) as Map<String, dynamic>;
      final uploadId = json['upload_id']?.toString() ?? '';
      final upload = _chunkUploads.remove(uploadId);
      if (upload == null) {
        request.response.statusCode = HttpStatus.notFound;
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode({'error': 'Upload session not found'}));
        await request.response.close();
        return;
      }

      await upload.closeHandle();
      if (upload.receivedBytes != upload.expectedSize) {
        try {
          if (await upload.tempFile.exists()) await upload.tempFile.delete();
        } catch (_) {}
        request.response.statusCode = HttpStatus.badRequest;
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode({
          'error': 'Incomplete transfer (${upload.receivedBytes}/${upload.expectedSize} bytes)'
        }));
        await request.response.close();
        return;
      }

      await upload.tempFile.rename(upload.targetFile.path);
      sessionTracker.recordActivity(token, 'Sent ${upload.finalName}');

      final shared = await registerStoredFile(
        file: upload.targetFile,
        displayName: upload.finalName,
        source: 'pc',
        uploadedBy: upload.uploadedBy,
      );

      try {
        await DatabaseService.instance.addInAppNotification(
          title: 'File Received from PC',
          message: '${shared.name} (${shared.sizeDisplay})',
          type: 'FILE_SHARE',
        );
      } catch (_) {}

      request.response.statusCode = HttpStatus.created;
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode({'success': true, 'file': shared.toMap()}));
    } catch (e) {
      request.response.statusCode = HttpStatus.badRequest;
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode({'error': e.toString()}));
    } finally {
      await request.response.close();
    }
  }

  Future<void> handleChunkAbort(HttpRequest request) async {
    try {
      final body = await utf8.decodeStream(request);
      final json = jsonDecode(body) as Map<String, dynamic>;
      final uploadId = json['upload_id']?.toString() ?? '';
      final upload = _chunkUploads.remove(uploadId);
      if (upload != null) {
        await upload.closeHandle();
        try {
          if (await upload.tempFile.exists()) await upload.tempFile.delete();
        } catch (_) {}
      }
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode({'success': true}));
    } catch (e) {
      request.response.statusCode = HttpStatus.badRequest;
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode({'error': e.toString()}));
    } finally {
      await request.response.close();
    }
  }

  Future<void> handleCreateDownloadTicket(HttpRequest request, {String? token}) async {
    try {
      if (!_loaded) await refreshFiles();
      final body = await utf8.decodeStream(request);
      final json = jsonDecode(body) as Map<String, dynamic>;
      final fileId = json['id']?.toString() ?? '';
      final caller = sessionTracker.deviceForToken(token);
      final exists = filesNotifier.value.any(
          (f) => f.id == fileId && f.isVisibleToDevice(caller?.id));
      if (!exists || token == null) {
        request.response.statusCode = HttpStatus.notFound;
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode({'error': 'File not found'}));
        await request.response.close();
        return;
      }
      final ticket = sessionTracker.createDownloadTicket(token, fileId);
      if (ticket == null) {
        request.response.statusCode = HttpStatus.unauthorized;
        await request.response.close();
        return;
      }
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode({'success': true, 'ticket': ticket}));
    } catch (e) {
      request.response.statusCode = HttpStatus.badRequest;
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode({'error': e.toString()}));
    } finally {
      await request.response.close();
    }
  }

  Future<void> handleDownload(
    HttpRequest request,
    String fileId, {
    String? sessionToken,
  }) async {
    try {
      if (!_loaded) await refreshFiles();
      final target = filesNotifier.value.where((f) => f.id == fileId).firstOrNull;
      final caller = sessionTracker.deviceForToken(sessionToken);
      if (target == null || !target.isVisibleToDevice(caller?.id)) {
        request.response.statusCode = target == null ? HttpStatus.notFound : HttpStatus.forbidden;
        request.response.write(target == null ? 'File not found' : 'File targeted to another device');
        await request.response.close();
        return;
      }

      final file = File(target.filePath);
      if (!await file.exists()) {
        request.response.statusCode = HttpStatus.notFound;
        request.response.write('File no longer exists on disk');
        await request.response.close();
        return;
      }

      final storageDir = await getStorageDir();
      final canonicalDir = storageDir.resolveSymbolicLinksSync();
      final canonicalFile = file.resolveSymbolicLinksSync();
      if (!canonicalFile.startsWith(canonicalDir)) {
        request.response.statusCode = HttpStatus.forbidden;
        await request.response.close();
        return;
      }

      final length = await file.length();
      final preview = request.uri.queryParameters['preview'] == '1';
      final safeDispositionName = Uri.encodeComponent(target.name);
      final dispositionType = preview ? 'inline' : 'attachment';

      request.response.bufferOutput = false;
      request.response.headers.set('Content-Type', target.mimeType);
      request.response.headers.set('Accept-Ranges', 'bytes');
      request.response.headers.set(
        'Content-Disposition',
        "$dispositionType; filename*=UTF-8''$safeDispositionName",
      );

      final rangeHeader = request.headers.value('range');
      int start = 0;
      int end = length > 0 ? length - 1 : 0;
      bool isRange = false;

      if (rangeHeader != null && rangeHeader.startsWith('bytes=') && length > 0) {
        final spec = rangeHeader.substring(6).split(',').first.trim();
        final parts = spec.split('-');
        if (parts.length == 2) {
          final parsedStart = int.tryParse(parts[0]);
          final parsedEnd = int.tryParse(parts[1]);
          if (parsedStart != null) {
            start = parsedStart.clamp(0, length - 1);
            end = parsedEnd != null ? parsedEnd.clamp(start, length - 1) : length - 1;
            isRange = true;
          } else if (parsedEnd != null && parsedEnd > 0) {
            start = (length - parsedEnd).clamp(0, length - 1);
            end = length - 1;
            isRange = true;
          }
        }
      }

      if (isRange) {
        request.response.statusCode = HttpStatus.partialContent;
        request.response.headers.set('Content-Range', 'bytes $start-$end/$length');
        request.response.contentLength = end - start + 1;
        if (!preview) {
          sessionTracker.recordActivity(sessionToken, 'Downloading ${target.name}');
        }
        await file.openRead(start, end + 1).pipe(request.response);
      } else {
        request.response.statusCode = HttpStatus.ok;
        request.response.contentLength = length;
        sessionTracker.recordActivity(
          sessionToken,
          preview ? 'Previewing ${target.name}' : 'Downloaded ${target.name}',
        );
        if (length == 0) {
          await request.response.close();
        } else {
          await file.openRead().pipe(request.response);
        }
      }
    } catch (e) {
      debugPrint('Error streaming shared file: $e');
      try {
        request.response.statusCode = HttpStatus.internalServerError;
        await request.response.close();
      } catch (_) {}
    }
  }

  Future<void> handleDeleteFile(HttpRequest request, String fileId, {String? token}) async {
    try {
      if (!_loaded) await refreshFiles();
      final target = filesNotifier.value.where((f) => f.id == fileId).firstOrNull;
      if (target != null) {
        sessionTracker.recordActivity(token, 'Removed ${target.name}');
        await removeFileById(fileId);
      }
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode({'success': true, 'id': fileId}));
    } catch (e) {
      request.response.statusCode = HttpStatus.internalServerError;
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode({'error': e.toString()}));
    } finally {
      await request.response.close();
    }
  }
}
