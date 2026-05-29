import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final memberChatServiceProvider = Provider<MemberChatService?>((ref) {
  if (Firebase.apps.isEmpty) {
    return null;
  }
  return MemberChatService(FirebaseFirestore.instance);
});

class MemberChatService {
  static const memberSchemaVersion = 2;
  static const flightRoomChatId = 'flight-radio-room';

  final FirebaseFirestore _firestore;

  const MemberChatService(this._firestore);

  CollectionReference<Map<String, dynamic>> get _members {
    return _firestore.collection('members');
  }

  CollectionReference<Map<String, dynamic>> get _chats {
    return _firestore.collection('chats');
  }

  Stream<List<MemberProfile>> watchMembers(String currentUid) {
    return _members.snapshots().map((snapshot) {
      final members = [
        for (final doc in snapshot.docs)
          if (doc.id != currentUid) MemberProfile.fromSnapshot(doc),
      ];
      members.removeWhere(
          (member) => member.isLegacyProfile || !_isVisibleFriend(member));
      members.sort((a, b) {
        if (a.visibleInMemberList != b.visibleInMemberList) {
          return a.visibleInMemberList ? -1 : 1;
        }
        final byName = a.displayName.compareTo(b.displayName);
        if (byName != 0) {
          return byName;
        }
        return a.uid.compareTo(b.uid);
      });
      return members;
    });
  }

  Stream<List<ChatSummary>> watchChatSummaries(String currentUid) {
    return _chats
        .where('participantIds', arrayContains: currentUid)
        .snapshots()
        .map((snapshot) {
      final chats = [
        for (final doc in snapshot.docs) ChatSummary.fromSnapshot(doc),
      ];
      chats.sort((a, b) {
        final aDate = a.lastMessageAt ?? a.updatedAt ?? DateTime(0);
        final bDate = b.lastMessageAt ?? b.updatedAt ?? DateTime(0);
        return bDate.compareTo(aDate);
      });
      return chats;
    });
  }

  Future<void> saveCurrentMemberProfile({
    required User user,
    required String displayName,
    required String club,
    required bool reachableByChat,
    required bool shareLocation,
    required String presenceStatus,
    String? photoSource,
    bool clearPhotoSource = false,
  }) {
    final cleanName = displayName.trim();
    final fallbackName = user.displayName?.trim();
    final publicName = cleanName.isNotEmpty
        ? cleanName
        : fallbackName != null && fallbackName.isNotEmpty
            ? fallbackName
            : user.email ?? 'Mitglied';

    final publishesPresence = reachableByChat && shareLocation;
    final data = {
      'uid': user.uid,
      'active': true,
      'memberSchemaVersion': memberSchemaVersion,
      'displayName': publicName,
      'displayNameLower': publicName.toLowerCase(),
      'email': user.email,
      'club': club.trim(),
      'reachableByChat': reachableByChat,
      'shareLocation': shareLocation,
      'presenceStatus': publishesPresence ? presenceStatus : 'offline',
      'lastSeen': publishesPresence ? FieldValue.serverTimestamp() : null,
      'lastSeenClient':
          publishesPresence ? DateTime.now().toUtc().toIso8601String() : null,
    };

    final cleanPhoto = photoSource?.trim();
    if (cleanPhoto != null && cleanPhoto.isNotEmpty) {
      data['photoSource'] = cleanPhoto;
    } else if (clearPhotoSource) {
      data['photoSource'] = null;
    }

    return _members.doc(user.uid).set(
          data,
          SetOptions(merge: true),
        );
  }

  Future<void> touchCurrentMemberPresence({
    required User user,
  }) {
    return _members.doc(user.uid).set(
      {
        'uid': user.uid,
        'lastSeen': FieldValue.serverTimestamp(),
        'lastSeenClient': DateTime.now().toUtc().toIso8601String(),
      },
      SetOptions(merge: true),
    );
  }

  String chatIdFor(String firstUid, String secondUid) {
    final ids = [firstUid, secondUid]..sort();
    return ids.join('_');
  }

  String groupChatIdFor(Iterable<String> participantIds) {
    final ids = participantIds.toSet().toList()..sort();
    return 'group_${ids.join('_')}';
  }

