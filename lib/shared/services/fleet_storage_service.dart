import 'dart:convert';
import 'dart:typed_data';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/aircraft_model.dart';
import '../models/fleet_state.dart';
import '../utils/image_thumbnail.dart';

final fleetStorageServiceProvider = Provider<FleetStorageService?>((ref) {
  if (Firebase.apps.isEmpty) {
    return null;
  }
  return FleetStorageService(FirebaseStorage.instance);
});

class FleetStorageService {
  final FirebaseStorage _storage;

  const FleetStorageService(this._storage);

  Future<FleetState> moveEmbeddedFilesToStorage({
    required User user,
    required FleetState state,
  }) async {
    final aircraft = <AircraftModel>[];
    for (final item in state.aircraft) {
      aircraft.add(await _moveAircraftPhotos(user.uid, item));
    }

    final pilotProfile = await _movePilotFiles(user.uid, state.pilotProfile);

    return state.copyWith(
      aircraft: aircraft,
      pilotProfile: pilotProfile,
    );
  }

  Future<AircraftModel> _moveAircraftPhotos(
    String uid,
    AircraftModel aircraft,
  ) async {
    final sources = aircraft.photos;
    final storagePaths = <String>[];
    final downloadUrls = <String>[];

    for (var index = 0; index < sources.length; index++) {
      final source = sources[index];
      if (_isDataUri(source)) {
        final uploaded = await _uploadDataUri(
          source,
          pathPrefix: 'users/$uid/aircraft/${aircraft.id}/photos',
          fileNameBase:
              'photo_${index + 1}_${DateTime.now().millisecondsSinceEpoch}',
        );
        storagePaths.add(uploaded.storagePath);
        downloadUrls.add(uploaded.downloadUrl);
      } else {
        final existingStoragePath = index < aircraft.photoStoragePaths.length
            ? aircraft.photoStoragePaths[index]
            : '';
        if (existingStoragePath.isNotEmpty) {
          storagePaths.add(existingStoragePath);
        }
        downloadUrls.add(source);
      }
    }

    if (downloadUrls.isEmpty &&
        aircraft.photoDownloadUrls.isEmpty &&
        aircraft.photoDataUris.isEmpty &&
        (aircraft.photoDataUri == null || aircraft.photoDataUri!.isEmpty)) {
      return aircraft;
    }

    return aircraft.copyWith(
      photoDataUri: null,
      photoDataUris: const [],
      photoStoragePaths: storagePaths,
      photoDownloadUrls: downloadUrls,
    );
  }

  Future<PilotProfile> _movePilotFiles(
    String uid,
    PilotProfile profile,
  ) async {
    var result = profile;

    final photoSource = result.photoSource;
    if (photoSource != null && photoSource.isNotEmpty) {
      if (_isDataUri(photoSource)) {
        final thumbnailDataUri = result.photoThumbnailDataUri ??
            createImageThumbnailDataUriFromDataUri(photoSource);
        final uploaded = await _uploadDataUri(
          photoSource,
          pathPrefix: 'users/$uid/profile',
          fileNameBase: 'pilot_photo',
        );
        result = result.copyWith(
          photoDataUri: null,
          photoThumbnailDataUri: thumbnailDataUri,
          photoStoragePath: uploaded.storagePath,
          photoDownloadUrl: uploaded.downloadUrl,
        );
      } else {
        result = result.copyWith(
          photoDataUri: null,
          photoDownloadUrl: photoSource,
        );
      }
    } else {
      result = result.copyWith(
        photoDataUri: null,
        photoThumbnailDataUri: null,
        photoStoragePath: null,
        photoDownloadUrl: null,
      );
    }

    final documentSource = result.insuranceDocumentSource;
    if (documentSource != null && documentSource.isNotEmpty) {
      if (_isDataUri(documentSource)) {
        final uploaded = await _uploadDataUri(
          documentSource,
          pathPrefix: 'users/$uid/profile/documents',
          fileNameBase: _safeFileName(
            result.insuranceDocumentName ?? 'insurance_document',
          ),
        );
        result = result.copyWith(
          insuranceDocumentDataUri: null,
          insuranceDocumentStoragePath: uploaded.storagePath,
          insuranceDocumentDownloadUrl: uploaded.downloadUrl,
        );
      } else {
        result = result.copyWith(
          insuranceDocumentDataUri: null,
          insuranceDocumentDownloadUrl: documentSource,
        );
      }
    } else {
      result = result.copyWith(
        insuranceDocumentName: null,
        insuranceDocumentDataUri: null,
        insuranceDocumentStoragePath: null,
        insuranceDocumentDownloadUrl: null,
      );
    }

    return result;
  }

  Future<_UploadedFile> _uploadDataUri(
    String dataUri, {
    required String pathPrefix,
    required String fileNameBase,
  }) async {
    final file = _decodeDataUri(dataUri);
    final extension = _extensionForMimeType(file.mimeType);
    final fileName = '${_safeFileName(fileNameBase)}.$extension';
    final path = '$pathPrefix/$fileName';
    final reference = _storage.ref(path);

    await reference.putData(
      file.bytes,
      SettableMetadata(
        contentType: file.mimeType,
        customMetadata: const {'source': 'modellflug_app'},
      ),
    );

    return _UploadedFile(
      storagePath: path,
      downloadUrl: await reference.getDownloadURL(),
    );
  }
}

bool _isDataUri(String value) => value.startsWith('data:');

_DecodedDataUri _decodeDataUri(String dataUri) {
  final match = RegExp(r'^data:([^;]+);base64,(.*)$').firstMatch(dataUri);
  if (match == null) {
    return _DecodedDataUri(
      mimeType: 'application/octet-stream',
      bytes: base64Decode(dataUri),
    );
  }

  return _DecodedDataUri(
    mimeType: match.group(1) ?? 'application/octet-stream',
    bytes: base64Decode(match.group(2) ?? ''),
  );
}

String _extensionForMimeType(String mimeType) {
  return switch (mimeType.toLowerCase()) {
    'image/jpeg' || 'image/jpg' => 'jpg',
    'image/png' => 'png',
    'image/webp' => 'webp',
    'image/gif' => 'gif',
    'application/pdf' => 'pdf',
    _ => 'bin',
  };
}

String _safeFileName(String value) {
  final cleaned = value
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'\.[a-z0-9]+$'), '')
      .replaceAll(RegExp(r'[^a-z0-9_-]+'), '_')
      .replaceAll(RegExp(r'_+'), '_')
      .replaceAll(RegExp(r'^_|_$'), '');
  return cleaned.isEmpty ? 'file' : cleaned;
}

class _DecodedDataUri {
  final String mimeType;
  final Uint8List bytes;

  const _DecodedDataUri({
    required this.mimeType,
    required this.bytes,
  });
}

class _UploadedFile {
  final String storagePath;
  final String downloadUrl;

  const _UploadedFile({
    required this.storagePath,
    required this.downloadUrl,
  });
}
