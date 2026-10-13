import '../../catalog/domain/repository_support.dart';

class Supplier {
  const Supplier({
    required this.id,
    required this.organizationId,
    required this.name,
    required this.active,
    required this.revision,
    this.branchId,
    this.contactName,
    this.email,
    this.phone,
    this.address,
    this.notes,
  });
  final String id;
  final String organizationId;
  final String name;
  final bool active;
  final int revision;
  final String? branchId;
  final String? contactName;
  final String? email;
  final String? phone;
  final String? address;
  final String? notes;
}

class Customer {
  const Customer({
    required this.id,
    required this.organizationId,
    required this.name,
    required this.active,
    required this.revision,
    this.branchId,
    this.email,
    this.phone,
    this.address,
    this.notes,
  });
  final String id;
  final String organizationId;
  final String name;
  final bool active;
  final int revision;
  final String? branchId;
  final String? email;
  final String? phone;
  final String? address;
  final String? notes;
}

class SupplierInput {
  const SupplierInput({
    required this.name,
    this.branchId,
    this.contactName,
    this.email,
    this.phone,
    this.address,
    this.notes,
    this.active = true,
  });
  final String name;
  final String? branchId;
  final String? contactName;
  final String? email;
  final String? phone;
  final String? address;
  final String? notes;
  final bool active;

  Map<String, dynamic> validatedValues() => {
    ...contactValues(
      name: name,
      email: email,
      phone: phone,
      address: address,
      notes: notes,
      branchId: branchId,
      active: active,
    ),
    'contact_name': optionalText(contactName, 'Contact name', 120),
  };
}

class CustomerInput {
  const CustomerInput({
    required this.name,
    this.branchId,
    this.email,
    this.phone,
    this.address,
    this.notes,
    this.active = true,
  });
  final String name;
  final String? branchId;
  final String? email;
  final String? phone;
  final String? address;
  final String? notes;
  final bool active;

  Map<String, dynamic> validatedValues() => contactValues(
    name: name,
    email: email,
    phone: phone,
    address: address,
    notes: notes,
    branchId: branchId,
    active: active,
  );
}

Map<String, dynamic> contactValues({
  required String name,
  required String? email,
  required String? phone,
  required String? address,
  required String? notes,
  required String? branchId,
  required bool active,
}) {
  final normalizedEmail = optionalText(email, 'Email', 254)?.toLowerCase();
  if (normalizedEmail != null &&
      !RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(normalizedEmail)) {
    throw const RepositoryFailure(
      RepositoryFailureType.validation,
      'Enter a valid contact email address.',
    );
  }
  return {
    'name': requiredText(name, 'Name', 160),
    'email': normalizedEmail,
    'phone': optionalText(phone, 'Phone', 40),
    'address': optionalText(address, 'Address', 1000),
    'notes': optionalText(notes, 'Notes', 2000),
    'branch_id': validateOptionalId(branchId),
    'active': active,
  };
}
