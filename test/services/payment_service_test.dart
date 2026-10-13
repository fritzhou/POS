import 'package:flutter_test/flutter_test.dart';
import 'package:nexapos/core/services/payment_service.dart';

void main() {
  test(
    'counted cash records exact applied money and change without provider claims',
    () {
      final evidence = CashPaymentService().recordTender(
        const TenderRequest(
          amountDueMinor: 12550,
          receivedMinor: 15000,
          operatorConfirmed: true,
        ),
      );
      expect(evidence.appliedMinor, 12550);
      expect(evidence.changeMinor, 2450);
      expect(evidence.providerAuthorized, isFalse);
    },
  );

  test(
    'manual digital tender requires operator evidence and never implies API authorization',
    () {
      final service = ManualDigitalPaymentService(PaymentMethod.gcash);
      expect(
        () => service.recordTender(
          const TenderRequest(
            amountDueMinor: 10000,
            receivedMinor: 10000,
            reference: 'fixture-reference',
          ),
        ),
        throwsFormatException,
      );
      expect(
        () => service.recordTender(
          const TenderRequest(
            amountDueMinor: 10000,
            receivedMinor: 9999,
            operatorConfirmed: true,
            reference: 'fixture-reference',
          ),
        ),
        throwsFormatException,
      );
      final evidence = service.recordTender(
        const TenderRequest(
          amountDueMinor: 10000,
          receivedMinor: 10000,
          operatorConfirmed: true,
          reference: 'fixture-reference',
        ),
      );
      expect(evidence.verification, PaymentVerification.manual);
      expect(evidence.providerAuthorized, isFalse);
      expect(service.statusLabel, 'Manual Payment Verification');
    },
  );

  test(
    'future payment providers fail explicitly rather than returning fake success',
    () {
      for (final service in [
        GCashPaymentService(),
        MayaPaymentService(),
        CardTerminalService(),
      ]) {
        expect(
          () => service.recordTender(
            const TenderRequest(
              amountDueMinor: 10000,
              receivedMinor: 10000,
              operatorConfirmed: true,
            ),
          ),
          throwsUnsupportedError,
        );
      }
    },
  );
}
