import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:tasks/services/desktop/desktop_files_handler.dart';
import 'package:tasks/services/desktop/desktop_session_tracker.dart';

void main() {
  group('DesktopSessionTracker', () {
    test('parses friendly browser and OS labels from User-Agent', () {
      expect(
        DesktopSessionTracker.parseDeviceLabel(
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/131.0.0.0 Safari/537.36'),
        'Chrome on Windows',
      );
      expect(
        DesktopSessionTracker.parseDeviceLabel(
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/131.0.0.0 Safari/537.36 Edg/131.0.0.0'),
        'Microsoft Edge on Windows',
      );
      expect(
        DesktopSessionTracker.parseDeviceLabel(
            'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 Version/17.0 Safari/605.1.15'),
        'Safari on macOS',
      );
      expect(DesktopSessionTracker.parseDeviceLabel(null), 'Desktop Browser');
    });

    test('tracks connected devices, activity updates, download tickets, and individual disconnect', () {
      final tracker = DesktopSessionTracker();
      final tokenA = tracker.createSession(
        ipAddress: '192.168.1.20',
        userAgent: 'Mozilla/5.0 (Windows NT 10.0) Chrome/130.0.0.0 Safari/537.36',
      );
      final tokenB = tracker.createSession(
        ipAddress: '192.168.1.35',
        userAgent: 'Mozilla/5.0 (X11; Linux x86_64) Firefox/132.0',
      );

      expect(tracker.devices.length, 2);
      expect(tracker.isTokenValid(tokenA, activity: 'Viewing Notes'), isTrue);
      final deviceA = tracker.deviceForToken(tokenA)!;
      expect(deviceA.deviceLabel, 'Chrome on Windows');
      expect(deviceA.lastActivity, 'Viewing Notes');

      final ticketA = tracker.createDownloadTicket(tokenA, 'f_123');
      expect(ticketA, isNotNull);
      expect(tracker.validateDownloadTicket(ticketA, 'f_123'), tokenA);
      expect(tracker.validateDownloadTicket(ticketA, 'f_other'), isNull);

      final removed = tracker.disconnectDevice(deviceA.id);
      expect(removed, tokenA);
      expect(tracker.isTokenValid(tokenA), isFalse);
      expect(tracker.validateDownloadTicket(ticketA, 'f_123'), isNull);
      expect(tracker.isTokenValid(tokenB), isTrue);
      expect(tracker.devices.length, 1);
    });
  });

  group('DesktopFilesHandler', () {
    late Directory tempDir;
    late DesktopSessionTracker tracker;
    late DesktopFilesHandler handler;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('prepdesk_files_test_');
      tracker = DesktopSessionTracker();
      handler = DesktopFilesHandler(
        sessionTracker: tracker,
        storageDirectory: tempDir,
      );
    });

    tearDown(() async {
      await handler.abortAllChunkUploads();
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('sanitizes filenames and resolves common media and document MIME types', () {
      expect(
        DesktopFilesHandler.sanitizeFileName('../../evil/folder/lecture%20notes.pdf'),
        'lecture notes.pdf',
      );
      expect(DesktopFilesHandler.resolveMimeType('video.mkv'), 'video/x-matroska');
      expect(DesktopFilesHandler.resolveMimeType('lecture.mp4'), 'video/mp4');
      expect(DesktopFilesHandler.resolveMimeType('audio.mp3'), 'audio/mpeg');
      expect(DesktopFilesHandler.resolveMimeType('sample.wav'), 'audio/wav');
      expect(DesktopFilesHandler.resolveMimeType('slides.pdf'), 'application/pdf');
      expect(DesktopFilesHandler.resolveMimeType('archive.bin'), 'application/octet-stream');
    });

    test('streams direct binary upload, parallel chunked upload, and supports HTTP Range downloads', () async {
      final token = tracker.createSession(
        ipAddress: '192.168.1.40',
        userAgent: 'Mozilla/5.0 (Windows NT 10.0) Chrome/131.0.0.0',
      );

      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));

      server.listen((req) async {
        final p = req.uri.path;
        if (req.method == 'GET' && p == '/api/files') {
          await handler.handleListFiles(req, token: token);
        } else if (req.method == 'POST' && p == '/api/files/upload') {
          await handler.handleSingleUpload(req, token: token);
        } else if (req.method == 'POST' && p == '/api/files/upload/init') {
          await handler.handleChunkInit(req, token: token);
        } else if (req.method == 'PUT' && p == '/api/files/upload/chunk') {
          await handler.handleChunkWrite(req, token: token);
        } else if (req.method == 'POST' && p == '/api/files/upload/complete') {
          await handler.handleChunkComplete(req, token: token);
        } else if (req.method == 'GET' && p.startsWith('/api/files/download/')) {
          final id = p.substring('/api/files/download/'.length);
          await handler.handleDownload(req, id, sessionToken: token);
        } else {
          req.response.statusCode = HttpStatus.notFound;
          await req.response.close();
        }
      });

      final client = HttpClient();
      addTearDown(() => client.close(force: true));
      final base = 'http://127.0.0.1:${server.port}';

      // 1. Chunked multi-offset upload (writing chunks out of order + retry test)
      final payload = List<int>.generate(256, (i) => i);
      final initReq = await client.postUrl(Uri.parse('$base/api/files/upload/init'));
      initReq.write(jsonEncode({'name': 'sample.mkv', 'size': payload.length}));
      final initRes = await initReq.close();
      expect(initRes.statusCode, HttpStatus.ok);
      final initJson = jsonDecode(await utf8.decodeStream(initRes)) as Map<String, dynamic>;
      final uploadId = initJson['upload_id'] as String;

      Future<void> putChunk(int offset, List<int> bytes) async {
        final r = await client.putUrl(
            Uri.parse('$base/api/files/upload/chunk?upload_id=$uploadId&offset=$offset'));
        r.add(bytes);
        final res = await r.close();
        expect(res.statusCode, HttpStatus.ok);
        await res.drain<void>();
      }

      // Send second half before first half, plus duplicate retry of second half
      await putChunk(128, payload.sublist(128));
      await putChunk(128, payload.sublist(128));
      await putChunk(0, payload.sublist(0, 128));

      final doneReq = await client.postUrl(Uri.parse('$base/api/files/upload/complete'));
      doneReq.write(jsonEncode({'upload_id': uploadId}));
      final doneRes = await doneReq.close();
      expect(doneRes.statusCode, HttpStatus.created);
      final doneJson = jsonDecode(await utf8.decodeStream(doneRes)) as Map<String, dynamic>;
      final fileId = (doneJson['file'] as Map<String, dynamic>)['id'] as String;
      expect((doneJson['file'] as Map<String, dynamic>)['name'], 'sample.mkv');

      // 2. Range request (bytes=100-149)
      final dlReq = await client.getUrl(Uri.parse('$base/api/files/download/$fileId'));
      dlReq.headers.set('Range', 'bytes=100-149');
      final dlRes = await dlReq.close();
      expect(dlRes.statusCode, HttpStatus.partialContent);
      expect(dlRes.headers.value('content-range'), 'bytes 100-149/256');
      final rangeBytes = await dlRes.expand((c) => c).toList();
      expect(rangeBytes, payload.sublist(100, 150));

      // 3. List files
      final listReq = await client.getUrl(Uri.parse('$base/api/files'));
      final listRes = await listReq.close();
      final listJson = jsonDecode(await utf8.decodeStream(listRes)) as Map<String, dynamic>;
      expect((listJson['files'] as List).length, 1);
    });
  });
}
