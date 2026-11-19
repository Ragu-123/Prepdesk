import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tasks/services/bitchat/bitchat_models.dart';
import 'package:tasks/services/bitchat/nostr_crypto.dart';
import 'package:tasks/services/bitchat/nostr_relay_service.dart';

void main() {
  test('Two opted-in clients receive one copy of a public relay message', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final sockets = <WebSocket, String?>{};
    final subscribed = Completer<void>();
    server.listen((request) async {
      final socket = await WebSocketTransformer.upgrade(request);
      sockets[socket] = null;
      socket.listen((frame) {
        final packet = jsonDecode(frame as String) as List;
        if (packet.first == 'REQ') {
          expect(packet[2]['#g'], ['study']);
          sockets[socket] = packet[1] as String;
          if (sockets.values.whereType<String>().length == 2 && !subscribed.isCompleted) {
            subscribed.complete();
          }
        }
        if (packet.first == 'EVENT' && packet[1]['kind'] == 20000) {
          final event = packet[1] as Map<String, dynamic>;
          socket.add(jsonEncode(['OK', event['id'], true, '']));
          for (final entry in sockets.entries) {
            final subscription = entry.value;
            if (subscription == null) continue;
            final delivery = jsonEncode(['EVENT', subscription, event]);
            entry.key.add(delivery);
            entry.key.add(delivery);
          }
        }
      });
    });
    final sender = NostrRelayService();
    final receiver = NostrRelayService();
    final sent = <BitchatMessage>[];
    final received = <BitchatMessage>[];
    final arrived = Completer<void>();
    sender.messageStream.listen(sent.add);
    receiver.messageStream.listen((message) {
      received.add(message);
      if (!arrived.isCompleted) arrived.complete();
    });
    try {
      for (final client in [sender, receiver]) {
        final key = NostrCrypto.generatePrivateKey();
        client.initialize(
          privateKeyHex: key,
          publicKeyHex: NostrCrypto.derivePublicKey(key),
          nickname: 'Student',
          customRelays: ['ws://127.0.0.1:${server.port}'],
          autoConnect: false,
        );
        client.subscribeToGeohash('study');
      }
      expect(await sender.publishEphemeralGeohashMessage(geohash: 'study', content: 'Offline'), isNull);
      expect(sockets, isEmpty);
      sender.connectAll();
      receiver.connectAll();
      await subscribed.future.timeout(const Duration(seconds: 5));
      final event = await sender.publishEphemeralGeohashMessage(geohash: 'study', content: 'Review together');
      expect(event, isNotNull);
      await arrived.future.timeout(const Duration(seconds: 5));
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(sent.map((message) => message.id), [event!.id]);
      expect(received.map((message) => message.id), [event.id]);
      expect(received.single.content, 'Review together');
    } finally {
      sender.dispose();
      receiver.dispose();
      await Future.wait(sockets.keys.map((socket) => socket.close()));
      await server.close(force: true);
    }
  });
}
