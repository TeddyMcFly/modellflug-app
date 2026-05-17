import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/widgets/app_scaffold.dart';
import '../../shared/providers/fleet_provider.dart';

class FriendsPage extends ConsumerStatefulWidget {
  const FriendsPage({super.key});

  @override
  ConsumerState<FriendsPage> createState() => _FriendsPageState();
}

class _FriendsPageState extends ConsumerState<FriendsPage> {
  final List<_FriendRow> _friends = [
    const _FriendRow(
      name: 'Martin Keller',
      club: 'LMFC Lohburg',
      availability: 'Samstag',
      flyingModel: 'ASW 28',
      status: _FriendStatus.atField,
      locationSharingEnabled: true,
      chatReachable: true,
      initials: 'MK',
      color: Color(0xFF0A84FF),
    ),
    const _FriendRow(
      name: 'Claudia Stein',
      club: 'MFC Adler',
      availability: 'Sonntag',
      flyingModel: '',
      status: _FriendStatus.home,
      locationSharingEnabled: false,
      chatReachable: true,
      initials: 'CS',
      color: Color(0xFF16A34A),
    ),
    const _FriendRow(
      name: 'Jens Hoffmann',
      club: 'Modellflug Nord',
      availability: 'Mittwoch',
      flyingModel: '',
      status: _FriendStatus.home,
      locationSharingEnabled: false,
      chatReachable: false,
      initials: 'JH',
      color: Color(0xFF7C3AED),
    ),
    const _FriendRow(
      name: 'Sabine Wolf',
      club: 'LMFC Lohburg',
      availability: 'Freitag',
      flyingModel: 'Slowflyer',
      status: _FriendStatus.flying,
      locationSharingEnabled: true,
      chatReachable: true,
      initials: 'SW',
      color: Color(0xFFEA580C),
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final appSettings = ref.watch(fleetProvider).appSettings;
    final showChatColumn = appSettings.reachableByChat;
    final chatReachableCount = showChatColumn
        ? _friends.where((friend) => friend.chatReachable).length
        : 0;
    final atFieldCount = _friends
        .where(
          (friend) =>
              friend.locationSharingEnabled &&
              friend.status == _FriendStatus.atField,
        )
        .length;

    return AppScaffold(
      title: 'Freunde',
      subtitle:
          'Modellflug-Freunde, gemeinsame Flugtage und Kontaktinfos im Blick behalten.',
      action: FilledButton.icon(
        onPressed: _showAddFriendDialog,
        icon: const Icon(Icons.person_add_alt_1_rounded),
        label: const Text('Freund hinzufuegen'),
      ),
      children: [
        _FriendsToolbar(
          friendsCount: _friends.length,
          atFieldCount: atFieldCount,
          chatReachableCount: chatReachableCount,
        ),
        const SizedBox(height: 12),
        _FriendsTable(
          friends: _friends,
          showChatColumn: showChatColumn,
          onChat: _showChatDialog,
        ),
      ],
    );
  }

  Future<void> _showAddFriendDialog() async {
    final friend = await showDialog<_FriendRow>(
      context: context,
      builder: (context) => const _FriendDialog(),
    );

    if (friend == null) {
      return;
    }

    setState(() => _friends.add(friend));
  }

  void _showChatDialog(_FriendRow friend) {
    showDialog<void>(
      context: context,
      builder: (context) => _FriendChatDialog(friend: friend),
    );
  }
}

class _FriendsToolbar extends StatelessWidget {
  final int friendsCount;
  final int atFieldCount;
  final int chatReachableCount;

  const _FriendsToolbar({
    required this.friendsCount,
    required this.atFieldCount,
    required this.chatReachableCount,
  });

  @override
  Widget build(BuildContext context) {
    final cards = [
      _FriendStatCard(
        icon: Icons.group_rounded,
        value: '$friendsCount',
        label: 'Freunde',
      ),
      _FriendStatCard(
        icon: Icons.place_rounded,
        value: '$atFieldCount',
        label: 'Am Platz',
      ),
      _FriendStatCard(
        icon: Icons.chat_bubble_rounded,
        value: '$chatReachableCount',
        label: 'Direkt erreichbar',
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 720) {
          return Wrap(
            spacing: 10,
            runSpacing: 10,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: cards,
          );
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: cards,
            ),
          ],
        );
      },
    );
  }
}

class _FriendStatCard extends StatelessWidget {
  final IconData icon;
  final String value;
  final String label;

