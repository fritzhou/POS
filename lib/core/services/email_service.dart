import 'package:supabase_flutter/supabase_flutter.dart';

/// Auth email submission, not a promise that an inbox received a message.
/// Privileged employee invitations belong in the backend, never in Flutter.
abstract interface class EmailService {
  Future<void> requestPasswordRecovery(
    String email, {
    required String redirectTo,
  });
  Future<void> requestVerification(String email, {String? redirectTo});
}

class SupabaseEmailService implements EmailService {
  SupabaseEmailService(this.client);
  final SupabaseClient client;

  @override
  Future<void> requestPasswordRecovery(
    String email, {
    required String redirectTo,
  }) => client.auth.resetPasswordForEmail(email, redirectTo: redirectTo);

  @override
  Future<void> requestVerification(String email, {String? redirectTo}) async {
    await client.auth.resend(
      type: OtpType.signup,
      email: email,
      emailRedirectTo: redirectTo,
    );
  }
}
