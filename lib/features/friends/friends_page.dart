import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/widgets/app_scaffold.dart';
import '../../shared/providers/fleet_provider.dart';
import '../../shared/utils/media_source.dart';

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
      lastOnline: 'gerade eben',
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
      lastOnline: 'vor 18 Min.',
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
      lastOnline: 'gestern 20:14',
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
      lastOnline: 'gerade eben',
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
          onDelete: _confirmDeleteFriend,
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

  Future<void> _confirmDeleteFriend(_FriendRow friend) async {
    final delete = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Freund loeschen'),
        content: Text(
          '${friend.name} wirklich aus der Freundesliste entfernen?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Abbrechen'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.of(context).pop(true),
            icon: const Icon(Icons.delete_rounded),
            label: const Text('Loeschen'),
          ),
        ],
      ),
    );

    if (delete != true) {
      return;
    }

    setState(() => _friends.remove(friend));
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
        label: 'Online',
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
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: const Color(0xFF0A84FF), size: 22),
              const SizedBox(width: 8),
              Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    value,
                    style: const TextStyle(
                      color: Color(0xFF06172E),
                      fontSize: 17,
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

class _FriendsTable extends StatefulWidget {
  final List<_FriendRow> friends;
  final bool showChatColumn;
  final ValueChanged<_FriendRow> onChat;
  final ValueChanged<_FriendRow> onDelete;

  const _FriendsTable({
    required this.friends,
    required this.showChatColumn,
    required this.onChat,
    required this.onDelete,
  });

  @override
  State<_FriendsTable> createState() => _FriendsTableState();
}

class _FriendsTableState extends State<_FriendsTable> {
  final ScrollController _horizontalController = ScrollController();

  @override
  void dispose() {
    _horizontalController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final tableWidth =
            constraints.maxWidth < 980 ? 980.0 : constraints.maxWidth;

        return ClipRect(
          child: SizedBox(
            width: constraints.maxWidth,
            child: Card(
              clipBehavior: Clip.antiAlias,
              child: Scrollbar(
                controller: _horizontalController,
                thumbVisibility: true,
                interactive: true,
                notificationPredicate: (notification) =>
                    notification.metrics.axis == Axis.horizontal,
                child: SingleChildScrollView(
                  controller: _horizontalController,
                  scrollDirection: Axis.horizontal,
                  primary: false,
                  padding: const EdgeInsets.only(bottom: 12),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(minWidth: tableWidth),
                    child: DataTable(
                      headingRowHeight: 38,
                      dataRowMinHeight: 82,
                      dataRowMaxHeight: 88,
                      horizontalMargin: 16,
                      columnSpacing: 30,
                      headingRowColor: WidgetStateProperty.all(
                        const Color(0xFFDCEBFF),
                      ),
                      headingTextStyle: const TextStyle(
                        color: Color(0xFF06172E),
                        fontSize: 13,
                        letterSpacing: 0.2,
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
                        const DataColumn(label: Text('Zuletzt online...')),
                        const DataColumn(label: Text('Fliegt mit...')),
                        const DataColumn(label: Text('Status')),
                        if (widget.showChatColumn)
                          const DataColumn(label: Text('Chat')),
                        const DataColumn(label: Text('Aktion')),
                      ],
                      rows: [
                        for (final friend in widget.friends)
                          DataRow(
                            cells: [
                              DataCell(_FriendIdentity(friend)),
                              DataCell(Text(friend.club)),
                              DataCell(Text(friend.lastOnline)),
                              DataCell(
                                friend.locationSharingEnabled
                                    ? Text(friend.flyingModel)
                                    : const _OfflineText(),
                              ),
                              DataCell(_FriendStatusPill(friend)),
                              if (widget.showChatColumn)
                                DataCell(
                                  friend.chatReachable
                                      ? IconButton(
                                          tooltip: 'Chat mit ${friend.name}',
                                          icon: const Icon(
                                            Icons.chat_rounded,
                                            size: 28,
                                          ),
                                          color: const Color(0xFF0A84FF),
                                          onPressed: () =>
                                              widget.onChat(friend),
                                        )
                                      : const SizedBox.shrink(),
                                ),
                              DataCell(_FriendActions(
                                  friend: friend, onDelete: widget.onDelete)),
                            ],
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
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
          radius: 35,
          backgroundColor: friend.color,
          foregroundImage: maybeMediaImageProvider(friend.settingsPhotoDataUri),
          child: friend.settingsPhotoDataUri != null
              ? null
              : Text(
                  friend.initials,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 19,
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

class _FriendActions extends StatelessWidget {
  final _FriendRow friend;
  final ValueChanged<_FriendRow> onDelete;

  const _FriendActions({
    required this.friend,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      tooltip: 'Aktionen fuer ${friend.name}',
      icon: const Icon(Icons.more_vert_rounded),
      itemBuilder: (context) => const [
        PopupMenuItem(
          value: 'delete',
          child: Row(
            children: [
              Icon(Icons.delete_rounded, size: 18),
              SizedBox(width: 8),
              Text('Loeschen'),
            ],
          ),
        ),
      ],
      onSelected: (value) {
        if (value == 'delete') {
          onDelete(friend);
        }
      },
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
  final String lastOnline;
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
    required this.lastOnline,
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
      return const _OfflineText();
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

class _OfflineText extends StatelessWidget {
  const _OfflineText();

  @override
  Widget build(BuildContext context) {
    return const Text(
      'Offline',
      style: TextStyle(
        color: Color(0xFF94A3B8),
        fontSize: 10,
        fontStyle: FontStyle.italic,
        fontWeight: FontWeight.w600,
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
        lastOnline: 'noch nie',
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
            foregroundImage:
                maybeMediaImageProvider(widget.friend.settingsPhotoDataUri),
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
