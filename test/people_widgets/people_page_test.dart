import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexapos/core/security/app_role.dart';
import 'package:nexapos/features/administration/domain/administration_models.dart';
import 'package:nexapos/features/catalog/domain/repository_support.dart';
import 'package:nexapos/features/people/domain/people_models.dart';
import 'package:nexapos/features/people/domain/people_repository.dart';
import 'package:nexapos/features/people/presentation/people_page.dart';

const _branch = BranchOption(
  id: '00000000-0000-0000-0000-000000000003',
  name: 'Downtown',
  code: 'DT',
);
const _supplier = Supplier(
  id: '00000000-0000-0000-0000-000000000001',
  organizationId: '00000000-0000-0000-0000-000000000002',
  name: 'Actual supplier',
  phone: '555-0100',
  active: true,
  revision: 7,
  branchId: '00000000-0000-0000-0000-000000000003',
);
const _customer = Customer(
  id: '00000000-0000-0000-0000-000000000004',
  organizationId: '00000000-0000-0000-0000-000000000002',
  name: 'Actual customer',
  active: true,
  revision: 4,
  branchId: '00000000-0000-0000-0000-000000000003',
);

void main() {
  Future<void> show(
    WidgetTester tester,
    PeoplePage page, {
    Size size = const Size(1280, 1000),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: page)));
    await tester.pumpAndSettle();
  }

  testWidgets('preview remains empty with an injected repository', (
    tester,
  ) async {
    final repo = _PeopleFake();
    await show(
      tester,
      PeoplePage(
        kind: PeopleKind.suppliers,
        repository: repo,
        role: AppRole.owner,
      ),
    );
    expect(repo.reads, 0);
    expect(find.text('Actual supplier'), findsNothing);
    expect(find.text('Not Yet Connected'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('people-add')))
          .onPressed,
      isNull,
    );
  });
  testWidgets('cashier can look up customers but cannot write them', (
    tester,
  ) async {
    final repo = _PeopleFake();
    await show(
      tester,
      PeoplePage(
        kind: PeopleKind.customers,
        repository: repo,
        role: AppRole.cashier,
        isPreview: false,
      ),
    );
    expect(find.text('Actual customer'), findsOneWidget);
    expect(find.text('Contact lookup · Read only'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('people-add')))
          .onPressed,
      isNull,
    );
    expect(find.byIcon(Icons.edit_outlined), findsNothing);
  });
  testWidgets('cashier supplier access is blocked before reads', (
    tester,
  ) async {
    final repo = _PeopleFake();
    await show(
      tester,
      PeoplePage(
        kind: PeopleKind.suppliers,
        repository: repo,
        role: AppRole.cashier,
        isPreview: false,
      ),
    );
    expect(repo.reads, 0);
    expect(find.text('Access restricted'), findsOneWidget);
  });
  testWidgets('contact form validates name and email before write', (
    tester,
  ) async {
    final repo = _PeopleFake();
    await show(
      tester,
      PeoplePage(
        kind: PeopleKind.customers,
        repository: repo,
        role: AppRole.manager,
        isPreview: false,
      ),
    );
    await tester.tap(find.byKey(const Key('people-add')));
    await tester.pumpAndSettle();
    await tester.enterText(_field('Email'), 'invalid-email');
    await tester.tap(find.text('Save contact'));
    await tester.pumpAndSettle();
    expect(find.text('Name is required.'), findsOneWidget);
    expect(find.text('Enter a valid email address.'), findsOneWidget);
    expect(repo.writes, 0);
  });
  testWidgets('contact success waits for server confirmation', (tester) async {
    final repo = _PeopleFake()..createResult = Completer<Customer>();
    await show(
      tester,
      PeoplePage(
        kind: PeopleKind.customers,
        repository: repo,
        role: AppRole.owner,
        isPreview: false,
      ),
    );
    await tester.tap(find.byKey(const Key('people-add')));
    await tester.pumpAndSettle();
    await tester.enterText(_field('Name'), 'New contact');
    await tester.tap(find.text('Save contact'));
    await tester.pump();
    expect(find.text('Customer saved.'), findsNothing);
    expect(find.text('Saving…'), findsOneWidget);
    repo.createResult!.complete(_customer);
    await tester.pumpAndSettle();
    expect(find.text('Customer saved.'), findsOneWidget);
  });
  testWidgets('contact conflict retains form and passes expected revision', (
    tester,
  ) async {
    final repo = _PeopleFake()
      ..updateFailure = const RepositoryFailure(
        RepositoryFailureType.conflict,
        'Conflict',
      );
    await show(
      tester,
      PeoplePage(
        kind: PeopleKind.suppliers,
        repository: repo,
        role: AppRole.inventoryStaff,
        isPreview: false,
      ),
    );
    await tester.tap(find.byTooltip('Edit Actual supplier'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save contact'));
    await tester.pumpAndSettle();
    expect(repo.expectedRevision, 7);
    expect(find.textContaining('This contact changed'), findsOneWidget);
    expect(find.text('Supplier saved.'), findsNothing);
    expect(find.text('Edit Supplier'), findsOneWidget);
  });
  testWidgets('search and pagination send server filters', (tester) async {
    final repo = _PeopleFake()..hasMore = true;
    await show(
      tester,
      PeoplePage(
        kind: PeopleKind.suppliers,
        repository: repo,
        role: AppRole.owner,
        isPreview: false,
      ),
    );
    await tester.enterText(find.byKey(const Key('people-search')), 'North');
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();
    expect(repo.lastQuery, 'North');
    await tester.tap(find.byTooltip('Next page'));
    await tester.pumpAndSettle();
    expect(repo.lastOffset, 20);
    expect(find.text('Page 2'), findsOneWidget);
  });
  testWidgets('connected customer cards fit a 320 pixel phone', (tester) async {
    await show(
      tester,
      PeoplePage(
        kind: PeopleKind.customers,
        repository: _PeopleFake(),
        role: AppRole.cashier,
        isPreview: false,
      ),
      size: const Size(320, 900),
    );
    expect(find.byType(DataTable), findsNothing);
    expect(find.text('Actual customer'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('supplier form fits a 320 pixel phone', (tester) async {
    await show(
      tester,
      PeoplePage(
        kind: PeopleKind.suppliers,
        repository: _PeopleFake(),
        role: AppRole.owner,
        isPreview: false,
      ),
      size: const Size(320, 900),
    );
    await tester.tap(find.byKey(const Key('people-add')));
    await tester.pumpAndSettle();
    expect(find.text('Add Supplier'), findsWidgets);
    await tester.enterText(_field('Name'), 'Real supplier');
    await tester.ensureVisible(find.widgetWithText(SwitchListTile, 'Active'));
    expect(tester.takeException(), isNull);
  });
}

Finder _field(String label) => find.widgetWithText(TextFormField, label);

class _PeopleFake implements PeopleRepository {
  int reads = 0, writes = 0, lastOffset = 0;
  String lastQuery = '';
  int? expectedRevision;
  bool hasMore = false;
  Completer<Customer>? createResult;
  RepositoryFailure? updateFailure;
  @override
  Future<List<BranchOption>> listBranches() async => [_branch];
  @override
  Future<DataPage<Supplier>> listSuppliers({
    String query = '',
    bool? active,
    String? branchId,
    PageRequest page = const PageRequest(),
  }) async {
    reads++;
    lastQuery = query;
    lastOffset = page.offset;
    return DataPage(items: [_supplier], hasMore: hasMore, offset: page.offset);
  }

  @override
  Future<DataPage<Customer>> listCustomers({
    String query = '',
    bool? active,
    String? branchId,
    PageRequest page = const PageRequest(),
  }) async {
    reads++;
    lastQuery = query;
    lastOffset = page.offset;
    return DataPage(items: [_customer], hasMore: hasMore, offset: page.offset);
  }

  @override
  Future<Supplier> createSupplier(SupplierInput input) async {
    writes++;
    return _supplier;
  }

  @override
  Future<Customer> createCustomer(CustomerInput input) async {
    writes++;
    return createResult == null ? _customer : await createResult!.future;
  }

  @override
  Future<Supplier> updateSupplier({
    required String id,
    required int expectedRevision,
    required SupplierInput input,
  }) async {
    writes++;
    this.expectedRevision = expectedRevision;
    if (updateFailure != null) throw updateFailure!;
    return _supplier;
  }

  @override
  Future<Customer> updateCustomer({
    required String id,
    required int expectedRevision,
    required CustomerInput input,
  }) async {
    writes++;
    this.expectedRevision = expectedRevision;
    if (updateFailure != null) throw updateFailure!;
    return _customer;
  }

  @override
  Future<Supplier> setSupplierActive({
    required String id,
    required int expectedRevision,
    required bool active,
  }) async => _supplier;
  @override
  Future<Customer> setCustomerActive({
    required String id,
    required int expectedRevision,
    required bool active,
  }) async => _customer;
}