  const _FriendStatCard({
    required this.icon,
    required this.value,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return IntrinsicWidth(
      child: Card(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: const Color(0xFF0A84FF), size: 28),
              const SizedBox(width: 10),
              Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    value,
                    style: const TextStyle(
                      color: Color(0xFF06172E),
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  Text(
                    label,
                    style: const TextStyle(
                      color: Color(0xFF64748B),
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FriendsTable extends StatelessWidget {
  final List<_FriendRow> friends;
  final bool showChatColumn;
  final ValueChanged<_FriendRow> onChat;

  const _FriendsTable({
    required this.friends,
    required this.showChatColumn,
    required this.onChat,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 760,
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            headingRowHeight: 38,
            dataRowMinHeight: 52,
            dataRowMaxHeight: 58,
            horizontalMargin: 16,
            columnSpacing: 30,
            headingRowColor: WidgetStateProperty.all(
              const Color(0xFF0A84FF),
            ),
            headingTextStyle: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w900,
            ),
            dataTextStyle: const TextStyle(
              color: Color(0xFF334155),
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
            columns: [
              const DataColumn(label: Text('Freund')),
              const DataColumn(label: Text('Verein')),
              const DataColumn(label: Text('Naechster Flugtag')),
              const DataColumn(label: Text('Fliegt mit...')),
              const DataColumn(label: Text('Status')),
              if (showChatColumn) const DataColumn(label: Text('Chat')),
            ],
            rows: [
              for (final friend in friends)
                DataRow(
                  cells: [
                    DataCell(_FriendIdentity(friend)),
                    DataCell(Text(friend.club)),
                    DataCell(Text(friend.availability)),
                    DataCell(Text(friend.flyingModel)),
                    DataCell(_FriendStatusPill(friend)),
                    if (showChatColumn)
                      DataCell(
                        friend.chatReachable
                            ? IconButton(
                                tooltip: 'Chat mit ${friend.name}',
                                icon: const Icon(Icons.chat_rounded),
                                color: const Color(0xFF0A84FF),
                                onPressed: () => onChat(friend),
                              )
                            : const SizedBox.shrink(),
                      ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FriendIdentity extends StatelessWidget {
  final _FriendRow friend;

  const _FriendIdentity(this.friend);

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        CircleAvatar(
          radius: 18,
          backgroundColor: friend.color,
          foregroundImage: friend.settingsPhotoDataUri == null
              ? null
              : MemoryImage(_bytesFromDataUri(friend.settingsPhotoDataUri!)),
          child: friend.settingsPhotoDataUri != null
              ? null
              : Text(
                  friend.initials,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                  ),
                ),
        ),
        const SizedBox(width: 10),
        Text(friend.name),
      ],
    );
  }
}

enum _FriendStatus {
  atField('Am Platz'),
  flying('Beim Fliegen'),
  home('Zuhause');

  final String label;

  const _FriendStatus(this.label);
}

class _FriendRow {
  final String name;
  final String club;
  final String availability;
  final String flyingModel;
  final _FriendStatus status;
  final bool locationSharingEnabled;
  final bool chatReachable;
  final String initials;
  final Color color;
  final String? settingsPhotoDataUri;

  const _FriendRow({
    required this.name,
    required this.club,
    required this.availability,
    required this.flyingModel,
    required this.status,
    required this.locationSharingEnabled,
    required this.chatReachable,
    required this.initials,
    required this.color,
    this.settingsPhotoDataUri,
  });
}

class _FriendStatusPill extends StatelessWidget {
  final _FriendRow friend;

  const _FriendStatusPill(this.friend);

  @override
  Widget build(BuildContext context) {
    if (!friend.locationSharingEnabled) {
      return const Text(
        'Unbekannt',
        style: TextStyle(
          color: Color(0xFF64748B),
          fontSize: 11,
          fontWeight: FontWeight.w900,
        ),
      );
    }

    final dotColor = switch (friend.status) {
      _FriendStatus.atField => const Color(0xFFFACC15),
      _FriendStatus.flying => const Color(0xFF22C55E),
      _FriendStatus.home => const Color(0xFF94A3B8),
    };

    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: dotColor,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 7),
            Text(
              friend.status.label,
              style: const TextStyle(
                color: Color(0xFF334155),
                fontSize: 11,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FriendDialog extends StatefulWidget {
  const _FriendDialog();

  @override
  State<_FriendDialog> createState() => _FriendDialogState();
}

class _FriendDialogState extends State<_FriendDialog> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _club = TextEditingController(text: 'LMFC Lohburg');

  @override
  void dispose() {
    _name.dispose();
    _club.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Freund hinzufuegen'),
      content: SizedBox(
        width: 460,
        child: Form(
          key: _formKey,
          child: Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _FriendTextField(controller: _name, label: 'Name'),
              _FriendTextField(controller: _club, label: 'Verein'),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Abbrechen'),
        ),
        FilledButton(
          onPressed: _submit,
          child: const Text('Speichern'),
        ),
      ],
    );
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    final name = _name.text.trim();
    Navigator.of(context).pop(
      _FriendRow(
        name: name,
        club: _club.text.trim(),
        availability: '',
        flyingModel: '',
        status: _FriendStatus.home,
        locationSharingEnabled: false,
        chatReachable: true,
        initials: _initialsFor(name),
        color: _avatarColorFor(name),
        settingsPhotoDataUri: null,
      ),
    );
  }
}

class _FriendTextField extends StatelessWidget {
  final TextEditingController controller;
  final String label;

  const _FriendTextField({
    required this.controller,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 220,
      child: TextFormField(
        controller: controller,
        decoration: InputDecoration(labelText: label),
        validator: (value) =>
            value == null || value.trim().isEmpty ? 'Pflichtfeld' : null,
      ),
    );
  }
}

class _FriendChatDialog extends StatefulWidget {
  final _FriendRow friend;

  const _FriendChatDialog({required this.friend});

  @override
  State<_FriendChatDialog> createState() => _FriendChatDialogState();
}

class _FriendChatDialogState extends State<_FriendChatDialog> {
  final _message = TextEditingController();
  final List<String> _messages = const [
    'Bist du am Wochenende am Platz?',
    'Ja, wenn der Wind passt.',
  ].toList();

  @override
  void dispose() {
    _message.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        children: [
          CircleAvatar(
            radius: 17,
            backgroundColor: widget.friend.color,
            foregroundImage: widget.friend.settingsPhotoDataUri == null
                ? null
                : MemoryImage(
                    _bytesFromDataUri(widget.friend.settingsPhotoDataUri!),
                  ),
            child: widget.friend.settingsPhotoDataUri != null
                ? null
                : Text(
                    widget.friend.initials,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
          ),
          const SizedBox(width: 10),
          Expanded(child: Text('Chat mit ${widget.friend.name}')),
        ],
      ),
      content: SizedBox(
        width: 440,
        height: 360,
        child: Column(
          children: [
            Expanded(
              child: ListView.separated(
                itemCount: _messages.length,
                separatorBuilder: (context, index) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  final own = index.isOdd;
                  return Align(
                    alignment:
                        own ? Alignment.centerRight : Alignment.centerLeft,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: own
                            ? const Color(0xFF0A84FF)
                            : const Color(0xFFE8EDF3),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 8,
                        ),
                        child: Text(
                          _messages[index],
                          style: TextStyle(
                            color: own ? Colors.white : const Color(0xFF334155),
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _message,
                    decoration: const InputDecoration(
                      labelText: 'Nachricht',
                    ),
                    onSubmitted: (_) => _send(),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  tooltip: 'Senden',
                  onPressed: _send,
                  icon: const Icon(Icons.send_rounded),
                ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Schliessen'),
        ),
      ],
    );
  }

  void _send() {
    final text = _message.text.trim();
    if (text.isEmpty) {
      return;
    }

    setState(() {
      _messages.add(text);
      _message.clear();
    });
  }
}

String _initialsFor(String name) {
  final parts = name
      .trim()
      .split(RegExp(r'\s+'))
      .where((part) => part.isNotEmpty)
      .toList();
  if (parts.isEmpty) {
    return '?';
  }
  if (parts.length == 1) {
    return parts.first.characters.first.toUpperCase();
  }
  return '${parts.first.characters.first}${parts.last.characters.first}'
      .toUpperCase();
}

Color _avatarColorFor(String name) {
  const colors = [
    Color(0xFF0A84FF),
    Color(0xFF16A34A),
    Color(0xFF7C3AED),
    Color(0xFFEA580C),
    Color(0xFF0891B2),
    Color(0xFFDC2626),
  ];

  final index = name.codeUnits.fold<int>(0, (sum, code) => sum + code);
  return colors[index % colors.length];
}

Uint8List _bytesFromDataUri(String dataUri) {
  final commaIndex = dataUri.indexOf(',');
  final encoded =
      commaIndex == -1 ? dataUri : dataUri.substring(commaIndex + 1);
  return base64Decode(encoded);
}
