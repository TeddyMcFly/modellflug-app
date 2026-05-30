import 'package:flutter_test/flutter_test.dart';
import 'package:modellflug_app/shared/services/subscription_service.dart';

void main() {
  group('AccountAccess', () {
    test('keeps a permanently active account unlocked', () {
      final access = AccountAccess.fromUserData(
        const {'subscriptionStatus': 'active'},
      );

      expect(access.status, AccountAccessStatus.active);
      expect(access.hasFullAccess, isTrue);
    });

    test('locks an account after the trial end', () {
      final now = DateTime.now().toUtc();
      final access = AccountAccess.fromUserData({
        'subscriptionStatus': 'trial',
        'trialStartedAt':
            now.subtract(const Duration(days: 31)).toIso8601String(),
        'trialEndsAt': now.subtract(const Duration(days: 1)).toIso8601String(),
      });

      expect(access.status, AccountAccessStatus.expired);
      expect(access.hasFullAccess, isFalse);
    });

    test('keeps an activation request usable until the trial ends', () {
      final now = DateTime.now().toUtc();
      final access = AccountAccess.fromUserData({
        'subscriptionStatus': 'activationRequested',
        'trialStartedAt':
            now.subtract(const Duration(days: 10)).toIso8601String(),
        'trialEndsAt': now.add(const Duration(days: 20)).toIso8601String(),
      });

      expect(access.status, AccountAccessStatus.activationRequested);
      expect(access.hasFullAccess, isTrue);
    });
  });

  group('PaymentSettings', () {
    test('accepts a valid PayPal link', () {
      const settings = PaymentSettings(
        paypalPaymentUrl: 'https://www.paypal.com/paypalme/example',
      );

      expect(settings.hasPaypalPaymentUrl, isTrue);
      expect(settings.paypalUri?.host, 'www.paypal.com');
    });

    test('rejects an empty or invalid PayPal link', () {
      expect(PaymentSettings.empty().hasPaypalPaymentUrl, isFalse);
      const settings = PaymentSettings(paypalPaymentUrl: 'kein-link');

      expect(settings.hasPaypalPaymentUrl, isFalse);
    });
  });
}
