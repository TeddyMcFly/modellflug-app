import 'package:flutter_test/flutter_test.dart';
import 'package:modellflug_app/shared/services/admin_access.dart';

void main() {
  test('admin access allows the owner and the Linus test account', () {
    expect(isAdminEmail('teddroste@me.com'), isTrue);
    expect(isAdminEmail('linus@web.de'), isTrue);
  });

  test('admin access ignores casing and surrounding spaces', () {
    expect(isAdminEmail('  LINUS@WEB.DE  '), isTrue);
  });

  test('admin access blocks ordinary accounts', () {
    expect(isAdminEmail('gast@example.com'), isFalse);
    expect(isAdminEmail(null), isFalse);
  });
}
