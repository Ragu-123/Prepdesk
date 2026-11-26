import 'dart:async';
import 'dart:convert';
import 'dart:io';

class _AttachedClient {
  final HttpResponse response;
  final String? sessionToken;
  const _AttachedClient(this.response, this.sessionToken);
}

/// Pushes instant session revocation and live file-sharing updates to paired browsers.
class DesktopSessionEvents {
  final Set<_AttachedClient> _clients = {};

  Future<void> attach(HttpRequest request, {String? sessionToken}) async {
    final response = request.response;
    response.bufferOutput = false;
    response.headers.contentType = ContentType('text', 'event-stream', charset: 'utf-8');
    response.headers.set('Cache-Control', 'no-store');
    response.headers.set('Connection', 'keep-alive');
    response.headers.set('X-Accel-Buffering', 'no');
    final client = _AttachedClient(response, sessionToken);
    _clients.add(client);
    final heartbeat = Timer.periodic(const Duration(seconds: 15), (_) async {
      try { response.write(': keep-alive\n\n'); await response.flush(); }
      catch (_) { try { await response.close(); } catch (_) {} }
    });
    try {
      response.write('event: ready\ndata: {}\n\n');
      await response.flush();
      await response.done;
    } catch (_) {
      // A browser can close its stream at any time.
    } finally { heartbeat.cancel(); _clients.remove(client); }
  }

  Future<void> broadcastFiles({required bool enabled}) async {
    final clients = List<_AttachedClient>.from(_clients);
    await Future.wait(clients.map((client) async {
      try {
        client.response.write(
          'event: files\ndata: ${jsonEncode({'file_sharing_enabled': enabled})}\n\n',
        );
        await client.response.flush();
      } catch (_) {}
    }));
  }

  Future<void> invalidateSession(String sessionToken, int revision) async {
    final matching = _clients.where((c) => c.sessionToken == sessionToken).toList();
    _clients.removeWhere((c) => c.sessionToken == sessionToken);
    await Future.wait(matching.map((client) async {
      try {
        client.response.write('event: privacy\ndata: ${jsonEncode({'revision': revision})}\n\n');
        await client.response.flush();
        await client.response.close();
      } catch (_) {}
    }));
  }

  Future<void> invalidate(int revision) async {
    final clients = List<_AttachedClient>.from(_clients);
    _clients.clear();
    await Future.wait(clients.map((client) async {
      try {
        client.response.write('event: privacy\ndata: ${jsonEncode({'revision': revision})}\n\n');
        await client.response.flush();
        await client.response.close();
      } catch (_) {}
    }));
  }
}