  Future<String> openChat({
    required User currentUser,
    required String currentDisplayName,
    required MemberProfile peer,
  }) async {
    final chatId = chatIdFor(currentUser.uid, peer.uid);
    final chatRef = _chats.doc(chatId);
    final now = DateTime.now().toUtc().toIso8601String();

    await chatRef.set(
      {
        'type': 'direct',
        'title': '',
        'participantIds': [currentUser.uid, peer.uid]..sort(),
        'participantNames': {
          currentUser.uid: currentDisplayName.trim().isNotEmpty
              ? currentDisplayName.trim()
              : currentUser.email ?? 'Ich',
          peer.uid: peer.displayName,
        },
        'participantEmails': {
          currentUser.uid: currentUser.email,
          peer.uid: peer.email,
        },
        'participantPhotos': {
          if (peer.photoSource != null && peer.photoSource!.isNotEmpty)
            peer.uid: peer.photoSource,
        },
        'createdAtClient': now,
        'updatedAt': FieldValue.serverTimestamp(),
        'updatedAtClient': now,
      },
      SetOptions(merge: true),
    );

    return chatId;
  }

  Future<String> openFlightRoom({
    required User currentUser,
    required String currentDisplayName,
    required String? currentPhotoSource,
    required Iterable<MemberProfile> reachableMembers,
  }) {
    return _openRoom(
      chatId: flightRoomChatId,
      type: 'flightRoom',
      title: 'Gemeinschaftsraum',
      currentUser: currentUser,
      currentDisplayName: currentDisplayName,
      currentPhotoSource: currentPhotoSource,
      peers: reachableMembers.where((member) => member.reachableByChat),
    );
  }

  Future<String> openGroupChat({
    required User currentUser,
    required String currentDisplayName,
    required String? currentPhotoSource,
    required String title,
    required Iterable<MemberProfile> peers,
  }) {
    final peerList = peers.toList();
    final participantIds = [
      currentUser.uid,
      for (final peer in peerList) peer.uid,
    ];
    return _openRoom(
      chatId: groupChatIdFor(participantIds),
      type: 'group',
      title: title.trim().isNotEmpty
          ? title.trim()
          : _defaultGroupTitle(peerList.map((peer) => peer.displayName)),
      currentUser: currentUser,
      currentDisplayName: currentDisplayName,
      currentPhotoSource: currentPhotoSource,
      peers: peerList,
    );
  }

  Future<String> _openRoom({
    required String chatId,
    required String type,
    required String title,
    required User currentUser,
    required String currentDisplayName,
    required String? currentPhotoSource,
    required Iterable<MemberProfile> peers,
  }) async {
    final chatRef = _chats.doc(chatId);
    final now = DateTime.now().toUtc().toIso8601String();
    final peerList = peers.toList();
    final participantIds = {
      currentUser.uid,
      for (final peer in peerList) peer.uid,
    }.toList()
      ..sort();
    final currentName = currentDisplayName.trim().isNotEmpty
        ? currentDisplayName.trim()
        : currentUser.email ?? 'Ich';

    await chatRef.set(
      {
        'type': type,
        'title': title,
        'participantIds': participantIds,
        'participantNames': {
          currentUser.uid: currentName,
          for (final peer in peerList) peer.uid: peer.displayName,
        },
        'participantEmails': {
          currentUser.uid: currentUser.email,
          for (final peer in peerList) peer.uid: peer.email,
        },
        'participantPhotos': {
          if (currentPhotoSource != null && currentPhotoSource.isNotEmpty)
            currentUser.uid: currentPhotoSource,
          for (final peer in peerList)
            if (peer.photoSource != null && peer.photoSource!.isNotEmpty)
              peer.uid: peer.photoSource,
        },
        'createdAtClient': now,
        'updatedAt': FieldValue.serverTimestamp(),
        'updatedAtClient': now,
      },
      SetOptions(merge: true),
    );

    return chatId;
  }

  Future<void> markChatRead({
    required String chatId,
    required String uid,
  }) {
    final now = DateTime.now().toUtc().toIso8601String();
    return _chats.doc(chatId).update({
      'readBy.$uid': FieldValue.serverTimestamp(),
      'readByClient.$uid': now,
      'unreadCounts.$uid': 0,
    });
  }

