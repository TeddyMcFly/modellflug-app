import 'package:flutter_test/flutter_test.dart';
import 'package:modellflug_app/shared/services/webcam_url_diagnostics.dart';

void main() {
  test('recognizes a direct image webcam URL', () {
    final diagnostic =
        diagnoseWebcamUrl('https://example.com/camera/webcam.jpg');

    expect(diagnostic.kind, WebcamSourceKind.directImage);
    expect(diagnostic.level, WebcamDiagnosticLevel.success);
    expect(diagnostic.displayUrl, 'https://example.com/camera/webcam.jpg');
  });

  test('maps the LMFC webcam page to the direct image URL', () {
    final diagnostic = diagnoseWebcamUrl('https://www.lmfc.de/webcam');

    expect(diagnostic.kind, WebcamSourceKind.knownWebcam);
    expect(diagnostic.level, WebcamDiagnosticLevel.success);
    expect(diagnostic.displayUrl, lmfcWebcamImageUrl);
    expect(diagnostic.suggestedUrl, lmfcWebcamImageUrl);
  });

  test('maps known Brouwersdam pages to the stable embed URL', () {
    final diagnostic =
        diagnoseWebcamUrl('https://www.brouwersdam.nl/brouwersdam/webcam');

    expect(diagnostic.kind, WebcamSourceKind.knownWebcam);
    expect(diagnostic.level, WebcamDiagnosticLevel.success);
    expect(diagnostic.displayUrl, brouwersdamWebcamEmbedUrl);
    expect(diagnostic.suggestedUrl, brouwersdamWebcamEmbedUrl);
  });

  test('warns for ordinary web pages', () {
    final diagnostic = diagnoseWebcamUrl('https://example.com/webcam');

    expect(diagnostic.kind, WebcamSourceKind.webPage);
    expect(diagnostic.level, WebcamDiagnosticLevel.warning);
  });
}
