import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Immediately invalidates visible browser state when phone protection changes.
class DesktopSessionEvents {
  final Set<HttpResponse> _clients = {};

  Future<void> attach(HttpRequest request) async {
    final response = request.response;
    response.bufferOutput = false;
    response.headers.contentType = ContentType('text', 'event-stream', charset: 'utf-8');
    response.headers.set('Cache-Control', 'no-store');
    response.headers.set('Connection', 'keep-alive');
    response.headers.set('X-Accel-Buffering', 'no');
    _clients.add(response);
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
    } finally { heartbeat.cancel(); _clients.remove(response); }
  }

  Future<void> invalidate(int revision) async {
    final clients = List<HttpResponse>.from(_clients);
    _clients.clear();
    await Future.wait(clients.map((response) async {
      try {
        response.write('event: privacy\ndata: ${jsonEncode({'revision': revision})}\n\n');
        await response.flush();
        await response.close();
      } catch (_) {}
    }));
  }
}
