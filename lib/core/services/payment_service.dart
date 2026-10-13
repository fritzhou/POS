enum PaymentMethod { cash, card, gcash, maya, other }

enum PaymentVerification { cashCounted, manual }

class TenderRequest {
  const TenderRequest({
    required this.amountDueMinor,
    required this.receivedMinor,
    this.currency = 'PHP',
    this.operatorConfirmed = false,
    this.reference,
  });
  final int amountDueMinor;
  final int receivedMinor;
  final String currency;
  final bool operatorConfirmed;
  final String? reference;
}

/// Local tender evidence only: never provider authorization or cloud acceptance.
class TenderEvidence {
  const TenderEvidence({
    required this.method,
    required this.verification,
    required this.appliedMinor,
    required this.receivedMinor,
    required this.changeMinor,
    required this.currency,
    this.reference,
  });
  final PaymentMethod method;
  final PaymentVerification verification;
  final int appliedMinor;
  final int receivedMinor;
  final int changeMinor;
  final String currency;
  final String? reference;
  bool get providerAuthorized => false;
}

abstract interface class PaymentService {
  PaymentMethod get method;
  String get statusLabel;
  TenderEvidence recordTender(TenderRequest request);
}

void _validate(TenderRequest request) {
  if (request.amountDueMinor <= 0 ||
      request.receivedMinor < 0 ||
      !RegExp(r'^[A-Z]{3}$').hasMatch(request.currency)) {
    throw const FormatException('Invalid tender amounts or currency');
  }
}

class CashPaymentService implements PaymentService {
  @override
  PaymentMethod get method => PaymentMethod.cash;
  @override
  String get statusLabel => 'Cash counted by operator';
  @override
  TenderEvidence recordTender(TenderRequest request) {
    _validate(request);
    if (!request.operatorConfirmed ||
        request.receivedMinor < request.amountDueMinor) {
      throw const FormatException('Count and confirm sufficient cash first');
    }
    return TenderEvidence(
      method: method,
      verification: PaymentVerification.cashCounted,
      appliedMinor: request.amountDueMinor,
      receivedMinor: request.receivedMinor,
      changeMinor: request.receivedMinor - request.amountDueMinor,
      currency: request.currency,
    );
  }
}

class ManualDigitalPaymentService implements PaymentService {
  ManualDigitalPaymentService(this.method) {
    if (method == PaymentMethod.cash) {
      throw const FormatException('Cash has a separate counted-tender service');
    }
  }
  @override
  final PaymentMethod method;
  @override
  String get statusLabel => 'Manual Payment Verification';
  @override
  TenderEvidence recordTender(TenderRequest request) {
    _validate(request);
    if (!request.operatorConfirmed ||
        request.receivedMinor != request.amountDueMinor ||
        request.reference == null ||
        request.reference!.trim().isEmpty) {
      throw const FormatException(
        'Confirm the payment amount and its reference first',
      );
    }
    return TenderEvidence(
      method: method,
      verification: PaymentVerification.manual,
      appliedMinor: request.amountDueMinor,
      receivedMinor: request.receivedMinor,
      changeMinor: 0,
      currency: request.currency,
      reference: request.reference!.trim(),
    );
  }
}

/// No provider network code or credentials exist in Phase 1.
sealed class FutureProviderPaymentService implements PaymentService {
  @override
  String get statusLabel => 'Not Yet Connected';
  @override
  TenderEvidence recordTender(TenderRequest request) =>
      throw UnsupportedError('Payment provider is Not Yet Connected');
}

class GCashPaymentService extends FutureProviderPaymentService {
  @override
  PaymentMethod get method => PaymentMethod.gcash;
}

class MayaPaymentService extends FutureProviderPaymentService {
  @override
  PaymentMethod get method => PaymentMethod.maya;
}

class CardTerminalService extends FutureProviderPaymentService {
  @override
  PaymentMethod get method => PaymentMethod.card;
}
