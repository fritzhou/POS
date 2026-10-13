import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexapos/app/app.dart';
import 'package:nexapos/app/business_services.dart';
import 'package:nexapos/core/auth/auth_models.dart';
import 'package:nexapos/core/auth/auth_repository.dart';
import 'package:nexapos/core/security/app_role.dart';
import 'package:nexapos/features/administration/domain/administration_models.dart';
import 'package:nexapos/features/administration/domain/administration_repository.dart';
import 'package:nexapos/features/administration/presentation/audit_logs_page.dart';
import 'package:nexapos/features/catalog/domain/catalog_models.dart';
import 'package:nexapos/features/catalog/domain/catalog_repository.dart';
import 'package:nexapos/features/catalog/domain/repository_support.dart';
import 'package:nexapos/features/catalog/presentation/products_page.dart';
import 'package:nexapos/features/employees/presentation/employees_page.dart';
import 'package:nexapos/features/people/domain/people_models.dart';
import 'package:nexapos/features/people/domain/people_repository.dart';
import 'package:nexapos/features/people/presentation/people_page.dart';
import 'package:nexapos/features/settings/settings_page.dart';

import '../auth/auth_gate_test.dart' show FakeAuthRepository;

// All identities, configuration and repositories below exist only in tests.
const _identity = AuthIdentity(
  userId: 'workspace-test-user',
  email: 'owner@example.test',
  emailVerified: true,
);

AuthenticatedUser _member(String suffix) => AuthenticatedUser(
  userId: _identity.userId,
  email: _identity.email,
  organizationId: 'organization-$suffix',
  membershipId: 'membership-$suffix',
  role: AppRole.owner,
  branchIds: {'branch-$suffix'},
  allBranches: true,
  businessName: 'Test business $suffix',
);

DataPage<T> _empty<T>(PageRequest page) =>
    DataPage(items: <T>[], hasMore: false, offset: page.offset);

abstract class _ScopeReader {
  _ScopeReader(this.scope);
  final AuthenticatedUser scope;
  final calls = <String>[];
  void record(String operation) => calls.add(
    '$operation:${scope.userId}:${scope.organizationId}:${scope.membershipId}',
  );

  // Unexpected writes must fail; these fakes never simulate saved business data.
  @override
  dynamic noSuchMethod(Invocation invocation) => throw StateError(
    'Unexpected workspace mutation: ${invocation.memberName}',
  );
}

class _CatalogReader extends _ScopeReader implements CatalogRepository {
  _CatalogReader(super.scope);
  @override
  Future<DataPage<Product>> searchProducts({
    ProductFilter filter = const ProductFilter(),
    PageRequest page = const PageRequest(),
  }) async {
    record('products');
    return _empty(page);
  }

  @override
  Future<DataPage<Category>> listCategories({
    bool? active,
    PageRequest page = const PageRequest(),
  }) async {
    record('categories');
    return _empty(page);
  }
}

class _PeopleReader extends _ScopeReader implements PeopleRepository {
  _PeopleReader(super.scope);
  @override
  Future<List<BranchOption>> listBranches() async {
    record('branches');
    return [];
  }

  @override
  Future<DataPage<Supplier>> listSuppliers({
    String query = '',
    bool? active,
    String? branchId,
    PageRequest page = const PageRequest(),
  }) async {
    record('suppliers');
    return _empty(page);
  }

  @override
  Future<DataPage<Customer>> listCustomers({
    String query = '',
    bool? active,
    String? branchId,
    PageRequest page = const PageRequest(),
  }) async {
    record('customers');
    return _empty(page);
  }
}

class _AdministrationReader extends _ScopeReader
    implements AdministrationRepository {
  _AdministrationReader(super.scope);
  @override
  Future<BusinessSettings> loadSettings() async {
    record('settings');
    return BusinessSettings(
      organizationId: scope.organizationId,
      businessName: scope.businessName,
      currency: 'PHP',
      taxBps: 0,
      revision: 1,
    );
  }

  @override
  Future<DataPage<AuditEntry>> listAudit({
    AuditFilter filter = const AuditFilter(),
    PageRequest page = const PageRequest(),
  }) async {
    record('audit');
    return _empty(page);
  }
}

class _EmployeeReader extends _ScopeReader implements EmployeeRepository {
  _EmployeeReader(super.scope);
  @override
  Future<List<BranchOption>> listBranches() async {
    record('employee-branches');
    return [];
  }

  @override
  Future<DataPage<Employee>> listEmployees({
    EmployeeStatus? status,
    PageRequest page = const PageRequest(),
  }) async {
    record('employees');
    return _empty(page);
  }
}

class _ScopedServices {
  _ScopedServices(this.actor) {
    catalog = _CatalogReader(actor);
    people = _PeopleReader(actor);
    administration = _AdministrationReader(actor);
    employees = _EmployeeReader(actor);
    services = BusinessServices(
      catalog: catalog,
      people: people,
      administration: administration,
      employees: employees,
    );
  }
  final AuthenticatedUser actor;
  late final _CatalogReader catalog;
  late final _PeopleReader people;
  late final _AdministrationReader administration;
  late final _EmployeeReader employees;
  late final BusinessServices services;
  List<String> get calls => [
    ...catalog.calls,
    ...people.calls,
    ...administration.calls,
    ...employees.calls,
  ];
}

