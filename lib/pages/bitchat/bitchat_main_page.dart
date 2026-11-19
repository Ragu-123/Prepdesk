import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../services/bitchat/bitchat_models.dart';
import '../../services/bitchat/bitchat_service.dart';

class BitchatMainPage extends StatefulWidget {
  const BitchatMainPage({super.key});

  @override
  State<BitchatMainPage> createState() => _BitchatMainPageState();
}

class _BitchatMainPageState extends State<BitchatMainPage> {
  final _chat = BitchatService.instance;
  final _draft = TextEditingController();
  bool _sending = false;
  bool _starting = false;

  @override
  void dispose() {
    _draft.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    setState(() => _starting = true);
    try {
      await _chat.setMasterPower(true);
    } catch (_) {
      if (mounted) _toast('Could not start BitChat. Try reopening Prepdesk.');
    } finally {
      if (mounted) setState(() => _starting = false);
    }
  }

  void _toast(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _send() async {
    final text = _draft.text.trim();
    if (_sending || text.isEmpty) return;
    setState(() => _sending = true);
    try {
      final accepted = await _chat.sendMessage(text);
      if (!mounted) return;
      if (accepted && _draft.text.trim() == text) _draft.clear();
      if (!accepted) _toast('No relay confirmed the message. Your draft is still here.');
    } catch (_) {
      if (mounted) _toast('Could not send. Your draft is still here.');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<String?> _ask(String title, String label, {String initial = '', int limit = 32}) async {
    var value = initial;
    return showDialog<String>(context: context, builder: (context) => AlertDialog(
      title: Text(title),
      content: TextFormField(
        initialValue: initial,
        autofocus: true,
        maxLength: limit,
        decoration: InputDecoration(labelText: label),
        onChanged: (text) => value = text,
        onFieldSubmitted: (_) => Navigator.of(context).pop(value.trim()),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.of(context).pop(value.trim()), child: const Text('Done')),
      ],
    ));
  }

  Future<void> _join() async {
    final code = (await _ask('Join a public room', 'Room code'))?.toLowerCase();
    if (!mounted || code == null || code.isEmpty) return;
    if (!RegExp(r'^[a-z0-9_-]{1,32}$').hasMatch(code)) {
      _toast('Use up to 32 letters, numbers, hyphens or underscores.');
      return;
    }
    final id = 'geo:$code';
    if (_chat.channelsNotifier.value.any((room) => room.id == id)) {
      await _chat.selectChannel(id);
    } else {
      await _chat.addChannel('#$code', ChannelType.geohash, geohash: code);
    }
  }

  Future<void> _chooseRoom() => showModalBottomSheet<void>(
    context: context, useSafeArea: true, showDragHandle: true,
    builder: (sheetContext) => SafeArea(top: false, child: ValueListenableBuilder<List<BitchatChannel>>(
      valueListenable: _chat.channelsNotifier,
      builder: (context, rooms, _) => ListView(
        shrinkWrap: true,
        children: [
          ListTile(leading: const Icon(Icons.add_rounded), title: const Text('Join a public room'),
            onTap: () { Navigator.pop(sheetContext); _join(); }),
          for (final room in rooms)
            ListTile(
              leading: Icon(room.type == ChannelType.geohash ? Icons.tag_rounded : Icons.history_rounded),
              title: Text(room.name),
              subtitle: room.type == ChannelType.geohash ? null : const Text('Saved history'),
              selected: room.id == _chat.activeChannel?.id,
              onTap: () { Navigator.pop(sheetContext); _chat.selectChannel(room.id); },
            ),
        ],
      ),
    )),
  );

  Future<void> _editNickname() async {
    final nickname = await _ask('Edit nickname', 'Nickname', initial: _chat.nickname, limit: 40);
    if (nickname != null && nickname.isNotEmpty) await _chat.setNickname(nickname);
  }

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<bool>(
    valueListenable: _chat.isMasterPowerOnNotifier,
    builder: (context, active, _) => Scaffold(
      appBar: AppBar(
        title: const Text('BitChat'),
        actions: [
          if (active) IconButton(
            tooltip: 'Edit nickname', icon: const Icon(Icons.person_outline_rounded),
            onPressed: _editNickname,
          ),
          if (active) IconButton(
            tooltip: 'Turn off BitChat', icon: const Icon(Icons.power_settings_new_rounded),
            onPressed: () => _chat.setMasterPower(false),
          ),
        ],
      ),
      body: active ? _workspace() : _standby(context),
    ),
  );

  Widget _standby(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Center(child: SingleChildScrollView(
      padding: const EdgeInsets.all(28),
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        CircleAvatar(radius: 36, backgroundColor: colors.primaryContainer,
          child: Icon(Icons.forum_outlined, size: 32, color: colors.onPrimaryContainer)),
        const SizedBox(height: 18),
        Text('BitChat is off', style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 8),
        const Text('Turn it on to join public rooms over the internet. Share a room code with someone to chat there.',
          textAlign: TextAlign.center),
        const SizedBox(height: 20),
        FilledButton(onPressed: _starting ? null : _start, child: Text(_starting ? 'Starting…' : 'Turn on BitChat')),
      ]),
    ));
  }

