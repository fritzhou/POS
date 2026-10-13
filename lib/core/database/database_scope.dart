/// Explicit tenant and branch context for every local data access.
///
/// This is a cache boundary, not proof of authorization. A server-verified
/// membership (and, later, an offline grant) must authorize business actions.
class DatabaseScope {
  DatabaseScope({required this.organizationId, required this.branchId}) {
    if (organizationId.trim().isEmpty || branchId.trim().isEmpty) {
      throw ArgumentError('Organization and branch identifiers are required.');
    }
  }

  final String organizationId;
  final String branchId;
}
