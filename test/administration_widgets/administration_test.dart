import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexapos/app/theme/app_theme.dart';
import 'package:nexapos/core/security/app_role.dart';
import 'package:nexapos/features/administration/domain/administration_models.dart';
import 'package:nexapos/features/administration/domain/administration_repository.dart';
import 'package:nexapos/features/administration/presentation/audit_logs_page.dart';
import 'package:nexapos/features/administration/presentation/business_settings_editor.dart';
import 'package:nexapos/features/catalog/domain/repository_support.dart';

const settings = BusinessSettings(
  organizationId: '00000000-0000-4000-8000-000000000001',
  businessName: 'Test business',
  currency: 'PHP',
  taxBps: 1200,
  revision: 4,
);

class _Repository implements AdministrationRepository {
  int settingsLoads = 0;
  int saves = 0;
  int? expectedRevision;
  BusinessSettingsInput? input;
  Completer<BusinessSettings>? saveCompleter;
  RepositoryFailure? saveFailure;
  BusinessSettings saved = settings;
  final auditRequests = <PageRequest>[];
  AuditFilter? filter;
  bool auditFailure = false;

  @override
  Future<BusinessSettings> loadSettings() async {
    settingsLoads++;
    return saved;
  }

  @override
  Future<BusinessSettings> updateSettings({
    required int expectedRevision,
    required BusinessSettingsInput input,
  }) async {
    saves++;
    this.expectedRevision = expectedRevision;
    this.input = input;
    if (saveFailure != null) {
      throw saveFailure!;
    }
    return saveCompleter != null ? await saveCompleter!.future : saved;
  }

  @override
  Future<DataPage<AuditEntry>> listAudit({
    AuditFilter filter = const AuditFilter(),
    PageRequest page = const PageRequest(),
  }) async {
    auditRequests.add(page);
    this.filter = filter;
    if (auditFailure) {
      throw const RepositoryFailure(
        RepositoryFailureType.permissionDenied,
        'Access is no longer available.',
      );
    }
    return DataPage(
      items: [
        AuditEntry(
          id: 'event-${page.offset}',
          organizationId: settings.organizationId,
          role: 'owner',
          action: 'product.updated',
          entity: 'products',
          occurredAt: DateTime.utc(2026, 10, 9, 23, 30),
          reason: 'Catalog corrected',
          metadata: {'revision': 4},
        ),
      ],
      hasMore: page.offset == 0,
      offset: page.offset,
    );
  }
}

Future<void> _pump(
  WidgetTester tester,
  Widget child, {
  Size size = const Size(800, 1000),
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(body: SafeArea(child: child)),
    ),
  );
  await tester.pumpAndSettle();
}

Widget _editor(
  _Repository repo, {
  AppRole role = AppRole.owner,
  bool preview = false,
  ValueChanged<String>? onSaved,
}) => ListView(
  children: [
    BusinessSettingsEditor(
      repository: repo,
      role: role,
      isPreview: preview,
      onBusinessNameSaved: onSaved,
    ),
  ],
);