  Widget _workspace() => ValueListenableBuilder<BitchatChannel?>(
    valueListenable: _chat.activeChannelNotifier,
    builder: (context, room, _) => ValueListenableBuilder<Map<String, bool>>(
      valueListenable: _chat.relayStatusNotifier,
      builder: (context, relays, _) {
        final connected = relays.values.where((value) => value).length;
        final canSend = connected > 0 && room?.type == ChannelType.geohash;
        final colors = Theme.of(context).colorScheme;
        return Column(children: [
          ListTile(
            tileColor: colors.surfaceContainerLow,
            leading: CircleAvatar(backgroundColor: colors.primaryContainer,
              foregroundColor: colors.onPrimaryContainer, child: const Icon(Icons.tag_rounded)),
            title: Text(room?.name ?? 'Rooms', maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: Text(room?.type != ChannelType.geohash ? 'Saved history' :
              (connected == 0 ? 'Waiting for a relay' : 'Public room · $connected connected')),
            trailing: const Icon(Icons.expand_more_rounded),
            onTap: _sending ? null : _chooseRoom,
          ),
          Expanded(child: _messages()),
          SafeArea(top: false, child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: canSend ? Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Expanded(child: TextField(controller: _draft, minLines: 1, maxLines: 4,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(hintText: 'Message this room'))),
              const SizedBox(width: 8),
              ValueListenableBuilder<TextEditingValue>(
                valueListenable: _draft,
                builder: (context, draft, _) => IconButton.filled(
                  tooltip: 'Send message',
                  onPressed: _sending || draft.text.trim().isEmpty ? null : _send,
                  icon: _sending
                    ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.arrow_upward_rounded),
                ),
              ),
            ]) : Text(room?.type == ChannelType.geohash
              ? 'Connect to a relay to send messages.'
              : 'Join a public room to send messages.'),
          )),
        ]);
      },
    ),
  );

  Widget _messages() => ValueListenableBuilder<List<BitchatMessage>>(
    valueListenable: _chat.currentChannelMessagesNotifier,
    builder: (context, messages, _) {
      if (messages.isEmpty) return const Center(child: Text('No messages in this room yet.'));
      final colors = Theme.of(context).colorScheme;
      return ListView.builder(
        reverse: true, padding: const EdgeInsets.all(16), itemCount: messages.length,
        itemBuilder: (context, index) {
          final message = messages[messages.length - 1 - index];
          final mine = _chat.isOwnMessage(message);
          return Align(
            alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.78),
              child: Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: mine ? colors.primaryContainer : colors.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${mine ? 'You' : message.sender} · ${DateFormat.Hm().format(message.timestamp)}',
                    style: Theme.of(context).textTheme.labelSmall),
                  const SizedBox(height: 4),
                  SelectableText(message.content, style: TextStyle(
                    color: mine ? colors.onPrimaryContainer : colors.onSurface)),
                ]),
              ),
            ),
          );
        },
      );
    },
  );
}
