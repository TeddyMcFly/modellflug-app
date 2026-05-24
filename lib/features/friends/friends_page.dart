import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/widgets/app_scaffold.dart';
import '../../shared/models/aircraft_model.dart';
import '../../shared/providers/fleet_provider.dart';
import '../../shared/services/auth_service.dart';
import '../../shared/services/member_chat_service.dart';
import '../../shared/utils/media_source.dart';

const _chatFrameColor = Color(0xFF06172E);

class FriendsPage extends ConsumerStatefulWidget {
  const FriendsPage({super.key});

  @override
  ConsumerState<FriendsPage> createState() => _FriendsPageState();
}

class _FriendsPageState extends ConsumerState<FriendsPage> {
  String? _lastProfileSignature;

  @override
  Widget build(BuildContext context) {
    final fleet = ref.watch(fleetProvider);
    final authUser = ref.watch(authStateProvider).maybeWhen(
          data: (user) => user,
          orElse: () => null,
        );
    final chatService = ref.watch(memberChatServiceProvider);
    final reachableByChat = fleet.appSettings.reachableByChat;

    _syncPublicMemberProfile(
      user: authUser,
      service: chatService,
      fleet: fleet,
    );

    return AppScaffold(
      title: 'Mitglieder',
      subtitle: 'Angemeldete Mitglieder und direkte Nachrichten im Blick.',
      action: _ChatAvailabilityPill(enabled: reachableByChat),
      children: [
        if (authUser == null || chatService == null)
          const _InfoCard(
            icon: Icons.lock_person_rounded,
            title: 'Anmeldung erforderlich',
            message:
                'Bitte melde dich an. Danach kann die App Mitglieder und Chats laden.',
          )
        else
          _MemberList(
            service: chatService,
            currentUser: authUser,
            currentDisplayName: _displayNameFor(authUser, fleet),
            currentPhotoSource: _chatAvatarSourceFor(
              authUser,
              fleet.pilotProfile,
            ),
            currentUserReachable: reachableByChat,
          ),
      ],
    );
  }

  void _syncPublicMemberProfile({
    required User? user,
    required MemberChatService? service,
    required FleetState fleet,
  }) {
    if (user == null || service == null) {
      _lastProfileSignature = null;
      return;
    }

    final displayName = _displayNameFor(user, fleet);
    final photoSource = _memberPreviewSourceFor(fleet.pilotProfile);
    final signature = [
      user.uid,
      displayName,
      fleet.pilotProfile.club,
      fleet.appSettings.reachableByChat,
      fleet.appSettings.shareLocationWithFriends,
      fleet.appSettings.presenceStatus.name,
      _hasProfilePhoto(user, fleet.pilotProfile),
      photoSource ?? '',
    ].join('|');

    if (_lastProfileSignature == signature) {
      return;
    }
    _lastProfileSignature = signature;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      unawaited(
        service
            .saveCurrentMemberProfile(
              user: user,
              displayName: displayName,
              club: fleet.pilotProfile.club,
              reachableByChat: fleet.appSettings.reachableByChat,
              shareLocation: fleet.appSettings.shareLocationWithFriends,
              presenceStatus: fleet.appSettings.presenceStatus.name,
              photoSource: photoSource,
              clearPhotoSource: !_hasProfilePhoto(user, fleet.pilotProfile),
            )
            .catchError((Object _) {}),
      );
    });
  }
}

class _MemberList extends StatefulWidget {
  final MemberChatService service;
  final User currentUser;
  final String currentDisplayName;
  final String? currentPhotoSource;
  final bool currentUserReachable;

  const _MemberList({
    required this.service,
    required this.currentUser,
    required this.currentDisplayName,
    required this.currentPhotoSource,
    required this.currentUserReachable,
  });

  @override
  State<_MemberList> createState() => _MemberListState();
}

class _MemberListState extends State<_MemberList> {
  final Set<String> _knownUnreadMessageKeys = {};
  bool _unreadNotificationsPrimed = false;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<MemberProfile>>(
      stream: widget.service.watchMembers(widget.currentUser.uid),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return const _InfoCard(
            icon: Icons.cloud_off_rounded,
            title: 'Mitglieder konnten nicht geladen werden',
            message:
                'Bitte pruefe, ob die neuen Firestore-Regeln veroeffentlicht sind.',
          );
        }