  Stream<List<ChatMessage>> watchMessages({
    required String chatId,
    required String currentUid,
  }) {
    final chatRef = _chats.doc(chatId);
    final controller = StreamController<List<ChatMessage>>();
    DocumentSnapshot<Map<String, dynamic>>? latestChat;
    QuerySnapshot<Map<String, dynamic>>? latestMessages;
    StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? chatSub;
    StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? messageSub;

    void emitMessages() {
      final messagesSnapshot = latestMessages;
      if (messagesSnapshot == null || controller.isClosed) {
        return;
      }
      final chatData = latestChat?.data() ?? const <String, dynamic>{};
      final clearedAt = _dateFrom(
            (chatData['clearedAt'] as Map<String, dynamic>?)?[currentUid],
          ) ??
          _dateFrom(
            (chatData['clearedAtClient'] as Map<String, dynamic>?)?[currentUid],
          );
      final messages = [
        for (final doc in messagesSnapshot.docs) ChatMessage.fromSnapshot(doc),
      ].where((message) {
        if (clearedAt == null) {
          return true;
        }
        final createdAt = message.createdAt;
        return createdAt == null || createdAt.isAfter(clearedAt);
      }).toList();
      controller.add(messages);
    }

    chatSub = chatRef.snapshots().listen(
      (snapshot) {
        latestChat = snapshot;
        emitMessages();
      },
      onError: controller.addError,
    );
    messageSub = chatRef
        .collection('messages')
        .orderBy('createdAtClient')
        .limitToLast(80)
        .snapshots()
        .listen(
      (snapshot) {
        latestMessages = snapshot;
        emitMessages();
      },
      onError: controller.addError,
    );

    controller.onCancel = () async {
      await chatSub?.cancel();
      await messageSub?.cancel();
    };

    return controller.stream;
  }

  Future<void> sendMessage({
    required String chatId,
    required User currentUser,
    required String text,
  }) async {
    final cleanText = text.trim();
    if (cleanText.isEmpty) {
      return;
    }

    final chatRef = _chats.doc(chatId);
    final chatSnapshot = await chatRef.get();
    final participantIds = [
      for (final item
          in chatSnapshot.data()?['participantIds'] as List<dynamic>? ?? [])
        if (item is String) item,
    ];
    final recipientIds = [
      for (final uid in participantIds)
        if (uid != currentUser.uid) uid,
    ];
    if (recipientIds.isEmpty) {
      throw StateError('A chat message needs at least one recipient.');
    }

    final messageRef = chatRef.collection('messages').doc();
    final now = DateTime.now().toUtc().toIso8601String();
    final batch = _firestore.batch();

    batch.set(messageRef, {
      'senderId': currentUser.uid,
      'recipientId': recipientIds.first,
      'recipientIds': recipientIds,
      'text': cleanText,
      'createdAt': FieldValue.serverTimestamp(),
      'createdAtClient': now,
    });
    batch.update(
      chatRef,
      {
        'lastMessage': cleanText,
        'lastSenderId': currentUser.uid,
        'lastRecipientId': recipientIds.first,
        'lastRecipientIds': recipientIds,
        'lastMessageAt': FieldValue.serverTimestamp(),
        'lastMessageAtClient': now,
        'unreadCounts.${currentUser.uid}': 0,
        for (final uid in recipientIds)
          'unreadCounts.$uid': FieldValue.increment(1),
        'updatedAt': FieldValue.serverTimestamp(),
        'updatedAtClient': now,
      },
    );

    await batch.commit();
  }

  Future<void> clearChatHistory({
    required String chatId,
    required String currentUid,
  }) async {
    final chatRef = _chats.doc(chatId);
    final chatSnapshot = await chatRef.get();
    final data = chatSnapshot.data();
    final participantIds = [
      for (final item in data?['participantIds'] as List<dynamic>? ?? [])
        if (item is String) item,
    ];
    if (!participantIds.contains(currentUid)) {
      throw StateError('Only chat participants can clear a chat history.');
    }

    final now = DateTime.now().toUtc().toIso8601String();
    await chatRef.update({
      'clearedAt.$currentUid': FieldValue.serverTimestamp(),
      'clearedAtClient.$currentUid': now,
      'readBy.$currentUid': FieldValue.serverTimestamp(),
      'readByClient.$currentUid': now,
      'unreadCounts.$currentUid': 0,
    });
  }
}

String _defaultGroupTitle(Iterable<String> names) {
  final cleanNames = [
    for (final name in names)
      if (name.trim().isNotEmpty) name.trim(),
  ];
  if (cleanNames.isEmpty) {
    return 'Private Runde';
  }
  return cleanNames.join(', ');
}