Future<void> _showSave(WidgetTester tester) async {
  await tester.scrollUntilVisible(
    find.byKey(const Key('save-business-settings')),
    250,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('preview and cashier never request settings or enable writes', (
    tester,
  ) async {
    final repo = _Repository();
    await _pump(tester, _editor(repo, preview: true));
    expect(repo.settingsLoads, 0);
    expect(
      tester
          .widget<TextFormField>(
            find.byKey(const Key('settings-Business name')),
          )
          .enabled,
      false,
    );
    await _pump(tester, _editor(repo, role: AppRole.cashier));
    expect(repo.settingsLoads, 0);
    expect(repo.saves, 0);
  });

  testWidgets(
    'save uses exact tax and revision and awaits canonical server result',
    (tester) async {
      final repo = _Repository()..saveCompleter = Completer();
      String? confirmedName;
      await _pump(
        tester,
        _editor(repo, onSaved: (name) => confirmedName = name),
      );
      await tester.enterText(
        find.byKey(const Key('settings-Business name')),
        'Edited name',
      );
      await tester.ensureVisible(
        find.byKey(const Key('settings-Tax rate (%)')),
      );
      await tester.enterText(
        find.byKey(const Key('settings-Tax rate (%)')),
        '12.34',
      );
      await _showSave(tester);
      await tester.tap(find.byKey(const Key('save-business-settings')));
      await tester.pump();
      expect(repo.expectedRevision, 4);
      expect(repo.input!.taxBps, 1234);
      expect(confirmedName, isNull);
      expect(find.text('Business settings saved.'), findsNothing);
      expect(
        tester
            .widget<FilledButton>(
              find.byKey(const Key('save-business-settings')),
            )
            .onPressed,
        isNull,
      );
      repo.saveCompleter!.complete(
        const BusinessSettings(
          organizationId: '00000000-0000-4000-8000-000000000001',
          businessName: 'Canonical name',
          currency: 'PHP',
          taxBps: 1234,
          revision: 5,
        ),
      );
      await tester.pumpAndSettle();
      expect(confirmedName, 'Canonical name');
      expect(find.text('Business settings saved.'), findsOneWidget);
      expect(find.text('Saved revision 5'), findsOneWidget);
    },
  );

  testWidgets(
    'stale revision keeps edits and requires reload before another save',
    (tester) async {
      final repo = _Repository()
        ..saveFailure = const RepositoryFailure(
          RepositoryFailureType.conflict,
          'This record changed. Reload before editing.',
        );
      await _pump(tester, _editor(repo));
      await tester.enterText(
        find.byKey(const Key('settings-Business name')),
        'Unsaved name',
      );
      await _showSave(tester);
      await tester.tap(find.byKey(const Key('save-business-settings')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('settings-error')), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(
              find.byKey(const Key('save-business-settings')),
            )
            .onPressed,
        isNull,
      );
      await tester.tap(find.byKey(const Key('reload-business-settings')));
      await tester.pumpAndSettle();
      expect(find.text('Reload saved settings?'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Reload'));
      await tester.pumpAndSettle();
      expect(repo.settingsLoads, 2);
      expect(
        tester
            .widget<TextFormField>(
              find.byKey(const Key('settings-Business name')),
            )
            .controller!
            .text,
        'Test business',
      );
      expect(repo.saves, 1);
    },
  );

  testWidgets('invalid tax does not make a server request', (tester) async {
    final repo = _Repository();
    await _pump(tester, _editor(repo));
    await tester.ensureVisible(find.byKey(const Key('settings-Tax rate (%)')));
    await tester.enterText(
      find.byKey(const Key('settings-Tax rate (%)')),
      '100.01',
    );
    await _showSave(tester);
    await tester.tap(find.byKey(const Key('save-business-settings')));
    await tester.pumpAndSettle();
    expect(repo.saves, 0);
    expect(find.text('Tax must be between 0% and 100%.'), findsOneWidget);
  });

  testWidgets('settings remains usable at 320px', (tester) async {
    final repo = _Repository();
    await _pump(tester, _editor(repo), size: const Size(320, 640));
    await _showSave(tester);
    expect(tester.takeException(), isNull);
  });

  testWidgets('audit preview and cashier do not fetch any events', (
    tester,
  ) async {
    final repo = _Repository();
    await _pump(tester, AuditLogsPage(repository: repo, role: AppRole.owner));
    await _pump(
      tester,
      AuditLogsPage(repository: repo, role: AppRole.cashier, isPreview: false),
    );
    expect(repo.auditRequests, isEmpty);
    expect(find.text('Audit viewer is Not Yet Connected'), findsOneWidget);
  });

  testWidgets('audit paging and filters are scoped server requests', (
    tester,
  ) async {
    final repo = _Repository();
    await _pump(
      tester,
      AuditLogsPage(repository: repo, role: AppRole.owner, isPreview: false),
    );
    expect(repo.auditRequests.single.limit, 20);
    expect(find.textContaining('2026-10-10 07:30:00'), findsOneWidget);
    await tester.tap(find.byKey(const Key('audit-next')));
    await tester.pumpAndSettle();
    expect(repo.auditRequests.last.offset, 1);
    await tester.enterText(
      find.byKey(const Key('audit-action')),
      'product.updated',
    );
    await tester.tap(find.byKey(const Key('filter-audit')));
    await tester.pumpAndSettle();
    expect(repo.filter!.action, 'product.updated');
    expect(repo.auditRequests.last.offset, 0);
    await tester.tap(find.text('product.updated · products'));
    await tester.pumpAndSettle();
    expect(find.textContaining('"revision": 4'), findsOneWidget);
  });

  testWidgets('revoked audit access clears visible records', (tester) async {
    final repo = _Repository();
    await _pump(
      tester,
      AuditLogsPage(repository: repo, role: AppRole.manager, isPreview: false),
    );
    expect(find.text('product.updated · products'), findsOneWidget);
    repo.auditFailure = true;
    await tester.tap(find.byKey(const Key('filter-audit')));
    await tester.pumpAndSettle();
    expect(find.text('product.updated · products'), findsNothing);
    expect(find.text('Access is no longer available.'), findsOneWidget);
  });

  testWidgets('audit filters and event cards fit a 320px phone', (
    tester,
  ) async {
    final repo = _Repository();
    await _pump(
      tester,
      AuditLogsPage(repository: repo, role: AppRole.owner, isPreview: false),
      size: const Size(320, 800),
    );
    expect(tester.takeException(), isNull);
    await tester.enterText(
      find.byKey(const Key('audit-entity')),
      List.filled(81, 'x').join(),
    );
    await tester.tap(find.byKey(const Key('filter-audit')));
    await tester.pumpAndSettle();
    expect(repo.auditRequests, hasLength(1));
    expect(find.byKey(const Key('audit-error')), findsOneWidget);
  });

  testWidgets('switching membership clears old audit filters', (tester) async {
    final first = _Repository();
    final second = _Repository();
    await _pump(
      tester,
      AuditLogsPage(repository: first, role: AppRole.owner, isPreview: false),
    );
    await tester.enterText(find.byKey(const Key('audit-entity')), 'products');
    await tester.tap(find.byKey(const Key('filter-audit')));
    await tester.pumpAndSettle();
    expect(first.filter!.entity, 'products');
    await _pump(
      tester,
      AuditLogsPage(repository: second, role: AppRole.owner, isPreview: false),
    );
    expect(second.filter!.entity, isNull);
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('audit-entity')))
          .controller!
          .text,
      isEmpty,
    );
    expect(tester.takeException(), isNull);
  });
}