        final members = snapshot.data ?? const <MemberProfile>[];
        final loading = snapshot.connectionState == ConnectionState.waiting &&
            !snapshot.hasData;

        if (loading) {
          return const _InfoCard(
            icon: Icons.sync_rounded,
            title: 'Mitglieder werden geladen',
            message: 'Die App verbindet sich gerade mit Firebase.',
            loading: true,
          );
        }

        final chatReachableCount =
            members.where((member) => member.reachableByChat).length;

        return StreamBuilder<List<ChatSummary>>(
          stream: widget.service.watchChatSummaries(widget.currentUser.uid),
          builder: (context, chatSnapshot) {
            final chatLoadFailed = chatSnapshot.hasError;
            final chats = chatLoadFailed
                ? const <ChatSummary>[]
                : chatSnapshot.data ?? const <ChatSummary>[];
            final chatsByPeer = {
              for (final chat in chats)
                if (chat.peerUidFor(widget.currentUser.uid).isNotEmpty)
                  chat.peerUidFor(widget.currentUser.uid): chat,
            };
            final unreadCount = chats.fold<int>(
              0,
              (sum, chat) => sum + chat.unreadCountFor(widget.currentUser.uid),
            );

            _notifyAboutNewUnreadMessages(context, chats, members);

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _MembersToolbar(
                  membersCount: members.length,
                  chatReachableCount: chatReachableCount,
                  unreadCount: unreadCount,
                ),
                if (!widget.currentUserReachable) ...[
                  const SizedBox(height: 12),
                  const _InfoCard(
                    icon: Icons.chat_bubble_outline_rounded,
                    title: 'Dein Chat ist ausgeschaltet',
                    message:
                        'Aktiviere ihn in den Einstellungen, wenn andere Mitglieder dich anschreiben duerfen.',
                  ),
                ],
                if (chatLoadFailed) ...[
                  const SizedBox(height: 12),
                  const _InfoCard(
                    icon: Icons.mark_chat_unread_rounded,
                    title: 'Chat-Uebersicht wird neu verbunden',
                    message:
                        'Die Mitglieder bleiben nutzbar. Bitte die Seite gleich einmal aktualisieren.',
                  ),
                ],
                const SizedBox(height: 12),
                const _MemberSectionHeader(),
                const SizedBox(height: 10),
                if (members.isEmpty)
                  _InfoCard(
                    icon: Icons.group_add_rounded,
                    title: 'Noch keine anderen Mitglieder',
                    message: _emptyMembersMessage(widget.currentUser),
                  )
                else
                  _MembersTable(
                    members: members,
                    chatsByPeer: chatsByPeer,
                    currentUser: widget.currentUser,
                    currentUserReachable: widget.currentUserReachable,
                    onChat: (member) => _openChat(context, member),
                  ),
              ],
            );
          },
        );
      },
    );
  }

  String _emptyMembersMessage(User currentUser) {
    final account = currentUser.email?.trim();
    final accountText =
        account == null || account.isEmpty ? 'diesem Konto' : account;
    return 'Du bist aktuell mit $accountText angemeldet. Die App zeigt hier nur andere Konten an, nicht dasselbe Konto auf einem zweiten Geraet.';
  }

  void _openChat(BuildContext context, MemberProfile member) {
    showDialog<void>(
      context: context,
      builder: (context) => _MemberChatDialog(
        service: widget.service,
        currentUser: widget.currentUser,
        currentDisplayName: widget.currentDisplayName,
        currentPhotoSource: widget.currentPhotoSource,
        peer: member,
      ),
    );
  }

  void _notifyAboutNewUnreadMessages(
    BuildContext context,
    List<ChatSummary> chats,
    List<MemberProfile> members,
  ) {
    final memberNames = {
      for (final member in members) member.uid: member.displayName,
    };
    final unreadChats = [
      for (final chat in chats)
        if (chat.isUnreadFor(widget.currentUser.uid)) chat,
    ];
    final unreadKeys = {
      for (final chat in unreadChats) _notificationKeyFor(chat),
    };

    if (!_unreadNotificationsPrimed) {
      _knownUnreadMessageKeys.addAll(unreadKeys);
      _unreadNotificationsPrimed = true;
      return;
    }

    final newKeys = unreadKeys.difference(_knownUnreadMessageKeys);
    _knownUnreadMessageKeys
      ..clear()
      ..addAll(unreadKeys);

    if (newKeys.isEmpty) {
      return;
    }

    final newestChat = unreadChats.firstWhere(
      (chat) => newKeys.contains(_notificationKeyFor(chat)),
      orElse: () => unreadChats.first,
    );
    final peerName =
        memberNames[newestChat.peerUidFor(widget.currentUser.uid)] ??
            'Mitglied';

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Neue Nachricht von $peerName'),
          action: SnackBarAction(
            label: 'Oeffnen',
            onPressed: () {
              final peer = members.where(
                (member) =>
                    member.uid == newestChat.peerUidFor(widget.currentUser.uid),
              );
              if (peer.isNotEmpty) {
                _openChat(context, peer.first);
              }
            },
          ),
        ),
      );
    });
  }

  String _notificationKeyFor(ChatSummary chat) {
    final date = chat.lastMessageAt ?? chat.updatedAt;
    return '${chat.id}:${date?.toIso8601String() ?? chat.lastMessage}';
  }
}

