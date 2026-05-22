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
      members.removeWhere((member) => member.isLegacyProfile);
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
      'presenceStatus': shareLocation ? presenceStatus : 'offline',
      'lastSeen': FieldValue.serverTimestamp(),
      'lastSeenClient': DateTime.now().toUtc().toIso8601String(),
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

  String chatIdFor(String firstUid, String secondUid) {
    final ids = [firstUid, secondUid]..sort();
    return ids.join('_');
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

  Stream<List<ChatMessage>> watchMessages(String chatId) {
    return _chats
        .doc(chatId)
        .collection('messages')
        .orderBy('createdAtClient')
        .limitToLast(80)
        .snapshots()
        .map(
          (snapshot) => [
            for (final doc in snapshot.docs) ChatMessage.fromSnapshot(doc),
          ],
        );
  }

  Future<void> sendMessage({
    required String chatId,
    required User currentUser,
    required MemberProfile peer,
    required String text,
  }) async {
    final cleanText = text.trim();
    if (cleanText.isEmpty) {
      return;
    }

    final chatRef = _chats.doc(chatId);
    final messageRef = chatRef.collection('messages').doc();
    final now = DateTime.now().toUtc().toIso8601String();
    final batch = _firestore.batch();

    batch.set(messageRef, {
      'senderId': currentUser.uid,
      'recipientId': peer.uid,
      'text': cleanText,
      'createdAt': FieldValue.serverTimestamp(),
      'createdAtClient': now,
    });
    batch.update(
      chatRef,
      {
        'lastMessage': cleanText,
        'lastSenderId': currentUser.uid,
        'lastRecipientId': peer.uid,
        'lastMessageAt': FieldValue.serverTimestamp(),
        'lastMessageAtClient': now,
        'unreadCounts.${currentUser.uid}': 0,
        'unreadCounts.${peer.uid}': FieldValue.increment(1),
        'updatedAt': FieldValue.serverTimestamp(),
        'updatedAtClient': now,
      },
    );

    await batch.commit();
  }
}

class ChatSummary {
  final String id;
  final List<String> participantIds;
  final String lastMessage;
  final String lastSenderId;
  final String lastRecipientId;
  final DateTime? lastMessageAt;
  final DateTime? updatedAt;
  final Map<String, DateTime> readBy;
  final Map<String, int> unreadCounts;

  const ChatSummary({
    required this.id,
    required this.participantIds,
    required this.lastMessage,
    required this.lastSenderId,
    required this.lastRecipientId,
    required this.lastMessageAt,
    required this.updatedAt,
    required this.readBy,
    required this.unreadCounts,
  });

  factory ChatSummary.fromSnapshot(
    DocumentSnapshot<Map<String, dynamic>> snapshot,
  ) {
    final data = snapshot.data() ?? const <String, dynamic>{};
    final readByClient = data['readByClient'] as Map<String, dynamic>? ?? {};
    final unreadCounts = data['unreadCounts'] as Map<String, dynamic>? ?? {};

    return ChatSummary(
      id: snapshot.id,
      participantIds: [
        for (final item in data['participantIds'] as List<dynamic>? ?? [])
          if (item is String) item,
      ],
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
    final readDate = readBy[currentUid];
    return readDate == null || lastDate.isAfter(readDate);
  }

  int unreadCountFor(String currentUid) {
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
      presenceStatus: data['presenceStatus'] as String? ?? 'offline',
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

DateTime? _dateFrom(Object? value) {
  if (value is Timestamp) {
    return value.toDate();
  }
  if (value is String) {
    return DateTime.tryParse(value);
  }
  return null;
}
