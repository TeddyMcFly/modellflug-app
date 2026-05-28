const lmfcWebcamImageUrl =
    'https://www.lmfc.de/fileadmin/Modellflug/cam/bilder/webcam.jpg';
const brouwersdamYoutubeVideoId = 'KjK02QIm4ZI';
const brouwersdamWebcamEmbedUrl =
    'https://g0.ipcamlive.com/player/player.php?alias=6878d928bbb14&autoplay=1&mute=1&disableautofullscreen=1&disablefullscreen=1&disablezoombutton=1&disableframecapture=1&disabletimelapseplayer=1&disablestorageplayer=1&disabledownloadbutton=1&disableplaybackspeedbutton=1&disablenavigation=1&disableuserpause=1&websocketenabled=1';

enum WebcamSourceKind {
  empty,
  invalid,
  directImage,
  directVideo,
  knownWebcam,
  youtube,
  webPage,
}

enum WebcamDiagnosticLevel { success, warning, error }

class WebcamUrlDiagnostic {
  final String rawUrl;
  final String? normalizedUrl;
  final String? displayUrl;
  final String? suggestedUrl;
  final WebcamSourceKind kind;
  final WebcamDiagnosticLevel level;
  final String title;
  final String message;
  final List<String> details;

  const WebcamUrlDiagnostic({
    required this.rawUrl,
    required this.normalizedUrl,
    required this.displayUrl,
    required this.suggestedUrl,
    required this.kind,
    required this.level,
    required this.title,
    required this.message,
    required this.details,
  });

  bool get hasPreview => displayUrl != null && kind != WebcamSourceKind.invalid;
}

WebcamUrlDiagnostic diagnoseWebcamUrl(String? value) {
  final rawUrl = value?.trim() ?? '';
  if (rawUrl.isEmpty) {
    return const WebcamUrlDiagnostic(
      rawUrl: '',
      normalizedUrl: null,
      displayUrl: null,
      suggestedUrl: null,
      kind: WebcamSourceKind.empty,
      level: WebcamDiagnosticLevel.warning,
      title: 'Noch keine Adresse',
      message: 'Trage eine Internet-Adresse der Webcam ein und pruefe sie.',
      details: [
        'Am besten funktioniert eine direkte Bild- oder Stream-Adresse.',
      ],
    );
  }

  final normalizedUrl = normalizedWebcamUrl(rawUrl);
  if (normalizedUrl == null) {
    return WebcamUrlDiagnostic(
      rawUrl: rawUrl,
      normalizedUrl: null,
      displayUrl: null,
      suggestedUrl: null,
      kind: WebcamSourceKind.invalid,
      level: WebcamDiagnosticLevel.error,
      title: 'Adresse nicht lesbar',
      message:
          'Diese Eingabe sieht nicht wie eine gueltige Internet-Adresse aus.',
      details: const [
        'Beispiel: https://example.com/webcam.jpg',
        'Adressen mit http oder https sind geeignet.',
      ],
    );
  }

  final uri = Uri.tryParse(normalizedUrl);
  if (uri == null ||
      !uri.hasScheme ||
      uri.host.isEmpty ||
      (uri.scheme != 'http' && uri.scheme != 'https')) {
    return WebcamUrlDiagnostic(
      rawUrl: rawUrl,
      normalizedUrl: normalizedUrl,
      displayUrl: null,
      suggestedUrl: null,
      kind: WebcamSourceKind.invalid,
      level: WebcamDiagnosticLevel.error,
      title: 'Adresse nicht lesbar',
      message:
          'Diese Eingabe sieht nicht wie eine gueltige Internet-Adresse aus.',
      details: const [
        'Beispiel: https://example.com/webcam.jpg',
        'Adressen mit http oder https sind geeignet.',
      ],
    );
  }

  final knownEmbedUrl = knownWebcamEmbedUrl(normalizedUrl);
  if (knownEmbedUrl != null) {
    return _knownWebcamDiagnostic(
      rawUrl: rawUrl,
      normalizedUrl: normalizedUrl,
      displayUrl: knownEmbedUrl,
      title: 'Bekannte Webcam erkannt',
      message:
          'Die App kennt fuer diese Webcam eine bessere interne Anzeige-Adresse.',
    );
  }

  final youtubeEmbedUrl = youtubeEmbedUrlForWebcam(normalizedUrl);
  if (youtubeEmbedUrl != null) {
    return WebcamUrlDiagnostic(
      rawUrl: rawUrl,
      normalizedUrl: normalizedUrl,
      displayUrl: youtubeEmbedUrl,
      suggestedUrl: youtubeEmbedUrl == normalizedUrl ? null : youtubeEmbedUrl,
      kind: WebcamSourceKind.youtube,
      level: WebcamDiagnosticLevel.success,
      title: 'YouTube-Video erkannt',
      message:
          'Die App wandelt diese Adresse in eine passende YouTube-Ansicht um.',
      details: const [
        'Wenn der Anbieter das Video beendet oder sperrt, kann die Vorschau trotzdem ausfallen.',
      ],
    );
  }

  final lmfcImageUrl = lmfcDirectImageUrl(normalizedUrl);
  if (lmfcImageUrl != null) {
    return _knownWebcamDiagnostic(
      rawUrl: rawUrl,
      normalizedUrl: normalizedUrl,
      displayUrl: lmfcImageUrl,
      title: 'LMFC-Webcam erkannt',
      message:
          'Die normale Webseite wird automatisch durch das direkte Webcam-Bild ersetzt.',
    );
  }

  final displayUrl = displayWebcamUrl(normalizedUrl);
  if (isDirectImageFeed(displayUrl)) {
    return WebcamUrlDiagnostic(
      rawUrl: rawUrl,
      normalizedUrl: normalizedUrl,
      displayUrl: displayUrl,
      suggestedUrl: displayUrl == normalizedUrl ? null : displayUrl,
      kind: WebcamSourceKind.directImage,
      level: WebcamDiagnosticLevel.success,
      title: 'Direktes Webcam-Bild',
      message:
          'Diese Adresse ist gut geeignet. Die App kann das Bild regelmaessig neu laden.',
      details: const [
        'Das ist meistens die stabilste Variante fuer Webcam-Vorschauen.',
      ],
    );
  }

  if (isDirectVideoFeed(displayUrl)) {
    return WebcamUrlDiagnostic(
      rawUrl: rawUrl,
      normalizedUrl: normalizedUrl,
      displayUrl: displayUrl,
      suggestedUrl: displayUrl == normalizedUrl ? null : displayUrl,
      kind: WebcamSourceKind.directVideo,
      level: WebcamDiagnosticLevel.success,
      title: 'Direkter Video-Stream',
      message:
          'Diese Adresse ist geeignet. Die App verbindet bei Fehlern automatisch neu.',
      details: const [
        'Live-Streams koennen vom Anbieter zeitweise getrennt werden.',
      ],
    );
  }

  return WebcamUrlDiagnostic(
    rawUrl: rawUrl,
    normalizedUrl: normalizedUrl,
    displayUrl: displayUrl,
    suggestedUrl: null,
    kind: WebcamSourceKind.webPage,
    level: WebcamDiagnosticLevel.warning,
    title: 'Normale Webseite erkannt',
    message:
        'Diese Adresse kann funktionieren, wird aber von vielen Anbietern in Apps blockiert.',
    details: const [
      'Besser ist eine direkte Bild-Adresse, ein Video-Stream oder eine bekannte Einbettung.',
      'Wenn die Vorschau schwarz bleibt, liegt es meist an der Webseite des Anbieters.',
    ],
  );
}