class ChatSummary {
  final String id;
  final String type;
  final String title;
  final List<String> participantIds;
  final Map<String, String> participantNames;
  final Map<String, String> participantEmails;
  final Map<String, String> participantPhotos;
  final String lastMessage;
  final String lastSenderId;
  final String lastRecipientId;
  final DateTime? lastMessageAt;
  final DateTime? updatedAt;
  final Map<String, DateTime> readBy;
  final Map<String, DateTime> clearedAt;
  final Map<String, int> unreadCounts;

  const ChatSummary({
    required this.id,
    required this.type,
    required this.title,
    required this.participantIds,
    required this.participantNames,
    required this.participantEmails,
    required this.participantPhotos,
    required this.lastMessage,
    required this.lastSenderId,
    required this.lastRecipientId,
    required this.lastMessageAt,
    required this.updatedAt,
    required this.readBy,
    required this.clearedAt,
    required this.unreadCounts,
  });

  factory ChatSummary.fromSnapshot(
    DocumentSnapshot<Map<String, dynamic>> snapshot,
  ) {
    final data = snapshot.data() ?? const <String, dynamic>{};
    final readByClient = data['readByClient'] as Map<String, dynamic>? ?? {};
    final clearedAtClient =
        data['clearedAtClient'] as Map<String, dynamic>? ?? {};
    final unreadCounts = data['unreadCounts'] as Map<String, dynamic>? ?? {};

    return ChatSummary(
      id: snapshot.id,
      type: data['type'] as String? ?? '',
      title: (data['title'] as String? ?? '').trim(),
      participantIds: [
        for (final item in data['participantIds'] as List<dynamic>? ?? [])
          if (item is String) item,
      ],
      participantNames: _stringMapFrom(data['participantNames']),
      participantEmails: _stringMapFrom(data['participantEmails']),
      participantPhotos: _stringMapFrom(data['participantPhotos']),
      lastMessage: data['lastMessage'] as String? ?? '',
      lastSenderId: data['lastSenderId'] as String? ?? '',
      lastRecipientId: data['lastRecipientId'] as String? ?? '',
      lastMessageAt: _dateFrom(data['lastMessageAt']) ??
          _dateFrom(data['lastMessageAtClient']),
      updatedAt:
          _dateFrom(data['updatedAt']) ?? _dateFrom(data['updatedAtClient']),
      readBy: {
        for (final entry in readByClient.entries)
          if (_dateFrom(entry.value) != null)
            entry.key: _dateFrom(entry.value)!,
      },
      clearedAt: {
        for (final entry in clearedAtClient.entries)
          if (_dateFrom(entry.value) != null)
            entry.key: _dateFrom(entry.value)!,
      },
      unreadCounts: {
        for (final entry in unreadCounts.entries)
          if (entry.value is num) entry.key: (entry.value as num).toInt(),
      },
    );
  }

  String peerUidFor(String currentUid) {
    return participantIds.firstWhere(
      (uid) => uid != currentUid,
      orElse: () => '',
    );
  }

  bool get isFlightRoom {
    return type == 'flightRoom' || id == MemberChatService.flightRoomChatId;
  }

  bool get isDirect {
    return !isFlightRoom &&
        (type == 'direct' || (type.isEmpty && participantIds.length == 2));
  }

  bool get isPrivateGroup {
    return !isFlightRoom && !isDirect;
  }

  String titleFor(String currentUid) {
    if (isFlightRoom) {
      return 'Gemeinschaftsraum';
    }
    if (isDirect) {
      final peerUid = peerUidFor(currentUid);
      final peerName = participantNames[peerUid]?.trim();
      if (peerName != null && peerName.isNotEmpty) {
        return peerName;
      }
    }
    return title.isNotEmpty ? title : 'Private Runde';
  }

  String lastMessageFor(String currentUid) {
    final lastDate = lastMessageAt ?? updatedAt;
    final clearDate = clearedAt[currentUid];
    if (lastDate != null && clearDate != null && !lastDate.isAfter(clearDate)) {
      return '';
    }
    return lastMessage;
  }