class _MemberSectionHeader extends StatelessWidget {
  const _MemberSectionHeader();

  @override
  Widget build(BuildContext context) {
    return const Row(
      children: [
        Icon(Icons.people_alt_rounded, color: Color(0xFF0A84FF)),
        SizedBox(width: 8),
        Expanded(
          child: Text(
            'Mitglieder',
            style: TextStyle(
              color: Color(0xFF06172E),
              fontSize: 18,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
      ],
    );
  }
}

class _ChatAvailabilityPill extends StatelessWidget {
  final bool enabled;

  const _ChatAvailabilityPill({required this.enabled});

  @override
  Widget build(BuildContext context) {
    final color = enabled ? const Color(0xFF16A34A) : const Color(0xFF94A3B8);
    final label = enabled ? 'Chat aktiv' : 'Chat aus';

    return DecoratedBox(
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.28)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              enabled ? Icons.chat_bubble_rounded : Icons.chat_bubble_outline,
              size: 18,
              color: color,
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 12,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MembersToolbar extends StatelessWidget {
  final int membersCount;
  final int chatReachableCount;
  final int unreadCount;

  const _MembersToolbar({
    required this.membersCount,
    required this.chatReachableCount,
    required this.unreadCount,
  });

  @override
  Widget build(BuildContext context) {
    final cards = [
      _MemberStatCard(
        icon: Icons.group_rounded,
        value: '$membersCount',
        label: 'Mitglieder',
      ),
      _MemberStatCard(
        icon: Icons.chat_bubble_rounded,
        value: '$chatReachableCount',
        label: 'Chatbereit',
      ),
      _MemberStatCard(
        icon: Icons.mark_chat_unread_rounded,
        value: '$unreadCount',
        label: 'Ungelesen',
      ),
    ];

    return Wrap(
      spacing: 10,
      runSpacing: 10,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: cards,
    );
  }
}

class _MemberStatCard extends StatelessWidget {
  final IconData icon;
  final String value;
  final String label;

  const _MemberStatCard({
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

class _MembersTable extends StatefulWidget {
  final List<MemberProfile> members;
  final Map<String, ChatSummary> chatsByPeer;
  final User currentUser;
  final bool currentUserReachable;
  final ValueChanged<MemberProfile> onChat;

  const _MembersTable({
    required this.members,
    required this.chatsByPeer,
    required this.currentUser,
    required this.currentUserReachable,
    required this.onChat,
  });

  @override
  State<_MembersTable> createState() => _MembersTableState();
}

class _MembersTableState extends State<_MembersTable> {
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
              color: Colors.white,
              surfaceTintColor: Colors.transparent,
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
                  child: SizedBox(
                    width: tableWidth,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const _MembersTableHeader(),
                        for (final member in widget.members)
                          _MemberTableRow(
                            member: member,
                            chat: widget.chatsByPeer[member.uid],
                            currentUser: widget.currentUser,
                            currentUserReachable: widget.currentUserReachable,
                            onChat: () => widget.onChat(member),
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

class _MembersTableHeader extends StatelessWidget {
  const _MembersTableHeader();

  @override
  Widget build(BuildContext context) {
    return const DecoratedBox(
      decoration: BoxDecoration(color: Color(0xFFDCEBFF)),
      child: SizedBox(
        height: 42,
        child: Row(
          children: [
            _TableHeaderCell(label: 'Mitglied', flex: 3),
            _TableHeaderCell(label: 'Verein', flex: 2),
            _TableHeaderCell(label: 'Zuletzt aktiv', flex: 2),
            _TableHeaderCell(label: 'Letzter Chat', flex: 3),
            _TableHeaderCell(label: 'Flugfunk', flex: 2),
          ],
        ),
      ),
    );
  }
}

class _MemberTableRow extends StatelessWidget {
  final MemberProfile member;
  final ChatSummary? chat;
  final User currentUser;
  final bool currentUserReachable;
  final VoidCallback onChat;

  const _MemberTableRow({
    required this.member,
    required this.chat,
    required this.currentUser,
    required this.currentUserReachable,
    required this.onChat,
  });

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(
          bottom: BorderSide(color: Color(0xFFE2E8F0)),
        ),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 92),
        child: Row(
          children: [
            Expanded(
              flex: 3,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: _MemberIdentity(member),
              ),
            ),
            Expanded(
              flex: 2,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: _TableBodyText(_clubLabel(member.club)),
              ),
            ),
            Expanded(
              flex: 2,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: _TableBodyText(_lastSeenLabel(member.lastSeen)),
              ),
            ),
            Expanded(
              flex: 3,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: _LastChatCell(
                  chat: chat,
                  currentUid: currentUser.uid,
                ),
              ),
            ),
            Expanded(
              flex: 2,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: _ChatButton(
                    enabled: currentUserReachable && member.reachableByChat,
                    memberName: member.displayName,
                    unreadCount: chat?.unreadCountFor(currentUser.uid) ?? 0,
                    onPressed: onChat,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TableHeaderCell extends StatelessWidget {
  final String label;
  final int flex;

  const _TableHeaderCell({
    required this.label,
    required this.flex,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      flex: flex,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: Color(0xFF06172E),
            fontSize: 13,
            letterSpacing: 0,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
    );
  }
}

class _TableBodyText extends StatelessWidget {
  final String text;

  const _TableBodyText(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(
        color: Color(0xFF334155),
        fontSize: 12,
        fontWeight: FontWeight.w700,
      ),
    );
  }
}

class _MemberIdentity extends StatelessWidget {
  final MemberProfile member;

  const _MemberIdentity(this.member);

  @override
  Widget build(BuildContext context) {
    final photoSource = _safeMemberPhotoSource(member.photoSource);
    final email = member.email?.trim();

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        CircleAvatar(
          radius: 30,
          backgroundColor: _avatarColorFor(member.uid),
          foregroundImage: maybeMediaImageProvider(photoSource),
          child: Text(
            _initialsFor(member.displayName),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 17,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
        const SizedBox(width: 10),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 220),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                member.displayName,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Color(0xFF06172E),
                  fontSize: 14,
                  fontWeight: FontWeight.w900,
                ),
              ),
              if (email != null && email.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(
                  email,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF64748B),
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _ChatButton extends StatelessWidget {
  final bool enabled;
  final String memberName;
  final int unreadCount;
  final VoidCallback onPressed;

  const _ChatButton({
    required this.enabled,
    required this.memberName,
    required this.unreadCount,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final wrappedButton = Tooltip(
      message: enabled
          ? 'Chat mit $memberName starten'
          : '$memberName ist aktuell nicht per Chat erreichbar',
      child: _VisibleChatActionButton(
        enabled: enabled,
        onPressed: onPressed,
      ),
    );

    if (unreadCount <= 0) {
      return wrappedButton;
    }

    return Stack(
      clipBehavior: Clip.none,
      children: [
        wrappedButton,
        Positioned(
          right: -5,
          top: -8,
          child: _UnreadBadge(count: unreadCount),
        ),
      ],
    );
  }
}

class _VisibleChatActionButton extends StatelessWidget {
  final bool enabled;
  final VoidCallback onPressed;

  const _VisibleChatActionButton({
    required this.enabled,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final background =
        enabled ? const Color(0xFF0A84FF) : const Color(0xFFE2E8F0);
    final foreground = enabled ? Colors.white : const Color(0xFF64748B);
    final border = enabled ? const Color(0xFF0067D6) : const Color(0xFFCBD5E1);
    final label = enabled ? 'Chat' : 'Aus';

    return Semantics(
      button: true,
      enabled: enabled,
      label: enabled ? 'Chat starten' : 'Chat nicht erreichbar',
      child: InkWell(
        onTap: enabled ? onPressed : null,
        borderRadius: BorderRadius.circular(8),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: border),
          ),
          child: SizedBox(
            width: 104,
            height: 44,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  enabled
                      ? Icons.chat_rounded
                      : Icons.chat_bubble_outline_rounded,
                  color: foreground,
                  size: 22,
                ),
                const SizedBox(width: 7),
                Text(
                  label,
                  style: TextStyle(
                    color: foreground,
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _LastChatCell extends StatelessWidget {
  final ChatSummary? chat;
  final String currentUid;

  const _LastChatCell({
    required this.chat,
    required this.currentUid,
  });

  @override
  Widget build(BuildContext context) {
    final chat = this.chat;
    if (chat == null || chat.lastMessage.isEmpty) {
      return const _MutedText('Noch kein Chat');
    }

    final own = chat.lastSenderId == currentUid;
    final text = own ? 'Du: ${chat.lastMessage}' : chat.lastMessage;
    final time = chat.lastMessageAt ?? chat.updatedAt;

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 260),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: chat.isUnreadFor(currentUid)
                  ? const Color(0xFF06172E)
                  : const Color(0xFF475569),
              fontWeight: chat.isUnreadFor(currentUid)
                  ? FontWeight.w900
                  : FontWeight.w700,
            ),
          ),
          if (time != null) ...[
            const SizedBox(height: 3),
            Text(
              _dateTimeLabel(time),
              style: const TextStyle(
                color: Color(0xFF94A3B8),
                fontSize: 10,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _UnreadBadge extends StatelessWidget {
  final int count;

  const _UnreadBadge({required this.count});

  @override
  Widget build(BuildContext context) {
    final label = count > 9 ? '9+' : '$count';
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFFDC2626),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white, width: 2),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 22, minHeight: 22),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 5),
          child: Center(
            child: Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 10,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _MemberChatDialog extends StatefulWidget {
  final MemberChatService service;
  final User currentUser;
  final String currentDisplayName;
  final String? currentPhotoSource;
  final MemberProfile peer;

  const _MemberChatDialog({
    required this.service,
    required this.currentUser,
    required this.currentDisplayName,
    required this.currentPhotoSource,
    required this.peer,
  });

  @override
  State<_MemberChatDialog> createState() => _MemberChatDialogState();
}

class _MemberChatDialogState extends State<_MemberChatDialog> {
  final _message = TextEditingController();
  final _scrollController = ScrollController();
  late final Future<String> _chatIdFuture;
  String? _lastReadSignature;
  bool _sending = false;
  bool _clearingHistory = false;

  @override
  void initState() {
    super.initState();
    _chatIdFuture = widget.service
        .openChat(
      currentUser: widget.currentUser,
      currentDisplayName: widget.currentDisplayName,
      peer: widget.peer,
    )
        .then((chatId) {
      unawaited(
        widget.service.markChatRead(
          chatId: chatId,
          uid: widget.currentUser.uid,
        ),
      );
      return chatId;
    });
  }

  @override
  void dispose() {
    _message.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      contentPadding: EdgeInsets.zero,
      insetPadding: const EdgeInsets.all(20),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: _chatFrameColor, width: 1.4),
      ),
      content: FutureBuilder<String>(
        future: _chatIdFuture,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return const SizedBox(
              width: 440,
              child: _DialogInfo(
                icon: Icons.cloud_off_rounded,
                message:
                    'Der Chat konnte nicht geoeffnet werden. Bitte pruefe Firebase.',
              ),
            );
          }

          final chatId = snapshot.data;
          if (chatId == null) {
            return const SizedBox(
              width: 440,
              height: 260,
              child: Center(child: CircularProgressIndicator()),
            );
          }

          return SizedBox(
            width: 460,
            height: 500,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _ChatDialogHeader(peer: widget.peer),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(24, 14, 24, 14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(child: _buildMessages(chatId)),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _message,
                                enabled: !_sending,
                                textInputAction: TextInputAction.send,
                                decoration: const InputDecoration(
                                  labelText: 'Nachricht',
                                ),
                                onSubmitted: (_) => _send(chatId),
                              ),
                            ),
                            const SizedBox(width: 8),
                            IconButton.filled(
                              tooltip: 'Senden',
                              onPressed: _sending ? null : () => _send(chatId),
                              icon: _sending
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Icon(Icons.send_rounded),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            TextButton.icon(
                              onPressed: _clearingHistory
                                  ? null
                                  : () => _confirmClearHistory(chatId),
                              icon: _clearingHistory
                                  ? const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Icon(Icons.delete_sweep_rounded),
                              label: const Text('Chatverlauf loeschen'),
                            ),
                            const Spacer(),
                            TextButton(
                              onPressed: () => Navigator.of(context).pop(),
                              child: const Text('Schliessen'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildMessages(String chatId) {
    return StreamBuilder<List<ChatMessage>>(
      stream: widget.service.watchMessages(chatId),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return const _DialogInfo(
            icon: Icons.error_outline_rounded,
            message: 'Nachrichten konnten nicht geladen werden.',
          );
        }

        final messages = snapshot.data ?? const <ChatMessage>[];
        final loading = snapshot.connectionState == ConnectionState.waiting &&
            !snapshot.hasData;

        if (loading) {
          return const Center(child: CircularProgressIndicator());
        }

        if (messages.isEmpty) {
          return const _DialogInfo(
            icon: Icons.chat_bubble_outline_rounded,
            message: 'Noch keine Nachrichten.',
          );
        }

        _markVisibleMessagesRead(chatId, messages);

        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!_scrollController.hasClients) {
            return;
          }
          _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
        });

        return ListView.separated(
          controller: _scrollController,
          itemCount: messages.length,
          separatorBuilder: (context, index) => const SizedBox(height: 8),
          itemBuilder: (context, index) {
            final message = messages[index];
            return _ChatBubble(
              message: message,
              own: message.senderId == widget.currentUser.uid,
              senderName: message.senderId == widget.currentUser.uid
                  ? 'Du'
                  : widget.peer.displayName,
              avatarName: message.senderId == widget.currentUser.uid
                  ? widget.currentDisplayName
                  : widget.peer.displayName,
              avatarSource: message.senderId == widget.currentUser.uid
                  ? widget.currentPhotoSource
                  : widget.peer.photoSource,
              avatarColorKey: message.senderId == widget.currentUser.uid
                  ? widget.currentUser.uid
                  : widget.peer.uid,
            );
          },
        );
      },
    );
  }

  Future<void> _send(String chatId) async {
    final text = _message.text.trim();
    if (text.isEmpty || _sending) {
      return;
    }

    setState(() => _sending = true);
    try {
      await widget.service.sendMessage(
        chatId: chatId,
        currentUser: widget.currentUser,
        peer: widget.peer,
        text: text,
      );
      _message.clear();
    } on Object {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Nachricht konnte nicht gesendet werden.'),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _sending = false);
      }
    }
  }

  Future<void> _confirmClearHistory(String chatId) async {
    final clear = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Chatverlauf loeschen?'),
        content: const Text(
          'Alle Nachrichten in diesem Chat werden entfernt. Das betrifft beide Chatteilnehmer.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Abbrechen'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.of(context).pop(true),
            icon: const Icon(Icons.delete_sweep_rounded),
            label: const Text('Loeschen'),
          ),
        ],
      ),
    );

    if (clear != true || _clearingHistory) {
      return;
    }

    setState(() => _clearingHistory = true);
    try {
      await widget.service.clearChatHistory(
        chatId: chatId,
        currentUid: widget.currentUser.uid,
      );
      _lastReadSignature = null;
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Chatverlauf geloescht.')),
      );
    } on Object {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Chatverlauf konnte nicht geloescht werden.'),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _clearingHistory = false);
      }
    }
  }

  void _markVisibleMessagesRead(String chatId, List<ChatMessage> messages) {
    final newestMessage = messages.last;
    final signature = '${newestMessage.id}:${newestMessage.createdAt}';
    if (_lastReadSignature == signature) {
      return;
    }
    _lastReadSignature = signature;

    unawaited(
      widget.service.markChatRead(
        chatId: chatId,
        uid: widget.currentUser.uid,
      ),
    );
  }
}

class _ChatDialogHeader extends StatelessWidget {
  final MemberProfile peer;

  const _ChatDialogHeader({required this.peer});

  @override
  Widget build(BuildContext context) {
    final photoSource = _safeMemberPhotoSource(peer.photoSource);
    final email = peer.email?.trim();

    return ColoredBox(
      color: _chatFrameColor,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
        child: Row(
          children: [
            CircleAvatar(
              radius: 28,
              backgroundColor: _avatarColorFor(peer.uid),
              foregroundImage: maybeMediaImageProvider(photoSource),
              child: Text(
                _initialsFor(peer.displayName),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 17,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Chat mit ${peer.displayName}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    email != null && email.isNotEmpty
                        ? email
                        : 'Chatteilnehmer',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xFFBFDBFE),
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ChatMessageAvatar extends StatelessWidget {
  final String? source;
  final String displayName;
  final String colorKey;

  const _ChatMessageAvatar({
    required this.source,
    required this.displayName,
    required this.colorKey,
  });

  @override
  Widget build(BuildContext context) {
    final photoSource = _safeMemberPhotoSource(source);
    return CircleAvatar(
      radius: 16,
      backgroundColor: _avatarColorFor(colorKey),
      foregroundImage: maybeMediaImageProvider(photoSource),
      child: Text(
        _initialsFor(displayName),
        style: const TextStyle(
          color: Colors.white,
          fontSize: 10,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _ChatBubble extends StatelessWidget {
  final ChatMessage message;
  final bool own;
  final String senderName;
  final String avatarName;
  final String? avatarSource;
  final String avatarColorKey;

  const _ChatBubble({
    required this.message,
    required this.own,
    required this.senderName,
    required this.avatarName,
    required this.avatarSource,
    required this.avatarColorKey,
  });

  @override
  Widget build(BuildContext context) {
    final avatar = _ChatMessageAvatar(
      source: avatarSource,
      displayName: avatarName,
      colorKey: avatarColorKey,
    );

    return Row(
      mainAxisAlignment: own ? MainAxisAlignment.end : MainAxisAlignment.start,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        if (!own) ...[
          avatar,
          const SizedBox(width: 8),
        ],
        Flexible(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 290),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: own ? const Color(0xFF0A84FF) : const Color(0xFFE8EDF3),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                child: Column(
                  crossAxisAlignment:
                      own ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      senderName,
                      style: TextStyle(
                        color: own
                            ? Colors.white.withValues(alpha: 0.82)
                            : const Color(0xFF0F172A),
                        fontSize: 11,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      message.text,
                      style: TextStyle(
                        color: own ? Colors.white : const Color(0xFF334155),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (message.createdAt != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        _timeLabel(message.createdAt!),
                        style: TextStyle(
                          color: own
                              ? Colors.white.withValues(alpha: 0.78)
                              : const Color(0xFF64748B),
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
        if (own) ...[
          const SizedBox(width: 8),
          avatar,
        ],
      ],
    );
  }
}

class _InfoCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  final bool loading;

  const _InfoCard({
    required this.icon,
    required this.title,
    required this.message,
    this.loading = false,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          children: [
            if (loading)
              const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else
              Icon(icon, color: const Color(0xFF0A84FF), size: 28),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: Color(0xFF06172E),
                      fontSize: 15,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    message,
                    style: const TextStyle(
                      color: Color(0xFF64748B),
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      height: 1.35,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DialogInfo extends StatelessWidget {
  final IconData icon;
  final String message;

  const _DialogInfo({
    required this.icon,
    required this.message,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: const Color(0xFF94A3B8), size: 34),
          const SizedBox(height: 10),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Color(0xFF64748B),
              fontSize: 13,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _MutedText extends StatelessWidget {
  final String text;

  const _MutedText(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        color: Color(0xFF94A3B8),
        fontSize: 10,
        fontStyle: FontStyle.italic,
        fontWeight: FontWeight.w600,
      ),
    );
  }
}

String _displayNameFor(User user, FleetState fleet) {
  final authName = user.displayName?.trim();
  if (authName != null && authName.isNotEmpty) {
    return authName;
  }
  final profileName = fleet.pilotProfile.name.trim();
  if (profileName.isNotEmpty) {
    return profileName;
  }
  return user.email ?? 'Mitglied';
}

String? _safeMemberPhotoSource(String? source) {
  final clean = source?.trim();
  if (clean == null || clean.isEmpty) {
    return null;
  }
  if (clean.startsWith('data:image/') || isNetworkMediaSource(clean)) {
    return clean;
  }
  return null;
}

String? _chatAvatarSourceFor(User user, PilotProfile profile) {
  final thumbnail = profile.memberPhotoSource?.trim();
  if (thumbnail != null && thumbnail.isNotEmpty) {
    return thumbnail;
  }
  final profilePhoto = profile.photoSource?.trim();
  if (profilePhoto != null && profilePhoto.isNotEmpty) {
    return profilePhoto;
  }
  final authPhoto = user.photoURL?.trim();
  if (authPhoto != null && authPhoto.isNotEmpty) {
    return authPhoto;
  }
  return null;
}

String? _memberPreviewSourceFor(PilotProfile profile) {
  final thumbnail = profile.memberPhotoSource?.trim();
  if (thumbnail != null && thumbnail.isNotEmpty) {
    return thumbnail;
  }
  return null;
}

bool _hasProfilePhoto(User user, PilotProfile profile) {
  final thumbnail = profile.memberPhotoSource?.trim();
  final embeddedPhoto = profile.photoDataUri?.trim();
  final profilePhoto = profile.photoDownloadUrl?.trim();
  final authPhoto = user.photoURL?.trim();
  return (thumbnail != null && thumbnail.isNotEmpty) ||
      (embeddedPhoto != null && embeddedPhoto.isNotEmpty) ||
      (profilePhoto != null && profilePhoto.isNotEmpty) ||
      (authPhoto != null && authPhoto.isNotEmpty);
}

String _clubLabel(String club) {
  final clean = club.trim();
  return clean.isEmpty ? '-' : clean;
}

String _lastSeenLabel(DateTime? lastSeen) {
  if (lastSeen == null) {
    return 'noch nie';
  }

  final now = DateTime.now();
  final localSeen = lastSeen.toLocal();
  final difference = now.difference(localSeen);

  if (difference.inMinutes < 2) {
    return 'gerade eben';
  }
  if (difference.inMinutes < 60) {
    return 'vor ${difference.inMinutes} Min.';
  }
  if (difference.inHours < 24) {
    return 'vor ${difference.inHours} Std.';
  }
  if (difference.inDays == 1) {
    return 'gestern ${_twoDigits(localSeen.hour)}:${_twoDigits(localSeen.minute)}';
  }
  return '${_twoDigits(localSeen.day)}.${_twoDigits(localSeen.month)}.${localSeen.year}';
}

String _timeLabel(DateTime date) {
  final local = date.toLocal();
  return '${_twoDigits(local.hour)}:${_twoDigits(local.minute)}';
}

String _dateTimeLabel(DateTime date) {
  final local = date.toLocal();
  final now = DateTime.now();
  final sameDay = local.year == now.year &&
      local.month == now.month &&
      local.day == now.day;
  if (sameDay) {
    return _timeLabel(local);
  }
  return '${_twoDigits(local.day)}.${_twoDigits(local.month)}. ${_timeLabel(local)}';
}

String _twoDigits(int value) {
  return value.toString().padLeft(2, '0');
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

Color _avatarColorFor(String value) {
  const colors = [
    Color(0xFF0A84FF),
    Color(0xFF16A34A),
    Color(0xFF7C3AED),
    Color(0xFFEA580C),
    Color(0xFF0891B2),
    Color(0xFFDC2626),
  ];

  final index = value.codeUnits.fold<int>(0, (sum, code) => sum + code);
  return colors[index % colors.length];
}