WebcamUrlDiagnostic _knownWebcamDiagnostic({
  required String rawUrl,
  required String normalizedUrl,
  required String displayUrl,
  required String title,
  required String message,
}) {
  return WebcamUrlDiagnostic(
    rawUrl: rawUrl,
    normalizedUrl: normalizedUrl,
    displayUrl: displayUrl,
    suggestedUrl: displayUrl == normalizedUrl ? null : displayUrl,
    kind: WebcamSourceKind.knownWebcam,
    level: WebcamDiagnosticLevel.success,
    title: title,
    message: message,
    details: const [
      'Diese Sonderbehandlung erspart dem Nutzer die Suche nach der richtigen Unteradresse.',
    ],
  );
}

String? normalizedWebcamUrl(String? value) {
  final url = value?.trim() ?? '';
  if (url.isEmpty) {
    return null;
  }

  final lower = url.toLowerCase();
  if (lower.startsWith('http://') || lower.startsWith('https://')) {
    return url;
  }

  return 'https://$url';
}

String displayWebcamUrl(String url) {
  final knownEmbedUrl = knownWebcamEmbedUrl(url);
  if (knownEmbedUrl != null) {
    return knownEmbedUrl;
  }

  final youtubeEmbedUrl = youtubeEmbedUrlForWebcam(url);
  if (youtubeEmbedUrl != null) {
    return youtubeEmbedUrl;
  }

  final lmfcImageUrl = lmfcDirectImageUrl(url);
  if (lmfcImageUrl != null) {
    return lmfcImageUrl;
  }

  return url;
}

String? lmfcDirectImageUrl(String url) {
  final uri = Uri.tryParse(url);
  if (uri == null || !uri.hasScheme) {
    return null;
  }

  final host = uri.host.toLowerCase();
  final path = uri.path.toLowerCase().replaceFirst(RegExp(r'/$'), '');
  final isLmfcWebcamPage = (host == 'lmfc.de' || host == 'www.lmfc.de') &&
      (path.isEmpty || path == '/webcam');

  return isLmfcWebcamPage ? lmfcWebcamImageUrl : null;
}