Future<void> _mount(
  WidgetTester tester,
  AuthRepository auth,
  BusinessServicesFactory factory,
) async {
  tester.view.physicalSize = const Size(1440, 1100);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authRepositoryProvider.overrideWithValue(auth),
        businessServicesFactoryProvider.overrideWithValue(factory),
      ],
      child: const NexaApp(),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _navigate(WidgetTester tester, String module) async {
  final route = find.byKey(Key('navigate-$module'));
  await tester.ensureVisible(route);
  await tester.tap(route);
  await tester.pumpAndSettle();
  expect(tester.takeException(), isNull);
}

void main() {
  testWidgets(
    'design preview never constructs authenticated Phase 2 services',
    (tester) async {
      final groups = <_ScopedServices>[];
      await _mount(tester, const NotConfiguredAuthRepository(), (actor) {
        final group = _ScopedServices(actor);
        groups.add(group);
        return group.services;
      });
      await tester.tap(find.text('Open design preview'));
      await tester.pumpAndSettle();
      for (final module in [
        'products',
        'suppliers',
        'employees',
        'settings',
        'auditLogs',
      ]) {
        await _navigate(tester, module);
        expect(groups, isEmpty);
      }
      final audit = tester.widget<AuditLogsPage>(find.byType(AuditLogsPage));
      expect(audit.isPreview, isTrue);
      expect(audit.repository, isNull);
      expect(audit.role, isNull);
    },
  );

  testWidgets(
    'verified business selection wires all Phase 2 routes and replaces old organization scope',
    (tester) async {
      final first = _member('a');
      final second = _member('b');
      final auth = FakeAuthRepository()
        ..identity = _identity
        ..memberships = [first, second];
      final groups = <_ScopedServices>[];
      await _mount(tester, auth, (actor) {
        final group = _ScopedServices(actor);
        groups.add(group);
        return group.services;
      });
      expect(find.text('Choose your business'), findsOneWidget);
      expect(groups, isEmpty);
      await tester.tap(find.text(first.businessName));
      await tester.pumpAndSettle();
      final selected = groups.last;
      expect(selected.actor, same(first));

      await _navigate(tester, 'products');
      final products = tester.widget<ProductsPage>(find.byType(ProductsPage));
      expect(products.repository, same(selected.catalog));
      expect(products.peopleRepository, same(selected.people));
      expect(products.role, first.role);
      expect(products.isPreview, isFalse);
      expect(
        selected.catalog.calls.any((call) => call.startsWith('products:')),
        isTrue,
      );

      await _navigate(tester, 'suppliers');
      final suppliers = tester.widget<PeoplePage>(find.byType(PeoplePage));
      expect(suppliers.kind, PeopleKind.suppliers);
      expect(suppliers.repository, same(selected.people));
      expect(suppliers.role, first.role);

      await _navigate(tester, 'employees');
      final employees = tester.widget<EmployeesPage>(
        find.byType(EmployeesPage),
      );
      expect(employees.repository, same(selected.employees));
      expect(employees.currentMembershipId, first.membershipId);
      expect(employees.role, first.role);
      expect(
        selected.employees.calls.any((call) => call.startsWith('employees:')),
        isTrue,
      );

      await _navigate(tester, 'settings');
      final settings = tester.widget<SettingsPage>(find.byType(SettingsPage));
      expect(settings.repository, same(selected.administration));
      expect(settings.role, first.role);
      expect(
        selected.administration.calls.any(
          (call) => call.startsWith('settings:'),
        ),
        isTrue,
      );

      await _navigate(tester, 'auditLogs');
      final audit = tester.widget<AuditLogsPage>(find.byType(AuditLogsPage));
      expect(audit.repository, same(selected.administration));
      expect(audit.peopleRepository, same(selected.people));
      expect(audit.role, first.role);
      expect(
        selected.administration.calls.any((call) => call.startsWith('audit:')),
        isTrue,
      );
      expect(
        selected.calls.every(
          (call) => call.endsWith(
            ':${first.userId}:${first.organizationId}:${first.membershipId}',
          ),
        ),
        isTrue,
      );

      final originalCalls = List<String>.of(selected.calls);
      auth.memberships = [second];
      auth.emitTokenRefreshed();
      await tester.pumpAndSettle();
      expect(
        find.byType(AuditLogsPage),
        findsNothing,
      ); // new shell starts at Dashboard
      expect(find.text(first.businessName), findsNothing);
      final changed = groups.last;
      expect(changed.actor, same(second));
      expect(changed.services, isNot(same(selected.services)));
      await _navigate(tester, 'products');
      expect(
        tester.widget<ProductsPage>(find.byType(ProductsPage)).repository,
        same(changed.catalog),
      );
      await _navigate(tester, 'employees');
      expect(
        tester
            .widget<EmployeesPage>(find.byType(EmployeesPage))
            .currentMembershipId,
        second.membershipId,
      );
      expect(selected.calls, originalCalls);
      expect(changed.calls, isNotEmpty);
      expect(
        changed.calls.every(
          (call) => call.endsWith(
            ':${second.userId}:${second.organizationId}:${second.membershipId}',
          ),
        ),
        isTrue,
      );
    },
  );
}
