import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

class DesktopConnectedDevice {
  final String id;
  final String ipAddress;
  final String userAgent;
  final String deviceLabel;
  final DateTime connectedAt;
  final DateTime lastSeenAt;
  final DateTime expiresAt;
  final String lastActivity;

  const DesktopConnectedDevice({
    required this.id,
    required this.ipAddress,
    required this.userAgent,
    required this.deviceLabel,
    required this.connectedAt,
    required this.lastSeenAt,
    required this.expiresAt,
    required this.lastActivity,
  });

  DesktopConnectedDevice copyWith({
    DateTime? lastSeenAt,
    String? lastActivity,
  }) {
    return DesktopConnectedDevice(
      id: id,
      ipAddress: ipAddress,
      userAgent: userAgent,
      deviceLabel: deviceLabel,
      connectedAt: connectedAt,
      lastSeenAt: lastSeenAt ?? this.lastSeenAt,
      expiresAt: expiresAt,
      lastActivity: lastActivity ?? this.lastActivity,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'ip': ipAddress,
      'device': deviceLabel,
      'connected_at': connectedAt.millisecondsSinceEpoch,
      'last_seen_at': lastSeenAt.millisecondsSinceEpoch,
      'last_activity': lastActivity,
    };
  }
}

class _TrackedSession {
  final String token;
  DesktopConnectedDevice device;

  _TrackedSession({
    required this.token,
    required this.device,
  });
}

class _DownloadTicket {
  final String ticket;
  final String fileId;
  final String sessionToken;
  final DateTime expiresAt;

  const _DownloadTicket({
    required this.ticket,
    required this.fileId,
    required this.sessionToken,
    required this.expiresAt,
  });
}

class DesktopSessionTracker {
  final Map<String, _TrackedSession> _sessions = <String, _TrackedSession>{};
  final Map<String, _DownloadTicket> _tickets = <String, _DownloadTicket>{};

  final ValueNotifier<List<DesktopConnectedDevice>> devicesNotifier =
      ValueNotifier<List<DesktopConnectedDevice>>(const []);

  List<DesktopConnectedDevice> get devices => devicesNotifier.value;

  static String parseDeviceLabel(String? userAgent) {
    final ua = (userAgent ?? '').trim();
    if (ua.isEmpty) return 'Desktop Browser';

    String browser = 'Browser';
    if (ua.contains('Edg/')) {
      browser = 'Microsoft Edge';
    } else if (ua.contains('OPR/') || ua.contains('Opera')) {
      browser = 'Opera';
    } else if (ua.contains('Firefox/')) {
      browser = 'Firefox';
    } else if (ua.contains('Chrome/') && !ua.contains('Edg/')) {
      browser = 'Chrome';
    } else if (ua.contains('Safari/') && !ua.contains('Chrome/')) {
      browser = 'Safari';
    } else if (ua.contains('curl/')) {
      browser = 'CLI Client';
    }

    String os = '';
    if (ua.contains('Windows')) {
      os = 'Windows';
    } else if (ua.contains('Macintosh') || ua.contains('Mac OS X')) {
      os = 'macOS';
    } else if (ua.contains('CrOS')) {
      os = 'Chromebook';
    } else if (ua.contains('Android')) {
      os = 'Android';
    } else if (ua.contains('iPhone') || ua.contains('iPad')) {
      os = 'iPad/iPhone';
    } else if (ua.contains('Linux')) {
      os = 'Linux';
    }

    return os.isEmpty ? browser : '$browser on $os';
  }

  static bool constantTimeEqual(String a, String b) {
    if (a.length != b.length) return false;
    int res = 0;
    for (int i = 0; i < a.length; i++) {
      res |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
    }
    return res == 0;
  }