  bool isUnreadFor(String currentUid) {
    if (unreadCountFor(currentUid) > 0) {
      return true;
    }
    if (lastMessage.isEmpty ||
        lastSenderId.isEmpty ||
        lastSenderId == currentUid) {
      return false;
    }
    final lastDate = lastMessageAt ?? updatedAt;
    if (lastDate == null) {
      return true;
    }
    final clearDate = clearedAt[currentUid];
    if (clearDate != null && !lastDate.isAfter(clearDate)) {
      return false;
    }
    final readDate = readBy[currentUid];
    return readDate == null || lastDate.isAfter(readDate);
  }

  int unreadCountFor(String currentUid) {
    final lastDate = lastMessageAt ?? updatedAt;
    final clearDate = clearedAt[currentUid];
    if (lastDate != null && clearDate != null && !lastDate.isAfter(clearDate)) {
      return 0;
    }
    return unreadCounts[currentUid] ?? 0;
  }
}

class MemberProfile {
  final String uid;
  final bool active;
  final int memberSchemaVersion;
  final String displayName;
  final String? email;
  final String club;
  final bool reachableByChat;
  final bool shareLocation;
  final String presenceStatus;
  final String? photoSource;
  final DateTime? lastSeen;

  const MemberProfile({
    required this.uid,
    required this.active,
    required this.memberSchemaVersion,
    required this.displayName,
    required this.email,
    required this.club,
    required this.reachableByChat,
    required this.shareLocation,
    required this.presenceStatus,
    required this.photoSource,
    required this.lastSeen,
  });

  factory MemberProfile.fromSnapshot(
    DocumentSnapshot<Map<String, dynamic>> snapshot,
  ) {
    final data = snapshot.data() ?? const <String, dynamic>{};
    final displayName = (data['displayName'] as String? ?? '').trim();
    final publicName = (data['publicName'] as String? ?? '').trim();
    final email = (data['email'] as String?)?.trim();

    return MemberProfile(
      uid: snapshot.id,
      active: data['active'] as bool? ?? false,
      memberSchemaVersion: data['memberSchemaVersion'] as int? ?? 0,
      displayName: displayName.isNotEmpty
          ? displayName
          : publicName.isNotEmpty
              ? publicName
              : email != null && email.isNotEmpty
                  ? email
                  : 'Mitglied',
      email: email,
      club: (data['club'] as String? ?? '').trim(),
      reachableByChat: data['reachableByChat'] as bool? ?? false,
      shareLocation: data['shareLocation'] as bool? ?? false,
      presenceStatus: _cleanPresenceStatus(data['presenceStatus']),
      photoSource: (data['photoSource'] as String?)?.trim(),
      lastSeen:
          _dateFrom(data['lastSeen']) ?? _dateFrom(data['lastSeenClient']),
    );
  }

  bool get visibleInMemberList {
    return active &&
        memberSchemaVersion >= MemberChatService.memberSchemaVersion;
  }

  bool get isLegacyProfile {
    return !active && memberSchemaVersion == 0;
  }
}

bool _isVisibleFriend(MemberProfile member) {
  return member.visibleInMemberList;
}

String _cleanPresenceStatus(Object? value) {
  final text = (value as String? ?? '').trim().toLowerCase();
  return switch (text) {
    'atfield' => 'atField',
    'flying' => 'flying',
    _ => 'offline',
  };
}

class ChatMessage {
  final String id;
  final String senderId;
  final String recipientId;
  final String text;
  final DateTime? createdAt;

  const ChatMessage({
    required this.id,
    required this.senderId,
    required this.recipientId,
    required this.text,
    required this.createdAt,
  });

  factory ChatMessage.fromSnapshot(
    DocumentSnapshot<Map<String, dynamic>> snapshot,
  ) {
    final data = snapshot.data() ?? const <String, dynamic>{};
    return ChatMessage(
      id: snapshot.id,
      senderId: data['senderId'] as String? ?? '',
      recipientId: data['recipientId'] as String? ?? '',
      text: data['text'] as String? ?? '',
      createdAt:
          _dateFrom(data['createdAt']) ?? _dateFrom(data['createdAtClient']),
    );
  }
}

Map<String, String> _stringMapFrom(Object? value) {
  final data = value as Map<String, dynamic>? ?? const <String, dynamic>{};
  return {
    for (final entry in data.entries)
      if (entry.value is String && (entry.value as String).trim().isNotEmpty)
        entry.key: (entry.value as String).trim(),
  };
}

DateTime? _dateFrom(Object? value) {
  if (value is Timestamp) {
    return value.toDate();
  }
  if (value is String) {
    return DateTime.tryParse(value);
  }
  return null;
}