String? knownWebcamEmbedUrl(String url) {
  final uri = Uri.tryParse(url);
  if (uri == null || !uri.hasScheme) {
    return null;
  }

  final host = uri.host.toLowerCase();
  final path = uri.path.toLowerCase();
  final isBrouwersdam = host == 'brouwersdam.nl' ||
      host == 'www.brouwersdam.nl' ||
      host == 'brouwersdam.com' ||
      host == 'www.brouwersdam.com';
  if (isBrouwersdam &&
      (path.contains('/brouwersdam/webcam') ||
          path.contains('/live-view/') ||
          path.endsWith('/webcam'))) {
    return brouwersdamWebcamEmbedUrl;
  }

  final isNaturalHigh = host == 'natural-high.nl' ||
      host == 'www.natural-high.nl' ||
      host == 'surfshop.natural-high.nl';
  if (isNaturalHigh && path.contains('webcam-brouwersdam')) {
    return brouwersdamWebcamEmbedUrl;
  }

  final isNaturalHighViewer = host == 'live.netcamviewer.nl' &&
      path.contains('natural-high-brouwersdam-webcam');
  if (isNaturalHighViewer) {
    return brouwersdamWebcamEmbedUrl;
  }

  final isCamStreamerBrouwersdam = host == 'camstreamer.com' &&
      (path.contains('597679676-live-camera-brouwersdam') ||
          path.contains('live-camera-brouwersdam') ||
          (path.startsWith('/embed/') &&
              url.toLowerCase().contains(
                    'bfbmydcnawfcqtjju11hwj8vjqljxehjoknafoyf',
                  )));
  if (isCamStreamerBrouwersdam) {
    return brouwersdamWebcamEmbedUrl;
  }

  final isBrouwersdamStreamlock = host.endsWith('streamlock.net') &&
      path.contains('/771/771.stream/') &&
      path.contains('playlist.m3u8');
  if (isBrouwersdamStreamlock) {
    return brouwersdamWebcamEmbedUrl;
  }

  return null;
}

String? youtubeEmbedUrlForWebcam(String url) {
  final uri = Uri.tryParse(url);
  if (uri == null || !uri.hasScheme) {
    return null;
  }

  final host = uri.host.toLowerCase();
  String? videoId;
  if (host == 'youtu.be' && uri.pathSegments.isNotEmpty) {
    videoId = uri.pathSegments.first;
  } else if (host == 'youtube.com' ||
      host == 'www.youtube.com' ||
      host == 'm.youtube.com') {
    if (uri.pathSegments.isNotEmpty) {
      final firstSegment = uri.pathSegments.first;
      if (firstSegment == 'watch') {
        videoId = uri.queryParameters['v'];
      } else if ((firstSegment == 'embed' || firstSegment == 'shorts') &&
          uri.pathSegments.length > 1) {
        videoId = uri.pathSegments[1];
      }
    }
  }

  if (videoId == null || videoId.trim().isEmpty) {
    return null;
  }

  if (videoId.trim() == brouwersdamYoutubeVideoId) {
    return brouwersdamWebcamEmbedUrl;
  }

  final query = <String, String>{
    'autoplay': '1',
    'mute': '1',
    'playsinline': '1',
    'rel': '0',
    if (uri.queryParameters['start'] != null)
      'start': uri.queryParameters['start']!,
  };
  return Uri.https('www.youtube.com', '/embed/${videoId.trim()}', query)
      .toString();
}

bool isDirectImageFeed(String url) {
  final lower = url.toLowerCase();
  return lower.contains('.jpg') ||
      lower.contains('.jpeg') ||
      lower.contains('.png') ||
      lower.contains('.webp') ||
      lower.contains('.gif') ||
      lower.contains('.mjpg') ||
      lower.contains('.mjpeg') ||
      lower.contains('snapshot') ||
      lower.contains('image');
}

bool isDirectVideoFeed(String url) {
  final lower = url.toLowerCase();
  return lower.contains('.m3u8') ||
      lower.contains('.mp4') ||
      lower.contains('.webm') ||
      lower.contains('.mov');
}

bool isLiveVideoStream(String url) {
  final lower = url.toLowerCase();
  return lower.contains('.m3u8') ||
      lower.contains('playlist') ||
      lower.contains('live') ||
      lower.contains('stream');
}

bool isKnownSlowWebcam(String url) {
  final lower = url.toLowerCase();
  return lower.contains('brouwersdam') ||
      lower.contains('natural-high') ||
      lower.contains('natural_high') ||
      lower.contains('6878d928bbb14') ||
      lower.contains('ipcamlive.com') ||
      lower.contains('camstreamer.com') ||
      lower.contains(brouwersdamYoutubeVideoId.toLowerCase()) ||
      lower.contains('bfbmydcnawfcqtjju11hwj8vjqljxehjoknafoyf');
}

Duration videoInitializeTimeout(String url) {
  if (isKnownSlowWebcam(url)) {
    return const Duration(seconds: 75);
  }
  if (isLiveVideoStream(url)) {
    return const Duration(seconds: 45);
  }
  return const Duration(seconds: 25);
}

Duration videoRetryDelay(int attempt) {
  if (attempt <= 0) {
    return const Duration(seconds: 10);
  }
  if (attempt == 1) {
    return const Duration(seconds: 25);
  }
  if (attempt == 2) {
    return const Duration(seconds: 45);
  }
  return const Duration(seconds: 60);
}