  String _randomHex(int byteCount) {
    final rand = Random.secure();
    final bytes = List<int>.generate(byteCount, (_) => rand.nextInt(256));
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  String createSession({
    required String ipAddress,
    String? userAgent,
    Duration ttl = const Duration(hours: 12),
  }) {
    pruneExpired();
    final now = DateTime.now();
    final token = _randomHex(32);
    final deviceId = sha256.convert(utf8.encode(token)).toString().substring(0, 12);
    final device = DesktopConnectedDevice(
      id: deviceId,
      ipAddress: ipAddress.isEmpty ? 'Unknown IP' : ipAddress,
      userAgent: userAgent ?? '',
      deviceLabel: parseDeviceLabel(userAgent),
      connectedAt: now,
      lastSeenAt: now,
      expiresAt: now.add(ttl),
      lastActivity: 'Paired with PIN',
    );
    _sessions[token] = _TrackedSession(token: token, device: device);
    _publishDevices();
    return token;
  }

  bool isTokenValid(String? token, {String? activity}) {
    if (token == null || token.isEmpty) return false;
    final trimmed = token.trim();
    if (!RegExp(r'^[a-fA-F0-9]{32,64}$').hasMatch(trimmed)) return false;

    final session = _sessions[trimmed];
    if (session == null) return false;

    final now = DateTime.now();
    if (now.isAfter(session.device.expiresAt)) {
      _removeSessionInternal(trimmed);
      _publishDevices();
      return false;
    }

    if (activity != null && activity.isNotEmpty) {
      session.device = session.device.copyWith(
        lastSeenAt: now,
        lastActivity: activity,
      );
      _publishDevices();
    } else if (now.difference(session.device.lastSeenAt).inSeconds >= 5) {
      session.device = session.device.copyWith(lastSeenAt: now);
      _publishDevices();
    }
    return true;
  }

  DesktopConnectedDevice? deviceForToken(String? token) {
    if (token == null) return null;
    return _sessions[token.trim()]?.device;
  }

  void recordActivity(String? token, String activity) {
    if (token == null) return;
    final session = _sessions[token.trim()];
    if (session == null) return;
    session.device = session.device.copyWith(
      lastSeenAt: DateTime.now(),
      lastActivity: activity,
    );
    _publishDevices();
  }

  String? createDownloadTicket(String sessionToken, String fileId) {
    if (!isTokenValid(sessionToken)) return null;
    pruneExpired();
    final ticket = _randomHex(24);
    _tickets[ticket] = _DownloadTicket(
      ticket: ticket,
      fileId: fileId,
      sessionToken: sessionToken.trim(),
      expiresAt: DateTime.now().add(const Duration(minutes: 10)),
    );
    return ticket;
  }

  String? validateDownloadTicket(String? ticket, String fileId) {
    if (ticket == null || ticket.isEmpty) return null;
    final entry = _tickets[ticket.trim()];
    if (entry == null) return null;
    if (entry.fileId != fileId || DateTime.now().isAfter(entry.expiresAt)) {
      _tickets.remove(ticket.trim());
      return null;
    }
    if (!isTokenValid(entry.sessionToken)) {
      _tickets.remove(ticket.trim());
      return null;
    }
    return entry.sessionToken;
  }

  bool revokeByToken(String? token) {
    if (token == null || token.isEmpty) return false;
    final removed = _removeSessionInternal(token.trim());
    if (removed) _publishDevices();
    return removed;
  }

  String? disconnectDevice(String deviceId) {
    String? targetToken;
    for (final entry in _sessions.entries) {
      if (entry.value.device.id == deviceId) {
        targetToken = entry.key;
        break;
      }
    }
    if (targetToken == null) return null;
    _removeSessionInternal(targetToken);
    _publishDevices();
    return targetToken;
  }

  void clearAll() {
    _sessions.clear();
    _tickets.clear();
    _publishDevices();
  }

  void pruneExpired() {
    final now = DateTime.now();
    bool changed = false;
    final expiredTokens = _sessions.entries
        .where((e) => now.isAfter(e.value.device.expiresAt))
        .map((e) => e.key)
        .toList();
    for (final token in expiredTokens) {
      _removeSessionInternal(token);
      changed = true;
    }
    _tickets.removeWhere((_, t) => now.isAfter(t.expiresAt));
    if (changed) _publishDevices();
  }

  bool _removeSessionInternal(String token) {
    final removed = _sessions.remove(token) != null;
    _tickets.removeWhere((_, t) => t.sessionToken == token);
    return removed;
  }

  void _publishDevices() {
    final list = _sessions.values.map((s) => s.device).toList()
      ..sort((a, b) => b.lastSeenAt.compareTo(a.lastSeenAt));
    devicesNotifier.value = List.unmodifiable(list);
  }
}
