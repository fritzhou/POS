// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'app_database.dart';

// ignore_for_file: type=lint
class $LocalCategoriesTable extends LocalCategories
    with TableInfo<$LocalCategoriesTable, CategoryRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $LocalCategoriesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _organizationIdMeta = const VerificationMeta(
    'organizationId',
  );
  @override
  late final GeneratedColumn<String> organizationId = GeneratedColumn<String>(
    'organization_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _branchIdMeta = const VerificationMeta(
    'branchId',
  );
  @override
  late final GeneratedColumn<String> branchId = GeneratedColumn<String>(
    'branch_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _activeMeta = const VerificationMeta('active');
  @override
  late final GeneratedColumn<bool> active = GeneratedColumn<bool>(
    'active',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("active" IN (0, 1))',
    ),
    defaultValue: const Constant(true),
  );
  static const VerificationMeta _revisionMeta = const VerificationMeta(
    'revision',
  );
  @override
  late final GeneratedColumn<int> revision = GeneratedColumn<int>(
    'revision',
    aliasedName,
    false,
    check: () => ComparableExpr(revision).isBiggerOrEqualValue(0),
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    organizationId,
    branchId,
    id,
    name,
    active,
    revision,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'local_categories';
  @override
  VerificationContext validateIntegrity(
    Insertable<CategoryRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('organization_id')) {
      context.handle(
        _organizationIdMeta,
        organizationId.isAcceptableOrUnknown(
          data['organization_id']!,
          _organizationIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_organizationIdMeta);
    }
    if (data.containsKey('branch_id')) {
      context.handle(
        _branchIdMeta,
        branchId.isAcceptableOrUnknown(data['branch_id']!, _branchIdMeta),
      );
    } else if (isInserting) {
      context.missing(_branchIdMeta);
    }
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('active')) {
      context.handle(
        _activeMeta,
        active.isAcceptableOrUnknown(data['active']!, _activeMeta),
      );
    }
    if (data.containsKey('revision')) {
      context.handle(
        _revisionMeta,
        revision.isAcceptableOrUnknown(data['revision']!, _revisionMeta),
      );
    } else if (isInserting) {
      context.missing(_revisionMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {organizationId, branchId, id};
  @override
  CategoryRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return CategoryRow(
      organizationId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}organization_id'],
      )!,
      branchId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}branch_id'],
      )!,
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      active: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}active'],
      )!,
      revision: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}revision'],
      )!,
    );
  }

  @override
  $LocalCategoriesTable createAlias(String alias) {
    return $LocalCategoriesTable(attachedDatabase, alias);
  }
}

class CategoryRow extends DataClass implements Insertable<CategoryRow> {
  final String organizationId;
  final String branchId;
  final String id;
  final String name;
  final bool active;
  final int revision;
  const CategoryRow({
    required this.organizationId,
    required this.branchId,
    required this.id,
    required this.name,
    required this.active,
    required this.revision,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['organization_id'] = Variable<String>(organizationId);
    map['branch_id'] = Variable<String>(branchId);
    map['id'] = Variable<String>(id);
    map['name'] = Variable<String>(name);
    map['active'] = Variable<bool>(active);
    map['revision'] = Variable<int>(revision);
    return map;
  }

  LocalCategoriesCompanion toCompanion(bool nullToAbsent) {
    return LocalCategoriesCompanion(
      organizationId: Value(organizationId),
      branchId: Value(branchId),
      id: Value(id),
      name: Value(name),
      active: Value(active),
      revision: Value(revision),
    );
  }

  factory CategoryRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return CategoryRow(
      organizationId: serializer.fromJson<String>(json['organizationId']),
      branchId: serializer.fromJson<String>(json['branchId']),
      id: serializer.fromJson<String>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      active: serializer.fromJson<bool>(json['active']),
      revision: serializer.fromJson<int>(json['revision']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'organizationId': serializer.toJson<String>(organizationId),
      'branchId': serializer.toJson<String>(branchId),
      'id': serializer.toJson<String>(id),
      'name': serializer.toJson<String>(name),
      'active': serializer.toJson<bool>(active),
      'revision': serializer.toJson<int>(revision),
    };
  }

  CategoryRow copyWith({
    String? organizationId,
    String? branchId,
    String? id,
    String? name,
    bool? active,
    int? revision,
  }) => CategoryRow(
    organizationId: organizationId ?? this.organizationId,
    branchId: branchId ?? this.branchId,
    id: id ?? this.id,
    name: name ?? this.name,
    active: active ?? this.active,
    revision: revision ?? this.revision,
  );
  CategoryRow copyWithCompanion(LocalCategoriesCompanion data) {
    return CategoryRow(
      organizationId: data.organizationId.present
          ? data.organizationId.value
          : this.organizationId,
      branchId: data.branchId.present ? data.branchId.value : this.branchId,
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      active: data.active.present ? data.active.value : this.active,
      revision: data.revision.present ? data.revision.value : this.revision,
    );
  }

  @override
  String toString() {
    return (StringBuffer('CategoryRow(')
          ..write('organizationId: $organizationId, ')
          ..write('branchId: $branchId, ')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('active: $active, ')
          ..write('revision: $revision')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(organizationId, branchId, id, name, active, revision);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CategoryRow &&
          other.organizationId == this.organizationId &&
          other.branchId == this.branchId &&
          other.id == this.id &&
          other.name == this.name &&
          other.active == this.active &&
          other.revision == this.revision);
}

class LocalCategoriesCompanion extends UpdateCompanion<CategoryRow> {
  final Value<String> organizationId;
  final Value<String> branchId;
  final Value<String> id;
  final Value<String> name;
  final Value<bool> active;
  final Value<int> revision;
  final Value<int> rowid;
  const LocalCategoriesCompanion({
    this.organizationId = const Value.absent(),
    this.branchId = const Value.absent(),
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.active = const Value.absent(),
    this.revision = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  LocalCategoriesCompanion.insert({
    required String organizationId,
    required String branchId,
    required String id,
    required String name,
    this.active = const Value.absent(),
    required int revision,
    this.rowid = const Value.absent(),
  }) : organizationId = Value(organizationId),
       branchId = Value(branchId),
       id = Value(id),
       name = Value(name),
       revision = Value(revision);
  static Insertable<CategoryRow> custom({
    Expression<String>? organizationId,
    Expression<String>? branchId,
    Expression<String>? id,
    Expression<String>? name,
    Expression<bool>? active,
    Expression<int>? revision,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (organizationId != null) 'organization_id': organizationId,
      if (branchId != null) 'branch_id': branchId,
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (active != null) 'active': active,
      if (revision != null) 'revision': revision,
      if (rowid != null) 'rowid': rowid,
    });
  }

  LocalCategoriesCompanion copyWith({
    Value<String>? organizationId,
    Value<String>? branchId,
    Value<String>? id,
    Value<String>? name,
    Value<bool>? active,
    Value<int>? revision,
    Value<int>? rowid,
  }) {
    return LocalCategoriesCompanion(
      organizationId: organizationId ?? this.organizationId,
      branchId: branchId ?? this.branchId,
      id: id ?? this.id,
      name: name ?? this.name,
      active: active ?? this.active,
      revision: revision ?? this.revision,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (organizationId.present) {
      map['organization_id'] = Variable<String>(organizationId.value);
    }
    if (branchId.present) {
      map['branch_id'] = Variable<String>(branchId.value);
    }
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (active.present) {
      map['active'] = Variable<bool>(active.value);
    }
    if (revision.present) {
      map['revision'] = Variable<int>(revision.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('LocalCategoriesCompanion(')
          ..write('organizationId: $organizationId, ')
          ..write('branchId: $branchId, ')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('active: $active, ')
          ..write('revision: $revision, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $LocalProductsTable extends LocalProducts
    with TableInfo<$LocalProductsTable, ProductRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $LocalProductsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _organizationIdMeta = const VerificationMeta(
    'organizationId',
  );
  @override
  late final GeneratedColumn<String> organizationId = GeneratedColumn<String>(
    'organization_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _branchIdMeta = const VerificationMeta(
    'branchId',
  );
  @override
  late final GeneratedColumn<String> branchId = GeneratedColumn<String>(
    'branch_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _categoryIdMeta = const VerificationMeta(
    'categoryId',
  );
  @override
  late final GeneratedColumn<String> categoryId = GeneratedColumn<String>(
    'category_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _skuMeta = const VerificationMeta('sku');
  @override
  late final GeneratedColumn<String> sku = GeneratedColumn<String>(
    'sku',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _barcodeMeta = const VerificationMeta(
    'barcode',
  );
  @override
  late final GeneratedColumn<String> barcode = GeneratedColumn<String>(
    'barcode',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _currencyMeta = const VerificationMeta(
    'currency',
  );
  @override
  late final GeneratedColumn<String> currency = GeneratedColumn<String>(
    'currency',
    aliasedName,
    false,
    additionalChecks: GeneratedColumn.checkTextLength(
      minTextLength: 3,
      maxTextLength: 3,
    ),
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _costMinorMeta = const VerificationMeta(
    'costMinor',
  );
  @override
  late final GeneratedColumn<int> costMinor = GeneratedColumn<int>(
    'cost_minor',
    aliasedName,
    false,
    check: () => ComparableExpr(costMinor).isBiggerOrEqualValue(0),
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _priceMinorMeta = const VerificationMeta(
    'priceMinor',
  );
  @override
  late final GeneratedColumn<int> priceMinor = GeneratedColumn<int>(
    'price_minor',
    aliasedName,
    false,
    check: () => ComparableExpr(priceMinor).isBiggerOrEqualValue(0),
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _reorderLevelMeta = const VerificationMeta(
    'reorderLevel',
  );
  @override
  late final GeneratedColumn<int> reorderLevel = GeneratedColumn<int>(
    'reorder_level',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _unitMeta = const VerificationMeta('unit');
  @override
  late final GeneratedColumn<String> unit = GeneratedColumn<String>(
    'unit',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('unit'),
  );
  static const VerificationMeta _activeMeta = const VerificationMeta('active');
  @override
  late final GeneratedColumn<bool> active = GeneratedColumn<bool>(
    'active',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("active" IN (0, 1))',
    ),
    defaultValue: const Constant(true),
  );
  static const VerificationMeta _revisionMeta = const VerificationMeta(
    'revision',
  );
  @override
  late final GeneratedColumn<int> revision = GeneratedColumn<int>(
    'revision',
    aliasedName,
    false,
    check: () => ComparableExpr(revision).isBiggerOrEqualValue(0),
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    organizationId,
    branchId,
    id,
    categoryId,
    sku,
    barcode,
    name,
    currency,
    costMinor,
    priceMinor,
    reorderLevel,
    unit,
    active,
    revision,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'local_products';
  @override
  VerificationContext validateIntegrity(
    Insertable<ProductRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('organization_id')) {
      context.handle(
        _organizationIdMeta,
        organizationId.isAcceptableOrUnknown(
          data['organization_id']!,
          _organizationIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_organizationIdMeta);
    }
    if (data.containsKey('branch_id')) {
      context.handle(
        _branchIdMeta,
        branchId.isAcceptableOrUnknown(data['branch_id']!, _branchIdMeta),
      );
    } else if (isInserting) {
      context.missing(_branchIdMeta);
    }
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('category_id')) {
      context.handle(
        _categoryIdMeta,
        categoryId.isAcceptableOrUnknown(data['category_id']!, _categoryIdMeta),
      );
    }
    if (data.containsKey('sku')) {
      context.handle(
        _skuMeta,
        sku.isAcceptableOrUnknown(data['sku']!, _skuMeta),
      );
    } else if (isInserting) {
      context.missing(_skuMeta);
    }
    if (data.containsKey('barcode')) {
      context.handle(
        _barcodeMeta,
        barcode.isAcceptableOrUnknown(data['barcode']!, _barcodeMeta),
      );
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('currency')) {
      context.handle(
        _currencyMeta,
        currency.isAcceptableOrUnknown(data['currency']!, _currencyMeta),
      );
    } else if (isInserting) {
      context.missing(_currencyMeta);
    }
    if (data.containsKey('cost_minor')) {
      context.handle(
        _costMinorMeta,
        costMinor.isAcceptableOrUnknown(data['cost_minor']!, _costMinorMeta),
      );
    } else if (isInserting) {
      context.missing(_costMinorMeta);
    }
    if (data.containsKey('price_minor')) {
      context.handle(
        _priceMinorMeta,
        priceMinor.isAcceptableOrUnknown(data['price_minor']!, _priceMinorMeta),
      );
    } else if (isInserting) {
      context.missing(_priceMinorMeta);
    }
    if (data.containsKey('reorder_level')) {
      context.handle(
        _reorderLevelMeta,
        reorderLevel.isAcceptableOrUnknown(
          data['reorder_level']!,
          _reorderLevelMeta,
        ),
      );
    }
    if (data.containsKey('unit')) {
      context.handle(
        _unitMeta,
        unit.isAcceptableOrUnknown(data['unit']!, _unitMeta),
      );
    }
    if (data.containsKey('active')) {
      context.handle(
        _activeMeta,
        active.isAcceptableOrUnknown(data['active']!, _activeMeta),
      );
    }
    if (data.containsKey('revision')) {
      context.handle(
        _revisionMeta,
        revision.isAcceptableOrUnknown(data['revision']!, _revisionMeta),
      );
    } else if (isInserting) {
      context.missing(_revisionMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {organizationId, branchId, id};
  @override
  List<Set<GeneratedColumn>> get uniqueKeys => [
    {organizationId, branchId, sku},
  ];
  @override
  ProductRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ProductRow(
      organizationId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}organization_id'],
      )!,
      branchId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}branch_id'],
      )!,
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      categoryId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}category_id'],
      ),
      sku: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}sku'],
      )!,
      barcode: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}barcode'],
      ),
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      currency: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}currency'],
      )!,
      costMinor: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}cost_minor'],
      )!,
      priceMinor: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}price_minor'],
      )!,
      reorderLevel: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}reorder_level'],
      )!,
      unit: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}unit'],
      )!,
      active: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}active'],
      )!,
      revision: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}revision'],
      )!,
    );
  }

  @override
  $LocalProductsTable createAlias(String alias) {
    return $LocalProductsTable(attachedDatabase, alias);
  }
}

class ProductRow extends DataClass implements Insertable<ProductRow> {
  final String organizationId;
  final String branchId;
  final String id;
  final String? categoryId;
  final String sku;
  final String? barcode;
  final String name;
  final String currency;
  final int costMinor;
  final int priceMinor;
  final int reorderLevel;
  final String unit;
  final bool active;
  final int revision;
  const ProductRow({
    required this.organizationId,
    required this.branchId,
    required this.id,
    this.categoryId,
    required this.sku,
    this.barcode,
    required this.name,
    required this.currency,
    required this.costMinor,
    required this.priceMinor,
    required this.reorderLevel,
    required this.unit,
    required this.active,
    required this.revision,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['organization_id'] = Variable<String>(organizationId);
    map['branch_id'] = Variable<String>(branchId);
    map['id'] = Variable<String>(id);
    if (!nullToAbsent || categoryId != null) {
      map['category_id'] = Variable<String>(categoryId);
    }
    map['sku'] = Variable<String>(sku);
    if (!nullToAbsent || barcode != null) {
      map['barcode'] = Variable<String>(barcode);
    }
    map['name'] = Variable<String>(name);
    map['currency'] = Variable<String>(currency);
    map['cost_minor'] = Variable<int>(costMinor);
    map['price_minor'] = Variable<int>(priceMinor);
    map['reorder_level'] = Variable<int>(reorderLevel);
    map['unit'] = Variable<String>(unit);
    map['active'] = Variable<bool>(active);
    map['revision'] = Variable<int>(revision);
    return map;
  }

  LocalProductsCompanion toCompanion(bool nullToAbsent) {
    return LocalProductsCompanion(
      organizationId: Value(organizationId),
      branchId: Value(branchId),
      id: Value(id),
      categoryId: categoryId == null && nullToAbsent
          ? const Value.absent()
          : Value(categoryId),
      sku: Value(sku),
      barcode: barcode == null && nullToAbsent
          ? const Value.absent()
          : Value(barcode),
      name: Value(name),
      currency: Value(currency),
      costMinor: Value(costMinor),
      priceMinor: Value(priceMinor),
      reorderLevel: Value(reorderLevel),
      unit: Value(unit),
      active: Value(active),
      revision: Value(revision),
    );
  }

  factory ProductRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ProductRow(
      organizationId: serializer.fromJson<String>(json['organizationId']),
      branchId: serializer.fromJson<String>(json['branchId']),
      id: serializer.fromJson<String>(json['id']),
      categoryId: serializer.fromJson<String?>(json['categoryId']),
      sku: serializer.fromJson<String>(json['sku']),
      barcode: serializer.fromJson<String?>(json['barcode']),
      name: serializer.fromJson<String>(json['name']),
      currency: serializer.fromJson<String>(json['currency']),
      costMinor: serializer.fromJson<int>(json['costMinor']),
      priceMinor: serializer.fromJson<int>(json['priceMinor']),
      reorderLevel: serializer.fromJson<int>(json['reorderLevel']),
      unit: serializer.fromJson<String>(json['unit']),
      active: serializer.fromJson<bool>(json['active']),
      revision: serializer.fromJson<int>(json['revision']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'organizationId': serializer.toJson<String>(organizationId),
      'branchId': serializer.toJson<String>(branchId),
      'id': serializer.toJson<String>(id),
      'categoryId': serializer.toJson<String?>(categoryId),
      'sku': serializer.toJson<String>(sku),
      'barcode': serializer.toJson<String?>(barcode),
      'name': serializer.toJson<String>(name),
      'currency': serializer.toJson<String>(currency),
      'costMinor': serializer.toJson<int>(costMinor),
      'priceMinor': serializer.toJson<int>(priceMinor),
      'reorderLevel': serializer.toJson<int>(reorderLevel),
      'unit': serializer.toJson<String>(unit),
      'active': serializer.toJson<bool>(active),
      'revision': serializer.toJson<int>(revision),
    };
  }

  ProductRow copyWith({
    String? organizationId,
    String? branchId,
    String? id,
    Value<String?> categoryId = const Value.absent(),
    String? sku,
    Value<String?> barcode = const Value.absent(),
    String? name,
    String? currency,
    int? costMinor,
    int? priceMinor,
    int? reorderLevel,
    String? unit,
    bool? active,
    int? revision,
  }) => ProductRow(
    organizationId: organizationId ?? this.organizationId,
    branchId: branchId ?? this.branchId,
    id: id ?? this.id,
    categoryId: categoryId.present ? categoryId.value : this.categoryId,
    sku: sku ?? this.sku,
    barcode: barcode.present ? barcode.value : this.barcode,
    name: name ?? this.name,
    currency: currency ?? this.currency,
    costMinor: costMinor ?? this.costMinor,
    priceMinor: priceMinor ?? this.priceMinor,
    reorderLevel: reorderLevel ?? this.reorderLevel,
    unit: unit ?? this.unit,
    active: active ?? this.active,
    revision: revision ?? this.revision,
  );
  ProductRow copyWithCompanion(LocalProductsCompanion data) {
    return ProductRow(
      organizationId: data.organizationId.present
          ? data.organizationId.value
          : this.organizationId,
      branchId: data.branchId.present ? data.branchId.value : this.branchId,
      id: data.id.present ? data.id.value : this.id,
      categoryId: data.categoryId.present
          ? data.categoryId.value
          : this.categoryId,
      sku: data.sku.present ? data.sku.value : this.sku,
      barcode: data.barcode.present ? data.barcode.value : this.barcode,
      name: data.name.present ? data.name.value : this.name,
      currency: data.currency.present ? data.currency.value : this.currency,
      costMinor: data.costMinor.present ? data.costMinor.value : this.costMinor,
      priceMinor: data.priceMinor.present
          ? data.priceMinor.value
          : this.priceMinor,
      reorderLevel: data.reorderLevel.present
          ? data.reorderLevel.value
          : this.reorderLevel,
      unit: data.unit.present ? data.unit.value : this.unit,
      active: data.active.present ? data.active.value : this.active,
      revision: data.revision.present ? data.revision.value : this.revision,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ProductRow(')
          ..write('organizationId: $organizationId, ')
          ..write('branchId: $branchId, ')
          ..write('id: $id, ')
          ..write('categoryId: $categoryId, ')
          ..write('sku: $sku, ')
          ..write('barcode: $barcode, ')
          ..write('name: $name, ')
          ..write('currency: $currency, ')
          ..write('costMinor: $costMinor, ')
          ..write('priceMinor: $priceMinor, ')
          ..write('reorderLevel: $reorderLevel, ')
          ..write('unit: $unit, ')
          ..write('active: $active, ')
          ..write('revision: $revision')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    organizationId,
    branchId,
    id,
    categoryId,
    sku,
    barcode,
    name,
    currency,
    costMinor,
    priceMinor,
    reorderLevel,
    unit,
    active,
    revision,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ProductRow &&
          other.organizationId == this.organizationId &&
          other.branchId == this.branchId &&
          other.id == this.id &&
          other.categoryId == this.categoryId &&
          other.sku == this.sku &&
          other.barcode == this.barcode &&
          other.name == this.name &&
          other.currency == this.currency &&
          other.costMinor == this.costMinor &&
          other.priceMinor == this.priceMinor &&
          other.reorderLevel == this.reorderLevel &&
          other.unit == this.unit &&
          other.active == this.active &&
          other.revision == this.revision);
}

class LocalProductsCompanion extends UpdateCompanion<ProductRow> {
  final Value<String> organizationId;
  final Value<String> branchId;
  final Value<String> id;
  final Value<String?> categoryId;
  final Value<String> sku;
  final Value<String?> barcode;
  final Value<String> name;
  final Value<String> currency;
  final Value<int> costMinor;
  final Value<int> priceMinor;
  final Value<int> reorderLevel;
  final Value<String> unit;
  final Value<bool> active;
  final Value<int> revision;
  final Value<int> rowid;
  const LocalProductsCompanion({
    this.organizationId = const Value.absent(),
    this.branchId = const Value.absent(),
    this.id = const Value.absent(),
    this.categoryId = const Value.absent(),
    this.sku = const Value.absent(),
    this.barcode = const Value.absent(),
    this.name = const Value.absent(),
    this.currency = const Value.absent(),
    this.costMinor = const Value.absent(),
    this.priceMinor = const Value.absent(),
    this.reorderLevel = const Value.absent(),
    this.unit = const Value.absent(),
    this.active = const Value.absent(),
    this.revision = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  LocalProductsCompanion.insert({
    required String organizationId,
    required String branchId,
    required String id,
    this.categoryId = const Value.absent(),
    required String sku,
    this.barcode = const Value.absent(),
    required String name,
    required String currency,
    required int costMinor,
    required int priceMinor,
    this.reorderLevel = const Value.absent(),
    this.unit = const Value.absent(),
    this.active = const Value.absent(),
    required int revision,
    this.rowid = const Value.absent(),
  }) : organizationId = Value(organizationId),
       branchId = Value(branchId),
       id = Value(id),
       sku = Value(sku),
       name = Value(name),
       currency = Value(currency),
       costMinor = Value(costMinor),
       priceMinor = Value(priceMinor),
       revision = Value(revision);
  static Insertable<ProductRow> custom({
    Expression<String>? organizationId,
    Expression<String>? branchId,
    Expression<String>? id,
    Expression<String>? categoryId,
    Expression<String>? sku,
    Expression<String>? barcode,
    Expression<String>? name,
    Expression<String>? currency,
    Expression<int>? costMinor,
    Expression<int>? priceMinor,
    Expression<int>? reorderLevel,
    Expression<String>? unit,
    Expression<bool>? active,
    Expression<int>? revision,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (organizationId != null) 'organization_id': organizationId,
      if (branchId != null) 'branch_id': branchId,
      if (id != null) 'id': id,
      if (categoryId != null) 'category_id': categoryId,
      if (sku != null) 'sku': sku,
      if (barcode != null) 'barcode': barcode,
      if (name != null) 'name': name,
      if (currency != null) 'currency': currency,
      if (costMinor != null) 'cost_minor': costMinor,
      if (priceMinor != null) 'price_minor': priceMinor,
      if (reorderLevel != null) 'reorder_level': reorderLevel,
      if (unit != null) 'unit': unit,
      if (active != null) 'active': active,
      if (revision != null) 'revision': revision,
      if (rowid != null) 'rowid': rowid,
    });
  }

  LocalProductsCompanion copyWith({
    Value<String>? organizationId,
    Value<String>? branchId,
    Value<String>? id,
    Value<String?>? categoryId,
    Value<String>? sku,
    Value<String?>? barcode,
    Value<String>? name,
    Value<String>? currency,
    Value<int>? costMinor,
    Value<int>? priceMinor,
    Value<int>? reorderLevel,
    Value<String>? unit,
    Value<bool>? active,
    Value<int>? revision,
    Value<int>? rowid,
  }) {
    return LocalProductsCompanion(
      organizationId: organizationId ?? this.organizationId,
      branchId: branchId ?? this.branchId,
      id: id ?? this.id,
      categoryId: categoryId ?? this.categoryId,
      sku: sku ?? this.sku,
      barcode: barcode ?? this.barcode,
      name: name ?? this.name,
      currency: currency ?? this.currency,
      costMinor: costMinor ?? this.costMinor,
      priceMinor: priceMinor ?? this.priceMinor,
      reorderLevel: reorderLevel ?? this.reorderLevel,
      unit: unit ?? this.unit,
      active: active ?? this.active,
      revision: revision ?? this.revision,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (organizationId.present) {
      map['organization_id'] = Variable<String>(organizationId.value);
    }
    if (branchId.present) {
      map['branch_id'] = Variable<String>(branchId.value);
    }
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (categoryId.present) {
      map['category_id'] = Variable<String>(categoryId.value);
    }
    if (sku.present) {
      map['sku'] = Variable<String>(sku.value);
    }
    if (barcode.present) {
      map['barcode'] = Variable<String>(barcode.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (currency.present) {
      map['currency'] = Variable<String>(currency.value);
    }
    if (costMinor.present) {
      map['cost_minor'] = Variable<int>(costMinor.value);
    }
    if (priceMinor.present) {
      map['price_minor'] = Variable<int>(priceMinor.value);
    }
    if (reorderLevel.present) {
      map['reorder_level'] = Variable<int>(reorderLevel.value);
    }
    if (unit.present) {
      map['unit'] = Variable<String>(unit.value);
    }
    if (active.present) {
      map['active'] = Variable<bool>(active.value);
    }
    if (revision.present) {
      map['revision'] = Variable<int>(revision.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('LocalProductsCompanion(')
          ..write('organizationId: $organizationId, ')
          ..write('branchId: $branchId, ')
          ..write('id: $id, ')
          ..write('categoryId: $categoryId, ')
          ..write('sku: $sku, ')
          ..write('barcode: $barcode, ')
          ..write('name: $name, ')
          ..write('currency: $currency, ')
          ..write('costMinor: $costMinor, ')
          ..write('priceMinor: $priceMinor, ')
          ..write('reorderLevel: $reorderLevel, ')
          ..write('unit: $unit, ')
          ..write('active: $active, ')
          ..write('revision: $revision, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $LocalProductPricesTable extends LocalProductPrices
    with TableInfo<$LocalProductPricesTable, PriceRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $LocalProductPricesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _organizationIdMeta = const VerificationMeta(
    'organizationId',
  );
  @override
  late final GeneratedColumn<String> organizationId = GeneratedColumn<String>(
    'organization_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _branchIdMeta = const VerificationMeta(
    'branchId',
  );
  @override
  late final GeneratedColumn<String> branchId = GeneratedColumn<String>(
    'branch_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _productIdMeta = const VerificationMeta(
    'productId',
  );
  @override
  late final GeneratedColumn<String> productId = GeneratedColumn<String>(
    'product_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _currencyMeta = const VerificationMeta(
    'currency',
  );
  @override
  late final GeneratedColumn<String> currency = GeneratedColumn<String>(
    'currency',
    aliasedName,
    false,
    additionalChecks: GeneratedColumn.checkTextLength(
      minTextLength: 3,
      maxTextLength: 3,
    ),
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _priceMinorMeta = const VerificationMeta(
    'priceMinor',
  );
  @override
  late final GeneratedColumn<int> priceMinor = GeneratedColumn<int>(
    'price_minor',
    aliasedName,
    false,
    check: () => ComparableExpr(priceMinor).isBiggerOrEqualValue(0),
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _effectiveAtMeta = const VerificationMeta(
    'effectiveAt',
  );
  @override
  late final GeneratedColumn<DateTime> effectiveAt = GeneratedColumn<DateTime>(
    'effective_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _revisionMeta = const VerificationMeta(
    'revision',
  );
  @override
  late final GeneratedColumn<int> revision = GeneratedColumn<int>(
    'revision',
    aliasedName,
    false,
    check: () => ComparableExpr(revision).isBiggerOrEqualValue(0),
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    organizationId,
    branchId,
    id,
    productId,
    currency,
    priceMinor,
    effectiveAt,
    revision,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'local_product_prices';
  @override
  VerificationContext validateIntegrity(
    Insertable<PriceRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('organization_id')) {
      context.handle(
        _organizationIdMeta,
        organizationId.isAcceptableOrUnknown(
          data['organization_id']!,
          _organizationIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_organizationIdMeta);
    }
    if (data.containsKey('branch_id')) {
      context.handle(
        _branchIdMeta,
        branchId.isAcceptableOrUnknown(data['branch_id']!, _branchIdMeta),
      );
    } else if (isInserting) {
      context.missing(_branchIdMeta);
    }
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('product_id')) {
      context.handle(
        _productIdMeta,
        productId.isAcceptableOrUnknown(data['product_id']!, _productIdMeta),
      );
    } else if (isInserting) {
      context.missing(_productIdMeta);
    }
    if (data.containsKey('currency')) {
      context.handle(
        _currencyMeta,
        currency.isAcceptableOrUnknown(data['currency']!, _currencyMeta),
      );
    } else if (isInserting) {
      context.missing(_currencyMeta);
    }
    if (data.containsKey('price_minor')) {
      context.handle(
        _priceMinorMeta,
        priceMinor.isAcceptableOrUnknown(data['price_minor']!, _priceMinorMeta),
      );
    } else if (isInserting) {
      context.missing(_priceMinorMeta);
    }
    if (data.containsKey('effective_at')) {
      context.handle(
        _effectiveAtMeta,
        effectiveAt.isAcceptableOrUnknown(
          data['effective_at']!,
          _effectiveAtMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_effectiveAtMeta);
    }
    if (data.containsKey('revision')) {
      context.handle(
        _revisionMeta,
        revision.isAcceptableOrUnknown(data['revision']!, _revisionMeta),
      );
    } else if (isInserting) {
      context.missing(_revisionMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {organizationId, branchId, id};
  @override
  PriceRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return PriceRow(
      organizationId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}organization_id'],
      )!,
      branchId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}branch_id'],
      )!,
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      productId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}product_id'],
      )!,
      currency: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}currency'],
      )!,
      priceMinor: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}price_minor'],
      )!,
      effectiveAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}effective_at'],
      )!,
      revision: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}revision'],
      )!,
    );
  }

  @override
  $LocalProductPricesTable createAlias(String alias) {
    return $LocalProductPricesTable(attachedDatabase, alias);
  }
}

class PriceRow extends DataClass implements Insertable<PriceRow> {
  final String organizationId;
  final String branchId;
  final String id;
  final String productId;
  final String currency;
  final int priceMinor;
  final DateTime effectiveAt;
  final int revision;
  const PriceRow({
    required this.organizationId,
    required this.branchId,
    required this.id,
    required this.productId,
    required this.currency,
    required this.priceMinor,
    required this.effectiveAt,
    required this.revision,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['organization_id'] = Variable<String>(organizationId);
    map['branch_id'] = Variable<String>(branchId);
    map['id'] = Variable<String>(id);
    map['product_id'] = Variable<String>(productId);
    map['currency'] = Variable<String>(currency);
    map['price_minor'] = Variable<int>(priceMinor);
    map['effective_at'] = Variable<DateTime>(effectiveAt);
    map['revision'] = Variable<int>(revision);
    return map;
  }

  LocalProductPricesCompanion toCompanion(bool nullToAbsent) {
    return LocalProductPricesCompanion(
      organizationId: Value(organizationId),
      branchId: Value(branchId),
      id: Value(id),
      productId: Value(productId),
      currency: Value(currency),
      priceMinor: Value(priceMinor),
      effectiveAt: Value(effectiveAt),
      revision: Value(revision),
    );
  }

  factory PriceRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return PriceRow(
      organizationId: serializer.fromJson<String>(json['organizationId']),
      branchId: serializer.fromJson<String>(json['branchId']),
      id: serializer.fromJson<String>(json['id']),
      productId: serializer.fromJson<String>(json['productId']),
      currency: serializer.fromJson<String>(json['currency']),
      priceMinor: serializer.fromJson<int>(json['priceMinor']),
      effectiveAt: serializer.fromJson<DateTime>(json['effectiveAt']),
      revision: serializer.fromJson<int>(json['revision']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'organizationId': serializer.toJson<String>(organizationId),
      'branchId': serializer.toJson<String>(branchId),
      'id': serializer.toJson<String>(id),
      'productId': serializer.toJson<String>(productId),
      'currency': serializer.toJson<String>(currency),
      'priceMinor': serializer.toJson<int>(priceMinor),
      'effectiveAt': serializer.toJson<DateTime>(effectiveAt),
      'revision': serializer.toJson<int>(revision),
    };
  }

  PriceRow copyWith({
    String? organizationId,
    String? branchId,
    String? id,
    String? productId,
    String? currency,
    int? priceMinor,
    DateTime? effectiveAt,
    int? revision,
  }) => PriceRow(
    organizationId: organizationId ?? this.organizationId,
    branchId: branchId ?? this.branchId,
    id: id ?? this.id,
    productId: productId ?? this.productId,
    currency: currency ?? this.currency,
    priceMinor: priceMinor ?? this.priceMinor,
    effectiveAt: effectiveAt ?? this.effectiveAt,
    revision: revision ?? this.revision,
  );
  PriceRow copyWithCompanion(LocalProductPricesCompanion data) {
    return PriceRow(
      organizationId: data.organizationId.present
          ? data.organizationId.value
          : this.organizationId,
      branchId: data.branchId.present ? data.branchId.value : this.branchId,
      id: data.id.present ? data.id.value : this.id,
      productId: data.productId.present ? data.productId.value : this.productId,
      currency: data.currency.present ? data.currency.value : this.currency,
      priceMinor: data.priceMinor.present
          ? data.priceMinor.value
          : this.priceMinor,
      effectiveAt: data.effectiveAt.present
          ? data.effectiveAt.value
          : this.effectiveAt,
      revision: data.revision.present ? data.revision.value : this.revision,
    );
  }

  @override
  String toString() {
    return (StringBuffer('PriceRow(')
          ..write('organizationId: $organizationId, ')
          ..write('branchId: $branchId, ')
          ..write('id: $id, ')
          ..write('productId: $productId, ')
          ..write('currency: $currency, ')
          ..write('priceMinor: $priceMinor, ')
          ..write('effectiveAt: $effectiveAt, ')
          ..write('revision: $revision')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    organizationId,
    branchId,
    id,
    productId,
    currency,
    priceMinor,
    effectiveAt,
    revision,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is PriceRow &&
          other.organizationId == this.organizationId &&
          other.branchId == this.branchId &&
          other.id == this.id &&
          other.productId == this.productId &&
          other.currency == this.currency &&
          other.priceMinor == this.priceMinor &&
          other.effectiveAt == this.effectiveAt &&
          other.revision == this.revision);
}

class LocalProductPricesCompanion extends UpdateCompanion<PriceRow> {
  final Value<String> organizationId;
  final Value<String> branchId;
  final Value<String> id;
  final Value<String> productId;
  final Value<String> currency;
  final Value<int> priceMinor;
  final Value<DateTime> effectiveAt;
  final Value<int> revision;
  final Value<int> rowid;
  const LocalProductPricesCompanion({
    this.organizationId = const Value.absent(),
    this.branchId = const Value.absent(),
    this.id = const Value.absent(),
    this.productId = const Value.absent(),
    this.currency = const Value.absent(),
    this.priceMinor = const Value.absent(),
    this.effectiveAt = const Value.absent(),
    this.revision = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  LocalProductPricesCompanion.insert({
    required String organizationId,
    required String branchId,
    required String id,
    required String productId,
    required String currency,
    required int priceMinor,
    required DateTime effectiveAt,
    required int revision,
    this.rowid = const Value.absent(),
  }) : organizationId = Value(organizationId),
       branchId = Value(branchId),
       id = Value(id),
       productId = Value(productId),
       currency = Value(currency),
       priceMinor = Value(priceMinor),
       effectiveAt = Value(effectiveAt),
       revision = Value(revision);
  static Insertable<PriceRow> custom({
    Expression<String>? organizationId,
    Expression<String>? branchId,
    Expression<String>? id,
    Expression<String>? productId,
    Expression<String>? currency,
    Expression<int>? priceMinor,
    Expression<DateTime>? effectiveAt,
    Expression<int>? revision,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (organizationId != null) 'organization_id': organizationId,
      if (branchId != null) 'branch_id': branchId,
      if (id != null) 'id': id,
      if (productId != null) 'product_id': productId,
      if (currency != null) 'currency': currency,
      if (priceMinor != null) 'price_minor': priceMinor,
      if (effectiveAt != null) 'effective_at': effectiveAt,
      if (revision != null) 'revision': revision,
      if (rowid != null) 'rowid': rowid,
    });
  }

  LocalProductPricesCompanion copyWith({
    Value<String>? organizationId,
    Value<String>? branchId,
    Value<String>? id,
    Value<String>? productId,
    Value<String>? currency,
    Value<int>? priceMinor,
    Value<DateTime>? effectiveAt,
    Value<int>? revision,
    Value<int>? rowid,
  }) {
    return LocalProductPricesCompanion(
      organizationId: organizationId ?? this.organizationId,
      branchId: branchId ?? this.branchId,
      id: id ?? this.id,
      productId: productId ?? this.productId,
      currency: currency ?? this.currency,
      priceMinor: priceMinor ?? this.priceMinor,
      effectiveAt: effectiveAt ?? this.effectiveAt,
      revision: revision ?? this.revision,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (organizationId.present) {
      map['organization_id'] = Variable<String>(organizationId.value);
    }
    if (branchId.present) {
      map['branch_id'] = Variable<String>(branchId.value);
    }
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (productId.present) {
      map['product_id'] = Variable<String>(productId.value);
    }
    if (currency.present) {
      map['currency'] = Variable<String>(currency.value);
    }
    if (priceMinor.present) {
      map['price_minor'] = Variable<int>(priceMinor.value);
    }
    if (effectiveAt.present) {
      map['effective_at'] = Variable<DateTime>(effectiveAt.value);
    }
    if (revision.present) {
      map['revision'] = Variable<int>(revision.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('LocalProductPricesCompanion(')
          ..write('organizationId: $organizationId, ')
          ..write('branchId: $branchId, ')
          ..write('id: $id, ')
          ..write('productId: $productId, ')
          ..write('currency: $currency, ')
          ..write('priceMinor: $priceMinor, ')
          ..write('effectiveAt: $effectiveAt, ')
          ..write('revision: $revision, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $LocalInventorySnapshotsTable extends LocalInventorySnapshots
    with TableInfo<$LocalInventorySnapshotsTable, InventorySnapshotRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $LocalInventorySnapshotsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _organizationIdMeta = const VerificationMeta(
    'organizationId',
  );
  @override
  late final GeneratedColumn<String> organizationId = GeneratedColumn<String>(
    'organization_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _branchIdMeta = const VerificationMeta(
    'branchId',
  );
  @override
  late final GeneratedColumn<String> branchId = GeneratedColumn<String>(
    'branch_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _productIdMeta = const VerificationMeta(
    'productId',
  );
  @override
  late final GeneratedColumn<String> productId = GeneratedColumn<String>(
    'product_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _quantityUnitsMeta = const VerificationMeta(
    'quantityUnits',
  );
  @override
  late final GeneratedColumn<int> quantityUnits = GeneratedColumn<int>(
    'quantity_units',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _uncertainMeta = const VerificationMeta(
    'uncertain',
  );
  @override
  late final GeneratedColumn<bool> uncertain = GeneratedColumn<bool>(
    'uncertain',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("uncertain" IN (0, 1))',
    ),
    defaultValue: const Constant(true),
  );
  static const VerificationMeta _observedAtMeta = const VerificationMeta(
    'observedAt',
  );
  @override
  late final GeneratedColumn<DateTime> observedAt = GeneratedColumn<DateTime>(
    'observed_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _revisionMeta = const VerificationMeta(
    'revision',
  );
  @override
  late final GeneratedColumn<int> revision = GeneratedColumn<int>(
    'revision',
    aliasedName,
    false,
    check: () => ComparableExpr(revision).isBiggerOrEqualValue(0),
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    organizationId,
    branchId,
    id,
    productId,
    quantityUnits,
    uncertain,
    observedAt,
    revision,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'local_inventory_snapshots';
  @override
  VerificationContext validateIntegrity(
    Insertable<InventorySnapshotRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('organization_id')) {
      context.handle(
        _organizationIdMeta,
        organizationId.isAcceptableOrUnknown(
          data['organization_id']!,
          _organizationIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_organizationIdMeta);
    }
    if (data.containsKey('branch_id')) {
      context.handle(
        _branchIdMeta,
        branchId.isAcceptableOrUnknown(data['branch_id']!, _branchIdMeta),
      );
    } else if (isInserting) {
      context.missing(_branchIdMeta);
    }
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('product_id')) {
      context.handle(
        _productIdMeta,
        productId.isAcceptableOrUnknown(data['product_id']!, _productIdMeta),
      );
    } else if (isInserting) {
      context.missing(_productIdMeta);
    }
    if (data.containsKey('quantity_units')) {
      context.handle(
        _quantityUnitsMeta,
        quantityUnits.isAcceptableOrUnknown(
          data['quantity_units']!,
          _quantityUnitsMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_quantityUnitsMeta);
    }
    if (data.containsKey('uncertain')) {
      context.handle(
        _uncertainMeta,
        uncertain.isAcceptableOrUnknown(data['uncertain']!, _uncertainMeta),
      );
    }
    if (data.containsKey('observed_at')) {
      context.handle(
        _observedAtMeta,
        observedAt.isAcceptableOrUnknown(data['observed_at']!, _observedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_observedAtMeta);
    }
    if (data.containsKey('revision')) {
      context.handle(
        _revisionMeta,
        revision.isAcceptableOrUnknown(data['revision']!, _revisionMeta),
      );
    } else if (isInserting) {
      context.missing(_revisionMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {organizationId, branchId, id};
  @override
  List<Set<GeneratedColumn>> get uniqueKeys => [
    {organizationId, branchId, productId},
  ];
  @override
  InventorySnapshotRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return InventorySnapshotRow(
      organizationId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}organization_id'],
      )!,
      branchId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}branch_id'],
      )!,
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      productId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}product_id'],
      )!,
      quantityUnits: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}quantity_units'],
      )!,
      uncertain: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}uncertain'],
      )!,
      observedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}observed_at'],
      )!,
      revision: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}revision'],
      )!,
    );
  }

  @override
  $LocalInventorySnapshotsTable createAlias(String alias) {
    return $LocalInventorySnapshotsTable(attachedDatabase, alias);
  }
}

class InventorySnapshotRow extends DataClass
    implements Insertable<InventorySnapshotRow> {
  final String organizationId;
  final String branchId;
  final String id;
  final String productId;
  final int quantityUnits;
  final bool uncertain;
  final DateTime observedAt;
  final int revision;
  const InventorySnapshotRow({
    required this.organizationId,
    required this.branchId,
    required this.id,
    required this.productId,
    required this.quantityUnits,
    required this.uncertain,
    required this.observedAt,
    required this.revision,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['organization_id'] = Variable<String>(organizationId);
    map['branch_id'] = Variable<String>(branchId);
    map['id'] = Variable<String>(id);
    map['product_id'] = Variable<String>(productId);
    map['quantity_units'] = Variable<int>(quantityUnits);
    map['uncertain'] = Variable<bool>(uncertain);
    map['observed_at'] = Variable<DateTime>(observedAt);
    map['revision'] = Variable<int>(revision);
    return map;
  }

  LocalInventorySnapshotsCompanion toCompanion(bool nullToAbsent) {
    return LocalInventorySnapshotsCompanion(
      organizationId: Value(organizationId),
      branchId: Value(branchId),
      id: Value(id),
      productId: Value(productId),
      quantityUnits: Value(quantityUnits),
      uncertain: Value(uncertain),
      observedAt: Value(observedAt),
      revision: Value(revision),
    );
  }

  factory InventorySnapshotRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return InventorySnapshotRow(
      organizationId: serializer.fromJson<String>(json['organizationId']),
      branchId: serializer.fromJson<String>(json['branchId']),
      id: serializer.fromJson<String>(json['id']),
      productId: serializer.fromJson<String>(json['productId']),
      quantityUnits: serializer.fromJson<int>(json['quantityUnits']),
      uncertain: serializer.fromJson<bool>(json['uncertain']),
      observedAt: serializer.fromJson<DateTime>(json['observedAt']),
      revision: serializer.fromJson<int>(json['revision']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'organizationId': serializer.toJson<String>(organizationId),
      'branchId': serializer.toJson<String>(branchId),
      'id': serializer.toJson<String>(id),
      'productId': serializer.toJson<String>(productId),
      'quantityUnits': serializer.toJson<int>(quantityUnits),
      'uncertain': serializer.toJson<bool>(uncertain),
      'observedAt': serializer.toJson<DateTime>(observedAt),
      'revision': serializer.toJson<int>(revision),
    };
  }

  InventorySnapshotRow copyWith({
    String? organizationId,
    String? branchId,
    String? id,
    String? productId,
    int? quantityUnits,
    bool? uncertain,
    DateTime? observedAt,
    int? revision,
  }) => InventorySnapshotRow(
    organizationId: organizationId ?? this.organizationId,
    branchId: branchId ?? this.branchId,
    id: id ?? this.id,
    productId: productId ?? this.productId,
    quantityUnits: quantityUnits ?? this.quantityUnits,
    uncertain: uncertain ?? this.uncertain,
    observedAt: observedAt ?? this.observedAt,
    revision: revision ?? this.revision,
  );
  InventorySnapshotRow copyWithCompanion(
    LocalInventorySnapshotsCompanion data,
  ) {
    return InventorySnapshotRow(
      organizationId: data.organizationId.present
          ? data.organizationId.value
          : this.organizationId,
      branchId: data.branchId.present ? data.branchId.value : this.branchId,
      id: data.id.present ? data.id.value : this.id,
      productId: data.productId.present ? data.productId.value : this.productId,
      quantityUnits: data.quantityUnits.present
          ? data.quantityUnits.value
          : this.quantityUnits,
      uncertain: data.uncertain.present ? data.uncertain.value : this.uncertain,
      observedAt: data.observedAt.present
          ? data.observedAt.value
          : this.observedAt,
      revision: data.revision.present ? data.revision.value : this.revision,
    );
  }

  @override
  String toString() {
    return (StringBuffer('InventorySnapshotRow(')
          ..write('organizationId: $organizationId, ')
          ..write('branchId: $branchId, ')
          ..write('id: $id, ')
          ..write('productId: $productId, ')
          ..write('quantityUnits: $quantityUnits, ')
          ..write('uncertain: $uncertain, ')
          ..write('observedAt: $observedAt, ')
          ..write('revision: $revision')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    organizationId,
    branchId,
    id,
    productId,
    quantityUnits,
    uncertain,
    observedAt,
    revision,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is InventorySnapshotRow &&
          other.organizationId == this.organizationId &&
          other.branchId == this.branchId &&
          other.id == this.id &&
          other.productId == this.productId &&
          other.quantityUnits == this.quantityUnits &&
          other.uncertain == this.uncertain &&
          other.observedAt == this.observedAt &&
          other.revision == this.revision);
}

class LocalInventorySnapshotsCompanion
    extends UpdateCompanion<InventorySnapshotRow> {
  final Value<String> organizationId;
  final Value<String> branchId;
  final Value<String> id;
  final Value<String> productId;
  final Value<int> quantityUnits;
  final Value<bool> uncertain;
  final Value<DateTime> observedAt;
  final Value<int> revision;
  final Value<int> rowid;
  const LocalInventorySnapshotsCompanion({
    this.organizationId = const Value.absent(),
    this.branchId = const Value.absent(),
    this.id = const Value.absent(),
    this.productId = const Value.absent(),
    this.quantityUnits = const Value.absent(),
    this.uncertain = const Value.absent(),
    this.observedAt = const Value.absent(),
    this.revision = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  LocalInventorySnapshotsCompanion.insert({
    required String organizationId,
    required String branchId,
    required String id,
    required String productId,
    required int quantityUnits,
    this.uncertain = const Value.absent(),
    required DateTime observedAt,
    required int revision,
    this.rowid = const Value.absent(),
  }) : organizationId = Value(organizationId),
       branchId = Value(branchId),
       id = Value(id),
       productId = Value(productId),
       quantityUnits = Value(quantityUnits),
       observedAt = Value(observedAt),
       revision = Value(revision);
  static Insertable<InventorySnapshotRow> custom({
    Expression<String>? organizationId,
    Expression<String>? branchId,
    Expression<String>? id,
    Expression<String>? productId,
    Expression<int>? quantityUnits,
    Expression<bool>? uncertain,
    Expression<DateTime>? observedAt,
    Expression<int>? revision,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (organizationId != null) 'organization_id': organizationId,
      if (branchId != null) 'branch_id': branchId,
      if (id != null) 'id': id,
      if (productId != null) 'product_id': productId,
      if (quantityUnits != null) 'quantity_units': quantityUnits,
      if (uncertain != null) 'uncertain': uncertain,
      if (observedAt != null) 'observed_at': observedAt,
      if (revision != null) 'revision': revision,
      if (rowid != null) 'rowid': rowid,
    });
  }

  LocalInventorySnapshotsCompanion copyWith({
    Value<String>? organizationId,
    Value<String>? branchId,
    Value<String>? id,
    Value<String>? productId,
    Value<int>? quantityUnits,
    Value<bool>? uncertain,
    Value<DateTime>? observedAt,
    Value<int>? revision,
    Value<int>? rowid,
  }) {
    return LocalInventorySnapshotsCompanion(
      organizationId: organizationId ?? this.organizationId,
      branchId: branchId ?? this.branchId,
      id: id ?? this.id,
      productId: productId ?? this.productId,
      quantityUnits: quantityUnits ?? this.quantityUnits,
      uncertain: uncertain ?? this.uncertain,
      observedAt: observedAt ?? this.observedAt,
      revision: revision ?? this.revision,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (organizationId.present) {
      map['organization_id'] = Variable<String>(organizationId.value);
    }
    if (branchId.present) {
      map['branch_id'] = Variable<String>(branchId.value);
    }
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (productId.present) {
      map['product_id'] = Variable<String>(productId.value);
    }
    if (quantityUnits.present) {
      map['quantity_units'] = Variable<int>(quantityUnits.value);
    }
    if (uncertain.present) {
      map['uncertain'] = Variable<bool>(uncertain.value);
    }
    if (observedAt.present) {
      map['observed_at'] = Variable<DateTime>(observedAt.value);
    }
    if (revision.present) {
      map['revision'] = Variable<int>(revision.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('LocalInventorySnapshotsCompanion(')
          ..write('organizationId: $organizationId, ')
          ..write('branchId: $branchId, ')
          ..write('id: $id, ')
          ..write('productId: $productId, ')
          ..write('quantityUnits: $quantityUnits, ')
          ..write('uncertain: $uncertain, ')
          ..write('observedAt: $observedAt, ')
          ..write('revision: $revision, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $LocalCustomersTable extends LocalCustomers
    with TableInfo<$LocalCustomersTable, CustomerRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $LocalCustomersTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _organizationIdMeta = const VerificationMeta(
    'organizationId',
  );
  @override
  late final GeneratedColumn<String> organizationId = GeneratedColumn<String>(
    'organization_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _branchIdMeta = const VerificationMeta(
    'branchId',
  );
  @override
  late final GeneratedColumn<String> branchId = GeneratedColumn<String>(
    'branch_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _activeMeta = const VerificationMeta('active');
  @override
  late final GeneratedColumn<bool> active = GeneratedColumn<bool>(
    'active',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("active" IN (0, 1))',
    ),
    defaultValue: const Constant(true),
  );
  static const VerificationMeta _revisionMeta = const VerificationMeta(
    'revision',
  );
  @override
  late final GeneratedColumn<int> revision = GeneratedColumn<int>(
    'revision',
    aliasedName,
    false,
    check: () => ComparableExpr(revision).isBiggerOrEqualValue(0),
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    organizationId,
    branchId,
    id,
    name,
    active,
    revision,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'local_customers';
  @override
  VerificationContext validateIntegrity(
    Insertable<CustomerRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('organization_id')) {
      context.handle(
        _organizationIdMeta,
        organizationId.isAcceptableOrUnknown(
          data['organization_id']!,
          _organizationIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_organizationIdMeta);
    }
    if (data.containsKey('branch_id')) {
      context.handle(
        _branchIdMeta,
        branchId.isAcceptableOrUnknown(data['branch_id']!, _branchIdMeta),
      );
    } else if (isInserting) {
      context.missing(_branchIdMeta);
    }
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('active')) {
      context.handle(
        _activeMeta,
        active.isAcceptableOrUnknown(data['active']!, _activeMeta),
      );
    }
    if (data.containsKey('revision')) {
      context.handle(
        _revisionMeta,
        revision.isAcceptableOrUnknown(data['revision']!, _revisionMeta),
      );
    } else if (isInserting) {
      context.missing(_revisionMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {organizationId, branchId, id};
  @override
  CustomerRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return CustomerRow(
      organizationId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}organization_id'],
      )!,
      branchId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}branch_id'],
      )!,
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      active: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}active'],
      )!,
      revision: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}revision'],
      )!,
    );
  }

  @override
  $LocalCustomersTable createAlias(String alias) {
    return $LocalCustomersTable(attachedDatabase, alias);
  }
}

class CustomerRow extends DataClass implements Insertable<CustomerRow> {
  final String organizationId;
  final String branchId;
  final String id;
  final String name;
  final bool active;
  final int revision;
  const CustomerRow({
    required this.organizationId,
    required this.branchId,
    required this.id,
    required this.name,
    required this.active,
    required this.revision,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['organization_id'] = Variable<String>(organizationId);
    map['branch_id'] = Variable<String>(branchId);
    map['id'] = Variable<String>(id);
    map['name'] = Variable<String>(name);
    map['active'] = Variable<bool>(active);
    map['revision'] = Variable<int>(revision);
    return map;
  }

  LocalCustomersCompanion toCompanion(bool nullToAbsent) {
    return LocalCustomersCompanion(
      organizationId: Value(organizationId),
      branchId: Value(branchId),
      id: Value(id),
      name: Value(name),
      active: Value(active),
      revision: Value(revision),
    );
  }

  factory CustomerRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return CustomerRow(
      organizationId: serializer.fromJson<String>(json['organizationId']),
      branchId: serializer.fromJson<String>(json['branchId']),
      id: serializer.fromJson<String>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      active: serializer.fromJson<bool>(json['active']),
      revision: serializer.fromJson<int>(json['revision']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'organizationId': serializer.toJson<String>(organizationId),
      'branchId': serializer.toJson<String>(branchId),
      'id': serializer.toJson<String>(id),
      'name': serializer.toJson<String>(name),
      'active': serializer.toJson<bool>(active),
      'revision': serializer.toJson<int>(revision),
    };
  }

  CustomerRow copyWith({
    String? organizationId,
    String? branchId,
    String? id,
    String? name,
    bool? active,
    int? revision,
  }) => CustomerRow(
    organizationId: organizationId ?? this.organizationId,
    branchId: branchId ?? this.branchId,
    id: id ?? this.id,
    name: name ?? this.name,
    active: active ?? this.active,
    revision: revision ?? this.revision,
  );
  CustomerRow copyWithCompanion(LocalCustomersCompanion data) {
    return CustomerRow(
      organizationId: data.organizationId.present
          ? data.organizationId.value
          : this.organizationId,
      branchId: data.branchId.present ? data.branchId.value : this.branchId,
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      active: data.active.present ? data.active.value : this.active,
      revision: data.revision.present ? data.revision.value : this.revision,
    );
  }

  @override
  String toString() {
    return (StringBuffer('CustomerRow(')
          ..write('organizationId: $organizationId, ')
          ..write('branchId: $branchId, ')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('active: $active, ')
          ..write('revision: $revision')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(organizationId, branchId, id, name, active, revision);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CustomerRow &&
          other.organizationId == this.organizationId &&
          other.branchId == this.branchId &&
          other.id == this.id &&
          other.name == this.name &&
          other.active == this.active &&
          other.revision == this.revision);
}

class LocalCustomersCompanion extends UpdateCompanion<CustomerRow> {
  final Value<String> organizationId;
  final Value<String> branchId;
  final Value<String> id;
  final Value<String> name;
  final Value<bool> active;
  final Value<int> revision;
  final Value<int> rowid;
  const LocalCustomersCompanion({
    this.organizationId = const Value.absent(),
    this.branchId = const Value.absent(),
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.active = const Value.absent(),
    this.revision = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  LocalCustomersCompanion.insert({
    required String organizationId,
    required String branchId,
    required String id,
    required String name,
    this.active = const Value.absent(),
    required int revision,
    this.rowid = const Value.absent(),
  }) : organizationId = Value(organizationId),
       branchId = Value(branchId),
       id = Value(id),
       name = Value(name),
       revision = Value(revision);
  static Insertable<CustomerRow> custom({
    Expression<String>? organizationId,
    Expression<String>? branchId,
    Expression<String>? id,
    Expression<String>? name,
    Expression<bool>? active,
    Expression<int>? revision,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (organizationId != null) 'organization_id': organizationId,
      if (branchId != null) 'branch_id': branchId,
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (active != null) 'active': active,
      if (revision != null) 'revision': revision,
      if (rowid != null) 'rowid': rowid,
    });
  }

  LocalCustomersCompanion copyWith({
    Value<String>? organizationId,
    Value<String>? branchId,
    Value<String>? id,
    Value<String>? name,
    Value<bool>? active,
    Value<int>? revision,
    Value<int>? rowid,
  }) {
    return LocalCustomersCompanion(
      organizationId: organizationId ?? this.organizationId,
      branchId: branchId ?? this.branchId,
      id: id ?? this.id,
      name: name ?? this.name,
      active: active ?? this.active,
      revision: revision ?? this.revision,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (organizationId.present) {
      map['organization_id'] = Variable<String>(organizationId.value);
    }
    if (branchId.present) {
      map['branch_id'] = Variable<String>(branchId.value);
    }
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (active.present) {
      map['active'] = Variable<bool>(active.value);
    }
    if (revision.present) {
      map['revision'] = Variable<int>(revision.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('LocalCustomersCompanion(')
          ..write('organizationId: $organizationId, ')
          ..write('branchId: $branchId, ')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('active: $active, ')
          ..write('revision: $revision, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $LocalShiftsTable extends LocalShifts
    with TableInfo<$LocalShiftsTable, ShiftRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $LocalShiftsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _organizationIdMeta = const VerificationMeta(
    'organizationId',
  );
  @override
  late final GeneratedColumn<String> organizationId = GeneratedColumn<String>(
    'organization_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _branchIdMeta = const VerificationMeta(
    'branchId',
  );
  @override
  late final GeneratedColumn<String> branchId = GeneratedColumn<String>(
    'branch_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _deviceIdMeta = const VerificationMeta(
    'deviceId',
  );
  @override
  late final GeneratedColumn<String> deviceId = GeneratedColumn<String>(
    'device_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _openedByMeta = const VerificationMeta(
    'openedBy',
  );
  @override
  late final GeneratedColumn<String> openedBy = GeneratedColumn<String>(
    'opened_by',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _openedAtMeta = const VerificationMeta(
    'openedAt',
  );
  @override
  late final GeneratedColumn<DateTime> openedAt = GeneratedColumn<DateTime>(
    'opened_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _openingCashMinorMeta = const VerificationMeta(
    'openingCashMinor',
  );
  @override
  late final GeneratedColumn<int> openingCashMinor = GeneratedColumn<int>(
    'opening_cash_minor',
    aliasedName,
    false,
    check: () => ComparableExpr(openingCashMinor).isBiggerOrEqualValue(0),
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _currencyMeta = const VerificationMeta(
    'currency',
  );
  @override
  late final GeneratedColumn<String> currency = GeneratedColumn<String>(
    'currency',
    aliasedName,
    false,
    additionalChecks: GeneratedColumn.checkTextLength(
      minTextLength: 3,
      maxTextLength: 3,
    ),
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    organizationId,
    branchId,
    id,
    deviceId,
    openedBy,
    openedAt,
    openingCashMinor,
    currency,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'local_shifts';
  @override
  VerificationContext validateIntegrity(
    Insertable<ShiftRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('organization_id')) {
      context.handle(
        _organizationIdMeta,
        organizationId.isAcceptableOrUnknown(
          data['organization_id']!,
          _organizationIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_organizationIdMeta);
    }
    if (data.containsKey('branch_id')) {
      context.handle(
        _branchIdMeta,
        branchId.isAcceptableOrUnknown(data['branch_id']!, _branchIdMeta),
      );
    } else if (isInserting) {
      context.missing(_branchIdMeta);
    }
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('device_id')) {
      context.handle(
        _deviceIdMeta,
        deviceId.isAcceptableOrUnknown(data['device_id']!, _deviceIdMeta),
      );
    } else if (isInserting) {
      context.missing(_deviceIdMeta);
    }
    if (data.containsKey('opened_by')) {
      context.handle(
        _openedByMeta,
        openedBy.isAcceptableOrUnknown(data['opened_by']!, _openedByMeta),
      );
    } else if (isInserting) {
      context.missing(_openedByMeta);
    }
    if (data.containsKey('opened_at')) {
      context.handle(
        _openedAtMeta,
        openedAt.isAcceptableOrUnknown(data['opened_at']!, _openedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_openedAtMeta);
    }
    if (data.containsKey('opening_cash_minor')) {
      context.handle(
        _openingCashMinorMeta,
        openingCashMinor.isAcceptableOrUnknown(
          data['opening_cash_minor']!,
          _openingCashMinorMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_openingCashMinorMeta);
    }
    if (data.containsKey('currency')) {
      context.handle(
        _currencyMeta,
        currency.isAcceptableOrUnknown(data['currency']!, _currencyMeta),
      );
    } else if (isInserting) {
      context.missing(_currencyMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {organizationId, branchId, id};
  @override
  ShiftRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ShiftRow(
      organizationId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}organization_id'],
      )!,
      branchId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}branch_id'],
      )!,
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      deviceId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}device_id'],
      )!,
      openedBy: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}opened_by'],
      )!,
      openedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}opened_at'],
      )!,
      openingCashMinor: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}opening_cash_minor'],
      )!,
      currency: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}currency'],
      )!,
    );
  }

  @override
  $LocalShiftsTable createAlias(String alias) {
    return $LocalShiftsTable(attachedDatabase, alias);
  }
}

class ShiftRow extends DataClass implements Insertable<ShiftRow> {
  final String organizationId;
  final String branchId;
  final String id;
  final String deviceId;
  final String openedBy;
  final DateTime openedAt;
  final int openingCashMinor;
  final String currency;
  const ShiftRow({
    required this.organizationId,
    required this.branchId,
    required this.id,
    required this.deviceId,
    required this.openedBy,
    required this.openedAt,
    required this.openingCashMinor,
    required this.currency,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['organization_id'] = Variable<String>(organizationId);
    map['branch_id'] = Variable<String>(branchId);
    map['id'] = Variable<String>(id);
    map['device_id'] = Variable<String>(deviceId);
    map['opened_by'] = Variable<String>(openedBy);
    map['opened_at'] = Variable<DateTime>(openedAt);
    map['opening_cash_minor'] = Variable<int>(openingCashMinor);
    map['currency'] = Variable<String>(currency);
    return map;
  }

  LocalShiftsCompanion toCompanion(bool nullToAbsent) {
    return LocalShiftsCompanion(
      organizationId: Value(organizationId),
      branchId: Value(branchId),
      id: Value(id),
      deviceId: Value(deviceId),
      openedBy: Value(openedBy),
      openedAt: Value(openedAt),
      openingCashMinor: Value(openingCashMinor),
      currency: Value(currency),
    );
  }

  factory ShiftRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ShiftRow(
      organizationId: serializer.fromJson<String>(json['organizationId']),
      branchId: serializer.fromJson<String>(json['branchId']),
      id: serializer.fromJson<String>(json['id']),
      deviceId: serializer.fromJson<String>(json['deviceId']),
      openedBy: serializer.fromJson<String>(json['openedBy']),
      openedAt: serializer.fromJson<DateTime>(json['openedAt']),
      openingCashMinor: serializer.fromJson<int>(json['openingCashMinor']),
      currency: serializer.fromJson<String>(json['currency']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'organizationId': serializer.toJson<String>(organizationId),
      'branchId': serializer.toJson<String>(branchId),
      'id': serializer.toJson<String>(id),
      'deviceId': serializer.toJson<String>(deviceId),
      'openedBy': serializer.toJson<String>(openedBy),
      'openedAt': serializer.toJson<DateTime>(openedAt),
      'openingCashMinor': serializer.toJson<int>(openingCashMinor),
      'currency': serializer.toJson<String>(currency),
    };
  }

  ShiftRow copyWith({
    String? organizationId,
    String? branchId,
    String? id,
    String? deviceId,
    String? openedBy,
    DateTime? openedAt,
    int? openingCashMinor,
    String? currency,
  }) => ShiftRow(
    organizationId: organizationId ?? this.organizationId,
    branchId: branchId ?? this.branchId,
    id: id ?? this.id,
    deviceId: deviceId ?? this.deviceId,
    openedBy: openedBy ?? this.openedBy,
    openedAt: openedAt ?? this.openedAt,
    openingCashMinor: openingCashMinor ?? this.openingCashMinor,
    currency: currency ?? this.currency,
  );
  ShiftRow copyWithCompanion(LocalShiftsCompanion data) {
    return ShiftRow(
      organizationId: data.organizationId.present
          ? data.organizationId.value
          : this.organizationId,
      branchId: data.branchId.present ? data.branchId.value : this.branchId,
      id: data.id.present ? data.id.value : this.id,
      deviceId: data.deviceId.present ? data.deviceId.value : this.deviceId,
      openedBy: data.openedBy.present ? data.openedBy.value : this.openedBy,
      openedAt: data.openedAt.present ? data.openedAt.value : this.openedAt,
      openingCashMinor: data.openingCashMinor.present
          ? data.openingCashMinor.value
          : this.openingCashMinor,
      currency: data.currency.present ? data.currency.value : this.currency,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ShiftRow(')
          ..write('organizationId: $organizationId, ')
          ..write('branchId: $branchId, ')
          ..write('id: $id, ')
          ..write('deviceId: $deviceId, ')
          ..write('openedBy: $openedBy, ')
          ..write('openedAt: $openedAt, ')
          ..write('openingCashMinor: $openingCashMinor, ')
          ..write('currency: $currency')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    organizationId,
    branchId,
    id,
    deviceId,
    openedBy,
    openedAt,
    openingCashMinor,
    currency,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ShiftRow &&
          other.organizationId == this.organizationId &&
          other.branchId == this.branchId &&
          other.id == this.id &&
          other.deviceId == this.deviceId &&
          other.openedBy == this.openedBy &&
          other.openedAt == this.openedAt &&
          other.openingCashMinor == this.openingCashMinor &&
          other.currency == this.currency);
}

class LocalShiftsCompanion extends UpdateCompanion<ShiftRow> {
  final Value<String> organizationId;
  final Value<String> branchId;
  final Value<String> id;
  final Value<String> deviceId;
  final Value<String> openedBy;
  final Value<DateTime> openedAt;
  final Value<int> openingCashMinor;
  final Value<String> currency;
  final Value<int> rowid;
  const LocalShiftsCompanion({
    this.organizationId = const Value.absent(),
    this.branchId = const Value.absent(),
    this.id = const Value.absent(),
    this.deviceId = const Value.absent(),
    this.openedBy = const Value.absent(),
    this.openedAt = const Value.absent(),
    this.openingCashMinor = const Value.absent(),
    this.currency = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  LocalShiftsCompanion.insert({
    required String organizationId,
    required String branchId,
    required String id,
    required String deviceId,
    required String openedBy,
    required DateTime openedAt,
    required int openingCashMinor,
    required String currency,
    this.rowid = const Value.absent(),
  }) : organizationId = Value(organizationId),
       branchId = Value(branchId),
       id = Value(id),
       deviceId = Value(deviceId),
       openedBy = Value(openedBy),
       openedAt = Value(openedAt),
       openingCashMinor = Value(openingCashMinor),
       currency = Value(currency);
  static Insertable<ShiftRow> custom({
    Expression<String>? organizationId,
    Expression<String>? branchId,
    Expression<String>? id,
    Expression<String>? deviceId,
    Expression<String>? openedBy,
    Expression<DateTime>? openedAt,
    Expression<int>? openingCashMinor,
    Expression<String>? currency,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (organizationId != null) 'organization_id': organizationId,
      if (branchId != null) 'branch_id': branchId,
      if (id != null) 'id': id,
      if (deviceId != null) 'device_id': deviceId,
      if (openedBy != null) 'opened_by': openedBy,
      if (openedAt != null) 'opened_at': openedAt,
      if (openingCashMinor != null) 'opening_cash_minor': openingCashMinor,
      if (currency != null) 'currency': currency,
      if (rowid != null) 'rowid': rowid,
    });
  }

  LocalShiftsCompanion copyWith({
    Value<String>? organizationId,
    Value<String>? branchId,
    Value<String>? id,
    Value<String>? deviceId,
    Value<String>? openedBy,
    Value<DateTime>? openedAt,
    Value<int>? openingCashMinor,
    Value<String>? currency,
    Value<int>? rowid,
  }) {
    return LocalShiftsCompanion(
      organizationId: organizationId ?? this.organizationId,
      branchId: branchId ?? this.branchId,
      id: id ?? this.id,
      deviceId: deviceId ?? this.deviceId,
      openedBy: openedBy ?? this.openedBy,
      openedAt: openedAt ?? this.openedAt,
      openingCashMinor: openingCashMinor ?? this.openingCashMinor,
      currency: currency ?? this.currency,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (organizationId.present) {
      map['organization_id'] = Variable<String>(organizationId.value);
    }
    if (branchId.present) {
      map['branch_id'] = Variable<String>(branchId.value);
    }
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (deviceId.present) {
      map['device_id'] = Variable<String>(deviceId.value);
    }
    if (openedBy.present) {
      map['opened_by'] = Variable<String>(openedBy.value);
    }
    if (openedAt.present) {
      map['opened_at'] = Variable<DateTime>(openedAt.value);
    }
    if (openingCashMinor.present) {
      map['opening_cash_minor'] = Variable<int>(openingCashMinor.value);
    }
    if (currency.present) {
      map['currency'] = Variable<String>(currency.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('LocalShiftsCompanion(')
          ..write('organizationId: $organizationId, ')
          ..write('branchId: $branchId, ')
          ..write('id: $id, ')
          ..write('deviceId: $deviceId, ')
          ..write('openedBy: $openedBy, ')
          ..write('openedAt: $openedAt, ')
          ..write('openingCashMinor: $openingCashMinor, ')
          ..write('currency: $currency, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $LocalSalesTable extends LocalSales
    with TableInfo<$LocalSalesTable, SaleRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $LocalSalesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _organizationIdMeta = const VerificationMeta(
    'organizationId',
  );
  @override
  late final GeneratedColumn<String> organizationId = GeneratedColumn<String>(
    'organization_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _branchIdMeta = const VerificationMeta(
    'branchId',
  );
  @override
  late final GeneratedColumn<String> branchId = GeneratedColumn<String>(
    'branch_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _deviceIdMeta = const VerificationMeta(
    'deviceId',
  );
  @override
  late final GeneratedColumn<String> deviceId = GeneratedColumn<String>(
    'device_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _shiftIdMeta = const VerificationMeta(
    'shiftId',
  );
  @override
  late final GeneratedColumn<String> shiftId = GeneratedColumn<String>(
    'shift_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _cashierIdMeta = const VerificationMeta(
    'cashierId',
  );
  @override
  late final GeneratedColumn<String> cashierId = GeneratedColumn<String>(
    'cashier_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _customerIdMeta = const VerificationMeta(
    'customerId',
  );
  @override
  late final GeneratedColumn<String> customerId = GeneratedColumn<String>(
    'customer_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _receiptNumberMeta = const VerificationMeta(
    'receiptNumber',
  );
  @override
  late final GeneratedColumn<String> receiptNumber = GeneratedColumn<String>(
    'receipt_number',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _currencyMeta = const VerificationMeta(
    'currency',
  );
  @override
  late final GeneratedColumn<String> currency = GeneratedColumn<String>(
    'currency',
    aliasedName,
    false,
    additionalChecks: GeneratedColumn.checkTextLength(
      minTextLength: 3,
      maxTextLength: 3,
    ),
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _subtotalMinorMeta = const VerificationMeta(
    'subtotalMinor',
  );
  @override
  late final GeneratedColumn<int> subtotalMinor = GeneratedColumn<int>(
    'subtotal_minor',
    aliasedName,
    false,
    check: () => ComparableExpr(subtotalMinor).isBiggerOrEqualValue(0),
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _discountMinorMeta = const VerificationMeta(
    'discountMinor',
  );
  @override
  late final GeneratedColumn<int> discountMinor = GeneratedColumn<int>(
    'discount_minor',
    aliasedName,
    false,
    check: () => ComparableExpr(discountMinor).isBiggerOrEqualValue(0),
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _taxMinorMeta = const VerificationMeta(
    'taxMinor',
  );
  @override
  late final GeneratedColumn<int> taxMinor = GeneratedColumn<int>(
    'tax_minor',
    aliasedName,
    false,
    check: () => ComparableExpr(taxMinor).isBiggerOrEqualValue(0),
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _totalMinorMeta = const VerificationMeta(
    'totalMinor',
  );
  @override
  late final GeneratedColumn<int> totalMinor = GeneratedColumn<int>(
    'total_minor',
    aliasedName,
    false,
    check: () => ComparableExpr(totalMinor).isBiggerOrEqualValue(0),
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    organizationId,
    branchId,
    id,
    deviceId,
    shiftId,
    cashierId,
    customerId,
    receiptNumber,
    currency,
    subtotalMinor,
    discountMinor,
    taxMinor,
    totalMinor,
    createdAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'local_sales';
  @override
  VerificationContext validateIntegrity(
    Insertable<SaleRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('organization_id')) {
      context.handle(
        _organizationIdMeta,
        organizationId.isAcceptableOrUnknown(
          data['organization_id']!,
          _organizationIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_organizationIdMeta);
    }
    if (data.containsKey('branch_id')) {
      context.handle(
        _branchIdMeta,
        branchId.isAcceptableOrUnknown(data['branch_id']!, _branchIdMeta),
      );
    } else if (isInserting) {
      context.missing(_branchIdMeta);
    }
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('device_id')) {
      context.handle(
        _deviceIdMeta,
        deviceId.isAcceptableOrUnknown(data['device_id']!, _deviceIdMeta),
      );
    } else if (isInserting) {
      context.missing(_deviceIdMeta);
    }
    if (data.containsKey('shift_id')) {
      context.handle(
        _shiftIdMeta,
        shiftId.isAcceptableOrUnknown(data['shift_id']!, _shiftIdMeta),
      );
    } else if (isInserting) {
      context.missing(_shiftIdMeta);
    }
    if (data.containsKey('cashier_id')) {
      context.handle(
        _cashierIdMeta,
        cashierId.isAcceptableOrUnknown(data['cashier_id']!, _cashierIdMeta),
      );
    } else if (isInserting) {
      context.missing(_cashierIdMeta);
    }
    if (data.containsKey('customer_id')) {
      context.handle(
        _customerIdMeta,
        customerId.isAcceptableOrUnknown(data['customer_id']!, _customerIdMeta),
      );
    }
    if (data.containsKey('receipt_number')) {
      context.handle(
        _receiptNumberMeta,
        receiptNumber.isAcceptableOrUnknown(
          data['receipt_number']!,
          _receiptNumberMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_receiptNumberMeta);
    }
    if (data.containsKey('currency')) {
      context.handle(
        _currencyMeta,
        currency.isAcceptableOrUnknown(data['currency']!, _currencyMeta),
      );
    } else if (isInserting) {
      context.missing(_currencyMeta);
    }
    if (data.containsKey('subtotal_minor')) {
      context.handle(
        _subtotalMinorMeta,
        subtotalMinor.isAcceptableOrUnknown(
          data['subtotal_minor']!,
          _subtotalMinorMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_subtotalMinorMeta);
    }
    if (data.containsKey('discount_minor')) {
      context.handle(
        _discountMinorMeta,
        discountMinor.isAcceptableOrUnknown(
          data['discount_minor']!,
          _discountMinorMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_discountMinorMeta);
    }
    if (data.containsKey('tax_minor')) {
      context.handle(
        _taxMinorMeta,
        taxMinor.isAcceptableOrUnknown(data['tax_minor']!, _taxMinorMeta),
      );
    } else if (isInserting) {
      context.missing(_taxMinorMeta);
    }
    if (data.containsKey('total_minor')) {
      context.handle(
        _totalMinorMeta,
        totalMinor.isAcceptableOrUnknown(data['total_minor']!, _totalMinorMeta),
      );
    } else if (isInserting) {
      context.missing(_totalMinorMeta);
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {organizationId, branchId, id};
  @override
  List<Set<GeneratedColumn>> get uniqueKeys => [
    {organizationId, branchId, receiptNumber},
  ];
  @override
  SaleRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SaleRow(
      organizationId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}organization_id'],
      )!,
      branchId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}branch_id'],
      )!,
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      deviceId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}device_id'],
      )!,
      shiftId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}shift_id'],
      )!,
      cashierId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}cashier_id'],
      )!,
      customerId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}customer_id'],
      ),
      receiptNumber: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}receipt_number'],
      )!,
      currency: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}currency'],
      )!,
      subtotalMinor: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}subtotal_minor'],
      )!,
      discountMinor: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}discount_minor'],
      )!,
      taxMinor: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}tax_minor'],
      )!,
      totalMinor: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}total_minor'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
    );
  }

  @override
  $LocalSalesTable createAlias(String alias) {
    return $LocalSalesTable(attachedDatabase, alias);
  }
}

class SaleRow extends DataClass implements Insertable<SaleRow> {
  final String organizationId;
  final String branchId;
  final String id;
  final String deviceId;
  final String shiftId;
  final String cashierId;
  final String? customerId;
  final String receiptNumber;
  final String currency;
  final int subtotalMinor;
  final int discountMinor;
  final int taxMinor;
  final int totalMinor;
  final DateTime createdAt;
  const SaleRow({
    required this.organizationId,
    required this.branchId,
    required this.id,
    required this.deviceId,
    required this.shiftId,
    required this.cashierId,
    this.customerId,
    required this.receiptNumber,
    required this.currency,
    required this.subtotalMinor,
    required this.discountMinor,
    required this.taxMinor,
    required this.totalMinor,
    required this.createdAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['organization_id'] = Variable<String>(organizationId);
    map['branch_id'] = Variable<String>(branchId);
    map['id'] = Variable<String>(id);
    map['device_id'] = Variable<String>(deviceId);
    map['shift_id'] = Variable<String>(shiftId);
    map['cashier_id'] = Variable<String>(cashierId);
    if (!nullToAbsent || customerId != null) {
      map['customer_id'] = Variable<String>(customerId);
    }
    map['receipt_number'] = Variable<String>(receiptNumber);
    map['currency'] = Variable<String>(currency);
    map['subtotal_minor'] = Variable<int>(subtotalMinor);
    map['discount_minor'] = Variable<int>(discountMinor);
    map['tax_minor'] = Variable<int>(taxMinor);
    map['total_minor'] = Variable<int>(totalMinor);
    map['created_at'] = Variable<DateTime>(createdAt);
    return map;
  }

  LocalSalesCompanion toCompanion(bool nullToAbsent) {
    return LocalSalesCompanion(
      organizationId: Value(organizationId),
      branchId: Value(branchId),
      id: Value(id),
      deviceId: Value(deviceId),
      shiftId: Value(shiftId),
      cashierId: Value(cashierId),
      customerId: customerId == null && nullToAbsent
          ? const Value.absent()
          : Value(customerId),
      receiptNumber: Value(receiptNumber),
      currency: Value(currency),
      subtotalMinor: Value(subtotalMinor),
      discountMinor: Value(discountMinor),
      taxMinor: Value(taxMinor),
      totalMinor: Value(totalMinor),
      createdAt: Value(createdAt),
    );
  }

  factory SaleRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SaleRow(
      organizationId: serializer.fromJson<String>(json['organizationId']),
      branchId: serializer.fromJson<String>(json['branchId']),
      id: serializer.fromJson<String>(json['id']),
      deviceId: serializer.fromJson<String>(json['deviceId']),
      shiftId: serializer.fromJson<String>(json['shiftId']),
      cashierId: serializer.fromJson<String>(json['cashierId']),
      customerId: serializer.fromJson<String?>(json['customerId']),
      receiptNumber: serializer.fromJson<String>(json['receiptNumber']),
      currency: serializer.fromJson<String>(json['currency']),
      subtotalMinor: serializer.fromJson<int>(json['subtotalMinor']),
      discountMinor: serializer.fromJson<int>(json['discountMinor']),
      taxMinor: serializer.fromJson<int>(json['taxMinor']),
      totalMinor: serializer.fromJson<int>(json['totalMinor']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'organizationId': serializer.toJson<String>(organizationId),
      'branchId': serializer.toJson<String>(branchId),
      'id': serializer.toJson<String>(id),
      'deviceId': serializer.toJson<String>(deviceId),
      'shiftId': serializer.toJson<String>(shiftId),
      'cashierId': serializer.toJson<String>(cashierId),
      'customerId': serializer.toJson<String?>(customerId),
      'receiptNumber': serializer.toJson<String>(receiptNumber),
      'currency': serializer.toJson<String>(currency),
      'subtotalMinor': serializer.toJson<int>(subtotalMinor),
      'discountMinor': serializer.toJson<int>(discountMinor),
      'taxMinor': serializer.toJson<int>(taxMinor),
      'totalMinor': serializer.toJson<int>(totalMinor),
      'createdAt': serializer.toJson<DateTime>(createdAt),
    };
  }

  SaleRow copyWith({
    String? organizationId,
    String? branchId,
    String? id,
    String? deviceId,
    String? shiftId,
    String? cashierId,
    Value<String?> customerId = const Value.absent(),
    String? receiptNumber,
    String? currency,
    int? subtotalMinor,
    int? discountMinor,
    int? taxMinor,
    int? totalMinor,
    DateTime? createdAt,
  }) => SaleRow(
    organizationId: organizationId ?? this.organizationId,
    branchId: branchId ?? this.branchId,
    id: id ?? this.id,
    deviceId: deviceId ?? this.deviceId,
    shiftId: shiftId ?? this.shiftId,
    cashierId: cashierId ?? this.cashierId,
    customerId: customerId.present ? customerId.value : this.customerId,
    receiptNumber: receiptNumber ?? this.receiptNumber,
    currency: currency ?? this.currency,
    subtotalMinor: subtotalMinor ?? this.subtotalMinor,
    discountMinor: discountMinor ?? this.discountMinor,
    taxMinor: taxMinor ?? this.taxMinor,
    totalMinor: totalMinor ?? this.totalMinor,
    createdAt: createdAt ?? this.createdAt,
  );
  SaleRow copyWithCompanion(LocalSalesCompanion data) {
    return SaleRow(
      organizationId: data.organizationId.present
          ? data.organizationId.value
          : this.organizationId,
      branchId: data.branchId.present ? data.branchId.value : this.branchId,
      id: data.id.present ? data.id.value : this.id,
      deviceId: data.deviceId.present ? data.deviceId.value : this.deviceId,
      shiftId: data.shiftId.present ? data.shiftId.value : this.shiftId,
      cashierId: data.cashierId.present ? data.cashierId.value : this.cashierId,
      customerId: data.customerId.present
          ? data.customerId.value
          : this.customerId,
      receiptNumber: data.receiptNumber.present
          ? data.receiptNumber.value
          : this.receiptNumber,
      currency: data.currency.present ? data.currency.value : this.currency,
      subtotalMinor: data.subtotalMinor.present
          ? data.subtotalMinor.value
          : this.subtotalMinor,
      discountMinor: data.discountMinor.present
          ? data.discountMinor.value
          : this.discountMinor,
      taxMinor: data.taxMinor.present ? data.taxMinor.value : this.taxMinor,
      totalMinor: data.totalMinor.present
          ? data.totalMinor.value
          : this.totalMinor,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SaleRow(')
          ..write('organizationId: $organizationId, ')
          ..write('branchId: $branchId, ')
          ..write('id: $id, ')
          ..write('deviceId: $deviceId, ')
          ..write('shiftId: $shiftId, ')
          ..write('cashierId: $cashierId, ')
          ..write('customerId: $customerId, ')
          ..write('receiptNumber: $receiptNumber, ')
          ..write('currency: $currency, ')
          ..write('subtotalMinor: $subtotalMinor, ')
          ..write('discountMinor: $discountMinor, ')
          ..write('taxMinor: $taxMinor, ')
          ..write('totalMinor: $totalMinor, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    organizationId,
    branchId,
    id,
    deviceId,
    shiftId,
    cashierId,
    customerId,
    receiptNumber,
    currency,
    subtotalMinor,
    discountMinor,
    taxMinor,
    totalMinor,
    createdAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SaleRow &&
          other.organizationId == this.organizationId &&
          other.branchId == this.branchId &&
          other.id == this.id &&
          other.deviceId == this.deviceId &&
          other.shiftId == this.shiftId &&
          other.cashierId == this.cashierId &&
          other.customerId == this.customerId &&
          other.receiptNumber == this.receiptNumber &&
          other.currency == this.currency &&
          other.subtotalMinor == this.subtotalMinor &&
          other.discountMinor == this.discountMinor &&
          other.taxMinor == this.taxMinor &&
          other.totalMinor == this.totalMinor &&
          other.createdAt == this.createdAt);
}

class LocalSalesCompanion extends UpdateCompanion<SaleRow> {
  final Value<String> organizationId;
  final Value<String> branchId;
  final Value<String> id;
  final Value<String> deviceId;
  final Value<String> shiftId;
  final Value<String> cashierId;
  final Value<String?> customerId;
  final Value<String> receiptNumber;
  final Value<String> currency;
  final Value<int> subtotalMinor;
  final Value<int> discountMinor;
  final Value<int> taxMinor;
  final Value<int> totalMinor;
  final Value<DateTime> createdAt;
  final Value<int> rowid;
  const LocalSalesCompanion({
    this.organizationId = const Value.absent(),
    this.branchId = const Value.absent(),
    this.id = const Value.absent(),
    this.deviceId = const Value.absent(),
    this.shiftId = const Value.absent(),
    this.cashierId = const Value.absent(),
    this.customerId = const Value.absent(),
    this.receiptNumber = const Value.absent(),
    this.currency = const Value.absent(),
    this.subtotalMinor = const Value.absent(),
    this.discountMinor = const Value.absent(),
    this.taxMinor = const Value.absent(),
    this.totalMinor = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  LocalSalesCompanion.insert({
    required String organizationId,
    required String branchId,
    required String id,
    required String deviceId,
    required String shiftId,
    required String cashierId,
    this.customerId = const Value.absent(),
    required String receiptNumber,
    required String currency,
    required int subtotalMinor,
    required int discountMinor,
    required int taxMinor,
    required int totalMinor,
    required DateTime createdAt,
    this.rowid = const Value.absent(),
  }) : organizationId = Value(organizationId),
       branchId = Value(branchId),
       id = Value(id),
       deviceId = Value(deviceId),
       shiftId = Value(shiftId),
       cashierId = Value(cashierId),
       receiptNumber = Value(receiptNumber),
       currency = Value(currency),
       subtotalMinor = Value(subtotalMinor),
       discountMinor = Value(discountMinor),
       taxMinor = Value(taxMinor),
       totalMinor = Value(totalMinor),
       createdAt = Value(createdAt);
  static Insertable<SaleRow> custom({
    Expression<String>? organizationId,
    Expression<String>? branchId,
    Expression<String>? id,
    Expression<String>? deviceId,
    Expression<String>? shiftId,
    Expression<String>? cashierId,
    Expression<String>? customerId,
    Expression<String>? receiptNumber,
    Expression<String>? currency,
    Expression<int>? subtotalMinor,
    Expression<int>? discountMinor,
    Expression<int>? taxMinor,
    Expression<int>? totalMinor,
    Expression<DateTime>? createdAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (organizationId != null) 'organization_id': organizationId,
      if (branchId != null) 'branch_id': branchId,
      if (id != null) 'id': id,
      if (deviceId != null) 'device_id': deviceId,
      if (shiftId != null) 'shift_id': shiftId,
      if (cashierId != null) 'cashier_id': cashierId,
      if (customerId != null) 'customer_id': customerId,
      if (receiptNumber != null) 'receipt_number': receiptNumber,
      if (currency != null) 'currency': currency,
      if (subtotalMinor != null) 'subtotal_minor': subtotalMinor,
      if (discountMinor != null) 'discount_minor': discountMinor,
      if (taxMinor != null) 'tax_minor': taxMinor,
      if (totalMinor != null) 'total_minor': totalMinor,
      if (createdAt != null) 'created_at': createdAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  LocalSalesCompanion copyWith({
    Value<String>? organizationId,
    Value<String>? branchId,
    Value<String>? id,
    Value<String>? deviceId,
    Value<String>? shiftId,
    Value<String>? cashierId,
    Value<String?>? customerId,
    Value<String>? receiptNumber,
    Value<String>? currency,
    Value<int>? subtotalMinor,
    Value<int>? discountMinor,
    Value<int>? taxMinor,
    Value<int>? totalMinor,
    Value<DateTime>? createdAt,
    Value<int>? rowid,
  }) {
    return LocalSalesCompanion(
      organizationId: organizationId ?? this.organizationId,
      branchId: branchId ?? this.branchId,
      id: id ?? this.id,
      deviceId: deviceId ?? this.deviceId,
      shiftId: shiftId ?? this.shiftId,
      cashierId: cashierId ?? this.cashierId,
      customerId: customerId ?? this.customerId,
      receiptNumber: receiptNumber ?? this.receiptNumber,
      currency: currency ?? this.currency,
      subtotalMinor: subtotalMinor ?? this.subtotalMinor,
      discountMinor: discountMinor ?? this.discountMinor,
      taxMinor: taxMinor ?? this.taxMinor,
      totalMinor: totalMinor ?? this.totalMinor,
      createdAt: createdAt ?? this.createdAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (organizationId.present) {
      map['organization_id'] = Variable<String>(organizationId.value);
    }
    if (branchId.present) {
      map['branch_id'] = Variable<String>(branchId.value);
    }
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (deviceId.present) {
      map['device_id'] = Variable<String>(deviceId.value);
    }
    if (shiftId.present) {
      map['shift_id'] = Variable<String>(shiftId.value);
    }
    if (cashierId.present) {
      map['cashier_id'] = Variable<String>(cashierId.value);
    }
    if (customerId.present) {
      map['customer_id'] = Variable<String>(customerId.value);
    }
    if (receiptNumber.present) {
      map['receipt_number'] = Variable<String>(receiptNumber.value);
    }
    if (currency.present) {
      map['currency'] = Variable<String>(currency.value);
    }
    if (subtotalMinor.present) {
      map['subtotal_minor'] = Variable<int>(subtotalMinor.value);
    }
    if (discountMinor.present) {
      map['discount_minor'] = Variable<int>(discountMinor.value);
    }
    if (taxMinor.present) {
      map['tax_minor'] = Variable<int>(taxMinor.value);
    }
    if (totalMinor.present) {
      map['total_minor'] = Variable<int>(totalMinor.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('LocalSalesCompanion(')
          ..write('organizationId: $organizationId, ')
          ..write('branchId: $branchId, ')
          ..write('id: $id, ')
          ..write('deviceId: $deviceId, ')
          ..write('shiftId: $shiftId, ')
          ..write('cashierId: $cashierId, ')
          ..write('customerId: $customerId, ')
          ..write('receiptNumber: $receiptNumber, ')
          ..write('currency: $currency, ')
          ..write('subtotalMinor: $subtotalMinor, ')
          ..write('discountMinor: $discountMinor, ')
          ..write('taxMinor: $taxMinor, ')
          ..write('totalMinor: $totalMinor, ')
          ..write('createdAt: $createdAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $LocalSaleItemsTable extends LocalSaleItems
    with TableInfo<$LocalSaleItemsTable, SaleItemRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $LocalSaleItemsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _organizationIdMeta = const VerificationMeta(
    'organizationId',
  );
  @override
  late final GeneratedColumn<String> organizationId = GeneratedColumn<String>(
    'organization_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _branchIdMeta = const VerificationMeta(
    'branchId',
  );
  @override
  late final GeneratedColumn<String> branchId = GeneratedColumn<String>(
    'branch_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _saleIdMeta = const VerificationMeta('saleId');
  @override
  late final GeneratedColumn<String> saleId = GeneratedColumn<String>(
    'sale_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _productIdMeta = const VerificationMeta(
    'productId',
  );
  @override
  late final GeneratedColumn<String> productId = GeneratedColumn<String>(
    'product_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _skuSnapshotMeta = const VerificationMeta(
    'skuSnapshot',
  );
  @override
  late final GeneratedColumn<String> skuSnapshot = GeneratedColumn<String>(
    'sku_snapshot',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _nameSnapshotMeta = const VerificationMeta(
    'nameSnapshot',
  );
  @override
  late final GeneratedColumn<String> nameSnapshot = GeneratedColumn<String>(
    'name_snapshot',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _quantityMeta = const VerificationMeta(
    'quantity',
  );
  @override
  late final GeneratedColumn<int> quantity = GeneratedColumn<int>(
    'quantity',
    aliasedName,
    false,
    check: () => ComparableExpr(quantity).isBiggerThanValue(0),
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _unitPriceMinorMeta = const VerificationMeta(
    'unitPriceMinor',
  );
  @override
  late final GeneratedColumn<int> unitPriceMinor = GeneratedColumn<int>(
    'unit_price_minor',
    aliasedName,
    false,
    check: () => ComparableExpr(unitPriceMinor).isBiggerOrEqualValue(0),
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _discountMinorMeta = const VerificationMeta(
    'discountMinor',
  );
  @override
  late final GeneratedColumn<int> discountMinor = GeneratedColumn<int>(
    'discount_minor',
    aliasedName,
    false,
    check: () => ComparableExpr(discountMinor).isBiggerOrEqualValue(0),
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _taxMinorMeta = const VerificationMeta(
    'taxMinor',
  );
  @override
  late final GeneratedColumn<int> taxMinor = GeneratedColumn<int>(
    'tax_minor',
    aliasedName,
    false,
    check: () => ComparableExpr(taxMinor).isBiggerOrEqualValue(0),
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _lineTotalMinorMeta = const VerificationMeta(
    'lineTotalMinor',
  );
  @override
  late final GeneratedColumn<int> lineTotalMinor = GeneratedColumn<int>(
    'line_total_minor',
    aliasedName,
    false,
    check: () => ComparableExpr(lineTotalMinor).isBiggerOrEqualValue(0),
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    organizationId,
    branchId,
    id,
    saleId,
    productId,
    skuSnapshot,
    nameSnapshot,
    quantity,
    unitPriceMinor,
    discountMinor,
    taxMinor,
    lineTotalMinor,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'local_sale_items';
  @override
  VerificationContext validateIntegrity(
    Insertable<SaleItemRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('organization_id')) {
      context.handle(
        _organizationIdMeta,
        organizationId.isAcceptableOrUnknown(
          data['organization_id']!,
          _organizationIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_organizationIdMeta);
    }
    if (data.containsKey('branch_id')) {
      context.handle(
        _branchIdMeta,
        branchId.isAcceptableOrUnknown(data['branch_id']!, _branchIdMeta),
      );
    } else if (isInserting) {
      context.missing(_branchIdMeta);
    }
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('sale_id')) {
      context.handle(
        _saleIdMeta,
        saleId.isAcceptableOrUnknown(data['sale_id']!, _saleIdMeta),
      );
    } else if (isInserting) {
      context.missing(_saleIdMeta);
    }
    if (data.containsKey('product_id')) {
      context.handle(
        _productIdMeta,
        productId.isAcceptableOrUnknown(data['product_id']!, _productIdMeta),
      );
    } else if (isInserting) {
      context.missing(_productIdMeta);
    }
    if (data.containsKey('sku_snapshot')) {
      context.handle(
        _skuSnapshotMeta,
        skuSnapshot.isAcceptableOrUnknown(
          data['sku_snapshot']!,
          _skuSnapshotMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_skuSnapshotMeta);
    }
    if (data.containsKey('name_snapshot')) {
      context.handle(
        _nameSnapshotMeta,
        nameSnapshot.isAcceptableOrUnknown(
          data['name_snapshot']!,
          _nameSnapshotMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_nameSnapshotMeta);
    }
    if (data.containsKey('quantity')) {
      context.handle(
        _quantityMeta,
        quantity.isAcceptableOrUnknown(data['quantity']!, _quantityMeta),
      );
    } else if (isInserting) {
      context.missing(_quantityMeta);
    }
    if (data.containsKey('unit_price_minor')) {
      context.handle(
        _unitPriceMinorMeta,
        unitPriceMinor.isAcceptableOrUnknown(
          data['unit_price_minor']!,
          _unitPriceMinorMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_unitPriceMinorMeta);
    }
    if (data.containsKey('discount_minor')) {
      context.handle(
        _discountMinorMeta,
        discountMinor.isAcceptableOrUnknown(
          data['discount_minor']!,
          _discountMinorMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_discountMinorMeta);
    }
    if (data.containsKey('tax_minor')) {
      context.handle(
        _taxMinorMeta,
        taxMinor.isAcceptableOrUnknown(data['tax_minor']!, _taxMinorMeta),
      );
    } else if (isInserting) {
      context.missing(_taxMinorMeta);
    }
    if (data.containsKey('line_total_minor')) {
      context.handle(
        _lineTotalMinorMeta,
        lineTotalMinor.isAcceptableOrUnknown(
          data['line_total_minor']!,
          _lineTotalMinorMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_lineTotalMinorMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {organizationId, branchId, id};
  @override
  SaleItemRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SaleItemRow(
      organizationId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}organization_id'],
      )!,
      branchId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}branch_id'],
      )!,
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      saleId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}sale_id'],
      )!,
      productId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}product_id'],
      )!,
      skuSnapshot: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}sku_snapshot'],
      )!,
      nameSnapshot: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name_snapshot'],
      )!,
      quantity: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}quantity'],
      )!,
      unitPriceMinor: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}unit_price_minor'],
      )!,
      discountMinor: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}discount_minor'],
      )!,
      taxMinor: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}tax_minor'],
      )!,
      lineTotalMinor: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}line_total_minor'],
      )!,
    );
  }

  @override
  $LocalSaleItemsTable createAlias(String alias) {
    return $LocalSaleItemsTable(attachedDatabase, alias);
  }
}

class SaleItemRow extends DataClass implements Insertable<SaleItemRow> {
  final String organizationId;
  final String branchId;
  final String id;
  final String saleId;
  final String productId;
  final String skuSnapshot;
  final String nameSnapshot;
  final int quantity;
  final int unitPriceMinor;
  final int discountMinor;
  final int taxMinor;
  final int lineTotalMinor;
  const SaleItemRow({
    required this.organizationId,
    required this.branchId,
    required this.id,
    required this.saleId,
    required this.productId,
    required this.skuSnapshot,
    required this.nameSnapshot,
    required this.quantity,
    required this.unitPriceMinor,
    required this.discountMinor,
    required this.taxMinor,
    required this.lineTotalMinor,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['organization_id'] = Variable<String>(organizationId);
    map['branch_id'] = Variable<String>(branchId);
    map['id'] = Variable<String>(id);
    map['sale_id'] = Variable<String>(saleId);
    map['product_id'] = Variable<String>(productId);
    map['sku_snapshot'] = Variable<String>(skuSnapshot);
    map['name_snapshot'] = Variable<String>(nameSnapshot);
    map['quantity'] = Variable<int>(quantity);
    map['unit_price_minor'] = Variable<int>(unitPriceMinor);
    map['discount_minor'] = Variable<int>(discountMinor);
    map['tax_minor'] = Variable<int>(taxMinor);
    map['line_total_minor'] = Variable<int>(lineTotalMinor);
    return map;
  }

  LocalSaleItemsCompanion toCompanion(bool nullToAbsent) {
    return LocalSaleItemsCompanion(
      organizationId: Value(organizationId),
      branchId: Value(branchId),
      id: Value(id),
      saleId: Value(saleId),
      productId: Value(productId),
      skuSnapshot: Value(skuSnapshot),
      nameSnapshot: Value(nameSnapshot),
      quantity: Value(quantity),
      unitPriceMinor: Value(unitPriceMinor),
      discountMinor: Value(discountMinor),
      taxMinor: Value(taxMinor),
      lineTotalMinor: Value(lineTotalMinor),
    );
  }

  factory SaleItemRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SaleItemRow(
      organizationId: serializer.fromJson<String>(json['organizationId']),
      branchId: serializer.fromJson<String>(json['branchId']),
      id: serializer.fromJson<String>(json['id']),
      saleId: serializer.fromJson<String>(json['saleId']),
      productId: serializer.fromJson<String>(json['productId']),
      skuSnapshot: serializer.fromJson<String>(json['skuSnapshot']),
      nameSnapshot: serializer.fromJson<String>(json['nameSnapshot']),
      quantity: serializer.fromJson<int>(json['quantity']),
      unitPriceMinor: serializer.fromJson<int>(json['unitPriceMinor']),
      discountMinor: serializer.fromJson<int>(json['discountMinor']),
      taxMinor: serializer.fromJson<int>(json['taxMinor']),
      lineTotalMinor: serializer.fromJson<int>(json['lineTotalMinor']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'organizationId': serializer.toJson<String>(organizationId),
      'branchId': serializer.toJson<String>(branchId),
      'id': serializer.toJson<String>(id),
      'saleId': serializer.toJson<String>(saleId),
      'productId': serializer.toJson<String>(productId),
      'skuSnapshot': serializer.toJson<String>(skuSnapshot),
      'nameSnapshot': serializer.toJson<String>(nameSnapshot),
      'quantity': serializer.toJson<int>(quantity),
      'unitPriceMinor': serializer.toJson<int>(unitPriceMinor),
      'discountMinor': serializer.toJson<int>(discountMinor),
      'taxMinor': serializer.toJson<int>(taxMinor),
      'lineTotalMinor': serializer.toJson<int>(lineTotalMinor),
    };
  }

  SaleItemRow copyWith({
    String? organizationId,
    String? branchId,
    String? id,
    String? saleId,
    String? productId,
    String? skuSnapshot,
    String? nameSnapshot,
    int? quantity,
    int? unitPriceMinor,
    int? discountMinor,
    int? taxMinor,
    int? lineTotalMinor,
  }) => SaleItemRow(
    organizationId: organizationId ?? this.organizationId,
    branchId: branchId ?? this.branchId,
    id: id ?? this.id,
    saleId: saleId ?? this.saleId,
    productId: productId ?? this.productId,
    skuSnapshot: skuSnapshot ?? this.skuSnapshot,
    nameSnapshot: nameSnapshot ?? this.nameSnapshot,
    quantity: quantity ?? this.quantity,
    unitPriceMinor: unitPriceMinor ?? this.unitPriceMinor,
    discountMinor: discountMinor ?? this.discountMinor,
    taxMinor: taxMinor ?? this.taxMinor,
    lineTotalMinor: lineTotalMinor ?? this.lineTotalMinor,
  );
  SaleItemRow copyWithCompanion(LocalSaleItemsCompanion data) {
    return SaleItemRow(
      organizationId: data.organizationId.present
          ? data.organizationId.value
          : this.organizationId,
      branchId: data.branchId.present ? data.branchId.value : this.branchId,
      id: data.id.present ? data.id.value : this.id,
      saleId: data.saleId.present ? data.saleId.value : this.saleId,
      productId: data.productId.present ? data.productId.value : this.productId,
      skuSnapshot: data.skuSnapshot.present
          ? data.skuSnapshot.value
          : this.skuSnapshot,
      nameSnapshot: data.nameSnapshot.present
          ? data.nameSnapshot.value
          : this.nameSnapshot,
      quantity: data.quantity.present ? data.quantity.value : this.quantity,
      unitPriceMinor: data.unitPriceMinor.present
          ? data.unitPriceMinor.value
          : this.unitPriceMinor,
      discountMinor: data.discountMinor.present
          ? data.discountMinor.value
          : this.discountMinor,
      taxMinor: data.taxMinor.present ? data.taxMinor.value : this.taxMinor,
      lineTotalMinor: data.lineTotalMinor.present
          ? data.lineTotalMinor.value
          : this.lineTotalMinor,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SaleItemRow(')
          ..write('organizationId: $organizationId, ')
          ..write('branchId: $branchId, ')
          ..write('id: $id, ')
          ..write('saleId: $saleId, ')
          ..write('productId: $productId, ')
          ..write('skuSnapshot: $skuSnapshot, ')
          ..write('nameSnapshot: $nameSnapshot, ')
          ..write('quantity: $quantity, ')
          ..write('unitPriceMinor: $unitPriceMinor, ')
          ..write('discountMinor: $discountMinor, ')
          ..write('taxMinor: $taxMinor, ')
          ..write('lineTotalMinor: $lineTotalMinor')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    organizationId,
    branchId,
    id,
    saleId,
    productId,
    skuSnapshot,
    nameSnapshot,
    quantity,
    unitPriceMinor,
    discountMinor,
    taxMinor,
    lineTotalMinor,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SaleItemRow &&
          other.organizationId == this.organizationId &&
          other.branchId == this.branchId &&
          other.id == this.id &&
          other.saleId == this.saleId &&
          other.productId == this.productId &&
          other.skuSnapshot == this.skuSnapshot &&
          other.nameSnapshot == this.nameSnapshot &&
          other.quantity == this.quantity &&
          other.unitPriceMinor == this.unitPriceMinor &&
          other.discountMinor == this.discountMinor &&
          other.taxMinor == this.taxMinor &&
          other.lineTotalMinor == this.lineTotalMinor);
}

class LocalSaleItemsCompanion extends UpdateCompanion<SaleItemRow> {
  final Value<String> organizationId;
  final Value<String> branchId;
  final Value<String> id;
  final Value<String> saleId;
  final Value<String> productId;
  final Value<String> skuSnapshot;
  final Value<String> nameSnapshot;
  final Value<int> quantity;
  final Value<int> unitPriceMinor;
  final Value<int> discountMinor;
  final Value<int> taxMinor;
  final Value<int> lineTotalMinor;
  final Value<int> rowid;
  const LocalSaleItemsCompanion({
    this.organizationId = const Value.absent(),
    this.branchId = const Value.absent(),
    this.id = const Value.absent(),
    this.saleId = const Value.absent(),
    this.productId = const Value.absent(),
    this.skuSnapshot = const Value.absent(),
    this.nameSnapshot = const Value.absent(),
    this.quantity = const Value.absent(),
    this.unitPriceMinor = const Value.absent(),
    this.discountMinor = const Value.absent(),
    this.taxMinor = const Value.absent(),
    this.lineTotalMinor = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  LocalSaleItemsCompanion.insert({
    required String organizationId,
    required String branchId,
    required String id,
    required String saleId,
    required String productId,
    required String skuSnapshot,
    required String nameSnapshot,
    required int quantity,
    required int unitPriceMinor,
    required int discountMinor,
    required int taxMinor,
    required int lineTotalMinor,
    this.rowid = const Value.absent(),
  }) : organizationId = Value(organizationId),
       branchId = Value(branchId),
       id = Value(id),
       saleId = Value(saleId),
       productId = Value(productId),
       skuSnapshot = Value(skuSnapshot),
       nameSnapshot = Value(nameSnapshot),
       quantity = Value(quantity),
       unitPriceMinor = Value(unitPriceMinor),
       discountMinor = Value(discountMinor),
       taxMinor = Value(taxMinor),
       lineTotalMinor = Value(lineTotalMinor);
  static Insertable<SaleItemRow> custom({
    Expression<String>? organizationId,
    Expression<String>? branchId,
    Expression<String>? id,
    Expression<String>? saleId,
    Expression<String>? productId,
    Expression<String>? skuSnapshot,
    Expression<String>? nameSnapshot,
    Expression<int>? quantity,
    Expression<int>? unitPriceMinor,
    Expression<int>? discountMinor,
    Expression<int>? taxMinor,
    Expression<int>? lineTotalMinor,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (organizationId != null) 'organization_id': organizationId,
      if (branchId != null) 'branch_id': branchId,
      if (id != null) 'id': id,
      if (saleId != null) 'sale_id': saleId,
      if (productId != null) 'product_id': productId,
      if (skuSnapshot != null) 'sku_snapshot': skuSnapshot,
      if (nameSnapshot != null) 'name_snapshot': nameSnapshot,
      if (quantity != null) 'quantity': quantity,
      if (unitPriceMinor != null) 'unit_price_minor': unitPriceMinor,
      if (discountMinor != null) 'discount_minor': discountMinor,
      if (taxMinor != null) 'tax_minor': taxMinor,
      if (lineTotalMinor != null) 'line_total_minor': lineTotalMinor,
      if (rowid != null) 'rowid': rowid,
    });
  }

  LocalSaleItemsCompanion copyWith({
    Value<String>? organizationId,
    Value<String>? branchId,
    Value<String>? id,
    Value<String>? saleId,
    Value<String>? productId,
    Value<String>? skuSnapshot,
    Value<String>? nameSnapshot,
    Value<int>? quantity,
    Value<int>? unitPriceMinor,
    Value<int>? discountMinor,
    Value<int>? taxMinor,
    Value<int>? lineTotalMinor,
    Value<int>? rowid,
  }) {
    return LocalSaleItemsCompanion(
      organizationId: organizationId ?? this.organizationId,
      branchId: branchId ?? this.branchId,
      id: id ?? this.id,
      saleId: saleId ?? this.saleId,
      productId: productId ?? this.productId,
      skuSnapshot: skuSnapshot ?? this.skuSnapshot,
      nameSnapshot: nameSnapshot ?? this.nameSnapshot,
      quantity: quantity ?? this.quantity,
      unitPriceMinor: unitPriceMinor ?? this.unitPriceMinor,
      discountMinor: discountMinor ?? this.discountMinor,
      taxMinor: taxMinor ?? this.taxMinor,
      lineTotalMinor: lineTotalMinor ?? this.lineTotalMinor,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (organizationId.present) {
      map['organization_id'] = Variable<String>(organizationId.value);
    }
    if (branchId.present) {
      map['branch_id'] = Variable<String>(branchId.value);
    }
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (saleId.present) {
      map['sale_id'] = Variable<String>(saleId.value);
    }
    if (productId.present) {
      map['product_id'] = Variable<String>(productId.value);
    }
    if (skuSnapshot.present) {
      map['sku_snapshot'] = Variable<String>(skuSnapshot.value);
    }
    if (nameSnapshot.present) {
      map['name_snapshot'] = Variable<String>(nameSnapshot.value);
    }
    if (quantity.present) {
      map['quantity'] = Variable<int>(quantity.value);
    }
    if (unitPriceMinor.present) {
      map['unit_price_minor'] = Variable<int>(unitPriceMinor.value);
    }
    if (discountMinor.present) {
      map['discount_minor'] = Variable<int>(discountMinor.value);
    }
    if (taxMinor.present) {
      map['tax_minor'] = Variable<int>(taxMinor.value);
    }
    if (lineTotalMinor.present) {
      map['line_total_minor'] = Variable<int>(lineTotalMinor.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('LocalSaleItemsCompanion(')
          ..write('organizationId: $organizationId, ')
          ..write('branchId: $branchId, ')
          ..write('id: $id, ')
          ..write('saleId: $saleId, ')
          ..write('productId: $productId, ')
          ..write('skuSnapshot: $skuSnapshot, ')
          ..write('nameSnapshot: $nameSnapshot, ')
          ..write('quantity: $quantity, ')
          ..write('unitPriceMinor: $unitPriceMinor, ')
          ..write('discountMinor: $discountMinor, ')
          ..write('taxMinor: $taxMinor, ')
          ..write('lineTotalMinor: $lineTotalMinor, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $LocalPaymentsTable extends LocalPayments
    with TableInfo<$LocalPaymentsTable, PaymentRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $LocalPaymentsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _organizationIdMeta = const VerificationMeta(
    'organizationId',
  );
  @override
  late final GeneratedColumn<String> organizationId = GeneratedColumn<String>(
    'organization_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _branchIdMeta = const VerificationMeta(
    'branchId',
  );
  @override
  late final GeneratedColumn<String> branchId = GeneratedColumn<String>(
    'branch_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _saleIdMeta = const VerificationMeta('saleId');
  @override
  late final GeneratedColumn<String> saleId = GeneratedColumn<String>(
    'sale_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _methodMeta = const VerificationMeta('method');
  @override
  late final GeneratedColumn<String> method = GeneratedColumn<String>(
    'method',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _amountMinorMeta = const VerificationMeta(
    'amountMinor',
  );
  @override
  late final GeneratedColumn<int> amountMinor = GeneratedColumn<int>(
    'amount_minor',
    aliasedName,
    false,
    check: () => ComparableExpr(amountMinor).isBiggerThanValue(0),
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _currencyMeta = const VerificationMeta(
    'currency',
  );
  @override
  late final GeneratedColumn<String> currency = GeneratedColumn<String>(
    'currency',
    aliasedName,
    false,
    additionalChecks: GeneratedColumn.checkTextLength(
      minTextLength: 3,
      maxTextLength: 3,
    ),
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _verificationModeMeta = const VerificationMeta(
    'verificationMode',
  );
  @override
  late final GeneratedColumn<String> verificationMode = GeneratedColumn<String>(
    'verification_mode',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _referenceMeta = const VerificationMeta(
    'reference',
  );
  @override
  late final GeneratedColumn<String> reference = GeneratedColumn<String>(
    'reference',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _recordedByMeta = const VerificationMeta(
    'recordedBy',
  );
  @override
  late final GeneratedColumn<String> recordedBy = GeneratedColumn<String>(
    'recorded_by',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _recordedAtMeta = const VerificationMeta(
    'recordedAt',
  );
  @override
  late final GeneratedColumn<DateTime> recordedAt = GeneratedColumn<DateTime>(
    'recorded_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    organizationId,
    branchId,
    id,
    saleId,
    method,
    amountMinor,
    currency,
    verificationMode,
    reference,
    recordedBy,
    recordedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'local_payments';
  @override
  VerificationContext validateIntegrity(
    Insertable<PaymentRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('organization_id')) {
      context.handle(
        _organizationIdMeta,
        organizationId.isAcceptableOrUnknown(
          data['organization_id']!,
          _organizationIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_organizationIdMeta);
    }
    if (data.containsKey('branch_id')) {
      context.handle(
        _branchIdMeta,
        branchId.isAcceptableOrUnknown(data['branch_id']!, _branchIdMeta),
      );
    } else if (isInserting) {
      context.missing(_branchIdMeta);
    }
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('sale_id')) {
      context.handle(
        _saleIdMeta,
        saleId.isAcceptableOrUnknown(data['sale_id']!, _saleIdMeta),
      );
    } else if (isInserting) {
      context.missing(_saleIdMeta);
    }
    if (data.containsKey('method')) {
      context.handle(
        _methodMeta,
        method.isAcceptableOrUnknown(data['method']!, _methodMeta),
      );
    } else if (isInserting) {
      context.missing(_methodMeta);
    }
    if (data.containsKey('amount_minor')) {
      context.handle(
        _amountMinorMeta,
        amountMinor.isAcceptableOrUnknown(
          data['amount_minor']!,
          _amountMinorMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_amountMinorMeta);
    }
    if (data.containsKey('currency')) {
      context.handle(
        _currencyMeta,
        currency.isAcceptableOrUnknown(data['currency']!, _currencyMeta),
      );
    } else if (isInserting) {
      context.missing(_currencyMeta);
    }
    if (data.containsKey('verification_mode')) {
      context.handle(
        _verificationModeMeta,
        verificationMode.isAcceptableOrUnknown(
          data['verification_mode']!,
          _verificationModeMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_verificationModeMeta);
    }
    if (data.containsKey('reference')) {
      context.handle(
        _referenceMeta,
        reference.isAcceptableOrUnknown(data['reference']!, _referenceMeta),
      );
    }
    if (data.containsKey('recorded_by')) {
      context.handle(
        _recordedByMeta,
        recordedBy.isAcceptableOrUnknown(data['recorded_by']!, _recordedByMeta),
      );
    } else if (isInserting) {
      context.missing(_recordedByMeta);
    }
    if (data.containsKey('recorded_at')) {
      context.handle(
        _recordedAtMeta,
        recordedAt.isAcceptableOrUnknown(data['recorded_at']!, _recordedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_recordedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {organizationId, branchId, id};
  @override
  PaymentRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return PaymentRow(
      organizationId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}organization_id'],
      )!,
      branchId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}branch_id'],
      )!,
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      saleId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}sale_id'],
      )!,
      method: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}method'],
      )!,
      amountMinor: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}amount_minor'],
      )!,
      currency: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}currency'],
      )!,
      verificationMode: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}verification_mode'],
      )!,
      reference: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}reference'],
      ),
      recordedBy: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}recorded_by'],
      )!,
      recordedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}recorded_at'],
      )!,
    );
  }

  @override
  $LocalPaymentsTable createAlias(String alias) {
    return $LocalPaymentsTable(attachedDatabase, alias);
  }
}

class PaymentRow extends DataClass implements Insertable<PaymentRow> {
  final String organizationId;
  final String branchId;
  final String id;
  final String saleId;
  final String method;
  final int amountMinor;
  final String currency;
  final String verificationMode;
  final String? reference;
  final String recordedBy;
  final DateTime recordedAt;
  const PaymentRow({
    required this.organizationId,
    required this.branchId,
    required this.id,
    required this.saleId,
    required this.method,
    required this.amountMinor,
    required this.currency,
    required this.verificationMode,
    this.reference,
    required this.recordedBy,
    required this.recordedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['organization_id'] = Variable<String>(organizationId);
    map['branch_id'] = Variable<String>(branchId);
    map['id'] = Variable<String>(id);
    map['sale_id'] = Variable<String>(saleId);
    map['method'] = Variable<String>(method);
    map['amount_minor'] = Variable<int>(amountMinor);
    map['currency'] = Variable<String>(currency);
    map['verification_mode'] = Variable<String>(verificationMode);
    if (!nullToAbsent || reference != null) {
      map['reference'] = Variable<String>(reference);
    }
    map['recorded_by'] = Variable<String>(recordedBy);
    map['recorded_at'] = Variable<DateTime>(recordedAt);
    return map;
  }

  LocalPaymentsCompanion toCompanion(bool nullToAbsent) {
    return LocalPaymentsCompanion(
      organizationId: Value(organizationId),
      branchId: Value(branchId),
      id: Value(id),
      saleId: Value(saleId),
      method: Value(method),
      amountMinor: Value(amountMinor),
      currency: Value(currency),
      verificationMode: Value(verificationMode),
      reference: reference == null && nullToAbsent
          ? const Value.absent()
          : Value(reference),
      recordedBy: Value(recordedBy),
      recordedAt: Value(recordedAt),
    );
  }

  factory PaymentRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return PaymentRow(
      organizationId: serializer.fromJson<String>(json['organizationId']),
      branchId: serializer.fromJson<String>(json['branchId']),
      id: serializer.fromJson<String>(json['id']),
      saleId: serializer.fromJson<String>(json['saleId']),
      method: serializer.fromJson<String>(json['method']),
      amountMinor: serializer.fromJson<int>(json['amountMinor']),
      currency: serializer.fromJson<String>(json['currency']),
      verificationMode: serializer.fromJson<String>(json['verificationMode']),
      reference: serializer.fromJson<String?>(json['reference']),
      recordedBy: serializer.fromJson<String>(json['recordedBy']),
      recordedAt: serializer.fromJson<DateTime>(json['recordedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'organizationId': serializer.toJson<String>(organizationId),
      'branchId': serializer.toJson<String>(branchId),
      'id': serializer.toJson<String>(id),
      'saleId': serializer.toJson<String>(saleId),
      'method': serializer.toJson<String>(method),
      'amountMinor': serializer.toJson<int>(amountMinor),
      'currency': serializer.toJson<String>(currency),
      'verificationMode': serializer.toJson<String>(verificationMode),
      'reference': serializer.toJson<String?>(reference),
      'recordedBy': serializer.toJson<String>(recordedBy),
      'recordedAt': serializer.toJson<DateTime>(recordedAt),
    };
  }

  PaymentRow copyWith({
    String? organizationId,
    String? branchId,
    String? id,
    String? saleId,
    String? method,
    int? amountMinor,
    String? currency,
    String? verificationMode,
    Value<String?> reference = const Value.absent(),
    String? recordedBy,
    DateTime? recordedAt,
  }) => PaymentRow(
    organizationId: organizationId ?? this.organizationId,
    branchId: branchId ?? this.branchId,
    id: id ?? this.id,
    saleId: saleId ?? this.saleId,
    method: method ?? this.method,
    amountMinor: amountMinor ?? this.amountMinor,
    currency: currency ?? this.currency,
    verificationMode: verificationMode ?? this.verificationMode,
    reference: reference.present ? reference.value : this.reference,
    recordedBy: recordedBy ?? this.recordedBy,
    recordedAt: recordedAt ?? this.recordedAt,
  );
  PaymentRow copyWithCompanion(LocalPaymentsCompanion data) {
    return PaymentRow(
      organizationId: data.organizationId.present
          ? data.organizationId.value
          : this.organizationId,
      branchId: data.branchId.present ? data.branchId.value : this.branchId,
      id: data.id.present ? data.id.value : this.id,
      saleId: data.saleId.present ? data.saleId.value : this.saleId,
      method: data.method.present ? data.method.value : this.method,
      amountMinor: data.amountMinor.present
          ? data.amountMinor.value
          : this.amountMinor,
      currency: data.currency.present ? data.currency.value : this.currency,
      verificationMode: data.verificationMode.present
          ? data.verificationMode.value
          : this.verificationMode,
      reference: data.reference.present ? data.reference.value : this.reference,
      recordedBy: data.recordedBy.present
          ? data.recordedBy.value
          : this.recordedBy,
      recordedAt: data.recordedAt.present
          ? data.recordedAt.value
          : this.recordedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('PaymentRow(')
          ..write('organizationId: $organizationId, ')
          ..write('branchId: $branchId, ')
          ..write('id: $id, ')
          ..write('saleId: $saleId, ')
          ..write('method: $method, ')
          ..write('amountMinor: $amountMinor, ')
          ..write('currency: $currency, ')
          ..write('verificationMode: $verificationMode, ')
          ..write('reference: $reference, ')
          ..write('recordedBy: $recordedBy, ')
          ..write('recordedAt: $recordedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    organizationId,
    branchId,
    id,
    saleId,
    method,
    amountMinor,
    currency,
    verificationMode,
    reference,
    recordedBy,
    recordedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is PaymentRow &&
          other.organizationId == this.organizationId &&
          other.branchId == this.branchId &&
          other.id == this.id &&
          other.saleId == this.saleId &&
          other.method == this.method &&
          other.amountMinor == this.amountMinor &&
          other.currency == this.currency &&
          other.verificationMode == this.verificationMode &&
          other.reference == this.reference &&
          other.recordedBy == this.recordedBy &&
          other.recordedAt == this.recordedAt);
}

class LocalPaymentsCompanion extends UpdateCompanion<PaymentRow> {
  final Value<String> organizationId;
  final Value<String> branchId;
  final Value<String> id;
  final Value<String> saleId;
  final Value<String> method;
  final Value<int> amountMinor;
  final Value<String> currency;
  final Value<String> verificationMode;
  final Value<String?> reference;
  final Value<String> recordedBy;
  final Value<DateTime> recordedAt;
  final Value<int> rowid;
  const LocalPaymentsCompanion({
    this.organizationId = const Value.absent(),
    this.branchId = const Value.absent(),
    this.id = const Value.absent(),
    this.saleId = const Value.absent(),
    this.method = const Value.absent(),
    this.amountMinor = const Value.absent(),
    this.currency = const Value.absent(),
    this.verificationMode = const Value.absent(),
    this.reference = const Value.absent(),
    this.recordedBy = const Value.absent(),
    this.recordedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  LocalPaymentsCompanion.insert({
    required String organizationId,
    required String branchId,
    required String id,
    required String saleId,
    required String method,
    required int amountMinor,
    required String currency,
    required String verificationMode,
    this.reference = const Value.absent(),
    required String recordedBy,
    required DateTime recordedAt,
    this.rowid = const Value.absent(),
  }) : organizationId = Value(organizationId),
       branchId = Value(branchId),
       id = Value(id),
       saleId = Value(saleId),
       method = Value(method),
       amountMinor = Value(amountMinor),
       currency = Value(currency),
       verificationMode = Value(verificationMode),
       recordedBy = Value(recordedBy),
       recordedAt = Value(recordedAt);
  static Insertable<PaymentRow> custom({
    Expression<String>? organizationId,
    Expression<String>? branchId,
    Expression<String>? id,
    Expression<String>? saleId,
    Expression<String>? method,
    Expression<int>? amountMinor,
    Expression<String>? currency,
    Expression<String>? verificationMode,
    Expression<String>? reference,
    Expression<String>? recordedBy,
    Expression<DateTime>? recordedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (organizationId != null) 'organization_id': organizationId,
      if (branchId != null) 'branch_id': branchId,
      if (id != null) 'id': id,
      if (saleId != null) 'sale_id': saleId,
      if (method != null) 'method': method,
      if (amountMinor != null) 'amount_minor': amountMinor,
      if (currency != null) 'currency': currency,
      if (verificationMode != null) 'verification_mode': verificationMode,
      if (reference != null) 'reference': reference,
      if (recordedBy != null) 'recorded_by': recordedBy,
      if (recordedAt != null) 'recorded_at': recordedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  LocalPaymentsCompanion copyWith({
    Value<String>? organizationId,
    Value<String>? branchId,
    Value<String>? id,
    Value<String>? saleId,
    Value<String>? method,
    Value<int>? amountMinor,
    Value<String>? currency,
    Value<String>? verificationMode,
    Value<String?>? reference,
    Value<String>? recordedBy,
    Value<DateTime>? recordedAt,
    Value<int>? rowid,
  }) {
    return LocalPaymentsCompanion(
      organizationId: organizationId ?? this.organizationId,
      branchId: branchId ?? this.branchId,
      id: id ?? this.id,
      saleId: saleId ?? this.saleId,
      method: method ?? this.method,
      amountMinor: amountMinor ?? this.amountMinor,
      currency: currency ?? this.currency,
      verificationMode: verificationMode ?? this.verificationMode,
      reference: reference ?? this.reference,
      recordedBy: recordedBy ?? this.recordedBy,
      recordedAt: recordedAt ?? this.recordedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (organizationId.present) {
      map['organization_id'] = Variable<String>(organizationId.value);
    }
    if (branchId.present) {
      map['branch_id'] = Variable<String>(branchId.value);
    }
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (saleId.present) {
      map['sale_id'] = Variable<String>(saleId.value);
    }
    if (method.present) {
      map['method'] = Variable<String>(method.value);
    }
    if (amountMinor.present) {
      map['amount_minor'] = Variable<int>(amountMinor.value);
    }
    if (currency.present) {
      map['currency'] = Variable<String>(currency.value);
    }
    if (verificationMode.present) {
      map['verification_mode'] = Variable<String>(verificationMode.value);
    }
    if (reference.present) {
      map['reference'] = Variable<String>(reference.value);
    }
    if (recordedBy.present) {
      map['recorded_by'] = Variable<String>(recordedBy.value);
    }
    if (recordedAt.present) {
      map['recorded_at'] = Variable<DateTime>(recordedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('LocalPaymentsCompanion(')
          ..write('organizationId: $organizationId, ')
          ..write('branchId: $branchId, ')
          ..write('id: $id, ')
          ..write('saleId: $saleId, ')
          ..write('method: $method, ')
          ..write('amountMinor: $amountMinor, ')
          ..write('currency: $currency, ')
          ..write('verificationMode: $verificationMode, ')
          ..write('reference: $reference, ')
          ..write('recordedBy: $recordedBy, ')
          ..write('recordedAt: $recordedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $SyncOutboxTable extends SyncOutbox
    with TableInfo<$SyncOutboxTable, OutboxRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SyncOutboxTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _organizationIdMeta = const VerificationMeta(
    'organizationId',
  );
  @override
  late final GeneratedColumn<String> organizationId = GeneratedColumn<String>(
    'organization_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _branchIdMeta = const VerificationMeta(
    'branchId',
  );
  @override
  late final GeneratedColumn<String> branchId = GeneratedColumn<String>(
    'branch_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _deviceIdMeta = const VerificationMeta(
    'deviceId',
  );
  @override
  late final GeneratedColumn<String> deviceId = GeneratedColumn<String>(
    'device_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _actorIdMeta = const VerificationMeta(
    'actorId',
  );
  @override
  late final GeneratedColumn<String> actorId = GeneratedColumn<String>(
    'actor_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _documentIdMeta = const VerificationMeta(
    'documentId',
  );
  @override
  late final GeneratedColumn<String> documentId = GeneratedColumn<String>(
    'document_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _eventTypeMeta = const VerificationMeta(
    'eventType',
  );
  @override
  late final GeneratedColumn<String> eventType = GeneratedColumn<String>(
    'event_type',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _schemaVersionMeta = const VerificationMeta(
    'schemaVersion',
  );
  @override
  late final GeneratedColumn<int> schemaVersion = GeneratedColumn<int>(
    'schema_version',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(1),
  );
  static const VerificationMeta _payloadJsonMeta = const VerificationMeta(
    'payloadJson',
  );
  @override
  late final GeneratedColumn<String> payloadJson = GeneratedColumn<String>(
    'payload_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _payloadDigestMeta = const VerificationMeta(
    'payloadDigest',
  );
  @override
  late final GeneratedColumn<String> payloadDigest = GeneratedColumn<String>(
    'payload_digest',
    aliasedName,
    false,
    additionalChecks: GeneratedColumn.checkTextLength(
      minTextLength: 64,
      maxTextLength: 64,
    ),
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _occurredAtIsoMeta = const VerificationMeta(
    'occurredAtIso',
  );
  @override
  late final GeneratedColumn<String> occurredAtIso = GeneratedColumn<String>(
    'occurred_at_iso',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _statusMeta = const VerificationMeta('status');
  @override
  late final GeneratedColumn<String> status = GeneratedColumn<String>(
    'status',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('PENDING'),
  );
  static const VerificationMeta _attemptsMeta = const VerificationMeta(
    'attempts',
  );
  @override
  late final GeneratedColumn<int> attempts = GeneratedColumn<int>(
    'attempts',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _leaseOwnerMeta = const VerificationMeta(
    'leaseOwner',
  );
  @override
  late final GeneratedColumn<String> leaseOwner = GeneratedColumn<String>(
    'lease_owner',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _leaseTokenMeta = const VerificationMeta(
    'leaseToken',
  );
  @override
  late final GeneratedColumn<String> leaseToken = GeneratedColumn<String>(
    'lease_token',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _leaseUntilMeta = const VerificationMeta(
    'leaseUntil',
  );
  @override
  late final GeneratedColumn<DateTime> leaseUntil = GeneratedColumn<DateTime>(
    'lease_until',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _nextAttemptAtMeta = const VerificationMeta(
    'nextAttemptAt',
  );
  @override
  late final GeneratedColumn<DateTime> nextAttemptAt =
      GeneratedColumn<DateTime>(
        'next_attempt_at',
        aliasedName,
        true,
        type: DriftSqlType.dateTime,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _lastErrorMeta = const VerificationMeta(
    'lastError',
  );
  @override
  late final GeneratedColumn<String> lastError = GeneratedColumn<String>(
    'last_error',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _acceptedAtMeta = const VerificationMeta(
    'acceptedAt',
  );
  @override
  late final GeneratedColumn<DateTime> acceptedAt = GeneratedColumn<DateTime>(
    'accepted_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _serverReceiptIdMeta = const VerificationMeta(
    'serverReceiptId',
  );
  @override
  late final GeneratedColumn<String> serverReceiptId = GeneratedColumn<String>(
    'server_receipt_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    organizationId,
    branchId,
    id,
    deviceId,
    actorId,
    documentId,
    eventType,
    schemaVersion,
    payloadJson,
    payloadDigest,
    occurredAtIso,
    status,
    attempts,
    leaseOwner,
    leaseToken,
    leaseUntil,
    nextAttemptAt,
    lastError,
    createdAt,
    acceptedAt,
    serverReceiptId,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'sync_outbox';
  @override
  VerificationContext validateIntegrity(
    Insertable<OutboxRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('organization_id')) {
      context.handle(
        _organizationIdMeta,
        organizationId.isAcceptableOrUnknown(
          data['organization_id']!,
          _organizationIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_organizationIdMeta);
    }
    if (data.containsKey('branch_id')) {
      context.handle(
        _branchIdMeta,
        branchId.isAcceptableOrUnknown(data['branch_id']!, _branchIdMeta),
      );
    } else if (isInserting) {
      context.missing(_branchIdMeta);
    }
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('device_id')) {
      context.handle(
        _deviceIdMeta,
        deviceId.isAcceptableOrUnknown(data['device_id']!, _deviceIdMeta),
      );
    } else if (isInserting) {
      context.missing(_deviceIdMeta);
    }
    if (data.containsKey('actor_id')) {
      context.handle(
        _actorIdMeta,
        actorId.isAcceptableOrUnknown(data['actor_id']!, _actorIdMeta),
      );
    } else if (isInserting) {
      context.missing(_actorIdMeta);
    }
    if (data.containsKey('document_id')) {
      context.handle(
        _documentIdMeta,
        documentId.isAcceptableOrUnknown(data['document_id']!, _documentIdMeta),
      );
    } else if (isInserting) {
      context.missing(_documentIdMeta);
    }
    if (data.containsKey('event_type')) {
      context.handle(
        _eventTypeMeta,
        eventType.isAcceptableOrUnknown(data['event_type']!, _eventTypeMeta),
      );
    } else if (isInserting) {
      context.missing(_eventTypeMeta);
    }
    if (data.containsKey('schema_version')) {
      context.handle(
        _schemaVersionMeta,
        schemaVersion.isAcceptableOrUnknown(
          data['schema_version']!,
          _schemaVersionMeta,
        ),
      );
    }
    if (data.containsKey('payload_json')) {
      context.handle(
        _payloadJsonMeta,
        payloadJson.isAcceptableOrUnknown(
          data['payload_json']!,
          _payloadJsonMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_payloadJsonMeta);
    }
    if (data.containsKey('payload_digest')) {
      context.handle(
        _payloadDigestMeta,
        payloadDigest.isAcceptableOrUnknown(
          data['payload_digest']!,
          _payloadDigestMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_payloadDigestMeta);
    }
    if (data.containsKey('occurred_at_iso')) {
      context.handle(
        _occurredAtIsoMeta,
        occurredAtIso.isAcceptableOrUnknown(
          data['occurred_at_iso']!,
          _occurredAtIsoMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_occurredAtIsoMeta);
    }
    if (data.containsKey('status')) {
      context.handle(
        _statusMeta,
        status.isAcceptableOrUnknown(data['status']!, _statusMeta),
      );
    }
    if (data.containsKey('attempts')) {
      context.handle(
        _attemptsMeta,
        attempts.isAcceptableOrUnknown(data['attempts']!, _attemptsMeta),
      );
    }
    if (data.containsKey('lease_owner')) {
      context.handle(
        _leaseOwnerMeta,
        leaseOwner.isAcceptableOrUnknown(data['lease_owner']!, _leaseOwnerMeta),
      );
    }
    if (data.containsKey('lease_token')) {
      context.handle(
        _leaseTokenMeta,
        leaseToken.isAcceptableOrUnknown(data['lease_token']!, _leaseTokenMeta),
      );
    }
    if (data.containsKey('lease_until')) {
      context.handle(
        _leaseUntilMeta,
        leaseUntil.isAcceptableOrUnknown(data['lease_until']!, _leaseUntilMeta),
      );
    }
    if (data.containsKey('next_attempt_at')) {
      context.handle(
        _nextAttemptAtMeta,
        nextAttemptAt.isAcceptableOrUnknown(
          data['next_attempt_at']!,
          _nextAttemptAtMeta,
        ),
      );
    }
    if (data.containsKey('last_error')) {
      context.handle(
        _lastErrorMeta,
        lastError.isAcceptableOrUnknown(data['last_error']!, _lastErrorMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('accepted_at')) {
      context.handle(
        _acceptedAtMeta,
        acceptedAt.isAcceptableOrUnknown(data['accepted_at']!, _acceptedAtMeta),
      );
    }
    if (data.containsKey('server_receipt_id')) {
      context.handle(
        _serverReceiptIdMeta,
        serverReceiptId.isAcceptableOrUnknown(
          data['server_receipt_id']!,
          _serverReceiptIdMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {organizationId, branchId, id};
  @override
  List<Set<GeneratedColumn>> get uniqueKeys => [
    {organizationId, deviceId, id},
    {organizationId, branchId, documentId, eventType},
  ];
  @override
  OutboxRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return OutboxRow(
      organizationId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}organization_id'],
      )!,
      branchId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}branch_id'],
      )!,
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      deviceId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}device_id'],
      )!,
      actorId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}actor_id'],
      )!,
      documentId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}document_id'],
      )!,
      eventType: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}event_type'],
      )!,
      schemaVersion: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}schema_version'],
      )!,
      payloadJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}payload_json'],
      )!,
      payloadDigest: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}payload_digest'],
      )!,
      occurredAtIso: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}occurred_at_iso'],
      )!,
      status: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}status'],
      )!,
      attempts: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}attempts'],
      )!,
      leaseOwner: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}lease_owner'],
      ),
      leaseToken: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}lease_token'],
      ),
      leaseUntil: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}lease_until'],
      ),
      nextAttemptAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}next_attempt_at'],
      ),
      lastError: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}last_error'],
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      acceptedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}accepted_at'],
      ),
      serverReceiptId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}server_receipt_id'],
      ),
    );
  }

  @override
  $SyncOutboxTable createAlias(String alias) {
    return $SyncOutboxTable(attachedDatabase, alias);
  }
}

class OutboxRow extends DataClass implements Insertable<OutboxRow> {
  final String organizationId;
  final String branchId;
  final String id;
  final String deviceId;
  final String actorId;
  final String documentId;
  final String eventType;
  final int schemaVersion;
  final String payloadJson;
  final String payloadDigest;
  final String occurredAtIso;
  final String status;
  final int attempts;
  final String? leaseOwner;
  final String? leaseToken;
  final DateTime? leaseUntil;
  final DateTime? nextAttemptAt;
  final String? lastError;
  final DateTime createdAt;
  final DateTime? acceptedAt;
  final String? serverReceiptId;
  const OutboxRow({
    required this.organizationId,
    required this.branchId,
    required this.id,
    required this.deviceId,
    required this.actorId,
    required this.documentId,
    required this.eventType,
    required this.schemaVersion,
    required this.payloadJson,
    required this.payloadDigest,
    required this.occurredAtIso,
    required this.status,
    required this.attempts,
    this.leaseOwner,
    this.leaseToken,
    this.leaseUntil,
    this.nextAttemptAt,
    this.lastError,
    required this.createdAt,
    this.acceptedAt,
    this.serverReceiptId,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['organization_id'] = Variable<String>(organizationId);
    map['branch_id'] = Variable<String>(branchId);
    map['id'] = Variable<String>(id);
    map['device_id'] = Variable<String>(deviceId);
    map['actor_id'] = Variable<String>(actorId);
    map['document_id'] = Variable<String>(documentId);
    map['event_type'] = Variable<String>(eventType);
    map['schema_version'] = Variable<int>(schemaVersion);
    map['payload_json'] = Variable<String>(payloadJson);
    map['payload_digest'] = Variable<String>(payloadDigest);
    map['occurred_at_iso'] = Variable<String>(occurredAtIso);
    map['status'] = Variable<String>(status);
    map['attempts'] = Variable<int>(attempts);
    if (!nullToAbsent || leaseOwner != null) {
      map['lease_owner'] = Variable<String>(leaseOwner);
    }
    if (!nullToAbsent || leaseToken != null) {
      map['lease_token'] = Variable<String>(leaseToken);
    }
    if (!nullToAbsent || leaseUntil != null) {
      map['lease_until'] = Variable<DateTime>(leaseUntil);
    }
    if (!nullToAbsent || nextAttemptAt != null) {
      map['next_attempt_at'] = Variable<DateTime>(nextAttemptAt);
    }
    if (!nullToAbsent || lastError != null) {
      map['last_error'] = Variable<String>(lastError);
    }
    map['created_at'] = Variable<DateTime>(createdAt);
    if (!nullToAbsent || acceptedAt != null) {
      map['accepted_at'] = Variable<DateTime>(acceptedAt);
    }
    if (!nullToAbsent || serverReceiptId != null) {
      map['server_receipt_id'] = Variable<String>(serverReceiptId);
    }
    return map;
  }

  SyncOutboxCompanion toCompanion(bool nullToAbsent) {
    return SyncOutboxCompanion(
      organizationId: Value(organizationId),
      branchId: Value(branchId),
      id: Value(id),
      deviceId: Value(deviceId),
      actorId: Value(actorId),
      documentId: Value(documentId),
      eventType: Value(eventType),
      schemaVersion: Value(schemaVersion),
      payloadJson: Value(payloadJson),
      payloadDigest: Value(payloadDigest),
      occurredAtIso: Value(occurredAtIso),
      status: Value(status),
      attempts: Value(attempts),
      leaseOwner: leaseOwner == null && nullToAbsent
          ? const Value.absent()
          : Value(leaseOwner),
      leaseToken: leaseToken == null && nullToAbsent
          ? const Value.absent()
          : Value(leaseToken),
      leaseUntil: leaseUntil == null && nullToAbsent
          ? const Value.absent()
          : Value(leaseUntil),
      nextAttemptAt: nextAttemptAt == null && nullToAbsent
          ? const Value.absent()
          : Value(nextAttemptAt),
      lastError: lastError == null && nullToAbsent
          ? const Value.absent()
          : Value(lastError),
      createdAt: Value(createdAt),
      acceptedAt: acceptedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(acceptedAt),
      serverReceiptId: serverReceiptId == null && nullToAbsent
          ? const Value.absent()
          : Value(serverReceiptId),
    );
  }

  factory OutboxRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return OutboxRow(
      organizationId: serializer.fromJson<String>(json['organizationId']),
      branchId: serializer.fromJson<String>(json['branchId']),
      id: serializer.fromJson<String>(json['id']),
      deviceId: serializer.fromJson<String>(json['deviceId']),
      actorId: serializer.fromJson<String>(json['actorId']),
      documentId: serializer.fromJson<String>(json['documentId']),
      eventType: serializer.fromJson<String>(json['eventType']),
      schemaVersion: serializer.fromJson<int>(json['schemaVersion']),
      payloadJson: serializer.fromJson<String>(json['payloadJson']),
      payloadDigest: serializer.fromJson<String>(json['payloadDigest']),
      occurredAtIso: serializer.fromJson<String>(json['occurredAtIso']),
      status: serializer.fromJson<String>(json['status']),
      attempts: serializer.fromJson<int>(json['attempts']),
      leaseOwner: serializer.fromJson<String?>(json['leaseOwner']),
      leaseToken: serializer.fromJson<String?>(json['leaseToken']),
      leaseUntil: serializer.fromJson<DateTime?>(json['leaseUntil']),
      nextAttemptAt: serializer.fromJson<DateTime?>(json['nextAttemptAt']),
      lastError: serializer.fromJson<String?>(json['lastError']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      acceptedAt: serializer.fromJson<DateTime?>(json['acceptedAt']),
      serverReceiptId: serializer.fromJson<String?>(json['serverReceiptId']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'organizationId': serializer.toJson<String>(organizationId),
      'branchId': serializer.toJson<String>(branchId),
      'id': serializer.toJson<String>(id),
      'deviceId': serializer.toJson<String>(deviceId),
      'actorId': serializer.toJson<String>(actorId),
      'documentId': serializer.toJson<String>(documentId),
      'eventType': serializer.toJson<String>(eventType),
      'schemaVersion': serializer.toJson<int>(schemaVersion),
      'payloadJson': serializer.toJson<String>(payloadJson),
      'payloadDigest': serializer.toJson<String>(payloadDigest),
      'occurredAtIso': serializer.toJson<String>(occurredAtIso),
      'status': serializer.toJson<String>(status),
      'attempts': serializer.toJson<int>(attempts),
      'leaseOwner': serializer.toJson<String?>(leaseOwner),
      'leaseToken': serializer.toJson<String?>(leaseToken),
      'leaseUntil': serializer.toJson<DateTime?>(leaseUntil),
      'nextAttemptAt': serializer.toJson<DateTime?>(nextAttemptAt),
      'lastError': serializer.toJson<String?>(lastError),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'acceptedAt': serializer.toJson<DateTime?>(acceptedAt),
      'serverReceiptId': serializer.toJson<String?>(serverReceiptId),
    };
  }

  OutboxRow copyWith({
    String? organizationId,
    String? branchId,
    String? id,
    String? deviceId,
    String? actorId,
    String? documentId,
    String? eventType,
    int? schemaVersion,
    String? payloadJson,
    String? payloadDigest,
    String? occurredAtIso,
    String? status,
    int? attempts,
    Value<String?> leaseOwner = const Value.absent(),
    Value<String?> leaseToken = const Value.absent(),
    Value<DateTime?> leaseUntil = const Value.absent(),
    Value<DateTime?> nextAttemptAt = const Value.absent(),
    Value<String?> lastError = const Value.absent(),
    DateTime? createdAt,
    Value<DateTime?> acceptedAt = const Value.absent(),
    Value<String?> serverReceiptId = const Value.absent(),
  }) => OutboxRow(
    organizationId: organizationId ?? this.organizationId,
    branchId: branchId ?? this.branchId,
    id: id ?? this.id,
    deviceId: deviceId ?? this.deviceId,
    actorId: actorId ?? this.actorId,
    documentId: documentId ?? this.documentId,
    eventType: eventType ?? this.eventType,
    schemaVersion: schemaVersion ?? this.schemaVersion,
    payloadJson: payloadJson ?? this.payloadJson,
    payloadDigest: payloadDigest ?? this.payloadDigest,
    occurredAtIso: occurredAtIso ?? this.occurredAtIso,
    status: status ?? this.status,
    attempts: attempts ?? this.attempts,
    leaseOwner: leaseOwner.present ? leaseOwner.value : this.leaseOwner,
    leaseToken: leaseToken.present ? leaseToken.value : this.leaseToken,
    leaseUntil: leaseUntil.present ? leaseUntil.value : this.leaseUntil,
    nextAttemptAt: nextAttemptAt.present
        ? nextAttemptAt.value
        : this.nextAttemptAt,
    lastError: lastError.present ? lastError.value : this.lastError,
    createdAt: createdAt ?? this.createdAt,
    acceptedAt: acceptedAt.present ? acceptedAt.value : this.acceptedAt,
    serverReceiptId: serverReceiptId.present
        ? serverReceiptId.value
        : this.serverReceiptId,
  );
  OutboxRow copyWithCompanion(SyncOutboxCompanion data) {
    return OutboxRow(
      organizationId: data.organizationId.present
          ? data.organizationId.value
          : this.organizationId,
      branchId: data.branchId.present ? data.branchId.value : this.branchId,
      id: data.id.present ? data.id.value : this.id,
      deviceId: data.deviceId.present ? data.deviceId.value : this.deviceId,
      actorId: data.actorId.present ? data.actorId.value : this.actorId,
      documentId: data.documentId.present
          ? data.documentId.value
          : this.documentId,
      eventType: data.eventType.present ? data.eventType.value : this.eventType,
      schemaVersion: data.schemaVersion.present
          ? data.schemaVersion.value
          : this.schemaVersion,
      payloadJson: data.payloadJson.present
          ? data.payloadJson.value
          : this.payloadJson,
      payloadDigest: data.payloadDigest.present
          ? data.payloadDigest.value
          : this.payloadDigest,
      occurredAtIso: data.occurredAtIso.present
          ? data.occurredAtIso.value
          : this.occurredAtIso,
      status: data.status.present ? data.status.value : this.status,
      attempts: data.attempts.present ? data.attempts.value : this.attempts,
      leaseOwner: data.leaseOwner.present
          ? data.leaseOwner.value
          : this.leaseOwner,
      leaseToken: data.leaseToken.present
          ? data.leaseToken.value
          : this.leaseToken,
      leaseUntil: data.leaseUntil.present
          ? data.leaseUntil.value
          : this.leaseUntil,
      nextAttemptAt: data.nextAttemptAt.present
          ? data.nextAttemptAt.value
          : this.nextAttemptAt,
      lastError: data.lastError.present ? data.lastError.value : this.lastError,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      acceptedAt: data.acceptedAt.present
          ? data.acceptedAt.value
          : this.acceptedAt,
      serverReceiptId: data.serverReceiptId.present
          ? data.serverReceiptId.value
          : this.serverReceiptId,
    );
  }

  @override
  String toString() {
    return (StringBuffer('OutboxRow(')
          ..write('organizationId: $organizationId, ')
          ..write('branchId: $branchId, ')
          ..write('id: $id, ')
          ..write('deviceId: $deviceId, ')
          ..write('actorId: $actorId, ')
          ..write('documentId: $documentId, ')
          ..write('eventType: $eventType, ')
          ..write('schemaVersion: $schemaVersion, ')
          ..write('payloadJson: $payloadJson, ')
          ..write('payloadDigest: $payloadDigest, ')
          ..write('occurredAtIso: $occurredAtIso, ')
          ..write('status: $status, ')
          ..write('attempts: $attempts, ')
          ..write('leaseOwner: $leaseOwner, ')
          ..write('leaseToken: $leaseToken, ')
          ..write('leaseUntil: $leaseUntil, ')
          ..write('nextAttemptAt: $nextAttemptAt, ')
          ..write('lastError: $lastError, ')
          ..write('createdAt: $createdAt, ')
          ..write('acceptedAt: $acceptedAt, ')
          ..write('serverReceiptId: $serverReceiptId')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hashAll([
    organizationId,
    branchId,
    id,
    deviceId,
    actorId,
    documentId,
    eventType,
    schemaVersion,
    payloadJson,
    payloadDigest,
    occurredAtIso,
    status,
    attempts,
    leaseOwner,
    leaseToken,
    leaseUntil,
    nextAttemptAt,
    lastError,
    createdAt,
    acceptedAt,
    serverReceiptId,
  ]);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is OutboxRow &&
          other.organizationId == this.organizationId &&
          other.branchId == this.branchId &&
          other.id == this.id &&
          other.deviceId == this.deviceId &&
          other.actorId == this.actorId &&
          other.documentId == this.documentId &&
          other.eventType == this.eventType &&
          other.schemaVersion == this.schemaVersion &&
          other.payloadJson == this.payloadJson &&
          other.payloadDigest == this.payloadDigest &&
          other.occurredAtIso == this.occurredAtIso &&
          other.status == this.status &&
          other.attempts == this.attempts &&
          other.leaseOwner == this.leaseOwner &&
          other.leaseToken == this.leaseToken &&
          other.leaseUntil == this.leaseUntil &&
          other.nextAttemptAt == this.nextAttemptAt &&
          other.lastError == this.lastError &&
          other.createdAt == this.createdAt &&
          other.acceptedAt == this.acceptedAt &&
          other.serverReceiptId == this.serverReceiptId);
}

class SyncOutboxCompanion extends UpdateCompanion<OutboxRow> {
  final Value<String> organizationId;
  final Value<String> branchId;
  final Value<String> id;
  final Value<String> deviceId;
  final Value<String> actorId;
  final Value<String> documentId;
  final Value<String> eventType;
  final Value<int> schemaVersion;
  final Value<String> payloadJson;
  final Value<String> payloadDigest;
  final Value<String> occurredAtIso;
  final Value<String> status;
  final Value<int> attempts;
  final Value<String?> leaseOwner;
  final Value<String?> leaseToken;
  final Value<DateTime?> leaseUntil;
  final Value<DateTime?> nextAttemptAt;
  final Value<String?> lastError;
  final Value<DateTime> createdAt;
  final Value<DateTime?> acceptedAt;
  final Value<String?> serverReceiptId;
  final Value<int> rowid;
  const SyncOutboxCompanion({
    this.organizationId = const Value.absent(),
    this.branchId = const Value.absent(),
    this.id = const Value.absent(),
    this.deviceId = const Value.absent(),
    this.actorId = const Value.absent(),
    this.documentId = const Value.absent(),
    this.eventType = const Value.absent(),
    this.schemaVersion = const Value.absent(),
    this.payloadJson = const Value.absent(),
    this.payloadDigest = const Value.absent(),
    this.occurredAtIso = const Value.absent(),
    this.status = const Value.absent(),
    this.attempts = const Value.absent(),
    this.leaseOwner = const Value.absent(),
    this.leaseToken = const Value.absent(),
    this.leaseUntil = const Value.absent(),
    this.nextAttemptAt = const Value.absent(),
    this.lastError = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.acceptedAt = const Value.absent(),
    this.serverReceiptId = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SyncOutboxCompanion.insert({
    required String organizationId,
    required String branchId,
    required String id,
    required String deviceId,
    required String actorId,
    required String documentId,
    required String eventType,
    this.schemaVersion = const Value.absent(),
    required String payloadJson,
    required String payloadDigest,
    required String occurredAtIso,
    this.status = const Value.absent(),
    this.attempts = const Value.absent(),
    this.leaseOwner = const Value.absent(),
    this.leaseToken = const Value.absent(),
    this.leaseUntil = const Value.absent(),
    this.nextAttemptAt = const Value.absent(),
    this.lastError = const Value.absent(),
    required DateTime createdAt,
    this.acceptedAt = const Value.absent(),
    this.serverReceiptId = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : organizationId = Value(organizationId),
       branchId = Value(branchId),
       id = Value(id),
       deviceId = Value(deviceId),
       actorId = Value(actorId),
       documentId = Value(documentId),
       eventType = Value(eventType),
       payloadJson = Value(payloadJson),
       payloadDigest = Value(payloadDigest),
       occurredAtIso = Value(occurredAtIso),
       createdAt = Value(createdAt);
  static Insertable<OutboxRow> custom({
    Expression<String>? organizationId,
    Expression<String>? branchId,
    Expression<String>? id,
    Expression<String>? deviceId,
    Expression<String>? actorId,
    Expression<String>? documentId,
    Expression<String>? eventType,
    Expression<int>? schemaVersion,
    Expression<String>? payloadJson,
    Expression<String>? payloadDigest,
    Expression<String>? occurredAtIso,
    Expression<String>? status,
    Expression<int>? attempts,
    Expression<String>? leaseOwner,
    Expression<String>? leaseToken,
    Expression<DateTime>? leaseUntil,
    Expression<DateTime>? nextAttemptAt,
    Expression<String>? lastError,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? acceptedAt,
    Expression<String>? serverReceiptId,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (organizationId != null) 'organization_id': organizationId,
      if (branchId != null) 'branch_id': branchId,
      if (id != null) 'id': id,
      if (deviceId != null) 'device_id': deviceId,
      if (actorId != null) 'actor_id': actorId,
      if (documentId != null) 'document_id': documentId,
      if (eventType != null) 'event_type': eventType,
      if (schemaVersion != null) 'schema_version': schemaVersion,
      if (payloadJson != null) 'payload_json': payloadJson,
      if (payloadDigest != null) 'payload_digest': payloadDigest,
      if (occurredAtIso != null) 'occurred_at_iso': occurredAtIso,
      if (status != null) 'status': status,
      if (attempts != null) 'attempts': attempts,
      if (leaseOwner != null) 'lease_owner': leaseOwner,
      if (leaseToken != null) 'lease_token': leaseToken,
      if (leaseUntil != null) 'lease_until': leaseUntil,
      if (nextAttemptAt != null) 'next_attempt_at': nextAttemptAt,
      if (lastError != null) 'last_error': lastError,
      if (createdAt != null) 'created_at': createdAt,
      if (acceptedAt != null) 'accepted_at': acceptedAt,
      if (serverReceiptId != null) 'server_receipt_id': serverReceiptId,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SyncOutboxCompanion copyWith({
    Value<String>? organizationId,
    Value<String>? branchId,
    Value<String>? id,
    Value<String>? deviceId,
    Value<String>? actorId,
    Value<String>? documentId,
    Value<String>? eventType,
    Value<int>? schemaVersion,
    Value<String>? payloadJson,
    Value<String>? payloadDigest,
    Value<String>? occurredAtIso,
    Value<String>? status,
    Value<int>? attempts,
    Value<String?>? leaseOwner,
    Value<String?>? leaseToken,
    Value<DateTime?>? leaseUntil,
    Value<DateTime?>? nextAttemptAt,
    Value<String?>? lastError,
    Value<DateTime>? createdAt,
    Value<DateTime?>? acceptedAt,
    Value<String?>? serverReceiptId,
    Value<int>? rowid,
  }) {
    return SyncOutboxCompanion(
      organizationId: organizationId ?? this.organizationId,
      branchId: branchId ?? this.branchId,
      id: id ?? this.id,
      deviceId: deviceId ?? this.deviceId,
      actorId: actorId ?? this.actorId,
      documentId: documentId ?? this.documentId,
      eventType: eventType ?? this.eventType,
      schemaVersion: schemaVersion ?? this.schemaVersion,
      payloadJson: payloadJson ?? this.payloadJson,
      payloadDigest: payloadDigest ?? this.payloadDigest,
      occurredAtIso: occurredAtIso ?? this.occurredAtIso,
      status: status ?? this.status,
      attempts: attempts ?? this.attempts,
      leaseOwner: leaseOwner ?? this.leaseOwner,
      leaseToken: leaseToken ?? this.leaseToken,
      leaseUntil: leaseUntil ?? this.leaseUntil,
      nextAttemptAt: nextAttemptAt ?? this.nextAttemptAt,
      lastError: lastError ?? this.lastError,
      createdAt: createdAt ?? this.createdAt,
      acceptedAt: acceptedAt ?? this.acceptedAt,
      serverReceiptId: serverReceiptId ?? this.serverReceiptId,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (organizationId.present) {
      map['organization_id'] = Variable<String>(organizationId.value);
    }
    if (branchId.present) {
      map['branch_id'] = Variable<String>(branchId.value);
    }
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (deviceId.present) {
      map['device_id'] = Variable<String>(deviceId.value);
    }
    if (actorId.present) {
      map['actor_id'] = Variable<String>(actorId.value);
    }
    if (documentId.present) {
      map['document_id'] = Variable<String>(documentId.value);
    }
    if (eventType.present) {
      map['event_type'] = Variable<String>(eventType.value);
    }
    if (schemaVersion.present) {
      map['schema_version'] = Variable<int>(schemaVersion.value);
    }
    if (payloadJson.present) {
      map['payload_json'] = Variable<String>(payloadJson.value);
    }
    if (payloadDigest.present) {
      map['payload_digest'] = Variable<String>(payloadDigest.value);
    }
    if (occurredAtIso.present) {
      map['occurred_at_iso'] = Variable<String>(occurredAtIso.value);
    }
    if (status.present) {
      map['status'] = Variable<String>(status.value);
    }
    if (attempts.present) {
      map['attempts'] = Variable<int>(attempts.value);
    }
    if (leaseOwner.present) {
      map['lease_owner'] = Variable<String>(leaseOwner.value);
    }
    if (leaseToken.present) {
      map['lease_token'] = Variable<String>(leaseToken.value);
    }
    if (leaseUntil.present) {
      map['lease_until'] = Variable<DateTime>(leaseUntil.value);
    }
    if (nextAttemptAt.present) {
      map['next_attempt_at'] = Variable<DateTime>(nextAttemptAt.value);
    }
    if (lastError.present) {
      map['last_error'] = Variable<String>(lastError.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (acceptedAt.present) {
      map['accepted_at'] = Variable<DateTime>(acceptedAt.value);
    }
    if (serverReceiptId.present) {
      map['server_receipt_id'] = Variable<String>(serverReceiptId.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SyncOutboxCompanion(')
          ..write('organizationId: $organizationId, ')
          ..write('branchId: $branchId, ')
          ..write('id: $id, ')
          ..write('deviceId: $deviceId, ')
          ..write('actorId: $actorId, ')
          ..write('documentId: $documentId, ')
          ..write('eventType: $eventType, ')
          ..write('schemaVersion: $schemaVersion, ')
          ..write('payloadJson: $payloadJson, ')
          ..write('payloadDigest: $payloadDigest, ')
          ..write('occurredAtIso: $occurredAtIso, ')
          ..write('status: $status, ')
          ..write('attempts: $attempts, ')
          ..write('leaseOwner: $leaseOwner, ')
          ..write('leaseToken: $leaseToken, ')
          ..write('leaseUntil: $leaseUntil, ')
          ..write('nextAttemptAt: $nextAttemptAt, ')
          ..write('lastError: $lastError, ')
          ..write('createdAt: $createdAt, ')
          ..write('acceptedAt: $acceptedAt, ')
          ..write('serverReceiptId: $serverReceiptId, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $SyncCursorsTable extends SyncCursors
    with TableInfo<$SyncCursorsTable, CursorRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SyncCursorsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _organizationIdMeta = const VerificationMeta(
    'organizationId',
  );
  @override
  late final GeneratedColumn<String> organizationId = GeneratedColumn<String>(
    'organization_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _branchIdMeta = const VerificationMeta(
    'branchId',
  );
  @override
  late final GeneratedColumn<String> branchId = GeneratedColumn<String>(
    'branch_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _cursorMeta = const VerificationMeta('cursor');
  @override
  late final GeneratedColumn<String> cursor = GeneratedColumn<String>(
    'cursor',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    organizationId,
    branchId,
    id,
    cursor,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'sync_cursors';
  @override
  VerificationContext validateIntegrity(
    Insertable<CursorRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('organization_id')) {
      context.handle(
        _organizationIdMeta,
        organizationId.isAcceptableOrUnknown(
          data['organization_id']!,
          _organizationIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_organizationIdMeta);
    }
    if (data.containsKey('branch_id')) {
      context.handle(
        _branchIdMeta,
        branchId.isAcceptableOrUnknown(data['branch_id']!, _branchIdMeta),
      );
    } else if (isInserting) {
      context.missing(_branchIdMeta);
    }
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('cursor')) {
      context.handle(
        _cursorMeta,
        cursor.isAcceptableOrUnknown(data['cursor']!, _cursorMeta),
      );
    } else if (isInserting) {
      context.missing(_cursorMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {organizationId, branchId, id};
  @override
  CursorRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return CursorRow(
      organizationId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}organization_id'],
      )!,
      branchId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}branch_id'],
      )!,
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      cursor: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}cursor'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $SyncCursorsTable createAlias(String alias) {
    return $SyncCursorsTable(attachedDatabase, alias);
  }
}

class CursorRow extends DataClass implements Insertable<CursorRow> {
  final String organizationId;
  final String branchId;
  final String id;
  final String cursor;
  final DateTime updatedAt;
  const CursorRow({
    required this.organizationId,
    required this.branchId,
    required this.id,
    required this.cursor,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['organization_id'] = Variable<String>(organizationId);
    map['branch_id'] = Variable<String>(branchId);
    map['id'] = Variable<String>(id);
    map['cursor'] = Variable<String>(cursor);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  SyncCursorsCompanion toCompanion(bool nullToAbsent) {
    return SyncCursorsCompanion(
      organizationId: Value(organizationId),
      branchId: Value(branchId),
      id: Value(id),
      cursor: Value(cursor),
      updatedAt: Value(updatedAt),
    );
  }

  factory CursorRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return CursorRow(
      organizationId: serializer.fromJson<String>(json['organizationId']),
      branchId: serializer.fromJson<String>(json['branchId']),
      id: serializer.fromJson<String>(json['id']),
      cursor: serializer.fromJson<String>(json['cursor']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'organizationId': serializer.toJson<String>(organizationId),
      'branchId': serializer.toJson<String>(branchId),
      'id': serializer.toJson<String>(id),
      'cursor': serializer.toJson<String>(cursor),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  CursorRow copyWith({
    String? organizationId,
    String? branchId,
    String? id,
    String? cursor,
    DateTime? updatedAt,
  }) => CursorRow(
    organizationId: organizationId ?? this.organizationId,
    branchId: branchId ?? this.branchId,
    id: id ?? this.id,
    cursor: cursor ?? this.cursor,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  CursorRow copyWithCompanion(SyncCursorsCompanion data) {
    return CursorRow(
      organizationId: data.organizationId.present
          ? data.organizationId.value
          : this.organizationId,
      branchId: data.branchId.present ? data.branchId.value : this.branchId,
      id: data.id.present ? data.id.value : this.id,
      cursor: data.cursor.present ? data.cursor.value : this.cursor,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('CursorRow(')
          ..write('organizationId: $organizationId, ')
          ..write('branchId: $branchId, ')
          ..write('id: $id, ')
          ..write('cursor: $cursor, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(organizationId, branchId, id, cursor, updatedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CursorRow &&
          other.organizationId == this.organizationId &&
          other.branchId == this.branchId &&
          other.id == this.id &&
          other.cursor == this.cursor &&
          other.updatedAt == this.updatedAt);
}

class SyncCursorsCompanion extends UpdateCompanion<CursorRow> {
  final Value<String> organizationId;
  final Value<String> branchId;
  final Value<String> id;
  final Value<String> cursor;
  final Value<DateTime> updatedAt;
  final Value<int> rowid;
  const SyncCursorsCompanion({
    this.organizationId = const Value.absent(),
    this.branchId = const Value.absent(),
    this.id = const Value.absent(),
    this.cursor = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SyncCursorsCompanion.insert({
    required String organizationId,
    required String branchId,
    required String id,
    required String cursor,
    required DateTime updatedAt,
    this.rowid = const Value.absent(),
  }) : organizationId = Value(organizationId),
       branchId = Value(branchId),
       id = Value(id),
       cursor = Value(cursor),
       updatedAt = Value(updatedAt);
  static Insertable<CursorRow> custom({
    Expression<String>? organizationId,
    Expression<String>? branchId,
    Expression<String>? id,
    Expression<String>? cursor,
    Expression<DateTime>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (organizationId != null) 'organization_id': organizationId,
      if (branchId != null) 'branch_id': branchId,
      if (id != null) 'id': id,
      if (cursor != null) 'cursor': cursor,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SyncCursorsCompanion copyWith({
    Value<String>? organizationId,
    Value<String>? branchId,
    Value<String>? id,
    Value<String>? cursor,
    Value<DateTime>? updatedAt,
    Value<int>? rowid,
  }) {
    return SyncCursorsCompanion(
      organizationId: organizationId ?? this.organizationId,
      branchId: branchId ?? this.branchId,
      id: id ?? this.id,
      cursor: cursor ?? this.cursor,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (organizationId.present) {
      map['organization_id'] = Variable<String>(organizationId.value);
    }
    if (branchId.present) {
      map['branch_id'] = Variable<String>(branchId.value);
    }
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (cursor.present) {
      map['cursor'] = Variable<String>(cursor.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SyncCursorsCompanion(')
          ..write('organizationId: $organizationId, ')
          ..write('branchId: $branchId, ')
          ..write('id: $id, ')
          ..write('cursor: $cursor, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $OfflineEventAuthorizationsTable extends OfflineEventAuthorizations
    with TableInfo<$OfflineEventAuthorizationsTable, OfflineAuthorizationRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $OfflineEventAuthorizationsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _organizationIdMeta = const VerificationMeta(
    'organizationId',
  );
  @override
  late final GeneratedColumn<String> organizationId = GeneratedColumn<String>(
    'organization_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _branchIdMeta = const VerificationMeta(
    'branchId',
  );
  @override
  late final GeneratedColumn<String> branchId = GeneratedColumn<String>(
    'branch_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _actorIdMeta = const VerificationMeta(
    'actorId',
  );
  @override
  late final GeneratedColumn<String> actorId = GeneratedColumn<String>(
    'actor_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _deviceIdMeta = const VerificationMeta(
    'deviceId',
  );
  @override
  late final GeneratedColumn<String> deviceId = GeneratedColumn<String>(
    'device_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _grantIdMeta = const VerificationMeta(
    'grantId',
  );
  @override
  late final GeneratedColumn<String> grantId = GeneratedColumn<String>(
    'grant_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _sequenceMeta = const VerificationMeta(
    'sequence',
  );
  @override
  late final GeneratedColumn<int> sequence = GeneratedColumn<int>(
    'sequence',
    aliasedName,
    false,
    check: () => ComparableExpr(sequence).isBetweenValues(1, 1000),
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _authorizationJsonMeta = const VerificationMeta(
    'authorizationJson',
  );
  @override
  late final GeneratedColumn<String> authorizationJson =
      GeneratedColumn<String>(
        'authorization_json',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
      );
  static const VerificationMeta _signatureMeta = const VerificationMeta(
    'signature',
  );
  @override
  late final GeneratedColumn<String> signature = GeneratedColumn<String>(
    'signature',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    organizationId,
    branchId,
    id,
    actorId,
    deviceId,
    grantId,
    sequence,
    authorizationJson,
    signature,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'offline_event_authorizations';
  @override
  VerificationContext validateIntegrity(
    Insertable<OfflineAuthorizationRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('organization_id')) {
      context.handle(
        _organizationIdMeta,
        organizationId.isAcceptableOrUnknown(
          data['organization_id']!,
          _organizationIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_organizationIdMeta);
    }
    if (data.containsKey('branch_id')) {
      context.handle(
        _branchIdMeta,
        branchId.isAcceptableOrUnknown(data['branch_id']!, _branchIdMeta),
      );
    } else if (isInserting) {
      context.missing(_branchIdMeta);
    }
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('actor_id')) {
      context.handle(
        _actorIdMeta,
        actorId.isAcceptableOrUnknown(data['actor_id']!, _actorIdMeta),
      );
    } else if (isInserting) {
      context.missing(_actorIdMeta);
    }
    if (data.containsKey('device_id')) {
      context.handle(
        _deviceIdMeta,
        deviceId.isAcceptableOrUnknown(data['device_id']!, _deviceIdMeta),
      );
    } else if (isInserting) {
      context.missing(_deviceIdMeta);
    }
    if (data.containsKey('grant_id')) {
      context.handle(
        _grantIdMeta,
        grantId.isAcceptableOrUnknown(data['grant_id']!, _grantIdMeta),
      );
    } else if (isInserting) {
      context.missing(_grantIdMeta);
    }
    if (data.containsKey('sequence')) {
      context.handle(
        _sequenceMeta,
        sequence.isAcceptableOrUnknown(data['sequence']!, _sequenceMeta),
      );
    } else if (isInserting) {
      context.missing(_sequenceMeta);
    }
    if (data.containsKey('authorization_json')) {
      context.handle(
        _authorizationJsonMeta,
        authorizationJson.isAcceptableOrUnknown(
          data['authorization_json']!,
          _authorizationJsonMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_authorizationJsonMeta);
    }
    if (data.containsKey('signature')) {
      context.handle(
        _signatureMeta,
        signature.isAcceptableOrUnknown(data['signature']!, _signatureMeta),
      );
    } else if (isInserting) {
      context.missing(_signatureMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {organizationId, branchId, id};
  @override
  List<Set<GeneratedColumn>> get uniqueKeys => [
    {organizationId, branchId, actorId, deviceId, grantId, sequence},
  ];
  @override
  OfflineAuthorizationRow map(
    Map<String, dynamic> data, {
    String? tablePrefix,
  }) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return OfflineAuthorizationRow(
      organizationId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}organization_id'],
      )!,
      branchId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}branch_id'],
      )!,
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      actorId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}actor_id'],
      )!,
      deviceId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}device_id'],
      )!,
      grantId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}grant_id'],
      )!,
      sequence: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}sequence'],
      )!,
      authorizationJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}authorization_json'],
      )!,
      signature: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}signature'],
      )!,
    );
  }

  @override
  $OfflineEventAuthorizationsTable createAlias(String alias) {
    return $OfflineEventAuthorizationsTable(attachedDatabase, alias);
  }
}

class OfflineAuthorizationRow extends DataClass
    implements Insertable<OfflineAuthorizationRow> {
  final String organizationId;
  final String branchId;
  final String id;
  final String actorId;
  final String deviceId;
  final String grantId;
  final int sequence;
  final String authorizationJson;
  final String signature;
  const OfflineAuthorizationRow({
    required this.organizationId,
    required this.branchId,
    required this.id,
    required this.actorId,
    required this.deviceId,
    required this.grantId,
    required this.sequence,
    required this.authorizationJson,
    required this.signature,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['organization_id'] = Variable<String>(organizationId);
    map['branch_id'] = Variable<String>(branchId);
    map['id'] = Variable<String>(id);
    map['actor_id'] = Variable<String>(actorId);
    map['device_id'] = Variable<String>(deviceId);
    map['grant_id'] = Variable<String>(grantId);
    map['sequence'] = Variable<int>(sequence);
    map['authorization_json'] = Variable<String>(authorizationJson);
    map['signature'] = Variable<String>(signature);
    return map;
  }

  OfflineEventAuthorizationsCompanion toCompanion(bool nullToAbsent) {
    return OfflineEventAuthorizationsCompanion(
      organizationId: Value(organizationId),
      branchId: Value(branchId),
      id: Value(id),
      actorId: Value(actorId),
      deviceId: Value(deviceId),
      grantId: Value(grantId),
      sequence: Value(sequence),
      authorizationJson: Value(authorizationJson),
      signature: Value(signature),
    );
  }

  factory OfflineAuthorizationRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return OfflineAuthorizationRow(
      organizationId: serializer.fromJson<String>(json['organizationId']),
      branchId: serializer.fromJson<String>(json['branchId']),
      id: serializer.fromJson<String>(json['id']),
      actorId: serializer.fromJson<String>(json['actorId']),
      deviceId: serializer.fromJson<String>(json['deviceId']),
      grantId: serializer.fromJson<String>(json['grantId']),
      sequence: serializer.fromJson<int>(json['sequence']),
      authorizationJson: serializer.fromJson<String>(json['authorizationJson']),
      signature: serializer.fromJson<String>(json['signature']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'organizationId': serializer.toJson<String>(organizationId),
      'branchId': serializer.toJson<String>(branchId),
      'id': serializer.toJson<String>(id),
      'actorId': serializer.toJson<String>(actorId),
      'deviceId': serializer.toJson<String>(deviceId),
      'grantId': serializer.toJson<String>(grantId),
      'sequence': serializer.toJson<int>(sequence),
      'authorizationJson': serializer.toJson<String>(authorizationJson),
      'signature': serializer.toJson<String>(signature),
    };
  }

  OfflineAuthorizationRow copyWith({
    String? organizationId,
    String? branchId,
    String? id,
    String? actorId,
    String? deviceId,
    String? grantId,
    int? sequence,
    String? authorizationJson,
    String? signature,
  }) => OfflineAuthorizationRow(
    organizationId: organizationId ?? this.organizationId,
    branchId: branchId ?? this.branchId,
    id: id ?? this.id,
    actorId: actorId ?? this.actorId,
    deviceId: deviceId ?? this.deviceId,
    grantId: grantId ?? this.grantId,
    sequence: sequence ?? this.sequence,
    authorizationJson: authorizationJson ?? this.authorizationJson,
    signature: signature ?? this.signature,
  );
  OfflineAuthorizationRow copyWithCompanion(
    OfflineEventAuthorizationsCompanion data,
  ) {
    return OfflineAuthorizationRow(
      organizationId: data.organizationId.present
          ? data.organizationId.value
          : this.organizationId,
      branchId: data.branchId.present ? data.branchId.value : this.branchId,
      id: data.id.present ? data.id.value : this.id,
      actorId: data.actorId.present ? data.actorId.value : this.actorId,
      deviceId: data.deviceId.present ? data.deviceId.value : this.deviceId,
      grantId: data.grantId.present ? data.grantId.value : this.grantId,
      sequence: data.sequence.present ? data.sequence.value : this.sequence,
      authorizationJson: data.authorizationJson.present
          ? data.authorizationJson.value
          : this.authorizationJson,
      signature: data.signature.present ? data.signature.value : this.signature,
    );
  }

  @override
  String toString() {
    return (StringBuffer('OfflineAuthorizationRow(')
          ..write('organizationId: $organizationId, ')
          ..write('branchId: $branchId, ')
          ..write('id: $id, ')
          ..write('actorId: $actorId, ')
          ..write('deviceId: $deviceId, ')
          ..write('grantId: $grantId, ')
          ..write('sequence: $sequence, ')
          ..write('authorizationJson: $authorizationJson, ')
          ..write('signature: $signature')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    organizationId,
    branchId,
    id,
    actorId,
    deviceId,
    grantId,
    sequence,
    authorizationJson,
    signature,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is OfflineAuthorizationRow &&
          other.organizationId == this.organizationId &&
          other.branchId == this.branchId &&
          other.id == this.id &&
          other.actorId == this.actorId &&
          other.deviceId == this.deviceId &&
          other.grantId == this.grantId &&
          other.sequence == this.sequence &&
          other.authorizationJson == this.authorizationJson &&
          other.signature == this.signature);
}

class OfflineEventAuthorizationsCompanion
    extends UpdateCompanion<OfflineAuthorizationRow> {
  final Value<String> organizationId;
  final Value<String> branchId;
  final Value<String> id;
  final Value<String> actorId;
  final Value<String> deviceId;
  final Value<String> grantId;
  final Value<int> sequence;
  final Value<String> authorizationJson;
  final Value<String> signature;
  final Value<int> rowid;
  const OfflineEventAuthorizationsCompanion({
    this.organizationId = const Value.absent(),
    this.branchId = const Value.absent(),
    this.id = const Value.absent(),
    this.actorId = const Value.absent(),
    this.deviceId = const Value.absent(),
    this.grantId = const Value.absent(),
    this.sequence = const Value.absent(),
    this.authorizationJson = const Value.absent(),
    this.signature = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  OfflineEventAuthorizationsCompanion.insert({
    required String organizationId,
    required String branchId,
    required String id,
    required String actorId,
    required String deviceId,
    required String grantId,
    required int sequence,
    required String authorizationJson,
    required String signature,
    this.rowid = const Value.absent(),
  }) : organizationId = Value(organizationId),
       branchId = Value(branchId),
       id = Value(id),
       actorId = Value(actorId),
       deviceId = Value(deviceId),
       grantId = Value(grantId),
       sequence = Value(sequence),
       authorizationJson = Value(authorizationJson),
       signature = Value(signature);
  static Insertable<OfflineAuthorizationRow> custom({
    Expression<String>? organizationId,
    Expression<String>? branchId,
    Expression<String>? id,
    Expression<String>? actorId,
    Expression<String>? deviceId,
    Expression<String>? grantId,
    Expression<int>? sequence,
    Expression<String>? authorizationJson,
    Expression<String>? signature,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (organizationId != null) 'organization_id': organizationId,
      if (branchId != null) 'branch_id': branchId,
      if (id != null) 'id': id,
      if (actorId != null) 'actor_id': actorId,
      if (deviceId != null) 'device_id': deviceId,
      if (grantId != null) 'grant_id': grantId,
      if (sequence != null) 'sequence': sequence,
      if (authorizationJson != null) 'authorization_json': authorizationJson,
      if (signature != null) 'signature': signature,
      if (rowid != null) 'rowid': rowid,
    });
  }

  OfflineEventAuthorizationsCompanion copyWith({
    Value<String>? organizationId,
    Value<String>? branchId,
    Value<String>? id,
    Value<String>? actorId,
    Value<String>? deviceId,
    Value<String>? grantId,
    Value<int>? sequence,
    Value<String>? authorizationJson,
    Value<String>? signature,
    Value<int>? rowid,
  }) {
    return OfflineEventAuthorizationsCompanion(
      organizationId: organizationId ?? this.organizationId,
      branchId: branchId ?? this.branchId,
      id: id ?? this.id,
      actorId: actorId ?? this.actorId,
      deviceId: deviceId ?? this.deviceId,
      grantId: grantId ?? this.grantId,
      sequence: sequence ?? this.sequence,
      authorizationJson: authorizationJson ?? this.authorizationJson,
      signature: signature ?? this.signature,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (organizationId.present) {
      map['organization_id'] = Variable<String>(organizationId.value);
    }
    if (branchId.present) {
      map['branch_id'] = Variable<String>(branchId.value);
    }
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (actorId.present) {
      map['actor_id'] = Variable<String>(actorId.value);
    }
    if (deviceId.present) {
      map['device_id'] = Variable<String>(deviceId.value);
    }
    if (grantId.present) {
      map['grant_id'] = Variable<String>(grantId.value);
    }
    if (sequence.present) {
      map['sequence'] = Variable<int>(sequence.value);
    }
    if (authorizationJson.present) {
      map['authorization_json'] = Variable<String>(authorizationJson.value);
    }
    if (signature.present) {
      map['signature'] = Variable<String>(signature.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('OfflineEventAuthorizationsCompanion(')
          ..write('organizationId: $organizationId, ')
          ..write('branchId: $branchId, ')
          ..write('id: $id, ')
          ..write('actorId: $actorId, ')
          ..write('deviceId: $deviceId, ')
          ..write('grantId: $grantId, ')
          ..write('sequence: $sequence, ')
          ..write('authorizationJson: $authorizationJson, ')
          ..write('signature: $signature, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $OfflineCacheRecordsTable extends OfflineCacheRecords
    with TableInfo<$OfflineCacheRecordsTable, OfflineCacheRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $OfflineCacheRecordsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _organizationIdMeta = const VerificationMeta(
    'organizationId',
  );
  @override
  late final GeneratedColumn<String> organizationId = GeneratedColumn<String>(
    'organization_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _branchIdMeta = const VerificationMeta(
    'branchId',
  );
  @override
  late final GeneratedColumn<String> branchId = GeneratedColumn<String>(
    'branch_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _actorIdMeta = const VerificationMeta(
    'actorId',
  );
  @override
  late final GeneratedColumn<String> actorId = GeneratedColumn<String>(
    'actor_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _deviceIdMeta = const VerificationMeta(
    'deviceId',
  );
  @override
  late final GeneratedColumn<String> deviceId = GeneratedColumn<String>(
    'device_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _kindMeta = const VerificationMeta('kind');
  @override
  late final GeneratedColumn<String> kind = GeneratedColumn<String>(
    'kind',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _revisionMeta = const VerificationMeta(
    'revision',
  );
  @override
  late final GeneratedColumn<int> revision = GeneratedColumn<int>(
    'revision',
    aliasedName,
    false,
    check: () => ComparableExpr(revision).isBiggerOrEqualValue(0),
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _deletedMeta = const VerificationMeta(
    'deleted',
  );
  @override
  late final GeneratedColumn<bool> deleted = GeneratedColumn<bool>(
    'deleted',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("deleted" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _valueJsonMeta = const VerificationMeta(
    'valueJson',
  );
  @override
  late final GeneratedColumn<String> valueJson = GeneratedColumn<String>(
    'value_json',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    organizationId,
    branchId,
    id,
    actorId,
    deviceId,
    kind,
    revision,
    deleted,
    valueJson,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'offline_cache_records';
  @override
  VerificationContext validateIntegrity(
    Insertable<OfflineCacheRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('organization_id')) {
      context.handle(
        _organizationIdMeta,
        organizationId.isAcceptableOrUnknown(
          data['organization_id']!,
          _organizationIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_organizationIdMeta);
    }
    if (data.containsKey('branch_id')) {
      context.handle(
        _branchIdMeta,
        branchId.isAcceptableOrUnknown(data['branch_id']!, _branchIdMeta),
      );
    } else if (isInserting) {
      context.missing(_branchIdMeta);
    }
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('actor_id')) {
      context.handle(
        _actorIdMeta,
        actorId.isAcceptableOrUnknown(data['actor_id']!, _actorIdMeta),
      );
    } else if (isInserting) {
      context.missing(_actorIdMeta);
    }
    if (data.containsKey('device_id')) {
      context.handle(
        _deviceIdMeta,
        deviceId.isAcceptableOrUnknown(data['device_id']!, _deviceIdMeta),
      );
    } else if (isInserting) {
      context.missing(_deviceIdMeta);
    }
    if (data.containsKey('kind')) {
      context.handle(
        _kindMeta,
        kind.isAcceptableOrUnknown(data['kind']!, _kindMeta),
      );
    } else if (isInserting) {
      context.missing(_kindMeta);
    }
    if (data.containsKey('revision')) {
      context.handle(
        _revisionMeta,
        revision.isAcceptableOrUnknown(data['revision']!, _revisionMeta),
      );
    } else if (isInserting) {
      context.missing(_revisionMeta);
    }
    if (data.containsKey('deleted')) {
      context.handle(
        _deletedMeta,
        deleted.isAcceptableOrUnknown(data['deleted']!, _deletedMeta),
      );
    }
    if (data.containsKey('value_json')) {
      context.handle(
        _valueJsonMeta,
        valueJson.isAcceptableOrUnknown(data['value_json']!, _valueJsonMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {
    organizationId,
    branchId,
    actorId,
    deviceId,
    kind,
    id,
  };
  @override
  OfflineCacheRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return OfflineCacheRow(
      organizationId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}organization_id'],
      )!,
      branchId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}branch_id'],
      )!,
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      actorId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}actor_id'],
      )!,
      deviceId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}device_id'],
      )!,
      kind: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}kind'],
      )!,
      revision: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}revision'],
      )!,
      deleted: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}deleted'],
      )!,
      valueJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}value_json'],
      ),
    );
  }

  @override
  $OfflineCacheRecordsTable createAlias(String alias) {
    return $OfflineCacheRecordsTable(attachedDatabase, alias);
  }
}

class OfflineCacheRow extends DataClass implements Insertable<OfflineCacheRow> {
  final String organizationId;
  final String branchId;
  final String id;
  final String actorId;
  final String deviceId;
  final String kind;
  final int revision;
  final bool deleted;
  final String? valueJson;
  const OfflineCacheRow({
    required this.organizationId,
    required this.branchId,
    required this.id,
    required this.actorId,
    required this.deviceId,
    required this.kind,
    required this.revision,
    required this.deleted,
    this.valueJson,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['organization_id'] = Variable<String>(organizationId);
    map['branch_id'] = Variable<String>(branchId);
    map['id'] = Variable<String>(id);
    map['actor_id'] = Variable<String>(actorId);
    map['device_id'] = Variable<String>(deviceId);
    map['kind'] = Variable<String>(kind);
    map['revision'] = Variable<int>(revision);
    map['deleted'] = Variable<bool>(deleted);
    if (!nullToAbsent || valueJson != null) {
      map['value_json'] = Variable<String>(valueJson);
    }
    return map;
  }

  OfflineCacheRecordsCompanion toCompanion(bool nullToAbsent) {
    return OfflineCacheRecordsCompanion(
      organizationId: Value(organizationId),
      branchId: Value(branchId),
      id: Value(id),
      actorId: Value(actorId),
      deviceId: Value(deviceId),
      kind: Value(kind),
      revision: Value(revision),
      deleted: Value(deleted),
      valueJson: valueJson == null && nullToAbsent
          ? const Value.absent()
          : Value(valueJson),
    );
  }

  factory OfflineCacheRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return OfflineCacheRow(
      organizationId: serializer.fromJson<String>(json['organizationId']),
      branchId: serializer.fromJson<String>(json['branchId']),
      id: serializer.fromJson<String>(json['id']),
      actorId: serializer.fromJson<String>(json['actorId']),
      deviceId: serializer.fromJson<String>(json['deviceId']),
      kind: serializer.fromJson<String>(json['kind']),
      revision: serializer.fromJson<int>(json['revision']),
      deleted: serializer.fromJson<bool>(json['deleted']),
      valueJson: serializer.fromJson<String?>(json['valueJson']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'organizationId': serializer.toJson<String>(organizationId),
      'branchId': serializer.toJson<String>(branchId),
      'id': serializer.toJson<String>(id),
      'actorId': serializer.toJson<String>(actorId),
      'deviceId': serializer.toJson<String>(deviceId),
      'kind': serializer.toJson<String>(kind),
      'revision': serializer.toJson<int>(revision),
      'deleted': serializer.toJson<bool>(deleted),
      'valueJson': serializer.toJson<String?>(valueJson),
    };
  }

  OfflineCacheRow copyWith({
    String? organizationId,
    String? branchId,
    String? id,
    String? actorId,
    String? deviceId,
    String? kind,
    int? revision,
    bool? deleted,
    Value<String?> valueJson = const Value.absent(),
  }) => OfflineCacheRow(
    organizationId: organizationId ?? this.organizationId,
    branchId: branchId ?? this.branchId,
    id: id ?? this.id,
    actorId: actorId ?? this.actorId,
    deviceId: deviceId ?? this.deviceId,
    kind: kind ?? this.kind,
    revision: revision ?? this.revision,
    deleted: deleted ?? this.deleted,
    valueJson: valueJson.present ? valueJson.value : this.valueJson,
  );
  OfflineCacheRow copyWithCompanion(OfflineCacheRecordsCompanion data) {
    return OfflineCacheRow(
      organizationId: data.organizationId.present
          ? data.organizationId.value
          : this.organizationId,
      branchId: data.branchId.present ? data.branchId.value : this.branchId,
      id: data.id.present ? data.id.value : this.id,
      actorId: data.actorId.present ? data.actorId.value : this.actorId,
      deviceId: data.deviceId.present ? data.deviceId.value : this.deviceId,
      kind: data.kind.present ? data.kind.value : this.kind,
      revision: data.revision.present ? data.revision.value : this.revision,
      deleted: data.deleted.present ? data.deleted.value : this.deleted,
      valueJson: data.valueJson.present ? data.valueJson.value : this.valueJson,
    );
  }

  @override
  String toString() {
    return (StringBuffer('OfflineCacheRow(')
          ..write('organizationId: $organizationId, ')
          ..write('branchId: $branchId, ')
          ..write('id: $id, ')
          ..write('actorId: $actorId, ')
          ..write('deviceId: $deviceId, ')
          ..write('kind: $kind, ')
          ..write('revision: $revision, ')
          ..write('deleted: $deleted, ')
          ..write('valueJson: $valueJson')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    organizationId,
    branchId,
    id,
    actorId,
    deviceId,
    kind,
    revision,
    deleted,
    valueJson,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is OfflineCacheRow &&
          other.organizationId == this.organizationId &&
          other.branchId == this.branchId &&
          other.id == this.id &&
          other.actorId == this.actorId &&
          other.deviceId == this.deviceId &&
          other.kind == this.kind &&
          other.revision == this.revision &&
          other.deleted == this.deleted &&
          other.valueJson == this.valueJson);
}

class OfflineCacheRecordsCompanion extends UpdateCompanion<OfflineCacheRow> {
  final Value<String> organizationId;
  final Value<String> branchId;
  final Value<String> id;
  final Value<String> actorId;
  final Value<String> deviceId;
  final Value<String> kind;
  final Value<int> revision;
  final Value<bool> deleted;
  final Value<String?> valueJson;
  final Value<int> rowid;
  const OfflineCacheRecordsCompanion({
    this.organizationId = const Value.absent(),
    this.branchId = const Value.absent(),
    this.id = const Value.absent(),
    this.actorId = const Value.absent(),
    this.deviceId = const Value.absent(),
    this.kind = const Value.absent(),
    this.revision = const Value.absent(),
    this.deleted = const Value.absent(),
    this.valueJson = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  OfflineCacheRecordsCompanion.insert({
    required String organizationId,
    required String branchId,
    required String id,
    required String actorId,
    required String deviceId,
    required String kind,
    required int revision,
    this.deleted = const Value.absent(),
    this.valueJson = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : organizationId = Value(organizationId),
       branchId = Value(branchId),
       id = Value(id),
       actorId = Value(actorId),
       deviceId = Value(deviceId),
       kind = Value(kind),
       revision = Value(revision);
  static Insertable<OfflineCacheRow> custom({
    Expression<String>? organizationId,
    Expression<String>? branchId,
    Expression<String>? id,
    Expression<String>? actorId,
    Expression<String>? deviceId,
    Expression<String>? kind,
    Expression<int>? revision,
    Expression<bool>? deleted,
    Expression<String>? valueJson,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (organizationId != null) 'organization_id': organizationId,
      if (branchId != null) 'branch_id': branchId,
      if (id != null) 'id': id,
      if (actorId != null) 'actor_id': actorId,
      if (deviceId != null) 'device_id': deviceId,
      if (kind != null) 'kind': kind,
      if (revision != null) 'revision': revision,
      if (deleted != null) 'deleted': deleted,
      if (valueJson != null) 'value_json': valueJson,
      if (rowid != null) 'rowid': rowid,
    });
  }

  OfflineCacheRecordsCompanion copyWith({
    Value<String>? organizationId,
    Value<String>? branchId,
    Value<String>? id,
    Value<String>? actorId,
    Value<String>? deviceId,
    Value<String>? kind,
    Value<int>? revision,
    Value<bool>? deleted,
    Value<String?>? valueJson,
    Value<int>? rowid,
  }) {
    return OfflineCacheRecordsCompanion(
      organizationId: organizationId ?? this.organizationId,
      branchId: branchId ?? this.branchId,
      id: id ?? this.id,
      actorId: actorId ?? this.actorId,
      deviceId: deviceId ?? this.deviceId,
      kind: kind ?? this.kind,
      revision: revision ?? this.revision,
      deleted: deleted ?? this.deleted,
      valueJson: valueJson ?? this.valueJson,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (organizationId.present) {
      map['organization_id'] = Variable<String>(organizationId.value);
    }
    if (branchId.present) {
      map['branch_id'] = Variable<String>(branchId.value);
    }
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (actorId.present) {
      map['actor_id'] = Variable<String>(actorId.value);
    }
    if (deviceId.present) {
      map['device_id'] = Variable<String>(deviceId.value);
    }
    if (kind.present) {
      map['kind'] = Variable<String>(kind.value);
    }
    if (revision.present) {
      map['revision'] = Variable<int>(revision.value);
    }
    if (deleted.present) {
      map['deleted'] = Variable<bool>(deleted.value);
    }
    if (valueJson.present) {
      map['value_json'] = Variable<String>(valueJson.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('OfflineCacheRecordsCompanion(')
          ..write('organizationId: $organizationId, ')
          ..write('branchId: $branchId, ')
          ..write('id: $id, ')
          ..write('actorId: $actorId, ')
          ..write('deviceId: $deviceId, ')
          ..write('kind: $kind, ')
          ..write('revision: $revision, ')
          ..write('deleted: $deleted, ')
          ..write('valueJson: $valueJson, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $OfflineCacheStatesTable extends OfflineCacheStates
    with TableInfo<$OfflineCacheStatesTable, OfflineCacheStateRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $OfflineCacheStatesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _organizationIdMeta = const VerificationMeta(
    'organizationId',
  );
  @override
  late final GeneratedColumn<String> organizationId = GeneratedColumn<String>(
    'organization_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _branchIdMeta = const VerificationMeta(
    'branchId',
  );
  @override
  late final GeneratedColumn<String> branchId = GeneratedColumn<String>(
    'branch_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _actorIdMeta = const VerificationMeta(
    'actorId',
  );
  @override
  late final GeneratedColumn<String> actorId = GeneratedColumn<String>(
    'actor_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _deviceIdMeta = const VerificationMeta(
    'deviceId',
  );
  @override
  late final GeneratedColumn<String> deviceId = GeneratedColumn<String>(
    'device_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _cursorMeta = const VerificationMeta('cursor');
  @override
  late final GeneratedColumn<String> cursor = GeneratedColumn<String>(
    'cursor',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _serverTimeMeta = const VerificationMeta(
    'serverTime',
  );
  @override
  late final GeneratedColumn<DateTime> serverTime = GeneratedColumn<DateTime>(
    'server_time',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _observedAtMeta = const VerificationMeta(
    'observedAt',
  );
  @override
  late final GeneratedColumn<DateTime> observedAt = GeneratedColumn<DateTime>(
    'observed_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _completeSnapshotMeta = const VerificationMeta(
    'completeSnapshot',
  );
  @override
  late final GeneratedColumn<bool> completeSnapshot = GeneratedColumn<bool>(
    'complete_snapshot',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("complete_snapshot" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _grantIdMeta = const VerificationMeta(
    'grantId',
  );
  @override
  late final GeneratedColumn<String> grantId = GeneratedColumn<String>(
    'grant_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    organizationId,
    branchId,
    id,
    actorId,
    deviceId,
    cursor,
    serverTime,
    observedAt,
    completeSnapshot,
    grantId,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'offline_cache_states';
  @override
  VerificationContext validateIntegrity(
    Insertable<OfflineCacheStateRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('organization_id')) {
      context.handle(
        _organizationIdMeta,
        organizationId.isAcceptableOrUnknown(
          data['organization_id']!,
          _organizationIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_organizationIdMeta);
    }
    if (data.containsKey('branch_id')) {
      context.handle(
        _branchIdMeta,
        branchId.isAcceptableOrUnknown(data['branch_id']!, _branchIdMeta),
      );
    } else if (isInserting) {
      context.missing(_branchIdMeta);
    }
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('actor_id')) {
      context.handle(
        _actorIdMeta,
        actorId.isAcceptableOrUnknown(data['actor_id']!, _actorIdMeta),
      );
    } else if (isInserting) {
      context.missing(_actorIdMeta);
    }
    if (data.containsKey('device_id')) {
      context.handle(
        _deviceIdMeta,
        deviceId.isAcceptableOrUnknown(data['device_id']!, _deviceIdMeta),
      );
    } else if (isInserting) {
      context.missing(_deviceIdMeta);
    }
    if (data.containsKey('cursor')) {
      context.handle(
        _cursorMeta,
        cursor.isAcceptableOrUnknown(data['cursor']!, _cursorMeta),
      );
    } else if (isInserting) {
      context.missing(_cursorMeta);
    }
    if (data.containsKey('server_time')) {
      context.handle(
        _serverTimeMeta,
        serverTime.isAcceptableOrUnknown(data['server_time']!, _serverTimeMeta),
      );
    } else if (isInserting) {
      context.missing(_serverTimeMeta);
    }
    if (data.containsKey('observed_at')) {
      context.handle(
        _observedAtMeta,
        observedAt.isAcceptableOrUnknown(data['observed_at']!, _observedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_observedAtMeta);
    }
    if (data.containsKey('complete_snapshot')) {
      context.handle(
        _completeSnapshotMeta,
        completeSnapshot.isAcceptableOrUnknown(
          data['complete_snapshot']!,
          _completeSnapshotMeta,
        ),
      );
    }
    if (data.containsKey('grant_id')) {
      context.handle(
        _grantIdMeta,
        grantId.isAcceptableOrUnknown(data['grant_id']!, _grantIdMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {
    organizationId,
    branchId,
    actorId,
    deviceId,
    id,
  };
  @override
  OfflineCacheStateRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return OfflineCacheStateRow(
      organizationId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}organization_id'],
      )!,
      branchId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}branch_id'],
      )!,
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      actorId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}actor_id'],
      )!,
      deviceId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}device_id'],
      )!,
      cursor: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}cursor'],
      )!,
      serverTime: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}server_time'],
      )!,
      observedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}observed_at'],
      )!,
      completeSnapshot: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}complete_snapshot'],
      )!,
      grantId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}grant_id'],
      ),
    );
  }

  @override
  $OfflineCacheStatesTable createAlias(String alias) {
    return $OfflineCacheStatesTable(attachedDatabase, alias);
  }
}

class OfflineCacheStateRow extends DataClass
    implements Insertable<OfflineCacheStateRow> {
  final String organizationId;
  final String branchId;
  final String id;
  final String actorId;
  final String deviceId;
  final String cursor;
  final DateTime serverTime;
  final DateTime observedAt;
  final bool completeSnapshot;
  final String? grantId;
  const OfflineCacheStateRow({
    required this.organizationId,
    required this.branchId,
    required this.id,
    required this.actorId,
    required this.deviceId,
    required this.cursor,
    required this.serverTime,
    required this.observedAt,
    required this.completeSnapshot,
    this.grantId,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['organization_id'] = Variable<String>(organizationId);
    map['branch_id'] = Variable<String>(branchId);
    map['id'] = Variable<String>(id);
    map['actor_id'] = Variable<String>(actorId);
    map['device_id'] = Variable<String>(deviceId);
    map['cursor'] = Variable<String>(cursor);
    map['server_time'] = Variable<DateTime>(serverTime);
    map['observed_at'] = Variable<DateTime>(observedAt);
    map['complete_snapshot'] = Variable<bool>(completeSnapshot);
    if (!nullToAbsent || grantId != null) {
      map['grant_id'] = Variable<String>(grantId);
    }
    return map;
  }

  OfflineCacheStatesCompanion toCompanion(bool nullToAbsent) {
    return OfflineCacheStatesCompanion(
      organizationId: Value(organizationId),
      branchId: Value(branchId),
      id: Value(id),
      actorId: Value(actorId),
      deviceId: Value(deviceId),
      cursor: Value(cursor),
      serverTime: Value(serverTime),
      observedAt: Value(observedAt),
      completeSnapshot: Value(completeSnapshot),
      grantId: grantId == null && nullToAbsent
          ? const Value.absent()
          : Value(grantId),
    );
  }

  factory OfflineCacheStateRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return OfflineCacheStateRow(
      organizationId: serializer.fromJson<String>(json['organizationId']),
      branchId: serializer.fromJson<String>(json['branchId']),
      id: serializer.fromJson<String>(json['id']),
      actorId: serializer.fromJson<String>(json['actorId']),
      deviceId: serializer.fromJson<String>(json['deviceId']),
      cursor: serializer.fromJson<String>(json['cursor']),
      serverTime: serializer.fromJson<DateTime>(json['serverTime']),
      observedAt: serializer.fromJson<DateTime>(json['observedAt']),
      completeSnapshot: serializer.fromJson<bool>(json['completeSnapshot']),
      grantId: serializer.fromJson<String?>(json['grantId']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'organizationId': serializer.toJson<String>(organizationId),
      'branchId': serializer.toJson<String>(branchId),
      'id': serializer.toJson<String>(id),
      'actorId': serializer.toJson<String>(actorId),
      'deviceId': serializer.toJson<String>(deviceId),
      'cursor': serializer.toJson<String>(cursor),
      'serverTime': serializer.toJson<DateTime>(serverTime),
      'observedAt': serializer.toJson<DateTime>(observedAt),
      'completeSnapshot': serializer.toJson<bool>(completeSnapshot),
      'grantId': serializer.toJson<String?>(grantId),
    };
  }

  OfflineCacheStateRow copyWith({
    String? organizationId,
    String? branchId,
    String? id,
    String? actorId,
    String? deviceId,
    String? cursor,
    DateTime? serverTime,
    DateTime? observedAt,
    bool? completeSnapshot,
    Value<String?> grantId = const Value.absent(),
  }) => OfflineCacheStateRow(
    organizationId: organizationId ?? this.organizationId,
    branchId: branchId ?? this.branchId,
    id: id ?? this.id,
    actorId: actorId ?? this.actorId,
    deviceId: deviceId ?? this.deviceId,
    cursor: cursor ?? this.cursor,
    serverTime: serverTime ?? this.serverTime,
    observedAt: observedAt ?? this.observedAt,
    completeSnapshot: completeSnapshot ?? this.completeSnapshot,
    grantId: grantId.present ? grantId.value : this.grantId,
  );
  OfflineCacheStateRow copyWithCompanion(OfflineCacheStatesCompanion data) {
    return OfflineCacheStateRow(
      organizationId: data.organizationId.present
          ? data.organizationId.value
          : this.organizationId,
      branchId: data.branchId.present ? data.branchId.value : this.branchId,
      id: data.id.present ? data.id.value : this.id,
      actorId: data.actorId.present ? data.actorId.value : this.actorId,
      deviceId: data.deviceId.present ? data.deviceId.value : this.deviceId,
      cursor: data.cursor.present ? data.cursor.value : this.cursor,
      serverTime: data.serverTime.present
          ? data.serverTime.value
          : this.serverTime,
      observedAt: data.observedAt.present
          ? data.observedAt.value
          : this.observedAt,
      completeSnapshot: data.completeSnapshot.present
          ? data.completeSnapshot.value
          : this.completeSnapshot,
      grantId: data.grantId.present ? data.grantId.value : this.grantId,
    );
  }

  @override
  String toString() {
    return (StringBuffer('OfflineCacheStateRow(')
          ..write('organizationId: $organizationId, ')
          ..write('branchId: $branchId, ')
          ..write('id: $id, ')
          ..write('actorId: $actorId, ')
          ..write('deviceId: $deviceId, ')
          ..write('cursor: $cursor, ')
          ..write('serverTime: $serverTime, ')
          ..write('observedAt: $observedAt, ')
          ..write('completeSnapshot: $completeSnapshot, ')
          ..write('grantId: $grantId')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    organizationId,
    branchId,
    id,
    actorId,
    deviceId,
    cursor,
    serverTime,
    observedAt,
    completeSnapshot,
    grantId,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is OfflineCacheStateRow &&
          other.organizationId == this.organizationId &&
          other.branchId == this.branchId &&
          other.id == this.id &&
          other.actorId == this.actorId &&
          other.deviceId == this.deviceId &&
          other.cursor == this.cursor &&
          other.serverTime == this.serverTime &&
          other.observedAt == this.observedAt &&
          other.completeSnapshot == this.completeSnapshot &&
          other.grantId == this.grantId);
}

class OfflineCacheStatesCompanion
    extends UpdateCompanion<OfflineCacheStateRow> {
  final Value<String> organizationId;
  final Value<String> branchId;
  final Value<String> id;
  final Value<String> actorId;
  final Value<String> deviceId;
  final Value<String> cursor;
  final Value<DateTime> serverTime;
  final Value<DateTime> observedAt;
  final Value<bool> completeSnapshot;
  final Value<String?> grantId;
  final Value<int> rowid;
  const OfflineCacheStatesCompanion({
    this.organizationId = const Value.absent(),
    this.branchId = const Value.absent(),
    this.id = const Value.absent(),
    this.actorId = const Value.absent(),
    this.deviceId = const Value.absent(),
    this.cursor = const Value.absent(),
    this.serverTime = const Value.absent(),
    this.observedAt = const Value.absent(),
    this.completeSnapshot = const Value.absent(),
    this.grantId = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  OfflineCacheStatesCompanion.insert({
    required String organizationId,
    required String branchId,
    required String id,
    required String actorId,
    required String deviceId,
    required String cursor,
    required DateTime serverTime,
    required DateTime observedAt,
    this.completeSnapshot = const Value.absent(),
    this.grantId = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : organizationId = Value(organizationId),
       branchId = Value(branchId),
       id = Value(id),
       actorId = Value(actorId),
       deviceId = Value(deviceId),
       cursor = Value(cursor),
       serverTime = Value(serverTime),
       observedAt = Value(observedAt);
  static Insertable<OfflineCacheStateRow> custom({
    Expression<String>? organizationId,
    Expression<String>? branchId,
    Expression<String>? id,
    Expression<String>? actorId,
    Expression<String>? deviceId,
    Expression<String>? cursor,
    Expression<DateTime>? serverTime,
    Expression<DateTime>? observedAt,
    Expression<bool>? completeSnapshot,
    Expression<String>? grantId,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (organizationId != null) 'organization_id': organizationId,
      if (branchId != null) 'branch_id': branchId,
      if (id != null) 'id': id,
      if (actorId != null) 'actor_id': actorId,
      if (deviceId != null) 'device_id': deviceId,
      if (cursor != null) 'cursor': cursor,
      if (serverTime != null) 'server_time': serverTime,
      if (observedAt != null) 'observed_at': observedAt,
      if (completeSnapshot != null) 'complete_snapshot': completeSnapshot,
      if (grantId != null) 'grant_id': grantId,
      if (rowid != null) 'rowid': rowid,
    });
  }

  OfflineCacheStatesCompanion copyWith({
    Value<String>? organizationId,
    Value<String>? branchId,
    Value<String>? id,
    Value<String>? actorId,
    Value<String>? deviceId,
    Value<String>? cursor,
    Value<DateTime>? serverTime,
    Value<DateTime>? observedAt,
    Value<bool>? completeSnapshot,
    Value<String?>? grantId,
    Value<int>? rowid,
  }) {
    return OfflineCacheStatesCompanion(
      organizationId: organizationId ?? this.organizationId,
      branchId: branchId ?? this.branchId,
      id: id ?? this.id,
      actorId: actorId ?? this.actorId,
      deviceId: deviceId ?? this.deviceId,
      cursor: cursor ?? this.cursor,
      serverTime: serverTime ?? this.serverTime,
      observedAt: observedAt ?? this.observedAt,
      completeSnapshot: completeSnapshot ?? this.completeSnapshot,
      grantId: grantId ?? this.grantId,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (organizationId.present) {
      map['organization_id'] = Variable<String>(organizationId.value);
    }
    if (branchId.present) {
      map['branch_id'] = Variable<String>(branchId.value);
    }
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (actorId.present) {
      map['actor_id'] = Variable<String>(actorId.value);
    }
    if (deviceId.present) {
      map['device_id'] = Variable<String>(deviceId.value);
    }
    if (cursor.present) {
      map['cursor'] = Variable<String>(cursor.value);
    }
    if (serverTime.present) {
      map['server_time'] = Variable<DateTime>(serverTime.value);
    }
    if (observedAt.present) {
      map['observed_at'] = Variable<DateTime>(observedAt.value);
    }
    if (completeSnapshot.present) {
      map['complete_snapshot'] = Variable<bool>(completeSnapshot.value);
    }
    if (grantId.present) {
      map['grant_id'] = Variable<String>(grantId.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('OfflineCacheStatesCompanion(')
          ..write('organizationId: $organizationId, ')
          ..write('branchId: $branchId, ')
          ..write('id: $id, ')
          ..write('actorId: $actorId, ')
          ..write('deviceId: $deviceId, ')
          ..write('cursor: $cursor, ')
          ..write('serverTime: $serverTime, ')
          ..write('observedAt: $observedAt, ')
          ..write('completeSnapshot: $completeSnapshot, ')
          ..write('grantId: $grantId, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $OfflineStockEffectsTable extends OfflineStockEffects
    with TableInfo<$OfflineStockEffectsTable, OfflineStockEffectRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $OfflineStockEffectsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _organizationIdMeta = const VerificationMeta(
    'organizationId',
  );
  @override
  late final GeneratedColumn<String> organizationId = GeneratedColumn<String>(
    'organization_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _branchIdMeta = const VerificationMeta(
    'branchId',
  );
  @override
  late final GeneratedColumn<String> branchId = GeneratedColumn<String>(
    'branch_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _actorIdMeta = const VerificationMeta(
    'actorId',
  );
  @override
  late final GeneratedColumn<String> actorId = GeneratedColumn<String>(
    'actor_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _deviceIdMeta = const VerificationMeta(
    'deviceId',
  );
  @override
  late final GeneratedColumn<String> deviceId = GeneratedColumn<String>(
    'device_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _eventIdMeta = const VerificationMeta(
    'eventId',
  );
  @override
  late final GeneratedColumn<String> eventId = GeneratedColumn<String>(
    'event_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _productIdMeta = const VerificationMeta(
    'productId',
  );
  @override
  late final GeneratedColumn<String> productId = GeneratedColumn<String>(
    'product_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _observedRevisionMeta = const VerificationMeta(
    'observedRevision',
  );
  @override
  late final GeneratedColumn<int> observedRevision = GeneratedColumn<int>(
    'observed_revision',
    aliasedName,
    false,
    check: () => ComparableExpr(observedRevision).isBiggerOrEqualValue(0),
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _quantityDeltaMeta = const VerificationMeta(
    'quantityDelta',
  );
  @override
  late final GeneratedColumn<int> quantityDelta = GeneratedColumn<int>(
    'quantity_delta',
    aliasedName,
    false,
    check: () => ComparableExpr(quantityDelta).isSmallerThanValue(0),
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    organizationId,
    branchId,
    id,
    actorId,
    deviceId,
    eventId,
    productId,
    observedRevision,
    quantityDelta,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'offline_stock_effects';
  @override
  VerificationContext validateIntegrity(
    Insertable<OfflineStockEffectRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('organization_id')) {
      context.handle(
        _organizationIdMeta,
        organizationId.isAcceptableOrUnknown(
          data['organization_id']!,
          _organizationIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_organizationIdMeta);
    }
    if (data.containsKey('branch_id')) {
      context.handle(
        _branchIdMeta,
        branchId.isAcceptableOrUnknown(data['branch_id']!, _branchIdMeta),
      );
    } else if (isInserting) {
      context.missing(_branchIdMeta);
    }
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('actor_id')) {
      context.handle(
        _actorIdMeta,
        actorId.isAcceptableOrUnknown(data['actor_id']!, _actorIdMeta),
      );
    } else if (isInserting) {
      context.missing(_actorIdMeta);
    }
    if (data.containsKey('device_id')) {
      context.handle(
        _deviceIdMeta,
        deviceId.isAcceptableOrUnknown(data['device_id']!, _deviceIdMeta),
      );
    } else if (isInserting) {
      context.missing(_deviceIdMeta);
    }
    if (data.containsKey('event_id')) {
      context.handle(
        _eventIdMeta,
        eventId.isAcceptableOrUnknown(data['event_id']!, _eventIdMeta),
      );
    } else if (isInserting) {
      context.missing(_eventIdMeta);
    }
    if (data.containsKey('product_id')) {
      context.handle(
        _productIdMeta,
        productId.isAcceptableOrUnknown(data['product_id']!, _productIdMeta),
      );
    } else if (isInserting) {
      context.missing(_productIdMeta);
    }
    if (data.containsKey('observed_revision')) {
      context.handle(
        _observedRevisionMeta,
        observedRevision.isAcceptableOrUnknown(
          data['observed_revision']!,
          _observedRevisionMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_observedRevisionMeta);
    }
    if (data.containsKey('quantity_delta')) {
      context.handle(
        _quantityDeltaMeta,
        quantityDelta.isAcceptableOrUnknown(
          data['quantity_delta']!,
          _quantityDeltaMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_quantityDeltaMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {organizationId, branchId, id};
  @override
  List<Set<GeneratedColumn>> get uniqueKeys => [
    {organizationId, branchId, actorId, deviceId, eventId, productId},
  ];
  @override
  OfflineStockEffectRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return OfflineStockEffectRow(
      organizationId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}organization_id'],
      )!,
      branchId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}branch_id'],
      )!,
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      actorId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}actor_id'],
      )!,
      deviceId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}device_id'],
      )!,
      eventId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}event_id'],
      )!,
      productId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}product_id'],
      )!,
      observedRevision: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}observed_revision'],
      )!,
      quantityDelta: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}quantity_delta'],
      )!,
    );
  }

  @override
  $OfflineStockEffectsTable createAlias(String alias) {
    return $OfflineStockEffectsTable(attachedDatabase, alias);
  }
}

class OfflineStockEffectRow extends DataClass
    implements Insertable<OfflineStockEffectRow> {
  final String organizationId;
  final String branchId;
  final String id;
  final String actorId;
  final String deviceId;
  final String eventId;
  final String productId;
  final int observedRevision;
  final int quantityDelta;
  const OfflineStockEffectRow({
    required this.organizationId,
    required this.branchId,
    required this.id,
    required this.actorId,
    required this.deviceId,
    required this.eventId,
    required this.productId,
    required this.observedRevision,
    required this.quantityDelta,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['organization_id'] = Variable<String>(organizationId);
    map['branch_id'] = Variable<String>(branchId);
    map['id'] = Variable<String>(id);
    map['actor_id'] = Variable<String>(actorId);
    map['device_id'] = Variable<String>(deviceId);
    map['event_id'] = Variable<String>(eventId);
    map['product_id'] = Variable<String>(productId);
    map['observed_revision'] = Variable<int>(observedRevision);
    map['quantity_delta'] = Variable<int>(quantityDelta);
    return map;
  }

  OfflineStockEffectsCompanion toCompanion(bool nullToAbsent) {
    return OfflineStockEffectsCompanion(
      organizationId: Value(organizationId),
      branchId: Value(branchId),
      id: Value(id),
      actorId: Value(actorId),
      deviceId: Value(deviceId),
      eventId: Value(eventId),
      productId: Value(productId),
      observedRevision: Value(observedRevision),
      quantityDelta: Value(quantityDelta),
    );
  }

  factory OfflineStockEffectRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return OfflineStockEffectRow(
      organizationId: serializer.fromJson<String>(json['organizationId']),
      branchId: serializer.fromJson<String>(json['branchId']),
      id: serializer.fromJson<String>(json['id']),
      actorId: serializer.fromJson<String>(json['actorId']),
      deviceId: serializer.fromJson<String>(json['deviceId']),
      eventId: serializer.fromJson<String>(json['eventId']),
      productId: serializer.fromJson<String>(json['productId']),
      observedRevision: serializer.fromJson<int>(json['observedRevision']),
      quantityDelta: serializer.fromJson<int>(json['quantityDelta']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'organizationId': serializer.toJson<String>(organizationId),
      'branchId': serializer.toJson<String>(branchId),
      'id': serializer.toJson<String>(id),
      'actorId': serializer.toJson<String>(actorId),
      'deviceId': serializer.toJson<String>(deviceId),
      'eventId': serializer.toJson<String>(eventId),
      'productId': serializer.toJson<String>(productId),
      'observedRevision': serializer.toJson<int>(observedRevision),
      'quantityDelta': serializer.toJson<int>(quantityDelta),
    };
  }

  OfflineStockEffectRow copyWith({
    String? organizationId,
    String? branchId,
    String? id,
    String? actorId,
    String? deviceId,
    String? eventId,
    String? productId,
    int? observedRevision,
    int? quantityDelta,
  }) => OfflineStockEffectRow(
    organizationId: organizationId ?? this.organizationId,
    branchId: branchId ?? this.branchId,
    id: id ?? this.id,
    actorId: actorId ?? this.actorId,
    deviceId: deviceId ?? this.deviceId,
    eventId: eventId ?? this.eventId,
    productId: productId ?? this.productId,
    observedRevision: observedRevision ?? this.observedRevision,
    quantityDelta: quantityDelta ?? this.quantityDelta,
  );
  OfflineStockEffectRow copyWithCompanion(OfflineStockEffectsCompanion data) {
    return OfflineStockEffectRow(
      organizationId: data.organizationId.present
          ? data.organizationId.value
          : this.organizationId,
      branchId: data.branchId.present ? data.branchId.value : this.branchId,
      id: data.id.present ? data.id.value : this.id,
      actorId: data.actorId.present ? data.actorId.value : this.actorId,
      deviceId: data.deviceId.present ? data.deviceId.value : this.deviceId,
      eventId: data.eventId.present ? data.eventId.value : this.eventId,
      productId: data.productId.present ? data.productId.value : this.productId,
      observedRevision: data.observedRevision.present
          ? data.observedRevision.value
          : this.observedRevision,
      quantityDelta: data.quantityDelta.present
          ? data.quantityDelta.value
          : this.quantityDelta,
    );
  }

  @override
  String toString() {
    return (StringBuffer('OfflineStockEffectRow(')
          ..write('organizationId: $organizationId, ')
          ..write('branchId: $branchId, ')
          ..write('id: $id, ')
          ..write('actorId: $actorId, ')
          ..write('deviceId: $deviceId, ')
          ..write('eventId: $eventId, ')
          ..write('productId: $productId, ')
          ..write('observedRevision: $observedRevision, ')
          ..write('quantityDelta: $quantityDelta')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    organizationId,
    branchId,
    id,
    actorId,
    deviceId,
    eventId,
    productId,
    observedRevision,
    quantityDelta,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is OfflineStockEffectRow &&
          other.organizationId == this.organizationId &&
          other.branchId == this.branchId &&
          other.id == this.id &&
          other.actorId == this.actorId &&
          other.deviceId == this.deviceId &&
          other.eventId == this.eventId &&
          other.productId == this.productId &&
          other.observedRevision == this.observedRevision &&
          other.quantityDelta == this.quantityDelta);
}

class OfflineStockEffectsCompanion
    extends UpdateCompanion<OfflineStockEffectRow> {
  final Value<String> organizationId;
  final Value<String> branchId;
  final Value<String> id;
  final Value<String> actorId;
  final Value<String> deviceId;
  final Value<String> eventId;
  final Value<String> productId;
  final Value<int> observedRevision;
  final Value<int> quantityDelta;
  final Value<int> rowid;
  const OfflineStockEffectsCompanion({
    this.organizationId = const Value.absent(),
    this.branchId = const Value.absent(),
    this.id = const Value.absent(),
    this.actorId = const Value.absent(),
    this.deviceId = const Value.absent(),
    this.eventId = const Value.absent(),
    this.productId = const Value.absent(),
    this.observedRevision = const Value.absent(),
    this.quantityDelta = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  OfflineStockEffectsCompanion.insert({
    required String organizationId,
    required String branchId,
    required String id,
    required String actorId,
    required String deviceId,
    required String eventId,
    required String productId,
    required int observedRevision,
    required int quantityDelta,
    this.rowid = const Value.absent(),
  }) : organizationId = Value(organizationId),
       branchId = Value(branchId),
       id = Value(id),
       actorId = Value(actorId),
       deviceId = Value(deviceId),
       eventId = Value(eventId),
       productId = Value(productId),
       observedRevision = Value(observedRevision),
       quantityDelta = Value(quantityDelta);
  static Insertable<OfflineStockEffectRow> custom({
    Expression<String>? organizationId,
    Expression<String>? branchId,
    Expression<String>? id,
    Expression<String>? actorId,
    Expression<String>? deviceId,
    Expression<String>? eventId,
    Expression<String>? productId,
    Expression<int>? observedRevision,
    Expression<int>? quantityDelta,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (organizationId != null) 'organization_id': organizationId,
      if (branchId != null) 'branch_id': branchId,
      if (id != null) 'id': id,
      if (actorId != null) 'actor_id': actorId,
      if (deviceId != null) 'device_id': deviceId,
      if (eventId != null) 'event_id': eventId,
      if (productId != null) 'product_id': productId,
      if (observedRevision != null) 'observed_revision': observedRevision,
      if (quantityDelta != null) 'quantity_delta': quantityDelta,
      if (rowid != null) 'rowid': rowid,
    });
  }

  OfflineStockEffectsCompanion copyWith({
    Value<String>? organizationId,
    Value<String>? branchId,
    Value<String>? id,
    Value<String>? actorId,
    Value<String>? deviceId,
    Value<String>? eventId,
    Value<String>? productId,
    Value<int>? observedRevision,
    Value<int>? quantityDelta,
    Value<int>? rowid,
  }) {
    return OfflineStockEffectsCompanion(
      organizationId: organizationId ?? this.organizationId,
      branchId: branchId ?? this.branchId,
      id: id ?? this.id,
      actorId: actorId ?? this.actorId,
      deviceId: deviceId ?? this.deviceId,
      eventId: eventId ?? this.eventId,
      productId: productId ?? this.productId,
      observedRevision: observedRevision ?? this.observedRevision,
      quantityDelta: quantityDelta ?? this.quantityDelta,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (organizationId.present) {
      map['organization_id'] = Variable<String>(organizationId.value);
    }
    if (branchId.present) {
      map['branch_id'] = Variable<String>(branchId.value);
    }
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (actorId.present) {
      map['actor_id'] = Variable<String>(actorId.value);
    }
    if (deviceId.present) {
      map['device_id'] = Variable<String>(deviceId.value);
    }
    if (eventId.present) {
      map['event_id'] = Variable<String>(eventId.value);
    }
    if (productId.present) {
      map['product_id'] = Variable<String>(productId.value);
    }
    if (observedRevision.present) {
      map['observed_revision'] = Variable<int>(observedRevision.value);
    }
    if (quantityDelta.present) {
      map['quantity_delta'] = Variable<int>(quantityDelta.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('OfflineStockEffectsCompanion(')
          ..write('organizationId: $organizationId, ')
          ..write('branchId: $branchId, ')
          ..write('id: $id, ')
          ..write('actorId: $actorId, ')
          ..write('deviceId: $deviceId, ')
          ..write('eventId: $eventId, ')
          ..write('productId: $productId, ')
          ..write('observedRevision: $observedRevision, ')
          ..write('quantityDelta: $quantityDelta, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $OfflineAcceptanceLinksTable extends OfflineAcceptanceLinks
    with TableInfo<$OfflineAcceptanceLinksTable, OfflineAcceptanceRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $OfflineAcceptanceLinksTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _organizationIdMeta = const VerificationMeta(
    'organizationId',
  );
  @override
  late final GeneratedColumn<String> organizationId = GeneratedColumn<String>(
    'organization_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _branchIdMeta = const VerificationMeta(
    'branchId',
  );
  @override
  late final GeneratedColumn<String> branchId = GeneratedColumn<String>(
    'branch_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _actorIdMeta = const VerificationMeta(
    'actorId',
  );
  @override
  late final GeneratedColumn<String> actorId = GeneratedColumn<String>(
    'actor_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _deviceIdMeta = const VerificationMeta(
    'deviceId',
  );
  @override
  late final GeneratedColumn<String> deviceId = GeneratedColumn<String>(
    'device_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _grantIdMeta = const VerificationMeta(
    'grantId',
  );
  @override
  late final GeneratedColumn<String> grantId = GeneratedColumn<String>(
    'grant_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _sequenceMeta = const VerificationMeta(
    'sequence',
  );
  @override
  late final GeneratedColumn<int> sequence = GeneratedColumn<int>(
    'sequence',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _documentIdMeta = const VerificationMeta(
    'documentId',
  );
  @override
  late final GeneratedColumn<String> documentId = GeneratedColumn<String>(
    'document_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _eventDigestMeta = const VerificationMeta(
    'eventDigest',
  );
  @override
  late final GeneratedColumn<String> eventDigest = GeneratedColumn<String>(
    'event_digest',
    aliasedName,
    false,
    additionalChecks: GeneratedColumn.checkTextLength(
      minTextLength: 64,
      maxTextLength: 64,
    ),
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _serverReceiptIdMeta = const VerificationMeta(
    'serverReceiptId',
  );
  @override
  late final GeneratedColumn<String> serverReceiptId = GeneratedColumn<String>(
    'server_receipt_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _acceptedAtIsoMeta = const VerificationMeta(
    'acceptedAtIso',
  );
  @override
  late final GeneratedColumn<String> acceptedAtIso = GeneratedColumn<String>(
    'accepted_at_iso',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _receiptJsonMeta = const VerificationMeta(
    'receiptJson',
  );
  @override
  late final GeneratedColumn<String> receiptJson = GeneratedColumn<String>(
    'receipt_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _reconciliationCodeMeta =
      const VerificationMeta('reconciliationCode');
  @override
  late final GeneratedColumn<String> reconciliationCode =
      GeneratedColumn<String>(
        'reconciliation_code',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      );
  @override
  List<GeneratedColumn> get $columns => [
    organizationId,
    branchId,
    id,
    actorId,
    deviceId,
    grantId,
    sequence,
    documentId,
    eventDigest,
    serverReceiptId,
    acceptedAtIso,
    receiptJson,
    reconciliationCode,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'offline_acceptance_links';
  @override
  VerificationContext validateIntegrity(
    Insertable<OfflineAcceptanceRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('organization_id')) {
      context.handle(
        _organizationIdMeta,
        organizationId.isAcceptableOrUnknown(
          data['organization_id']!,
          _organizationIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_organizationIdMeta);
    }
    if (data.containsKey('branch_id')) {
      context.handle(
        _branchIdMeta,
        branchId.isAcceptableOrUnknown(data['branch_id']!, _branchIdMeta),
      );
    } else if (isInserting) {
      context.missing(_branchIdMeta);
    }
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('actor_id')) {
      context.handle(
        _actorIdMeta,
        actorId.isAcceptableOrUnknown(data['actor_id']!, _actorIdMeta),
      );
    } else if (isInserting) {
      context.missing(_actorIdMeta);
    }
    if (data.containsKey('device_id')) {
      context.handle(
        _deviceIdMeta,
        deviceId.isAcceptableOrUnknown(data['device_id']!, _deviceIdMeta),
      );
    } else if (isInserting) {
      context.missing(_deviceIdMeta);
    }
    if (data.containsKey('grant_id')) {
      context.handle(
        _grantIdMeta,
        grantId.isAcceptableOrUnknown(data['grant_id']!, _grantIdMeta),
      );
    } else if (isInserting) {
      context.missing(_grantIdMeta);
    }
    if (data.containsKey('sequence')) {
      context.handle(
        _sequenceMeta,
        sequence.isAcceptableOrUnknown(data['sequence']!, _sequenceMeta),
      );
    } else if (isInserting) {
      context.missing(_sequenceMeta);
    }
    if (data.containsKey('document_id')) {
      context.handle(
        _documentIdMeta,
        documentId.isAcceptableOrUnknown(data['document_id']!, _documentIdMeta),
      );
    } else if (isInserting) {
      context.missing(_documentIdMeta);
    }
    if (data.containsKey('event_digest')) {
      context.handle(
        _eventDigestMeta,
        eventDigest.isAcceptableOrUnknown(
          data['event_digest']!,
          _eventDigestMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_eventDigestMeta);
    }
    if (data.containsKey('server_receipt_id')) {
      context.handle(
        _serverReceiptIdMeta,
        serverReceiptId.isAcceptableOrUnknown(
          data['server_receipt_id']!,
          _serverReceiptIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_serverReceiptIdMeta);
    }
    if (data.containsKey('accepted_at_iso')) {
      context.handle(
        _acceptedAtIsoMeta,
        acceptedAtIso.isAcceptableOrUnknown(
          data['accepted_at_iso']!,
          _acceptedAtIsoMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_acceptedAtIsoMeta);
    }
    if (data.containsKey('receipt_json')) {
      context.handle(
        _receiptJsonMeta,
        receiptJson.isAcceptableOrUnknown(
          data['receipt_json']!,
          _receiptJsonMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_receiptJsonMeta);
    }
    if (data.containsKey('reconciliation_code')) {
      context.handle(
        _reconciliationCodeMeta,
        reconciliationCode.isAcceptableOrUnknown(
          data['reconciliation_code']!,
          _reconciliationCodeMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {organizationId, branchId, id};
  @override
  OfflineAcceptanceRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return OfflineAcceptanceRow(
      organizationId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}organization_id'],
      )!,
      branchId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}branch_id'],
      )!,
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      actorId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}actor_id'],
      )!,
      deviceId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}device_id'],
      )!,
      grantId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}grant_id'],
      )!,
      sequence: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}sequence'],
      )!,
      documentId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}document_id'],
      )!,
      eventDigest: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}event_digest'],
      )!,
      serverReceiptId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}server_receipt_id'],
      )!,
      acceptedAtIso: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}accepted_at_iso'],
      )!,
      receiptJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}receipt_json'],
      )!,
      reconciliationCode: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}reconciliation_code'],
      ),
    );
  }

  @override
  $OfflineAcceptanceLinksTable createAlias(String alias) {
    return $OfflineAcceptanceLinksTable(attachedDatabase, alias);
  }
}

class OfflineAcceptanceRow extends DataClass
    implements Insertable<OfflineAcceptanceRow> {
  final String organizationId;
  final String branchId;
  final String id;
  final String actorId;
  final String deviceId;
  final String grantId;
  final int sequence;
  final String documentId;
  final String eventDigest;
  final String serverReceiptId;
  final String acceptedAtIso;
  final String receiptJson;
  final String? reconciliationCode;
  const OfflineAcceptanceRow({
    required this.organizationId,
    required this.branchId,
    required this.id,
    required this.actorId,
    required this.deviceId,
    required this.grantId,
    required this.sequence,
    required this.documentId,
    required this.eventDigest,
    required this.serverReceiptId,
    required this.acceptedAtIso,
    required this.receiptJson,
    this.reconciliationCode,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['organization_id'] = Variable<String>(organizationId);
    map['branch_id'] = Variable<String>(branchId);
    map['id'] = Variable<String>(id);
    map['actor_id'] = Variable<String>(actorId);
    map['device_id'] = Variable<String>(deviceId);
    map['grant_id'] = Variable<String>(grantId);
    map['sequence'] = Variable<int>(sequence);
    map['document_id'] = Variable<String>(documentId);
    map['event_digest'] = Variable<String>(eventDigest);
    map['server_receipt_id'] = Variable<String>(serverReceiptId);
    map['accepted_at_iso'] = Variable<String>(acceptedAtIso);
    map['receipt_json'] = Variable<String>(receiptJson);
    if (!nullToAbsent || reconciliationCode != null) {
      map['reconciliation_code'] = Variable<String>(reconciliationCode);
    }
    return map;
  }

  OfflineAcceptanceLinksCompanion toCompanion(bool nullToAbsent) {
    return OfflineAcceptanceLinksCompanion(
      organizationId: Value(organizationId),
      branchId: Value(branchId),
      id: Value(id),
      actorId: Value(actorId),
      deviceId: Value(deviceId),
      grantId: Value(grantId),
      sequence: Value(sequence),
      documentId: Value(documentId),
      eventDigest: Value(eventDigest),
      serverReceiptId: Value(serverReceiptId),
      acceptedAtIso: Value(acceptedAtIso),
      receiptJson: Value(receiptJson),
      reconciliationCode: reconciliationCode == null && nullToAbsent
          ? const Value.absent()
          : Value(reconciliationCode),
    );
  }

  factory OfflineAcceptanceRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return OfflineAcceptanceRow(
      organizationId: serializer.fromJson<String>(json['organizationId']),
      branchId: serializer.fromJson<String>(json['branchId']),
      id: serializer.fromJson<String>(json['id']),
      actorId: serializer.fromJson<String>(json['actorId']),
      deviceId: serializer.fromJson<String>(json['deviceId']),
      grantId: serializer.fromJson<String>(json['grantId']),
      sequence: serializer.fromJson<int>(json['sequence']),
      documentId: serializer.fromJson<String>(json['documentId']),
      eventDigest: serializer.fromJson<String>(json['eventDigest']),
      serverReceiptId: serializer.fromJson<String>(json['serverReceiptId']),
      acceptedAtIso: serializer.fromJson<String>(json['acceptedAtIso']),
      receiptJson: serializer.fromJson<String>(json['receiptJson']),
      reconciliationCode: serializer.fromJson<String?>(
        json['reconciliationCode'],
      ),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'organizationId': serializer.toJson<String>(organizationId),
      'branchId': serializer.toJson<String>(branchId),
      'id': serializer.toJson<String>(id),
      'actorId': serializer.toJson<String>(actorId),
      'deviceId': serializer.toJson<String>(deviceId),
      'grantId': serializer.toJson<String>(grantId),
      'sequence': serializer.toJson<int>(sequence),
      'documentId': serializer.toJson<String>(documentId),
      'eventDigest': serializer.toJson<String>(eventDigest),
      'serverReceiptId': serializer.toJson<String>(serverReceiptId),
      'acceptedAtIso': serializer.toJson<String>(acceptedAtIso),
      'receiptJson': serializer.toJson<String>(receiptJson),
      'reconciliationCode': serializer.toJson<String?>(reconciliationCode),
    };
  }

  OfflineAcceptanceRow copyWith({
    String? organizationId,
    String? branchId,
    String? id,
    String? actorId,
    String? deviceId,
    String? grantId,
    int? sequence,
    String? documentId,
    String? eventDigest,
    String? serverReceiptId,
    String? acceptedAtIso,
    String? receiptJson,
    Value<String?> reconciliationCode = const Value.absent(),
  }) => OfflineAcceptanceRow(
    organizationId: organizationId ?? this.organizationId,
    branchId: branchId ?? this.branchId,
    id: id ?? this.id,
    actorId: actorId ?? this.actorId,
    deviceId: deviceId ?? this.deviceId,
    grantId: grantId ?? this.grantId,
    sequence: sequence ?? this.sequence,
    documentId: documentId ?? this.documentId,
    eventDigest: eventDigest ?? this.eventDigest,
    serverReceiptId: serverReceiptId ?? this.serverReceiptId,
    acceptedAtIso: acceptedAtIso ?? this.acceptedAtIso,
    receiptJson: receiptJson ?? this.receiptJson,
    reconciliationCode: reconciliationCode.present
        ? reconciliationCode.value
        : this.reconciliationCode,
  );
  OfflineAcceptanceRow copyWithCompanion(OfflineAcceptanceLinksCompanion data) {
    return OfflineAcceptanceRow(
      organizationId: data.organizationId.present
          ? data.organizationId.value
          : this.organizationId,
      branchId: data.branchId.present ? data.branchId.value : this.branchId,
      id: data.id.present ? data.id.value : this.id,
      actorId: data.actorId.present ? data.actorId.value : this.actorId,
      deviceId: data.deviceId.present ? data.deviceId.value : this.deviceId,
      grantId: data.grantId.present ? data.grantId.value : this.grantId,
      sequence: data.sequence.present ? data.sequence.value : this.sequence,
      documentId: data.documentId.present
          ? data.documentId.value
          : this.documentId,
      eventDigest: data.eventDigest.present
          ? data.eventDigest.value
          : this.eventDigest,
      serverReceiptId: data.serverReceiptId.present
          ? data.serverReceiptId.value
          : this.serverReceiptId,
      acceptedAtIso: data.acceptedAtIso.present
          ? data.acceptedAtIso.value
          : this.acceptedAtIso,
      receiptJson: data.receiptJson.present
          ? data.receiptJson.value
          : this.receiptJson,
      reconciliationCode: data.reconciliationCode.present
          ? data.reconciliationCode.value
          : this.reconciliationCode,
    );
  }

  @override
  String toString() {
    return (StringBuffer('OfflineAcceptanceRow(')
          ..write('organizationId: $organizationId, ')
          ..write('branchId: $branchId, ')
          ..write('id: $id, ')
          ..write('actorId: $actorId, ')
          ..write('deviceId: $deviceId, ')
          ..write('grantId: $grantId, ')
          ..write('sequence: $sequence, ')
          ..write('documentId: $documentId, ')
          ..write('eventDigest: $eventDigest, ')
          ..write('serverReceiptId: $serverReceiptId, ')
          ..write('acceptedAtIso: $acceptedAtIso, ')
          ..write('receiptJson: $receiptJson, ')
          ..write('reconciliationCode: $reconciliationCode')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    organizationId,
    branchId,
    id,
    actorId,
    deviceId,
    grantId,
    sequence,
    documentId,
    eventDigest,
    serverReceiptId,
    acceptedAtIso,
    receiptJson,
    reconciliationCode,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is OfflineAcceptanceRow &&
          other.organizationId == this.organizationId &&
          other.branchId == this.branchId &&
          other.id == this.id &&
          other.actorId == this.actorId &&
          other.deviceId == this.deviceId &&
          other.grantId == this.grantId &&
          other.sequence == this.sequence &&
          other.documentId == this.documentId &&
          other.eventDigest == this.eventDigest &&
          other.serverReceiptId == this.serverReceiptId &&
          other.acceptedAtIso == this.acceptedAtIso &&
          other.receiptJson == this.receiptJson &&
          other.reconciliationCode == this.reconciliationCode);
}

class OfflineAcceptanceLinksCompanion
    extends UpdateCompanion<OfflineAcceptanceRow> {
  final Value<String> organizationId;
  final Value<String> branchId;
  final Value<String> id;
  final Value<String> actorId;
  final Value<String> deviceId;
  final Value<String> grantId;
  final Value<int> sequence;
  final Value<String> documentId;
  final Value<String> eventDigest;
  final Value<String> serverReceiptId;
  final Value<String> acceptedAtIso;
  final Value<String> receiptJson;
  final Value<String?> reconciliationCode;
  final Value<int> rowid;
  const OfflineAcceptanceLinksCompanion({
    this.organizationId = const Value.absent(),
    this.branchId = const Value.absent(),
    this.id = const Value.absent(),
    this.actorId = const Value.absent(),
    this.deviceId = const Value.absent(),
    this.grantId = const Value.absent(),
    this.sequence = const Value.absent(),
    this.documentId = const Value.absent(),
    this.eventDigest = const Value.absent(),
    this.serverReceiptId = const Value.absent(),
    this.acceptedAtIso = const Value.absent(),
    this.receiptJson = const Value.absent(),
    this.reconciliationCode = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  OfflineAcceptanceLinksCompanion.insert({
    required String organizationId,
    required String branchId,
    required String id,
    required String actorId,
    required String deviceId,
    required String grantId,
    required int sequence,
    required String documentId,
    required String eventDigest,
    required String serverReceiptId,
    required String acceptedAtIso,
    required String receiptJson,
    this.reconciliationCode = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : organizationId = Value(organizationId),
       branchId = Value(branchId),
       id = Value(id),
       actorId = Value(actorId),
       deviceId = Value(deviceId),
       grantId = Value(grantId),
       sequence = Value(sequence),
       documentId = Value(documentId),
       eventDigest = Value(eventDigest),
       serverReceiptId = Value(serverReceiptId),
       acceptedAtIso = Value(acceptedAtIso),
       receiptJson = Value(receiptJson);
  static Insertable<OfflineAcceptanceRow> custom({
    Expression<String>? organizationId,
    Expression<String>? branchId,
    Expression<String>? id,
    Expression<String>? actorId,
    Expression<String>? deviceId,
    Expression<String>? grantId,
    Expression<int>? sequence,
    Expression<String>? documentId,
    Expression<String>? eventDigest,
    Expression<String>? serverReceiptId,
    Expression<String>? acceptedAtIso,
    Expression<String>? receiptJson,
    Expression<String>? reconciliationCode,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (organizationId != null) 'organization_id': organizationId,
      if (branchId != null) 'branch_id': branchId,
      if (id != null) 'id': id,
      if (actorId != null) 'actor_id': actorId,
      if (deviceId != null) 'device_id': deviceId,
      if (grantId != null) 'grant_id': grantId,
      if (sequence != null) 'sequence': sequence,
      if (documentId != null) 'document_id': documentId,
      if (eventDigest != null) 'event_digest': eventDigest,
      if (serverReceiptId != null) 'server_receipt_id': serverReceiptId,
      if (acceptedAtIso != null) 'accepted_at_iso': acceptedAtIso,
      if (receiptJson != null) 'receipt_json': receiptJson,
      if (reconciliationCode != null) 'reconciliation_code': reconciliationCode,
      if (rowid != null) 'rowid': rowid,
    });
  }

  OfflineAcceptanceLinksCompanion copyWith({
    Value<String>? organizationId,
    Value<String>? branchId,
    Value<String>? id,
    Value<String>? actorId,
    Value<String>? deviceId,
    Value<String>? grantId,
    Value<int>? sequence,
    Value<String>? documentId,
    Value<String>? eventDigest,
    Value<String>? serverReceiptId,
    Value<String>? acceptedAtIso,
    Value<String>? receiptJson,
    Value<String?>? reconciliationCode,
    Value<int>? rowid,
  }) {
    return OfflineAcceptanceLinksCompanion(
      organizationId: organizationId ?? this.organizationId,
      branchId: branchId ?? this.branchId,
      id: id ?? this.id,
      actorId: actorId ?? this.actorId,
      deviceId: deviceId ?? this.deviceId,
      grantId: grantId ?? this.grantId,
      sequence: sequence ?? this.sequence,
      documentId: documentId ?? this.documentId,
      eventDigest: eventDigest ?? this.eventDigest,
      serverReceiptId: serverReceiptId ?? this.serverReceiptId,
      acceptedAtIso: acceptedAtIso ?? this.acceptedAtIso,
      receiptJson: receiptJson ?? this.receiptJson,
      reconciliationCode: reconciliationCode ?? this.reconciliationCode,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (organizationId.present) {
      map['organization_id'] = Variable<String>(organizationId.value);
    }
    if (branchId.present) {
      map['branch_id'] = Variable<String>(branchId.value);
    }
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (actorId.present) {
      map['actor_id'] = Variable<String>(actorId.value);
    }
    if (deviceId.present) {
      map['device_id'] = Variable<String>(deviceId.value);
    }
    if (grantId.present) {
      map['grant_id'] = Variable<String>(grantId.value);
    }
    if (sequence.present) {
      map['sequence'] = Variable<int>(sequence.value);
    }
    if (documentId.present) {
      map['document_id'] = Variable<String>(documentId.value);
    }
    if (eventDigest.present) {
      map['event_digest'] = Variable<String>(eventDigest.value);
    }
    if (serverReceiptId.present) {
      map['server_receipt_id'] = Variable<String>(serverReceiptId.value);
    }
    if (acceptedAtIso.present) {
      map['accepted_at_iso'] = Variable<String>(acceptedAtIso.value);
    }
    if (receiptJson.present) {
      map['receipt_json'] = Variable<String>(receiptJson.value);
    }
    if (reconciliationCode.present) {
      map['reconciliation_code'] = Variable<String>(reconciliationCode.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('OfflineAcceptanceLinksCompanion(')
          ..write('organizationId: $organizationId, ')
          ..write('branchId: $branchId, ')
          ..write('id: $id, ')
          ..write('actorId: $actorId, ')
          ..write('deviceId: $deviceId, ')
          ..write('grantId: $grantId, ')
          ..write('sequence: $sequence, ')
          ..write('documentId: $documentId, ')
          ..write('eventDigest: $eventDigest, ')
          ..write('serverReceiptId: $serverReceiptId, ')
          ..write('acceptedAtIso: $acceptedAtIso, ')
          ..write('receiptJson: $receiptJson, ')
          ..write('reconciliationCode: $reconciliationCode, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $OfflineStockAcceptancesTable extends OfflineStockAcceptances
    with TableInfo<$OfflineStockAcceptancesTable, OfflineStockAcceptanceRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $OfflineStockAcceptancesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _organizationIdMeta = const VerificationMeta(
    'organizationId',
  );
  @override
  late final GeneratedColumn<String> organizationId = GeneratedColumn<String>(
    'organization_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _branchIdMeta = const VerificationMeta(
    'branchId',
  );
  @override
  late final GeneratedColumn<String> branchId = GeneratedColumn<String>(
    'branch_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _actorIdMeta = const VerificationMeta(
    'actorId',
  );
  @override
  late final GeneratedColumn<String> actorId = GeneratedColumn<String>(
    'actor_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _deviceIdMeta = const VerificationMeta(
    'deviceId',
  );
  @override
  late final GeneratedColumn<String> deviceId = GeneratedColumn<String>(
    'device_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _eventIdMeta = const VerificationMeta(
    'eventId',
  );
  @override
  late final GeneratedColumn<String> eventId = GeneratedColumn<String>(
    'event_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _productIdMeta = const VerificationMeta(
    'productId',
  );
  @override
  late final GeneratedColumn<String> productId = GeneratedColumn<String>(
    'product_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _revisionMeta = const VerificationMeta(
    'revision',
  );
  @override
  late final GeneratedColumn<int> revision = GeneratedColumn<int>(
    'revision',
    aliasedName,
    false,
    check: () => ComparableExpr(revision).isBiggerOrEqualValue(0),
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    organizationId,
    branchId,
    id,
    actorId,
    deviceId,
    eventId,
    productId,
    revision,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'offline_stock_acceptances';
  @override
  VerificationContext validateIntegrity(
    Insertable<OfflineStockAcceptanceRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('organization_id')) {
      context.handle(
        _organizationIdMeta,
        organizationId.isAcceptableOrUnknown(
          data['organization_id']!,
          _organizationIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_organizationIdMeta);
    }
    if (data.containsKey('branch_id')) {
      context.handle(
        _branchIdMeta,
        branchId.isAcceptableOrUnknown(data['branch_id']!, _branchIdMeta),
      );
    } else if (isInserting) {
      context.missing(_branchIdMeta);
    }
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('actor_id')) {
      context.handle(
        _actorIdMeta,
        actorId.isAcceptableOrUnknown(data['actor_id']!, _actorIdMeta),
      );
    } else if (isInserting) {
      context.missing(_actorIdMeta);
    }
    if (data.containsKey('device_id')) {
      context.handle(
        _deviceIdMeta,
        deviceId.isAcceptableOrUnknown(data['device_id']!, _deviceIdMeta),
      );
    } else if (isInserting) {
      context.missing(_deviceIdMeta);
    }
    if (data.containsKey('event_id')) {
      context.handle(
        _eventIdMeta,
        eventId.isAcceptableOrUnknown(data['event_id']!, _eventIdMeta),
      );
    } else if (isInserting) {
      context.missing(_eventIdMeta);
    }
    if (data.containsKey('product_id')) {
      context.handle(
        _productIdMeta,
        productId.isAcceptableOrUnknown(data['product_id']!, _productIdMeta),
      );
    } else if (isInserting) {
      context.missing(_productIdMeta);
    }
    if (data.containsKey('revision')) {
      context.handle(
        _revisionMeta,
        revision.isAcceptableOrUnknown(data['revision']!, _revisionMeta),
      );
    } else if (isInserting) {
      context.missing(_revisionMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {organizationId, branchId, id};
  @override
  List<Set<GeneratedColumn>> get uniqueKeys => [
    {organizationId, branchId, actorId, deviceId, eventId, productId},
  ];
  @override
  OfflineStockAcceptanceRow map(
    Map<String, dynamic> data, {
    String? tablePrefix,
  }) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return OfflineStockAcceptanceRow(
      organizationId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}organization_id'],
      )!,
      branchId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}branch_id'],
      )!,
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      actorId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}actor_id'],
      )!,
      deviceId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}device_id'],
      )!,
      eventId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}event_id'],
      )!,
      productId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}product_id'],
      )!,
      revision: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}revision'],
      )!,
    );
  }

  @override
  $OfflineStockAcceptancesTable createAlias(String alias) {
    return $OfflineStockAcceptancesTable(attachedDatabase, alias);
  }
}

class OfflineStockAcceptanceRow extends DataClass
    implements Insertable<OfflineStockAcceptanceRow> {
  final String organizationId;
  final String branchId;
  final String id;
  final String actorId;
  final String deviceId;
  final String eventId;
  final String productId;
  final int revision;
  const OfflineStockAcceptanceRow({
    required this.organizationId,
    required this.branchId,
    required this.id,
    required this.actorId,
    required this.deviceId,
    required this.eventId,
    required this.productId,
    required this.revision,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['organization_id'] = Variable<String>(organizationId);
    map['branch_id'] = Variable<String>(branchId);
    map['id'] = Variable<String>(id);
    map['actor_id'] = Variable<String>(actorId);
    map['device_id'] = Variable<String>(deviceId);
    map['event_id'] = Variable<String>(eventId);
    map['product_id'] = Variable<String>(productId);
    map['revision'] = Variable<int>(revision);
    return map;
  }

  OfflineStockAcceptancesCompanion toCompanion(bool nullToAbsent) {
    return OfflineStockAcceptancesCompanion(
      organizationId: Value(organizationId),
      branchId: Value(branchId),
      id: Value(id),
      actorId: Value(actorId),
      deviceId: Value(deviceId),
      eventId: Value(eventId),
      productId: Value(productId),
      revision: Value(revision),
    );
  }

  factory OfflineStockAcceptanceRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return OfflineStockAcceptanceRow(
      organizationId: serializer.fromJson<String>(json['organizationId']),
      branchId: serializer.fromJson<String>(json['branchId']),
      id: serializer.fromJson<String>(json['id']),
      actorId: serializer.fromJson<String>(json['actorId']),
      deviceId: serializer.fromJson<String>(json['deviceId']),
      eventId: serializer.fromJson<String>(json['eventId']),
      productId: serializer.fromJson<String>(json['productId']),
      revision: serializer.fromJson<int>(json['revision']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'organizationId': serializer.toJson<String>(organizationId),
      'branchId': serializer.toJson<String>(branchId),
      'id': serializer.toJson<String>(id),
      'actorId': serializer.toJson<String>(actorId),
      'deviceId': serializer.toJson<String>(deviceId),
      'eventId': serializer.toJson<String>(eventId),
      'productId': serializer.toJson<String>(productId),
      'revision': serializer.toJson<int>(revision),
    };
  }

  OfflineStockAcceptanceRow copyWith({
    String? organizationId,
    String? branchId,
    String? id,
    String? actorId,
    String? deviceId,
    String? eventId,
    String? productId,
    int? revision,
  }) => OfflineStockAcceptanceRow(
    organizationId: organizationId ?? this.organizationId,
    branchId: branchId ?? this.branchId,
    id: id ?? this.id,
    actorId: actorId ?? this.actorId,
    deviceId: deviceId ?? this.deviceId,
    eventId: eventId ?? this.eventId,
    productId: productId ?? this.productId,
    revision: revision ?? this.revision,
  );
  OfflineStockAcceptanceRow copyWithCompanion(
    OfflineStockAcceptancesCompanion data,
  ) {
    return OfflineStockAcceptanceRow(
      organizationId: data.organizationId.present
          ? data.organizationId.value
          : this.organizationId,
      branchId: data.branchId.present ? data.branchId.value : this.branchId,
      id: data.id.present ? data.id.value : this.id,
      actorId: data.actorId.present ? data.actorId.value : this.actorId,
      deviceId: data.deviceId.present ? data.deviceId.value : this.deviceId,
      eventId: data.eventId.present ? data.eventId.value : this.eventId,
      productId: data.productId.present ? data.productId.value : this.productId,
      revision: data.revision.present ? data.revision.value : this.revision,
    );
  }

  @override
  String toString() {
    return (StringBuffer('OfflineStockAcceptanceRow(')
          ..write('organizationId: $organizationId, ')
          ..write('branchId: $branchId, ')
          ..write('id: $id, ')
          ..write('actorId: $actorId, ')
          ..write('deviceId: $deviceId, ')
          ..write('eventId: $eventId, ')
          ..write('productId: $productId, ')
          ..write('revision: $revision')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    organizationId,
    branchId,
    id,
    actorId,
    deviceId,
    eventId,
    productId,
    revision,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is OfflineStockAcceptanceRow &&
          other.organizationId == this.organizationId &&
          other.branchId == this.branchId &&
          other.id == this.id &&
          other.actorId == this.actorId &&
          other.deviceId == this.deviceId &&
          other.eventId == this.eventId &&
          other.productId == this.productId &&
          other.revision == this.revision);
}

class OfflineStockAcceptancesCompanion
    extends UpdateCompanion<OfflineStockAcceptanceRow> {
  final Value<String> organizationId;
  final Value<String> branchId;
  final Value<String> id;
  final Value<String> actorId;
  final Value<String> deviceId;
  final Value<String> eventId;
  final Value<String> productId;
  final Value<int> revision;
  final Value<int> rowid;
  const OfflineStockAcceptancesCompanion({
    this.organizationId = const Value.absent(),
    this.branchId = const Value.absent(),
    this.id = const Value.absent(),
    this.actorId = const Value.absent(),
    this.deviceId = const Value.absent(),
    this.eventId = const Value.absent(),
    this.productId = const Value.absent(),
    this.revision = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  OfflineStockAcceptancesCompanion.insert({
    required String organizationId,
    required String branchId,
    required String id,
    required String actorId,
    required String deviceId,
    required String eventId,
    required String productId,
    required int revision,
    this.rowid = const Value.absent(),
  }) : organizationId = Value(organizationId),
       branchId = Value(branchId),
       id = Value(id),
       actorId = Value(actorId),
       deviceId = Value(deviceId),
       eventId = Value(eventId),
       productId = Value(productId),
       revision = Value(revision);
  static Insertable<OfflineStockAcceptanceRow> custom({
    Expression<String>? organizationId,
    Expression<String>? branchId,
    Expression<String>? id,
    Expression<String>? actorId,
    Expression<String>? deviceId,
    Expression<String>? eventId,
    Expression<String>? productId,
    Expression<int>? revision,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (organizationId != null) 'organization_id': organizationId,
      if (branchId != null) 'branch_id': branchId,
      if (id != null) 'id': id,
      if (actorId != null) 'actor_id': actorId,
      if (deviceId != null) 'device_id': deviceId,
      if (eventId != null) 'event_id': eventId,
      if (productId != null) 'product_id': productId,
      if (revision != null) 'revision': revision,
      if (rowid != null) 'rowid': rowid,
    });
  }

  OfflineStockAcceptancesCompanion copyWith({
    Value<String>? organizationId,
    Value<String>? branchId,
    Value<String>? id,
    Value<String>? actorId,
    Value<String>? deviceId,
    Value<String>? eventId,
    Value<String>? productId,
    Value<int>? revision,
    Value<int>? rowid,
  }) {
    return OfflineStockAcceptancesCompanion(
      organizationId: organizationId ?? this.organizationId,
      branchId: branchId ?? this.branchId,
      id: id ?? this.id,
      actorId: actorId ?? this.actorId,
      deviceId: deviceId ?? this.deviceId,
      eventId: eventId ?? this.eventId,
      productId: productId ?? this.productId,
      revision: revision ?? this.revision,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (organizationId.present) {
      map['organization_id'] = Variable<String>(organizationId.value);
    }
    if (branchId.present) {
      map['branch_id'] = Variable<String>(branchId.value);
    }
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (actorId.present) {
      map['actor_id'] = Variable<String>(actorId.value);
    }
    if (deviceId.present) {
      map['device_id'] = Variable<String>(deviceId.value);
    }
    if (eventId.present) {
      map['event_id'] = Variable<String>(eventId.value);
    }
    if (productId.present) {
      map['product_id'] = Variable<String>(productId.value);
    }
    if (revision.present) {
      map['revision'] = Variable<int>(revision.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('OfflineStockAcceptancesCompanion(')
          ..write('organizationId: $organizationId, ')
          ..write('branchId: $branchId, ')
          ..write('id: $id, ')
          ..write('actorId: $actorId, ')
          ..write('deviceId: $deviceId, ')
          ..write('eventId: $eventId, ')
          ..write('productId: $productId, ')
          ..write('revision: $revision, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $OfflinePreparationsTable extends OfflinePreparations
    with TableInfo<$OfflinePreparationsTable, OfflinePreparationRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $OfflinePreparationsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _organizationIdMeta = const VerificationMeta(
    'organizationId',
  );
  @override
  late final GeneratedColumn<String> organizationId = GeneratedColumn<String>(
    'organization_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _branchIdMeta = const VerificationMeta(
    'branchId',
  );
  @override
  late final GeneratedColumn<String> branchId = GeneratedColumn<String>(
    'branch_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _actorIdMeta = const VerificationMeta(
    'actorId',
  );
  @override
  late final GeneratedColumn<String> actorId = GeneratedColumn<String>(
    'actor_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _deviceIdMeta = const VerificationMeta(
    'deviceId',
  );
  @override
  late final GeneratedColumn<String> deviceId = GeneratedColumn<String>(
    'device_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _grantJsonMeta = const VerificationMeta(
    'grantJson',
  );
  @override
  late final GeneratedColumn<String> grantJson = GeneratedColumn<String>(
    'grant_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _snapshotJsonMeta = const VerificationMeta(
    'snapshotJson',
  );
  @override
  late final GeneratedColumn<String> snapshotJson = GeneratedColumn<String>(
    'snapshot_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _preparedAtMeta = const VerificationMeta(
    'preparedAt',
  );
  @override
  late final GeneratedColumn<DateTime> preparedAt = GeneratedColumn<DateTime>(
    'prepared_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    organizationId,
    branchId,
    id,
    actorId,
    deviceId,
    grantJson,
    snapshotJson,
    preparedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'offline_preparations';
  @override
  VerificationContext validateIntegrity(
    Insertable<OfflinePreparationRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('organization_id')) {
      context.handle(
        _organizationIdMeta,
        organizationId.isAcceptableOrUnknown(
          data['organization_id']!,
          _organizationIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_organizationIdMeta);
    }
    if (data.containsKey('branch_id')) {
      context.handle(
        _branchIdMeta,
        branchId.isAcceptableOrUnknown(data['branch_id']!, _branchIdMeta),
      );
    } else if (isInserting) {
      context.missing(_branchIdMeta);
    }
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('actor_id')) {
      context.handle(
        _actorIdMeta,
        actorId.isAcceptableOrUnknown(data['actor_id']!, _actorIdMeta),
      );
    } else if (isInserting) {
      context.missing(_actorIdMeta);
    }
    if (data.containsKey('device_id')) {
      context.handle(
        _deviceIdMeta,
        deviceId.isAcceptableOrUnknown(data['device_id']!, _deviceIdMeta),
      );
    } else if (isInserting) {
      context.missing(_deviceIdMeta);
    }
    if (data.containsKey('grant_json')) {
      context.handle(
        _grantJsonMeta,
        grantJson.isAcceptableOrUnknown(data['grant_json']!, _grantJsonMeta),
      );
    } else if (isInserting) {
      context.missing(_grantJsonMeta);
    }
    if (data.containsKey('snapshot_json')) {
      context.handle(
        _snapshotJsonMeta,
        snapshotJson.isAcceptableOrUnknown(
          data['snapshot_json']!,
          _snapshotJsonMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_snapshotJsonMeta);
    }
    if (data.containsKey('prepared_at')) {
      context.handle(
        _preparedAtMeta,
        preparedAt.isAcceptableOrUnknown(data['prepared_at']!, _preparedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_preparedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {organizationId, branchId, id};
  @override
  OfflinePreparationRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return OfflinePreparationRow(
      organizationId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}organization_id'],
      )!,
      branchId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}branch_id'],
      )!,
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      actorId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}actor_id'],
      )!,
      deviceId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}device_id'],
      )!,
      grantJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}grant_json'],
      )!,
      snapshotJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}snapshot_json'],
      )!,
      preparedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}prepared_at'],
      )!,
    );
  }

  @override
  $OfflinePreparationsTable createAlias(String alias) {
    return $OfflinePreparationsTable(attachedDatabase, alias);
  }
}

class OfflinePreparationRow extends DataClass
    implements Insertable<OfflinePreparationRow> {
  final String organizationId;
  final String branchId;
  final String id;
  final String actorId;
  final String deviceId;
  final String grantJson;
  final String snapshotJson;
  final DateTime preparedAt;
  const OfflinePreparationRow({
    required this.organizationId,
    required this.branchId,
    required this.id,
    required this.actorId,
    required this.deviceId,
    required this.grantJson,
    required this.snapshotJson,
    required this.preparedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['organization_id'] = Variable<String>(organizationId);
    map['branch_id'] = Variable<String>(branchId);
    map['id'] = Variable<String>(id);
    map['actor_id'] = Variable<String>(actorId);
    map['device_id'] = Variable<String>(deviceId);
    map['grant_json'] = Variable<String>(grantJson);
    map['snapshot_json'] = Variable<String>(snapshotJson);
    map['prepared_at'] = Variable<DateTime>(preparedAt);
    return map;
  }

  OfflinePreparationsCompanion toCompanion(bool nullToAbsent) {
    return OfflinePreparationsCompanion(
      organizationId: Value(organizationId),
      branchId: Value(branchId),
      id: Value(id),
      actorId: Value(actorId),
      deviceId: Value(deviceId),
      grantJson: Value(grantJson),
      snapshotJson: Value(snapshotJson),
      preparedAt: Value(preparedAt),
    );
  }

  factory OfflinePreparationRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return OfflinePreparationRow(
      organizationId: serializer.fromJson<String>(json['organizationId']),
      branchId: serializer.fromJson<String>(json['branchId']),
      id: serializer.fromJson<String>(json['id']),
      actorId: serializer.fromJson<String>(json['actorId']),
      deviceId: serializer.fromJson<String>(json['deviceId']),
      grantJson: serializer.fromJson<String>(json['grantJson']),
      snapshotJson: serializer.fromJson<String>(json['snapshotJson']),
      preparedAt: serializer.fromJson<DateTime>(json['preparedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'organizationId': serializer.toJson<String>(organizationId),
      'branchId': serializer.toJson<String>(branchId),
      'id': serializer.toJson<String>(id),
      'actorId': serializer.toJson<String>(actorId),
      'deviceId': serializer.toJson<String>(deviceId),
      'grantJson': serializer.toJson<String>(grantJson),
      'snapshotJson': serializer.toJson<String>(snapshotJson),
      'preparedAt': serializer.toJson<DateTime>(preparedAt),
    };
  }

  OfflinePreparationRow copyWith({
    String? organizationId,
    String? branchId,
    String? id,
    String? actorId,
    String? deviceId,
    String? grantJson,
    String? snapshotJson,
    DateTime? preparedAt,
  }) => OfflinePreparationRow(
    organizationId: organizationId ?? this.organizationId,
    branchId: branchId ?? this.branchId,
    id: id ?? this.id,
    actorId: actorId ?? this.actorId,
    deviceId: deviceId ?? this.deviceId,
    grantJson: grantJson ?? this.grantJson,
    snapshotJson: snapshotJson ?? this.snapshotJson,
    preparedAt: preparedAt ?? this.preparedAt,
  );
  OfflinePreparationRow copyWithCompanion(OfflinePreparationsCompanion data) {
    return OfflinePreparationRow(
      organizationId: data.organizationId.present
          ? data.organizationId.value
          : this.organizationId,
      branchId: data.branchId.present ? data.branchId.value : this.branchId,
      id: data.id.present ? data.id.value : this.id,
      actorId: data.actorId.present ? data.actorId.value : this.actorId,
      deviceId: data.deviceId.present ? data.deviceId.value : this.deviceId,
      grantJson: data.grantJson.present ? data.grantJson.value : this.grantJson,
      snapshotJson: data.snapshotJson.present
          ? data.snapshotJson.value
          : this.snapshotJson,
      preparedAt: data.preparedAt.present
          ? data.preparedAt.value
          : this.preparedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('OfflinePreparationRow(')
          ..write('organizationId: $organizationId, ')
          ..write('branchId: $branchId, ')
          ..write('id: $id, ')
          ..write('actorId: $actorId, ')
          ..write('deviceId: $deviceId, ')
          ..write('grantJson: $grantJson, ')
          ..write('snapshotJson: $snapshotJson, ')
          ..write('preparedAt: $preparedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    organizationId,
    branchId,
    id,
    actorId,
    deviceId,
    grantJson,
    snapshotJson,
    preparedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is OfflinePreparationRow &&
          other.organizationId == this.organizationId &&
          other.branchId == this.branchId &&
          other.id == this.id &&
          other.actorId == this.actorId &&
          other.deviceId == this.deviceId &&
          other.grantJson == this.grantJson &&
          other.snapshotJson == this.snapshotJson &&
          other.preparedAt == this.preparedAt);
}

class OfflinePreparationsCompanion
    extends UpdateCompanion<OfflinePreparationRow> {
  final Value<String> organizationId;
  final Value<String> branchId;
  final Value<String> id;
  final Value<String> actorId;
  final Value<String> deviceId;
  final Value<String> grantJson;
  final Value<String> snapshotJson;
  final Value<DateTime> preparedAt;
  final Value<int> rowid;
  const OfflinePreparationsCompanion({
    this.organizationId = const Value.absent(),
    this.branchId = const Value.absent(),
    this.id = const Value.absent(),
    this.actorId = const Value.absent(),
    this.deviceId = const Value.absent(),
    this.grantJson = const Value.absent(),
    this.snapshotJson = const Value.absent(),
    this.preparedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  OfflinePreparationsCompanion.insert({
    required String organizationId,
    required String branchId,
    required String id,
    required String actorId,
    required String deviceId,
    required String grantJson,
    required String snapshotJson,
    required DateTime preparedAt,
    this.rowid = const Value.absent(),
  }) : organizationId = Value(organizationId),
       branchId = Value(branchId),
       id = Value(id),
       actorId = Value(actorId),
       deviceId = Value(deviceId),
       grantJson = Value(grantJson),
       snapshotJson = Value(snapshotJson),
       preparedAt = Value(preparedAt);
  static Insertable<OfflinePreparationRow> custom({
    Expression<String>? organizationId,
    Expression<String>? branchId,
    Expression<String>? id,
    Expression<String>? actorId,
    Expression<String>? deviceId,
    Expression<String>? grantJson,
    Expression<String>? snapshotJson,
    Expression<DateTime>? preparedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (organizationId != null) 'organization_id': organizationId,
      if (branchId != null) 'branch_id': branchId,
      if (id != null) 'id': id,
      if (actorId != null) 'actor_id': actorId,
      if (deviceId != null) 'device_id': deviceId,
      if (grantJson != null) 'grant_json': grantJson,
      if (snapshotJson != null) 'snapshot_json': snapshotJson,
      if (preparedAt != null) 'prepared_at': preparedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  OfflinePreparationsCompanion copyWith({
    Value<String>? organizationId,
    Value<String>? branchId,
    Value<String>? id,
    Value<String>? actorId,
    Value<String>? deviceId,
    Value<String>? grantJson,
    Value<String>? snapshotJson,
    Value<DateTime>? preparedAt,
    Value<int>? rowid,
  }) {
    return OfflinePreparationsCompanion(
      organizationId: organizationId ?? this.organizationId,
      branchId: branchId ?? this.branchId,
      id: id ?? this.id,
      actorId: actorId ?? this.actorId,
      deviceId: deviceId ?? this.deviceId,
      grantJson: grantJson ?? this.grantJson,
      snapshotJson: snapshotJson ?? this.snapshotJson,
      preparedAt: preparedAt ?? this.preparedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (organizationId.present) {
      map['organization_id'] = Variable<String>(organizationId.value);
    }
    if (branchId.present) {
      map['branch_id'] = Variable<String>(branchId.value);
    }
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (actorId.present) {
      map['actor_id'] = Variable<String>(actorId.value);
    }
    if (deviceId.present) {
      map['device_id'] = Variable<String>(deviceId.value);
    }
    if (grantJson.present) {
      map['grant_json'] = Variable<String>(grantJson.value);
    }
    if (snapshotJson.present) {
      map['snapshot_json'] = Variable<String>(snapshotJson.value);
    }
    if (preparedAt.present) {
      map['prepared_at'] = Variable<DateTime>(preparedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('OfflinePreparationsCompanion(')
          ..write('organizationId: $organizationId, ')
          ..write('branchId: $branchId, ')
          ..write('id: $id, ')
          ..write('actorId: $actorId, ')
          ..write('deviceId: $deviceId, ')
          ..write('grantJson: $grantJson, ')
          ..write('snapshotJson: $snapshotJson, ')
          ..write('preparedAt: $preparedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $OfflineGrantReleasesTable extends OfflineGrantReleases
    with TableInfo<$OfflineGrantReleasesTable, OfflineGrantReleaseRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $OfflineGrantReleasesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _organizationIdMeta = const VerificationMeta(
    'organizationId',
  );
  @override
  late final GeneratedColumn<String> organizationId = GeneratedColumn<String>(
    'organization_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _branchIdMeta = const VerificationMeta(
    'branchId',
  );
  @override
  late final GeneratedColumn<String> branchId = GeneratedColumn<String>(
    'branch_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _actorIdMeta = const VerificationMeta(
    'actorId',
  );
  @override
  late final GeneratedColumn<String> actorId = GeneratedColumn<String>(
    'actor_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _deviceIdMeta = const VerificationMeta(
    'deviceId',
  );
  @override
  late final GeneratedColumn<String> deviceId = GeneratedColumn<String>(
    'device_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _finalSequenceMeta = const VerificationMeta(
    'finalSequence',
  );
  @override
  late final GeneratedColumn<int> finalSequence = GeneratedColumn<int>(
    'final_sequence',
    aliasedName,
    false,
    check: () => ComparableExpr(finalSequence).isBetweenValues(0, 1000),
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _releasedAtMeta = const VerificationMeta(
    'releasedAt',
  );
  @override
  late final GeneratedColumn<DateTime> releasedAt = GeneratedColumn<DateTime>(
    'released_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    organizationId,
    branchId,
    id,
    actorId,
    deviceId,
    finalSequence,
    releasedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'offline_grant_releases';
  @override
  VerificationContext validateIntegrity(
    Insertable<OfflineGrantReleaseRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('organization_id')) {
      context.handle(
        _organizationIdMeta,
        organizationId.isAcceptableOrUnknown(
          data['organization_id']!,
          _organizationIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_organizationIdMeta);
    }
    if (data.containsKey('branch_id')) {
      context.handle(
        _branchIdMeta,
        branchId.isAcceptableOrUnknown(data['branch_id']!, _branchIdMeta),
      );
    } else if (isInserting) {
      context.missing(_branchIdMeta);
    }
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('actor_id')) {
      context.handle(
        _actorIdMeta,
        actorId.isAcceptableOrUnknown(data['actor_id']!, _actorIdMeta),
      );
    } else if (isInserting) {
      context.missing(_actorIdMeta);
    }
    if (data.containsKey('device_id')) {
      context.handle(
        _deviceIdMeta,
        deviceId.isAcceptableOrUnknown(data['device_id']!, _deviceIdMeta),
      );
    } else if (isInserting) {
      context.missing(_deviceIdMeta);
    }
    if (data.containsKey('final_sequence')) {
      context.handle(
        _finalSequenceMeta,
        finalSequence.isAcceptableOrUnknown(
          data['final_sequence']!,
          _finalSequenceMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_finalSequenceMeta);
    }
    if (data.containsKey('released_at')) {
      context.handle(
        _releasedAtMeta,
        releasedAt.isAcceptableOrUnknown(data['released_at']!, _releasedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_releasedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {organizationId, branchId, id};
  @override
  OfflineGrantReleaseRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return OfflineGrantReleaseRow(
      organizationId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}organization_id'],
      )!,
      branchId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}branch_id'],
      )!,
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      actorId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}actor_id'],
      )!,
      deviceId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}device_id'],
      )!,
      finalSequence: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}final_sequence'],
      )!,
      releasedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}released_at'],
      )!,
    );
  }

  @override
  $OfflineGrantReleasesTable createAlias(String alias) {
    return $OfflineGrantReleasesTable(attachedDatabase, alias);
  }
}

class OfflineGrantReleaseRow extends DataClass
    implements Insertable<OfflineGrantReleaseRow> {
  final String organizationId;
  final String branchId;
  final String id;
  final String actorId;
  final String deviceId;
  final int finalSequence;
  final DateTime releasedAt;
  const OfflineGrantReleaseRow({
    required this.organizationId,
    required this.branchId,
    required this.id,
    required this.actorId,
    required this.deviceId,
    required this.finalSequence,
    required this.releasedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['organization_id'] = Variable<String>(organizationId);
    map['branch_id'] = Variable<String>(branchId);
    map['id'] = Variable<String>(id);
    map['actor_id'] = Variable<String>(actorId);
    map['device_id'] = Variable<String>(deviceId);
    map['final_sequence'] = Variable<int>(finalSequence);
    map['released_at'] = Variable<DateTime>(releasedAt);
    return map;
  }

  OfflineGrantReleasesCompanion toCompanion(bool nullToAbsent) {
    return OfflineGrantReleasesCompanion(
      organizationId: Value(organizationId),
      branchId: Value(branchId),
      id: Value(id),
      actorId: Value(actorId),
      deviceId: Value(deviceId),
      finalSequence: Value(finalSequence),
      releasedAt: Value(releasedAt),
    );
  }

  factory OfflineGrantReleaseRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return OfflineGrantReleaseRow(
      organizationId: serializer.fromJson<String>(json['organizationId']),
      branchId: serializer.fromJson<String>(json['branchId']),
      id: serializer.fromJson<String>(json['id']),
      actorId: serializer.fromJson<String>(json['actorId']),
      deviceId: serializer.fromJson<String>(json['deviceId']),
      finalSequence: serializer.fromJson<int>(json['finalSequence']),
      releasedAt: serializer.fromJson<DateTime>(json['releasedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'organizationId': serializer.toJson<String>(organizationId),
      'branchId': serializer.toJson<String>(branchId),
      'id': serializer.toJson<String>(id),
      'actorId': serializer.toJson<String>(actorId),
      'deviceId': serializer.toJson<String>(deviceId),
      'finalSequence': serializer.toJson<int>(finalSequence),
      'releasedAt': serializer.toJson<DateTime>(releasedAt),
    };
  }

  OfflineGrantReleaseRow copyWith({
    String? organizationId,
    String? branchId,
    String? id,
    String? actorId,
    String? deviceId,
    int? finalSequence,
    DateTime? releasedAt,
  }) => OfflineGrantReleaseRow(
    organizationId: organizationId ?? this.organizationId,
    branchId: branchId ?? this.branchId,
    id: id ?? this.id,
    actorId: actorId ?? this.actorId,
    deviceId: deviceId ?? this.deviceId,
    finalSequence: finalSequence ?? this.finalSequence,
    releasedAt: releasedAt ?? this.releasedAt,
  );
  OfflineGrantReleaseRow copyWithCompanion(OfflineGrantReleasesCompanion data) {
    return OfflineGrantReleaseRow(
      organizationId: data.organizationId.present
          ? data.organizationId.value
          : this.organizationId,
      branchId: data.branchId.present ? data.branchId.value : this.branchId,
      id: data.id.present ? data.id.value : this.id,
      actorId: data.actorId.present ? data.actorId.value : this.actorId,
      deviceId: data.deviceId.present ? data.deviceId.value : this.deviceId,
      finalSequence: data.finalSequence.present
          ? data.finalSequence.value
          : this.finalSequence,
      releasedAt: data.releasedAt.present
          ? data.releasedAt.value
          : this.releasedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('OfflineGrantReleaseRow(')
          ..write('organizationId: $organizationId, ')
          ..write('branchId: $branchId, ')
          ..write('id: $id, ')
          ..write('actorId: $actorId, ')
          ..write('deviceId: $deviceId, ')
          ..write('finalSequence: $finalSequence, ')
          ..write('releasedAt: $releasedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    organizationId,
    branchId,
    id,
    actorId,
    deviceId,
    finalSequence,
    releasedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is OfflineGrantReleaseRow &&
          other.organizationId == this.organizationId &&
          other.branchId == this.branchId &&
          other.id == this.id &&
          other.actorId == this.actorId &&
          other.deviceId == this.deviceId &&
          other.finalSequence == this.finalSequence &&
          other.releasedAt == this.releasedAt);
}

class OfflineGrantReleasesCompanion
    extends UpdateCompanion<OfflineGrantReleaseRow> {
  final Value<String> organizationId;
  final Value<String> branchId;
  final Value<String> id;
  final Value<String> actorId;
  final Value<String> deviceId;
  final Value<int> finalSequence;
  final Value<DateTime> releasedAt;
  final Value<int> rowid;
  const OfflineGrantReleasesCompanion({
    this.organizationId = const Value.absent(),
    this.branchId = const Value.absent(),
    this.id = const Value.absent(),
    this.actorId = const Value.absent(),
    this.deviceId = const Value.absent(),
    this.finalSequence = const Value.absent(),
    this.releasedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  OfflineGrantReleasesCompanion.insert({
    required String organizationId,
    required String branchId,
    required String id,
    required String actorId,
    required String deviceId,
    required int finalSequence,
    required DateTime releasedAt,
    this.rowid = const Value.absent(),
  }) : organizationId = Value(organizationId),
       branchId = Value(branchId),
       id = Value(id),
       actorId = Value(actorId),
       deviceId = Value(deviceId),
       finalSequence = Value(finalSequence),
       releasedAt = Value(releasedAt);
  static Insertable<OfflineGrantReleaseRow> custom({
    Expression<String>? organizationId,
    Expression<String>? branchId,
    Expression<String>? id,
    Expression<String>? actorId,
    Expression<String>? deviceId,
    Expression<int>? finalSequence,
    Expression<DateTime>? releasedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (organizationId != null) 'organization_id': organizationId,
      if (branchId != null) 'branch_id': branchId,
      if (id != null) 'id': id,
      if (actorId != null) 'actor_id': actorId,
      if (deviceId != null) 'device_id': deviceId,
      if (finalSequence != null) 'final_sequence': finalSequence,
      if (releasedAt != null) 'released_at': releasedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  OfflineGrantReleasesCompanion copyWith({
    Value<String>? organizationId,
    Value<String>? branchId,
    Value<String>? id,
    Value<String>? actorId,
    Value<String>? deviceId,
    Value<int>? finalSequence,
    Value<DateTime>? releasedAt,
    Value<int>? rowid,
  }) {
    return OfflineGrantReleasesCompanion(
      organizationId: organizationId ?? this.organizationId,
      branchId: branchId ?? this.branchId,
      id: id ?? this.id,
      actorId: actorId ?? this.actorId,
      deviceId: deviceId ?? this.deviceId,
      finalSequence: finalSequence ?? this.finalSequence,
      releasedAt: releasedAt ?? this.releasedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (organizationId.present) {
      map['organization_id'] = Variable<String>(organizationId.value);
    }
    if (branchId.present) {
      map['branch_id'] = Variable<String>(branchId.value);
    }
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (actorId.present) {
      map['actor_id'] = Variable<String>(actorId.value);
    }
    if (deviceId.present) {
      map['device_id'] = Variable<String>(deviceId.value);
    }
    if (finalSequence.present) {
      map['final_sequence'] = Variable<int>(finalSequence.value);
    }
    if (releasedAt.present) {
      map['released_at'] = Variable<DateTime>(releasedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('OfflineGrantReleasesCompanion(')
          ..write('organizationId: $organizationId, ')
          ..write('branchId: $branchId, ')
          ..write('id: $id, ')
          ..write('actorId: $actorId, ')
          ..write('deviceId: $deviceId, ')
          ..write('finalSequence: $finalSequence, ')
          ..write('releasedAt: $releasedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$AppDatabase extends GeneratedDatabase {
  _$AppDatabase(QueryExecutor e) : super(e);
  $AppDatabaseManager get managers => $AppDatabaseManager(this);
  late final $LocalCategoriesTable localCategories = $LocalCategoriesTable(
    this,
  );
  late final $LocalProductsTable localProducts = $LocalProductsTable(this);
  late final $LocalProductPricesTable localProductPrices =
      $LocalProductPricesTable(this);
  late final $LocalInventorySnapshotsTable localInventorySnapshots =
      $LocalInventorySnapshotsTable(this);
  late final $LocalCustomersTable localCustomers = $LocalCustomersTable(this);
  late final $LocalShiftsTable localShifts = $LocalShiftsTable(this);
  late final $LocalSalesTable localSales = $LocalSalesTable(this);
  late final $LocalSaleItemsTable localSaleItems = $LocalSaleItemsTable(this);
  late final $LocalPaymentsTable localPayments = $LocalPaymentsTable(this);
  late final $SyncOutboxTable syncOutbox = $SyncOutboxTable(this);
  late final $SyncCursorsTable syncCursors = $SyncCursorsTable(this);
  late final $OfflineEventAuthorizationsTable offlineEventAuthorizations =
      $OfflineEventAuthorizationsTable(this);
  late final $OfflineCacheRecordsTable offlineCacheRecords =
      $OfflineCacheRecordsTable(this);
  late final $OfflineCacheStatesTable offlineCacheStates =
      $OfflineCacheStatesTable(this);
  late final $OfflineStockEffectsTable offlineStockEffects =
      $OfflineStockEffectsTable(this);
  late final $OfflineAcceptanceLinksTable offlineAcceptanceLinks =
      $OfflineAcceptanceLinksTable(this);
  late final $OfflineStockAcceptancesTable offlineStockAcceptances =
      $OfflineStockAcceptancesTable(this);
  late final $OfflinePreparationsTable offlinePreparations =
      $OfflinePreparationsTable(this);
  late final $OfflineGrantReleasesTable offlineGrantReleases =
      $OfflineGrantReleasesTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    localCategories,
    localProducts,
    localProductPrices,
    localInventorySnapshots,
    localCustomers,
    localShifts,
    localSales,
    localSaleItems,
    localPayments,
    syncOutbox,
    syncCursors,
    offlineEventAuthorizations,
    offlineCacheRecords,
    offlineCacheStates,
    offlineStockEffects,
    offlineAcceptanceLinks,
    offlineStockAcceptances,
    offlinePreparations,
    offlineGrantReleases,
  ];
}

typedef $$LocalCategoriesTableCreateCompanionBuilder =
    LocalCategoriesCompanion Function({
      required String organizationId,
      required String branchId,
      required String id,
      required String name,
      Value<bool> active,
      required int revision,
      Value<int> rowid,
    });
typedef $$LocalCategoriesTableUpdateCompanionBuilder =
    LocalCategoriesCompanion Function({
      Value<String> organizationId,
      Value<String> branchId,
      Value<String> id,
      Value<String> name,
      Value<bool> active,
      Value<int> revision,
      Value<int> rowid,
    });

class $$LocalCategoriesTableFilterComposer
    extends Composer<_$AppDatabase, $LocalCategoriesTable> {
  $$LocalCategoriesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get organizationId => $composableBuilder(
    column: $table.organizationId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get branchId => $composableBuilder(
    column: $table.branchId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get active => $composableBuilder(
    column: $table.active,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get revision => $composableBuilder(
    column: $table.revision,
    builder: (column) => ColumnFilters(column),
  );
}

class $$LocalCategoriesTableOrderingComposer
    extends Composer<_$AppDatabase, $LocalCategoriesTable> {
  $$LocalCategoriesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get organizationId => $composableBuilder(
    column: $table.organizationId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get branchId => $composableBuilder(
    column: $table.branchId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get active => $composableBuilder(
    column: $table.active,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get revision => $composableBuilder(
    column: $table.revision,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$LocalCategoriesTableAnnotationComposer
    extends Composer<_$AppDatabase, $LocalCategoriesTable> {
  $$LocalCategoriesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get organizationId => $composableBuilder(
    column: $table.organizationId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get branchId =>
      $composableBuilder(column: $table.branchId, builder: (column) => column);

  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<bool> get active =>
      $composableBuilder(column: $table.active, builder: (column) => column);

  GeneratedColumn<int> get revision =>
      $composableBuilder(column: $table.revision, builder: (column) => column);
}

class $$LocalCategoriesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $LocalCategoriesTable,
          CategoryRow,
          $$LocalCategoriesTableFilterComposer,
          $$LocalCategoriesTableOrderingComposer,
          $$LocalCategoriesTableAnnotationComposer,
          $$LocalCategoriesTableCreateCompanionBuilder,
          $$LocalCategoriesTableUpdateCompanionBuilder,
          (
            CategoryRow,
            BaseReferences<_$AppDatabase, $LocalCategoriesTable, CategoryRow>,
          ),
          CategoryRow,
          PrefetchHooks Function()
        > {
  $$LocalCategoriesTableTableManager(
    _$AppDatabase db,
    $LocalCategoriesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$LocalCategoriesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$LocalCategoriesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$LocalCategoriesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> organizationId = const Value.absent(),
                Value<String> branchId = const Value.absent(),
                Value<String> id = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<bool> active = const Value.absent(),
                Value<int> revision = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => LocalCategoriesCompanion(
                organizationId: organizationId,
                branchId: branchId,
                id: id,
                name: name,
                active: active,
                revision: revision,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String organizationId,
                required String branchId,
                required String id,
                required String name,
                Value<bool> active = const Value.absent(),
                required int revision,
                Value<int> rowid = const Value.absent(),
              }) => LocalCategoriesCompanion.insert(
                organizationId: organizationId,
                branchId: branchId,
                id: id,
                name: name,
                active: active,
                revision: revision,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$LocalCategoriesTable, CategoryRow>(table),
                  BaseReferences<
                    _$AppDatabase,
                    $LocalCategoriesTable,
                    CategoryRow
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$LocalCategoriesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $LocalCategoriesTable,
      CategoryRow,
      $$LocalCategoriesTableFilterComposer,
      $$LocalCategoriesTableOrderingComposer,
      $$LocalCategoriesTableAnnotationComposer,
      $$LocalCategoriesTableCreateCompanionBuilder,
      $$LocalCategoriesTableUpdateCompanionBuilder,
      (
        CategoryRow,
        BaseReferences<_$AppDatabase, $LocalCategoriesTable, CategoryRow>,
      ),
      CategoryRow,
      PrefetchHooks Function()
    >;
typedef $$LocalProductsTableCreateCompanionBuilder =
    LocalProductsCompanion Function({
      required String organizationId,
      required String branchId,
      required String id,
      Value<String?> categoryId,
      required String sku,
      Value<String?> barcode,
      required String name,
      required String currency,
      required int costMinor,
      required int priceMinor,
      Value<int> reorderLevel,
      Value<String> unit,
      Value<bool> active,
      required int revision,
      Value<int> rowid,
    });
typedef $$LocalProductsTableUpdateCompanionBuilder =
    LocalProductsCompanion Function({
      Value<String> organizationId,
      Value<String> branchId,
      Value<String> id,
      Value<String?> categoryId,
      Value<String> sku,
      Value<String?> barcode,
      Value<String> name,
      Value<String> currency,
      Value<int> costMinor,
      Value<int> priceMinor,
      Value<int> reorderLevel,
      Value<String> unit,
      Value<bool> active,
      Value<int> revision,
      Value<int> rowid,
    });

class $$LocalProductsTableFilterComposer
    extends Composer<_$AppDatabase, $LocalProductsTable> {
  $$LocalProductsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get organizationId => $composableBuilder(
    column: $table.organizationId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get branchId => $composableBuilder(
    column: $table.branchId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get categoryId => $composableBuilder(
    column: $table.categoryId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get sku => $composableBuilder(
    column: $table.sku,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get barcode => $composableBuilder(
    column: $table.barcode,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get currency => $composableBuilder(
    column: $table.currency,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get costMinor => $composableBuilder(
    column: $table.costMinor,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get priceMinor => $composableBuilder(
    column: $table.priceMinor,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get reorderLevel => $composableBuilder(
    column: $table.reorderLevel,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get unit => $composableBuilder(
    column: $table.unit,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get active => $composableBuilder(
    column: $table.active,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get revision => $composableBuilder(
    column: $table.revision,
    builder: (column) => ColumnFilters(column),
  );
}

class $$LocalProductsTableOrderingComposer
    extends Composer<_$AppDatabase, $LocalProductsTable> {
  $$LocalProductsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get organizationId => $composableBuilder(
    column: $table.organizationId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get branchId => $composableBuilder(
    column: $table.branchId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get categoryId => $composableBuilder(
    column: $table.categoryId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get sku => $composableBuilder(
    column: $table.sku,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get barcode => $composableBuilder(
    column: $table.barcode,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get currency => $composableBuilder(
    column: $table.currency,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get costMinor => $composableBuilder(
    column: $table.costMinor,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get priceMinor => $composableBuilder(
    column: $table.priceMinor,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get reorderLevel => $composableBuilder(
    column: $table.reorderLevel,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get unit => $composableBuilder(
    column: $table.unit,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get active => $composableBuilder(
    column: $table.active,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get revision => $composableBuilder(
    column: $table.revision,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$LocalProductsTableAnnotationComposer
    extends Composer<_$AppDatabase, $LocalProductsTable> {
  $$LocalProductsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get organizationId => $composableBuilder(
    column: $table.organizationId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get branchId =>
      $composableBuilder(column: $table.branchId, builder: (column) => column);

  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get categoryId => $composableBuilder(
    column: $table.categoryId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get sku =>
      $composableBuilder(column: $table.sku, builder: (column) => column);

  GeneratedColumn<String> get barcode =>
      $composableBuilder(column: $table.barcode, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get currency =>
      $composableBuilder(column: $table.currency, builder: (column) => column);

  GeneratedColumn<int> get costMinor =>
      $composableBuilder(column: $table.costMinor, builder: (column) => column);

  GeneratedColumn<int> get priceMinor => $composableBuilder(
    column: $table.priceMinor,
    builder: (column) => column,
  );

  GeneratedColumn<int> get reorderLevel => $composableBuilder(
    column: $table.reorderLevel,
    builder: (column) => column,
  );

  GeneratedColumn<String> get unit =>
      $composableBuilder(column: $table.unit, builder: (column) => column);

  GeneratedColumn<bool> get active =>
      $composableBuilder(column: $table.active, builder: (column) => column);

  GeneratedColumn<int> get revision =>
      $composableBuilder(column: $table.revision, builder: (column) => column);
}

class $$LocalProductsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $LocalProductsTable,
          ProductRow,
          $$LocalProductsTableFilterComposer,
          $$LocalProductsTableOrderingComposer,
          $$LocalProductsTableAnnotationComposer,
          $$LocalProductsTableCreateCompanionBuilder,
          $$LocalProductsTableUpdateCompanionBuilder,
          (
            ProductRow,
            BaseReferences<_$AppDatabase, $LocalProductsTable, ProductRow>,
          ),
          ProductRow,
          PrefetchHooks Function()
        > {
  $$LocalProductsTableTableManager(_$AppDatabase db, $LocalProductsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$LocalProductsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$LocalProductsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$LocalProductsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> organizationId = const Value.absent(),
                Value<String> branchId = const Value.absent(),
                Value<String> id = const Value.absent(),
                Value<String?> categoryId = const Value.absent(),
                Value<String> sku = const Value.absent(),
                Value<String?> barcode = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String> currency = const Value.absent(),
                Value<int> costMinor = const Value.absent(),
                Value<int> priceMinor = const Value.absent(),
                Value<int> reorderLevel = const Value.absent(),
                Value<String> unit = const Value.absent(),
                Value<bool> active = const Value.absent(),
                Value<int> revision = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => LocalProductsCompanion(
                organizationId: organizationId,
                branchId: branchId,
                id: id,
                categoryId: categoryId,
                sku: sku,
                barcode: barcode,
                name: name,
                currency: currency,
                costMinor: costMinor,
                priceMinor: priceMinor,
                reorderLevel: reorderLevel,
                unit: unit,
                active: active,
                revision: revision,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String organizationId,
                required String branchId,
                required String id,
                Value<String?> categoryId = const Value.absent(),
                required String sku,
                Value<String?> barcode = const Value.absent(),
                required String name,
                required String currency,
                required int costMinor,
                required int priceMinor,
                Value<int> reorderLevel = const Value.absent(),
                Value<String> unit = const Value.absent(),
                Value<bool> active = const Value.absent(),
                required int revision,
                Value<int> rowid = const Value.absent(),
              }) => LocalProductsCompanion.insert(
                organizationId: organizationId,
                branchId: branchId,
                id: id,
                categoryId: categoryId,
                sku: sku,
                barcode: barcode,
                name: name,
                currency: currency,
                costMinor: costMinor,
                priceMinor: priceMinor,
                reorderLevel: reorderLevel,
                unit: unit,
                active: active,
                revision: revision,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$LocalProductsTable, ProductRow>(table),
                  BaseReferences<
                    _$AppDatabase,
                    $LocalProductsTable,
                    ProductRow
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$LocalProductsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $LocalProductsTable,
      ProductRow,
      $$LocalProductsTableFilterComposer,
      $$LocalProductsTableOrderingComposer,
      $$LocalProductsTableAnnotationComposer,
      $$LocalProductsTableCreateCompanionBuilder,
      $$LocalProductsTableUpdateCompanionBuilder,
      (
        ProductRow,
        BaseReferences<_$AppDatabase, $LocalProductsTable, ProductRow>,
      ),
      ProductRow,
      PrefetchHooks Function()
    >;
typedef $$LocalProductPricesTableCreateCompanionBuilder =
    LocalProductPricesCompanion Function({
      required String organizationId,
      required String branchId,
      required String id,
      required String productId,
      required String currency,
      required int priceMinor,
      required DateTime effectiveAt,
      required int revision,
      Value<int> rowid,
    });
typedef $$LocalProductPricesTableUpdateCompanionBuilder =
    LocalProductPricesCompanion Function({
      Value<String> organizationId,
      Value<String> branchId,
      Value<String> id,
      Value<String> productId,
      Value<String> currency,
      Value<int> priceMinor,
      Value<DateTime> effectiveAt,
      Value<int> revision,
      Value<int> rowid,
    });

class $$LocalProductPricesTableFilterComposer
    extends Composer<_$AppDatabase, $LocalProductPricesTable> {
  $$LocalProductPricesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get organizationId => $composableBuilder(
    column: $table.organizationId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get branchId => $composableBuilder(
    column: $table.branchId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get productId => $composableBuilder(
    column: $table.productId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get currency => $composableBuilder(
    column: $table.currency,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get priceMinor => $composableBuilder(
    column: $table.priceMinor,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get effectiveAt => $composableBuilder(
    column: $table.effectiveAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get revision => $composableBuilder(
    column: $table.revision,
    builder: (column) => ColumnFilters(column),
  );
}

class $$LocalProductPricesTableOrderingComposer
    extends Composer<_$AppDatabase, $LocalProductPricesTable> {
  $$LocalProductPricesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get organizationId => $composableBuilder(
    column: $table.organizationId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get branchId => $composableBuilder(
    column: $table.branchId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get productId => $composableBuilder(
    column: $table.productId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get currency => $composableBuilder(
    column: $table.currency,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get priceMinor => $composableBuilder(
    column: $table.priceMinor,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get effectiveAt => $composableBuilder(
    column: $table.effectiveAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get revision => $composableBuilder(
    column: $table.revision,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$LocalProductPricesTableAnnotationComposer
    extends Composer<_$AppDatabase, $LocalProductPricesTable> {
  $$LocalProductPricesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get organizationId => $composableBuilder(
    column: $table.organizationId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get branchId =>
      $composableBuilder(column: $table.branchId, builder: (column) => column);

  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get productId =>
      $composableBuilder(column: $table.productId, builder: (column) => column);

  GeneratedColumn<String> get currency =>
      $composableBuilder(column: $table.currency, builder: (column) => column);

  GeneratedColumn<int> get priceMinor => $composableBuilder(
    column: $table.priceMinor,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get effectiveAt => $composableBuilder(
    column: $table.effectiveAt,
    builder: (column) => column,
  );

  GeneratedColumn<int> get revision =>
      $composableBuilder(column: $table.revision, builder: (column) => column);
}

class $$LocalProductPricesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $LocalProductPricesTable,
          PriceRow,
          $$LocalProductPricesTableFilterComposer,
          $$LocalProductPricesTableOrderingComposer,
          $$LocalProductPricesTableAnnotationComposer,
          $$LocalProductPricesTableCreateCompanionBuilder,
          $$LocalProductPricesTableUpdateCompanionBuilder,
          (
            PriceRow,
            BaseReferences<_$AppDatabase, $LocalProductPricesTable, PriceRow>,
          ),
          PriceRow,
          PrefetchHooks Function()
        > {
  $$LocalProductPricesTableTableManager(
    _$AppDatabase db,
    $LocalProductPricesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$LocalProductPricesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$LocalProductPricesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$LocalProductPricesTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> organizationId = const Value.absent(),
                Value<String> branchId = const Value.absent(),
                Value<String> id = const Value.absent(),
                Value<String> productId = const Value.absent(),
                Value<String> currency = const Value.absent(),
                Value<int> priceMinor = const Value.absent(),
                Value<DateTime> effectiveAt = const Value.absent(),
                Value<int> revision = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => LocalProductPricesCompanion(
                organizationId: organizationId,
                branchId: branchId,
                id: id,
                productId: productId,
                currency: currency,
                priceMinor: priceMinor,
                effectiveAt: effectiveAt,
                revision: revision,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String organizationId,
                required String branchId,
                required String id,
                required String productId,
                required String currency,
                required int priceMinor,
                required DateTime effectiveAt,
                required int revision,
                Value<int> rowid = const Value.absent(),
              }) => LocalProductPricesCompanion.insert(
                organizationId: organizationId,
                branchId: branchId,
                id: id,
                productId: productId,
                currency: currency,
                priceMinor: priceMinor,
                effectiveAt: effectiveAt,
                revision: revision,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$LocalProductPricesTable, PriceRow>(table),
                  BaseReferences<
                    _$AppDatabase,
                    $LocalProductPricesTable,
                    PriceRow
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$LocalProductPricesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $LocalProductPricesTable,
      PriceRow,
      $$LocalProductPricesTableFilterComposer,
      $$LocalProductPricesTableOrderingComposer,
      $$LocalProductPricesTableAnnotationComposer,
      $$LocalProductPricesTableCreateCompanionBuilder,
      $$LocalProductPricesTableUpdateCompanionBuilder,
      (
        PriceRow,
        BaseReferences<_$AppDatabase, $LocalProductPricesTable, PriceRow>,
      ),
      PriceRow,
      PrefetchHooks Function()
    >;
typedef $$LocalInventorySnapshotsTableCreateCompanionBuilder =
    LocalInventorySnapshotsCompanion Function({
      required String organizationId,
      required String branchId,
      required String id,
      required String productId,
      required int quantityUnits,
      Value<bool> uncertain,
      required DateTime observedAt,
      required int revision,
      Value<int> rowid,
    });
typedef $$LocalInventorySnapshotsTableUpdateCompanionBuilder =
    LocalInventorySnapshotsCompanion Function({
      Value<String> organizationId,
      Value<String> branchId,
      Value<String> id,
      Value<String> productId,
      Value<int> quantityUnits,
      Value<bool> uncertain,
      Value<DateTime> observedAt,
      Value<int> revision,
      Value<int> rowid,
    });

class $$LocalInventorySnapshotsTableFilterComposer
    extends Composer<_$AppDatabase, $LocalInventorySnapshotsTable> {
  $$LocalInventorySnapshotsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get organizationId => $composableBuilder(
    column: $table.organizationId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get branchId => $composableBuilder(
    column: $table.branchId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get productId => $composableBuilder(
    column: $table.productId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get quantityUnits => $composableBuilder(
    column: $table.quantityUnits,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get uncertain => $composableBuilder(
    column: $table.uncertain,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get observedAt => $composableBuilder(
    column: $table.observedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get revision => $composableBuilder(
    column: $table.revision,
    builder: (column) => ColumnFilters(column),
  );
}

class $$LocalInventorySnapshotsTableOrderingComposer
    extends Composer<_$AppDatabase, $LocalInventorySnapshotsTable> {
  $$LocalInventorySnapshotsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get organizationId => $composableBuilder(
    column: $table.organizationId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get branchId => $composableBuilder(
    column: $table.branchId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get productId => $composableBuilder(
    column: $table.productId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get quantityUnits => $composableBuilder(
    column: $table.quantityUnits,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get uncertain => $composableBuilder(
    column: $table.uncertain,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get observedAt => $composableBuilder(
    column: $table.observedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get revision => $composableBuilder(
    column: $table.revision,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$LocalInventorySnapshotsTableAnnotationComposer
    extends Composer<_$AppDatabase, $LocalInventorySnapshotsTable> {
  $$LocalInventorySnapshotsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get organizationId => $composableBuilder(
    column: $table.organizationId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get branchId =>
      $composableBuilder(column: $table.branchId, builder: (column) => column);

  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get productId =>
      $composableBuilder(column: $table.productId, builder: (column) => column);

  GeneratedColumn<int> get quantityUnits => $composableBuilder(
    column: $table.quantityUnits,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get uncertain =>
      $composableBuilder(column: $table.uncertain, builder: (column) => column);

  GeneratedColumn<DateTime> get observedAt => $composableBuilder(
    column: $table.observedAt,
    builder: (column) => column,
  );

  GeneratedColumn<int> get revision =>
      $composableBuilder(column: $table.revision, builder: (column) => column);
}

class $$LocalInventorySnapshotsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $LocalInventorySnapshotsTable,
          InventorySnapshotRow,
          $$LocalInventorySnapshotsTableFilterComposer,
          $$LocalInventorySnapshotsTableOrderingComposer,
          $$LocalInventorySnapshotsTableAnnotationComposer,
          $$LocalInventorySnapshotsTableCreateCompanionBuilder,
          $$LocalInventorySnapshotsTableUpdateCompanionBuilder,
          (
            InventorySnapshotRow,
            BaseReferences<
              _$AppDatabase,
              $LocalInventorySnapshotsTable,
              InventorySnapshotRow
            >,
          ),
          InventorySnapshotRow,
          PrefetchHooks Function()
        > {
  $$LocalInventorySnapshotsTableTableManager(
    _$AppDatabase db,
    $LocalInventorySnapshotsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$LocalInventorySnapshotsTableFilterComposer(
                $db: db,
                $table: table,
              ),
          createOrderingComposer: () =>
              $$LocalInventorySnapshotsTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$LocalInventorySnapshotsTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> organizationId = const Value.absent(),
                Value<String> branchId = const Value.absent(),
                Value<String> id = const Value.absent(),
                Value<String> productId = const Value.absent(),
                Value<int> quantityUnits = const Value.absent(),
                Value<bool> uncertain = const Value.absent(),
                Value<DateTime> observedAt = const Value.absent(),
                Value<int> revision = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => LocalInventorySnapshotsCompanion(
                organizationId: organizationId,
                branchId: branchId,
                id: id,
                productId: productId,
                quantityUnits: quantityUnits,
                uncertain: uncertain,
                observedAt: observedAt,
                revision: revision,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String organizationId,
                required String branchId,
                required String id,
                required String productId,
                required int quantityUnits,
                Value<bool> uncertain = const Value.absent(),
                required DateTime observedAt,
                required int revision,
                Value<int> rowid = const Value.absent(),
              }) => LocalInventorySnapshotsCompanion.insert(
                organizationId: organizationId,
                branchId: branchId,
                id: id,
                productId: productId,
                quantityUnits: quantityUnits,
                uncertain: uncertain,
                observedAt: observedAt,
                revision: revision,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<
                    $LocalInventorySnapshotsTable,
                    InventorySnapshotRow
                  >(table),
                  BaseReferences<
                    _$AppDatabase,
                    $LocalInventorySnapshotsTable,
                    InventorySnapshotRow
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$LocalInventorySnapshotsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $LocalInventorySnapshotsTable,
      InventorySnapshotRow,
      $$LocalInventorySnapshotsTableFilterComposer,
      $$LocalInventorySnapshotsTableOrderingComposer,
      $$LocalInventorySnapshotsTableAnnotationComposer,
      $$LocalInventorySnapshotsTableCreateCompanionBuilder,
      $$LocalInventorySnapshotsTableUpdateCompanionBuilder,
      (
        InventorySnapshotRow,
        BaseReferences<
          _$AppDatabase,
          $LocalInventorySnapshotsTable,
          InventorySnapshotRow
        >,
      ),
      InventorySnapshotRow,
      PrefetchHooks Function()
    >;
typedef $$LocalCustomersTableCreateCompanionBuilder =
    LocalCustomersCompanion Function({
      required String organizationId,
      required String branchId,
      required String id,
      required String name,
      Value<bool> active,
      required int revision,
      Value<int> rowid,
    });
typedef $$LocalCustomersTableUpdateCompanionBuilder =
    LocalCustomersCompanion Function({
      Value<String> organizationId,
      Value<String> branchId,
      Value<String> id,
      Value<String> name,
      Value<bool> active,
      Value<int> revision,
      Value<int> rowid,
    });

class $$LocalCustomersTableFilterComposer
    extends Composer<_$AppDatabase, $LocalCustomersTable> {
  $$LocalCustomersTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get organizationId => $composableBuilder(
    column: $table.organizationId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get branchId => $composableBuilder(
    column: $table.branchId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get active => $composableBuilder(
    column: $table.active,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get revision => $composableBuilder(
    column: $table.revision,
    builder: (column) => ColumnFilters(column),
  );
}

class $$LocalCustomersTableOrderingComposer
    extends Composer<_$AppDatabase, $LocalCustomersTable> {
  $$LocalCustomersTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get organizationId => $composableBuilder(
    column: $table.organizationId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get branchId => $composableBuilder(
    column: $table.branchId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get active => $composableBuilder(
    column: $table.active,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get revision => $composableBuilder(
    column: $table.revision,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$LocalCustomersTableAnnotationComposer
    extends Composer<_$AppDatabase, $LocalCustomersTable> {
  $$LocalCustomersTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get organizationId => $composableBuilder(
    column: $table.organizationId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get branchId =>
      $composableBuilder(column: $table.branchId, builder: (column) => column);

  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<bool> get active =>
      $composableBuilder(column: $table.active, builder: (column) => column);

  GeneratedColumn<int> get revision =>
      $composableBuilder(column: $table.revision, builder: (column) => column);
}

class $$LocalCustomersTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $LocalCustomersTable,
          CustomerRow,
          $$LocalCustomersTableFilterComposer,
          $$LocalCustomersTableOrderingComposer,
          $$LocalCustomersTableAnnotationComposer,
          $$LocalCustomersTableCreateCompanionBuilder,
          $$LocalCustomersTableUpdateCompanionBuilder,
          (
            CustomerRow,
            BaseReferences<_$AppDatabase, $LocalCustomersTable, CustomerRow>,
          ),
          CustomerRow,
          PrefetchHooks Function()
        > {
  $$LocalCustomersTableTableManager(
    _$AppDatabase db,
    $LocalCustomersTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$LocalCustomersTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$LocalCustomersTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$LocalCustomersTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> organizationId = const Value.absent(),
                Value<String> branchId = const Value.absent(),
                Value<String> id = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<bool> active = const Value.absent(),
                Value<int> revision = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => LocalCustomersCompanion(
                organizationId: organizationId,
                branchId: branchId,
                id: id,
                name: name,
                active: active,
                revision: revision,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String organizationId,
                required String branchId,
                required String id,
                required String name,
                Value<bool> active = const Value.absent(),
                required int revision,
                Value<int> rowid = const Value.absent(),
              }) => LocalCustomersCompanion.insert(
                organizationId: organizationId,
                branchId: branchId,
                id: id,
                name: name,
                active: active,
                revision: revision,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$LocalCustomersTable, CustomerRow>(table),
                  BaseReferences<
                    _$AppDatabase,
                    $LocalCustomersTable,
                    CustomerRow
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$LocalCustomersTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $LocalCustomersTable,
      CustomerRow,
      $$LocalCustomersTableFilterComposer,
      $$LocalCustomersTableOrderingComposer,
      $$LocalCustomersTableAnnotationComposer,
      $$LocalCustomersTableCreateCompanionBuilder,
      $$LocalCustomersTableUpdateCompanionBuilder,
      (
        CustomerRow,
        BaseReferences<_$AppDatabase, $LocalCustomersTable, CustomerRow>,
      ),
      CustomerRow,
      PrefetchHooks Function()
    >;
typedef $$LocalShiftsTableCreateCompanionBuilder =
    LocalShiftsCompanion Function({
      required String organizationId,
      required String branchId,
      required String id,
      required String deviceId,
      required String openedBy,
      required DateTime openedAt,
      required int openingCashMinor,
      required String currency,
      Value<int> rowid,
    });
typedef $$LocalShiftsTableUpdateCompanionBuilder =
    LocalShiftsCompanion Function({
      Value<String> organizationId,
      Value<String> branchId,
      Value<String> id,
      Value<String> deviceId,
      Value<String> openedBy,
      Value<DateTime> openedAt,
      Value<int> openingCashMinor,
      Value<String> currency,
      Value<int> rowid,
    });

class $$LocalShiftsTableFilterComposer
    extends Composer<_$AppDatabase, $LocalShiftsTable> {
  $$LocalShiftsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get organizationId => $composableBuilder(
    column: $table.organizationId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get branchId => $composableBuilder(
    column: $table.branchId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get deviceId => $composableBuilder(
    column: $table.deviceId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get openedBy => $composableBuilder(
    column: $table.openedBy,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get openedAt => $composableBuilder(
    column: $table.openedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get openingCashMinor => $composableBuilder(
    column: $table.openingCashMinor,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get currency => $composableBuilder(
    column: $table.currency,
    builder: (column) => ColumnFilters(column),
  );
}

class $$LocalShiftsTableOrderingComposer
    extends Composer<_$AppDatabase, $LocalShiftsTable> {
  $$LocalShiftsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get organizationId => $composableBuilder(
    column: $table.organizationId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get branchId => $composableBuilder(
    column: $table.branchId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get deviceId => $composableBuilder(
    column: $table.deviceId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get openedBy => $composableBuilder(
    column: $table.openedBy,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get openedAt => $composableBuilder(
    column: $table.openedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get openingCashMinor => $composableBuilder(
    column: $table.openingCashMinor,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get currency => $composableBuilder(
    column: $table.currency,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$LocalShiftsTableAnnotationComposer
    extends Composer<_$AppDatabase, $LocalShiftsTable> {
  $$LocalShiftsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get organizationId => $composableBuilder(
    column: $table.organizationId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get branchId =>
      $composableBuilder(column: $table.branchId, builder: (column) => column);

  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get deviceId =>
      $composableBuilder(column: $table.deviceId, builder: (column) => column);

  GeneratedColumn<String> get openedBy =>
      $composableBuilder(column: $table.openedBy, builder: (column) => column);

  GeneratedColumn<DateTime> get openedAt =>
      $composableBuilder(column: $table.openedAt, builder: (column) => column);

  GeneratedColumn<int> get openingCashMinor => $composableBuilder(
    column: $table.openingCashMinor,
    builder: (column) => column,
  );

  GeneratedColumn<String> get currency =>
      $composableBuilder(column: $table.currency, builder: (column) => column);
}

class $$LocalShiftsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $LocalShiftsTable,
          ShiftRow,
          $$LocalShiftsTableFilterComposer,
          $$LocalShiftsTableOrderingComposer,
          $$LocalShiftsTableAnnotationComposer,
          $$LocalShiftsTableCreateCompanionBuilder,
          $$LocalShiftsTableUpdateCompanionBuilder,
          (
            ShiftRow,
            BaseReferences<_$AppDatabase, $LocalShiftsTable, ShiftRow>,
          ),
          ShiftRow,
          PrefetchHooks Function()
        > {
  $$LocalShiftsTableTableManager(_$AppDatabase db, $LocalShiftsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$LocalShiftsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$LocalShiftsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$LocalShiftsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> organizationId = const Value.absent(),
                Value<String> branchId = const Value.absent(),
                Value<String> id = const Value.absent(),
                Value<String> deviceId = const Value.absent(),
                Value<String> openedBy = const Value.absent(),
                Value<DateTime> openedAt = const Value.absent(),
                Value<int> openingCashMinor = const Value.absent(),
                Value<String> currency = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => LocalShiftsCompanion(
                organizationId: organizationId,
                branchId: branchId,
                id: id,
                deviceId: deviceId,
                openedBy: openedBy,
                openedAt: openedAt,
                openingCashMinor: openingCashMinor,
                currency: currency,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String organizationId,
                required String branchId,
                required String id,
                required String deviceId,
                required String openedBy,
                required DateTime openedAt,
                required int openingCashMinor,
                required String currency,
                Value<int> rowid = const Value.absent(),
              }) => LocalShiftsCompanion.insert(
                organizationId: organizationId,
                branchId: branchId,
                id: id,
                deviceId: deviceId,
                openedBy: openedBy,
                openedAt: openedAt,
                openingCashMinor: openingCashMinor,
                currency: currency,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$LocalShiftsTable, ShiftRow>(table),
                  BaseReferences<_$AppDatabase, $LocalShiftsTable, ShiftRow>(
                    db,
                    table,
                    e,
                  ),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$LocalShiftsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $LocalShiftsTable,
      ShiftRow,
      $$LocalShiftsTableFilterComposer,
      $$LocalShiftsTableOrderingComposer,
      $$LocalShiftsTableAnnotationComposer,
      $$LocalShiftsTableCreateCompanionBuilder,
      $$LocalShiftsTableUpdateCompanionBuilder,
      (ShiftRow, BaseReferences<_$AppDatabase, $LocalShiftsTable, ShiftRow>),
      ShiftRow,
      PrefetchHooks Function()
    >;
typedef $$LocalSalesTableCreateCompanionBuilder =
    LocalSalesCompanion Function({
      required String organizationId,
      required String branchId,
      required String id,
      required String deviceId,
      required String shiftId,
      required String cashierId,
      Value<String?> customerId,
      required String receiptNumber,
      required String currency,
      required int subtotalMinor,
      required int discountMinor,
      required int taxMinor,
      required int totalMinor,
      required DateTime createdAt,
      Value<int> rowid,
    });
typedef $$LocalSalesTableUpdateCompanionBuilder =
    LocalSalesCompanion Function({
      Value<String> organizationId,
      Value<String> branchId,
      Value<String> id,
      Value<String> deviceId,
      Value<String> shiftId,
      Value<String> cashierId,
      Value<String?> customerId,
      Value<String> receiptNumber,
      Value<String> currency,
      Value<int> subtotalMinor,
      Value<int> discountMinor,
      Value<int> taxMinor,
      Value<int> totalMinor,
      Value<DateTime> createdAt,
      Value<int> rowid,
    });

class $$LocalSalesTableFilterComposer
    extends Composer<_$AppDatabase, $LocalSalesTable> {
  $$LocalSalesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get organizationId => $composableBuilder(
    column: $table.organizationId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get branchId => $composableBuilder(
    column: $table.branchId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get deviceId => $composableBuilder(
    column: $table.deviceId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get shiftId => $composableBuilder(
    column: $table.shiftId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get cashierId => $composableBuilder(
    column: $table.cashierId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get customerId => $composableBuilder(
    column: $table.customerId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get receiptNumber => $composableBuilder(
    column: $table.receiptNumber,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get currency => $composableBuilder(
    column: $table.currency,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get subtotalMinor => $composableBuilder(
    column: $table.subtotalMinor,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get discountMinor => $composableBuilder(
    column: $table.discountMinor,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get taxMinor => $composableBuilder(
    column: $table.taxMinor,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get totalMinor => $composableBuilder(
    column: $table.totalMinor,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$LocalSalesTableOrderingComposer
    extends Composer<_$AppDatabase, $LocalSalesTable> {
  $$LocalSalesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get organizationId => $composableBuilder(
    column: $table.organizationId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get branchId => $composableBuilder(
    column: $table.branchId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get deviceId => $composableBuilder(
    column: $table.deviceId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get shiftId => $composableBuilder(
    column: $table.shiftId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get cashierId => $composableBuilder(
    column: $table.cashierId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get customerId => $composableBuilder(
    column: $table.customerId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get receiptNumber => $composableBuilder(
    column: $table.receiptNumber,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get currency => $composableBuilder(
    column: $table.currency,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get subtotalMinor => $composableBuilder(
    column: $table.subtotalMinor,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get discountMinor => $composableBuilder(
    column: $table.discountMinor,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get taxMinor => $composableBuilder(
    column: $table.taxMinor,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get totalMinor => $composableBuilder(
    column: $table.totalMinor,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$LocalSalesTableAnnotationComposer
    extends Composer<_$AppDatabase, $LocalSalesTable> {
  $$LocalSalesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get organizationId => $composableBuilder(
    column: $table.organizationId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get branchId =>
      $composableBuilder(column: $table.branchId, builder: (column) => column);

  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get deviceId =>
      $composableBuilder(column: $table.deviceId, builder: (column) => column);

  GeneratedColumn<String> get shiftId =>
      $composableBuilder(column: $table.shiftId, builder: (column) => column);

  GeneratedColumn<String> get cashierId =>
      $composableBuilder(column: $table.cashierId, builder: (column) => column);

  GeneratedColumn<String> get customerId => $composableBuilder(
    column: $table.customerId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get receiptNumber => $composableBuilder(
    column: $table.receiptNumber,
    builder: (column) => column,
  );

  GeneratedColumn<String> get currency =>
      $composableBuilder(column: $table.currency, builder: (column) => column);

  GeneratedColumn<int> get subtotalMinor => $composableBuilder(
    column: $table.subtotalMinor,
    builder: (column) => column,
  );

  GeneratedColumn<int> get discountMinor => $composableBuilder(
    column: $table.discountMinor,
    builder: (column) => column,
  );

  GeneratedColumn<int> get taxMinor =>
      $composableBuilder(column: $table.taxMinor, builder: (column) => column);

  GeneratedColumn<int> get totalMinor => $composableBuilder(
    column: $table.totalMinor,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);
}

class $$LocalSalesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $LocalSalesTable,
          SaleRow,
          $$LocalSalesTableFilterComposer,
          $$LocalSalesTableOrderingComposer,
          $$LocalSalesTableAnnotationComposer,
          $$LocalSalesTableCreateCompanionBuilder,
          $$LocalSalesTableUpdateCompanionBuilder,
          (SaleRow, BaseReferences<_$AppDatabase, $LocalSalesTable, SaleRow>),
          SaleRow,
          PrefetchHooks Function()
        > {
  $$LocalSalesTableTableManager(_$AppDatabase db, $LocalSalesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$LocalSalesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$LocalSalesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$LocalSalesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> organizationId = const Value.absent(),
                Value<String> branchId = const Value.absent(),
                Value<String> id = const Value.absent(),
                Value<String> deviceId = const Value.absent(),
                Value<String> shiftId = const Value.absent(),
                Value<String> cashierId = const Value.absent(),
                Value<String?> customerId = const Value.absent(),
                Value<String> receiptNumber = const Value.absent(),
                Value<String> currency = const Value.absent(),
                Value<int> subtotalMinor = const Value.absent(),
                Value<int> discountMinor = const Value.absent(),
                Value<int> taxMinor = const Value.absent(),
                Value<int> totalMinor = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => LocalSalesCompanion(
                organizationId: organizationId,
                branchId: branchId,
                id: id,
                deviceId: deviceId,
                shiftId: shiftId,
                cashierId: cashierId,
                customerId: customerId,
                receiptNumber: receiptNumber,
                currency: currency,
                subtotalMinor: subtotalMinor,
                discountMinor: discountMinor,
                taxMinor: taxMinor,
                totalMinor: totalMinor,
                createdAt: createdAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String organizationId,
                required String branchId,
                required String id,
                required String deviceId,
                required String shiftId,
                required String cashierId,
                Value<String?> customerId = const Value.absent(),
                required String receiptNumber,
                required String currency,
                required int subtotalMinor,
                required int discountMinor,
                required int taxMinor,
                required int totalMinor,
                required DateTime createdAt,
                Value<int> rowid = const Value.absent(),
              }) => LocalSalesCompanion.insert(
                organizationId: organizationId,
                branchId: branchId,
                id: id,
                deviceId: deviceId,
                shiftId: shiftId,
                cashierId: cashierId,
                customerId: customerId,
                receiptNumber: receiptNumber,
                currency: currency,
                subtotalMinor: subtotalMinor,
                discountMinor: discountMinor,
                taxMinor: taxMinor,
                totalMinor: totalMinor,
                createdAt: createdAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$LocalSalesTable, SaleRow>(table),
                  BaseReferences<_$AppDatabase, $LocalSalesTable, SaleRow>(
                    db,
                    table,
                    e,
                  ),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$LocalSalesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $LocalSalesTable,
      SaleRow,
      $$LocalSalesTableFilterComposer,
      $$LocalSalesTableOrderingComposer,
      $$LocalSalesTableAnnotationComposer,
      $$LocalSalesTableCreateCompanionBuilder,
      $$LocalSalesTableUpdateCompanionBuilder,
      (SaleRow, BaseReferences<_$AppDatabase, $LocalSalesTable, SaleRow>),
      SaleRow,
      PrefetchHooks Function()
    >;
typedef $$LocalSaleItemsTableCreateCompanionBuilder =
    LocalSaleItemsCompanion Function({
      required String organizationId,
      required String branchId,
      required String id,
      required String saleId,
      required String productId,
      required String skuSnapshot,
      required String nameSnapshot,
      required int quantity,
      required int unitPriceMinor,
      required int discountMinor,
      required int taxMinor,
      required int lineTotalMinor,
      Value<int> rowid,
    });
typedef $$LocalSaleItemsTableUpdateCompanionBuilder =
    LocalSaleItemsCompanion Function({
      Value<String> organizationId,
      Value<String> branchId,
      Value<String> id,
      Value<String> saleId,
      Value<String> productId,
      Value<String> skuSnapshot,
      Value<String> nameSnapshot,
      Value<int> quantity,
      Value<int> unitPriceMinor,
      Value<int> discountMinor,
      Value<int> taxMinor,
      Value<int> lineTotalMinor,
      Value<int> rowid,
    });

class $$LocalSaleItemsTableFilterComposer
    extends Composer<_$AppDatabase, $LocalSaleItemsTable> {
  $$LocalSaleItemsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get organizationId => $composableBuilder(
    column: $table.organizationId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get branchId => $composableBuilder(
    column: $table.branchId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get saleId => $composableBuilder(
    column: $table.saleId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get productId => $composableBuilder(
    column: $table.productId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get skuSnapshot => $composableBuilder(
    column: $table.skuSnapshot,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get nameSnapshot => $composableBuilder(
    column: $table.nameSnapshot,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get quantity => $composableBuilder(
    column: $table.quantity,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get unitPriceMinor => $composableBuilder(
    column: $table.unitPriceMinor,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get discountMinor => $composableBuilder(
    column: $table.discountMinor,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get taxMinor => $composableBuilder(
    column: $table.taxMinor,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get lineTotalMinor => $composableBuilder(
    column: $table.lineTotalMinor,
    builder: (column) => ColumnFilters(column),
  );
}

class $$LocalSaleItemsTableOrderingComposer
    extends Composer<_$AppDatabase, $LocalSaleItemsTable> {
  $$LocalSaleItemsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get organizationId => $composableBuilder(
    column: $table.organizationId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get branchId => $composableBuilder(
    column: $table.branchId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get saleId => $composableBuilder(
    column: $table.saleId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get productId => $composableBuilder(
    column: $table.productId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get skuSnapshot => $composableBuilder(
    column: $table.skuSnapshot,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get nameSnapshot => $composableBuilder(
    column: $table.nameSnapshot,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get quantity => $composableBuilder(
    column: $table.quantity,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get unitPriceMinor => $composableBuilder(
    column: $table.unitPriceMinor,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get discountMinor => $composableBuilder(
    column: $table.discountMinor,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get taxMinor => $composableBuilder(
    column: $table.taxMinor,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get lineTotalMinor => $composableBuilder(
    column: $table.lineTotalMinor,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$LocalSaleItemsTableAnnotationComposer
    extends Composer<_$AppDatabase, $LocalSaleItemsTable> {
  $$LocalSaleItemsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get organizationId => $composableBuilder(
    column: $table.organizationId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get branchId =>
      $composableBuilder(column: $table.branchId, builder: (column) => column);

  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get saleId =>
      $composableBuilder(column: $table.saleId, builder: (column) => column);

  GeneratedColumn<String> get productId =>
      $composableBuilder(column: $table.productId, builder: (column) => column);

  GeneratedColumn<String> get skuSnapshot => $composableBuilder(
    column: $table.skuSnapshot,
    builder: (column) => column,
  );

  GeneratedColumn<String> get nameSnapshot => $composableBuilder(
    column: $table.nameSnapshot,
    builder: (column) => column,
  );

  GeneratedColumn<int> get quantity =>
      $composableBuilder(column: $table.quantity, builder: (column) => column);

  GeneratedColumn<int> get unitPriceMinor => $composableBuilder(
    column: $table.unitPriceMinor,
    builder: (column) => column,
  );

  GeneratedColumn<int> get discountMinor => $composableBuilder(
    column: $table.discountMinor,
    builder: (column) => column,
  );

  GeneratedColumn<int> get taxMinor =>
      $composableBuilder(column: $table.taxMinor, builder: (column) => column);

  GeneratedColumn<int> get lineTotalMinor => $composableBuilder(
    column: $table.lineTotalMinor,
    builder: (column) => column,
  );
}

class $$LocalSaleItemsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $LocalSaleItemsTable,
          SaleItemRow,
          $$LocalSaleItemsTableFilterComposer,
          $$LocalSaleItemsTableOrderingComposer,
          $$LocalSaleItemsTableAnnotationComposer,
          $$LocalSaleItemsTableCreateCompanionBuilder,
          $$LocalSaleItemsTableUpdateCompanionBuilder,
          (
            SaleItemRow,
            BaseReferences<_$AppDatabase, $LocalSaleItemsTable, SaleItemRow>,
          ),
          SaleItemRow,
          PrefetchHooks Function()
        > {
  $$LocalSaleItemsTableTableManager(
    _$AppDatabase db,
    $LocalSaleItemsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$LocalSaleItemsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$LocalSaleItemsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$LocalSaleItemsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> organizationId = const Value.absent(),
                Value<String> branchId = const Value.absent(),
                Value<String> id = const Value.absent(),
                Value<String> saleId = const Value.absent(),
                Value<String> productId = const Value.absent(),
                Value<String> skuSnapshot = const Value.absent(),
                Value<String> nameSnapshot = const Value.absent(),
                Value<int> quantity = const Value.absent(),
                Value<int> unitPriceMinor = const Value.absent(),
                Value<int> discountMinor = const Value.absent(),
                Value<int> taxMinor = const Value.absent(),
                Value<int> lineTotalMinor = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => LocalSaleItemsCompanion(
                organizationId: organizationId,
                branchId: branchId,
                id: id,
                saleId: saleId,
                productId: productId,
                skuSnapshot: skuSnapshot,
                nameSnapshot: nameSnapshot,
                quantity: quantity,
                unitPriceMinor: unitPriceMinor,
                discountMinor: discountMinor,
                taxMinor: taxMinor,
                lineTotalMinor: lineTotalMinor,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String organizationId,
                required String branchId,
                required String id,
                required String saleId,
                required String productId,
                required String skuSnapshot,
                required String nameSnapshot,
                required int quantity,
                required int unitPriceMinor,
                required int discountMinor,
                required int taxMinor,
                required int lineTotalMinor,
                Value<int> rowid = const Value.absent(),
              }) => LocalSaleItemsCompanion.insert(
                organizationId: organizationId,
                branchId: branchId,
                id: id,
                saleId: saleId,
                productId: productId,
                skuSnapshot: skuSnapshot,
                nameSnapshot: nameSnapshot,
                quantity: quantity,
                unitPriceMinor: unitPriceMinor,
                discountMinor: discountMinor,
                taxMinor: taxMinor,
                lineTotalMinor: lineTotalMinor,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$LocalSaleItemsTable, SaleItemRow>(table),
                  BaseReferences<
                    _$AppDatabase,
                    $LocalSaleItemsTable,
                    SaleItemRow
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$LocalSaleItemsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $LocalSaleItemsTable,
      SaleItemRow,
      $$LocalSaleItemsTableFilterComposer,
      $$LocalSaleItemsTableOrderingComposer,
      $$LocalSaleItemsTableAnnotationComposer,
      $$LocalSaleItemsTableCreateCompanionBuilder,
      $$LocalSaleItemsTableUpdateCompanionBuilder,
      (
        SaleItemRow,
        BaseReferences<_$AppDatabase, $LocalSaleItemsTable, SaleItemRow>,
      ),
      SaleItemRow,
      PrefetchHooks Function()
    >;
typedef $$LocalPaymentsTableCreateCompanionBuilder =
    LocalPaymentsCompanion Function({
      required String organizationId,
      required String branchId,
      required String id,
      required String saleId,
      required String method,
      required int amountMinor,
      required String currency,
      required String verificationMode,
      Value<String?> reference,
      required String recordedBy,
      required DateTime recordedAt,
      Value<int> rowid,
    });
typedef $$LocalPaymentsTableUpdateCompanionBuilder =
    LocalPaymentsCompanion Function({
      Value<String> organizationId,
      Value<String> branchId,
      Value<String> id,
      Value<String> saleId,
      Value<String> method,
      Value<int> amountMinor,
      Value<String> currency,
      Value<String> verificationMode,
      Value<String?> reference,
      Value<String> recordedBy,
      Value<DateTime> recordedAt,
      Value<int> rowid,
    });

class $$LocalPaymentsTableFilterComposer
    extends Composer<_$AppDatabase, $LocalPaymentsTable> {
  $$LocalPaymentsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get organizationId => $composableBuilder(
    column: $table.organizationId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get branchId => $composableBuilder(
    column: $table.branchId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get saleId => $composableBuilder(
    column: $table.saleId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get method => $composableBuilder(
    column: $table.method,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get amountMinor => $composableBuilder(
    column: $table.amountMinor,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get currency => $composableBuilder(
    column: $table.currency,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get verificationMode => $composableBuilder(
    column: $table.verificationMode,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get reference => $composableBuilder(
    column: $table.reference,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get recordedBy => $composableBuilder(
    column: $table.recordedBy,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get recordedAt => $composableBuilder(
    column: $table.recordedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$LocalPaymentsTableOrderingComposer
    extends Composer<_$AppDatabase, $LocalPaymentsTable> {
  $$LocalPaymentsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get organizationId => $composableBuilder(
    column: $table.organizationId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get branchId => $composableBuilder(
    column: $table.branchId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get saleId => $composableBuilder(
    column: $table.saleId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get method => $composableBuilder(
    column: $table.method,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get amountMinor => $composableBuilder(
    column: $table.amountMinor,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get currency => $composableBuilder(
    column: $table.currency,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get verificationMode => $composableBuilder(
    column: $table.verificationMode,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get reference => $composableBuilder(
    column: $table.reference,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get recordedBy => $composableBuilder(
    column: $table.recordedBy,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get recordedAt => $composableBuilder(
    column: $table.recordedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$LocalPaymentsTableAnnotationComposer
    extends Composer<_$AppDatabase, $LocalPaymentsTable> {
  $$LocalPaymentsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get organizationId => $composableBuilder(
    column: $table.organizationId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get branchId =>
      $composableBuilder(column: $table.branchId, builder: (column) => column);

  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get saleId =>
      $composableBuilder(column: $table.saleId, builder: (column) => column);

  GeneratedColumn<String> get method =>
      $composableBuilder(column: $table.method, builder: (column) => column);

  GeneratedColumn<int> get amountMinor => $composableBuilder(
    column: $table.amountMinor,
    builder: (column) => column,
  );

  GeneratedColumn<String> get currency =>
      $composableBuilder(column: $table.currency, builder: (column) => column);

  GeneratedColumn<String> get verificationMode => $composableBuilder(
    column: $table.verificationMode,
    builder: (column) => column,
  );

  GeneratedColumn<String> get reference =>
      $composableBuilder(column: $table.reference, builder: (column) => column);

  GeneratedColumn<String> get recordedBy => $composableBuilder(
    column: $table.recordedBy,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get recordedAt => $composableBuilder(
    column: $table.recordedAt,
    builder: (column) => column,
  );
}

class $$LocalPaymentsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $LocalPaymentsTable,
          PaymentRow,
          $$LocalPaymentsTableFilterComposer,
          $$LocalPaymentsTableOrderingComposer,
          $$LocalPaymentsTableAnnotationComposer,
          $$LocalPaymentsTableCreateCompanionBuilder,
          $$LocalPaymentsTableUpdateCompanionBuilder,
          (
            PaymentRow,
            BaseReferences<_$AppDatabase, $LocalPaymentsTable, PaymentRow>,
          ),
          PaymentRow,
          PrefetchHooks Function()
        > {
  $$LocalPaymentsTableTableManager(_$AppDatabase db, $LocalPaymentsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$LocalPaymentsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$LocalPaymentsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$LocalPaymentsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> organizationId = const Value.absent(),
                Value<String> branchId = const Value.absent(),
                Value<String> id = const Value.absent(),
                Value<String> saleId = const Value.absent(),
                Value<String> method = const Value.absent(),
                Value<int> amountMinor = const Value.absent(),
                Value<String> currency = const Value.absent(),
                Value<String> verificationMode = const Value.absent(),
                Value<String?> reference = const Value.absent(),
                Value<String> recordedBy = const Value.absent(),
                Value<DateTime> recordedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => LocalPaymentsCompanion(
                organizationId: organizationId,
                branchId: branchId,
                id: id,
                saleId: saleId,
                method: method,
                amountMinor: amountMinor,
                currency: currency,
                verificationMode: verificationMode,
                reference: reference,
                recordedBy: recordedBy,
                recordedAt: recordedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String organizationId,
                required String branchId,
                required String id,
                required String saleId,
                required String method,
                required int amountMinor,
                required String currency,
                required String verificationMode,
                Value<String?> reference = const Value.absent(),
                required String recordedBy,
                required DateTime recordedAt,
                Value<int> rowid = const Value.absent(),
              }) => LocalPaymentsCompanion.insert(
                organizationId: organizationId,
                branchId: branchId,
                id: id,
                saleId: saleId,
                method: method,
                amountMinor: amountMinor,
                currency: currency,
                verificationMode: verificationMode,
                reference: reference,
                recordedBy: recordedBy,
                recordedAt: recordedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$LocalPaymentsTable, PaymentRow>(table),
                  BaseReferences<
                    _$AppDatabase,
                    $LocalPaymentsTable,
                    PaymentRow
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$LocalPaymentsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $LocalPaymentsTable,
      PaymentRow,
      $$LocalPaymentsTableFilterComposer,
      $$LocalPaymentsTableOrderingComposer,
      $$LocalPaymentsTableAnnotationComposer,
      $$LocalPaymentsTableCreateCompanionBuilder,
      $$LocalPaymentsTableUpdateCompanionBuilder,
      (
        PaymentRow,
        BaseReferences<_$AppDatabase, $LocalPaymentsTable, PaymentRow>,
      ),
      PaymentRow,
      PrefetchHooks Function()
    >;
typedef $$SyncOutboxTableCreateCompanionBuilder =
    SyncOutboxCompanion Function({
      required String organizationId,
      required String branchId,
      required String id,
      required String deviceId,
      required String actorId,
      required String documentId,
      required String eventType,
      Value<int> schemaVersion,
      required String payloadJson,
      required String payloadDigest,
      required String occurredAtIso,
      Value<String> status,
      Value<int> attempts,
      Value<String?> leaseOwner,
      Value<String?> leaseToken,
      Value<DateTime?> leaseUntil,
      Value<DateTime?> nextAttemptAt,
      Value<String?> lastError,
      required DateTime createdAt,
      Value<DateTime?> acceptedAt,
      Value<String?> serverReceiptId,
      Value<int> rowid,
    });
typedef $$SyncOutboxTableUpdateCompanionBuilder =
    SyncOutboxCompanion Function({
      Value<String> organizationId,
      Value<String> branchId,
      Value<String> id,
      Value<String> deviceId,
      Value<String> actorId,
      Value<String> documentId,
      Value<String> eventType,
      Value<int> schemaVersion,
      Value<String> payloadJson,
      Value<String> payloadDigest,
      Value<String> occurredAtIso,
      Value<String> status,
      Value<int> attempts,
      Value<String?> leaseOwner,
      Value<String?> leaseToken,
      Value<DateTime?> leaseUntil,
      Value<DateTime?> nextAttemptAt,
      Value<String?> lastError,
      Value<DateTime> createdAt,
      Value<DateTime?> acceptedAt,
      Value<String?> serverReceiptId,
      Value<int> rowid,
    });

class $$SyncOutboxTableFilterComposer
    extends Composer<_$AppDatabase, $SyncOutboxTable> {
  $$SyncOutboxTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get organizationId => $composableBuilder(
    column: $table.organizationId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get branchId => $composableBuilder(
    column: $table.branchId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get deviceId => $composableBuilder(
    column: $table.deviceId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get actorId => $composableBuilder(
    column: $table.actorId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get documentId => $composableBuilder(
    column: $table.documentId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get eventType => $composableBuilder(
    column: $table.eventType,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get schemaVersion => $composableBuilder(
    column: $table.schemaVersion,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get payloadJson => $composableBuilder(
    column: $table.payloadJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get payloadDigest => $composableBuilder(
    column: $table.payloadDigest,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get occurredAtIso => $composableBuilder(
    column: $table.occurredAtIso,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get attempts => $composableBuilder(
    column: $table.attempts,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get leaseOwner => $composableBuilder(
    column: $table.leaseOwner,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get leaseToken => $composableBuilder(
    column: $table.leaseToken,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get leaseUntil => $composableBuilder(
    column: $table.leaseUntil,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get nextAttemptAt => $composableBuilder(
    column: $table.nextAttemptAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get lastError => $composableBuilder(
    column: $table.lastError,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get acceptedAt => $composableBuilder(
    column: $table.acceptedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get serverReceiptId => $composableBuilder(
    column: $table.serverReceiptId,
    builder: (column) => ColumnFilters(column),
  );
}

class $$SyncOutboxTableOrderingComposer
    extends Composer<_$AppDatabase, $SyncOutboxTable> {
  $$SyncOutboxTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get organizationId => $composableBuilder(
    column: $table.organizationId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get branchId => $composableBuilder(
    column: $table.branchId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get deviceId => $composableBuilder(
    column: $table.deviceId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get actorId => $composableBuilder(
    column: $table.actorId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get documentId => $composableBuilder(
    column: $table.documentId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get eventType => $composableBuilder(
    column: $table.eventType,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get schemaVersion => $composableBuilder(
    column: $table.schemaVersion,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get payloadJson => $composableBuilder(
    column: $table.payloadJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get payloadDigest => $composableBuilder(
    column: $table.payloadDigest,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get occurredAtIso => $composableBuilder(
    column: $table.occurredAtIso,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get attempts => $composableBuilder(
    column: $table.attempts,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get leaseOwner => $composableBuilder(
    column: $table.leaseOwner,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get leaseToken => $composableBuilder(
    column: $table.leaseToken,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get leaseUntil => $composableBuilder(
    column: $table.leaseUntil,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get nextAttemptAt => $composableBuilder(
    column: $table.nextAttemptAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get lastError => $composableBuilder(
    column: $table.lastError,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get acceptedAt => $composableBuilder(
    column: $table.acceptedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get serverReceiptId => $composableBuilder(
    column: $table.serverReceiptId,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$SyncOutboxTableAnnotationComposer
    extends Composer<_$AppDatabase, $SyncOutboxTable> {
  $$SyncOutboxTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get organizationId => $composableBuilder(
    column: $table.organizationId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get branchId =>
      $composableBuilder(column: $table.branchId, builder: (column) => column);

  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get deviceId =>
      $composableBuilder(column: $table.deviceId, builder: (column) => column);

  GeneratedColumn<String> get actorId =>
      $composableBuilder(column: $table.actorId, builder: (column) => column);

  GeneratedColumn<String> get documentId => $composableBuilder(
    column: $table.documentId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get eventType =>
      $composableBuilder(column: $table.eventType, builder: (column) => column);

  GeneratedColumn<int> get schemaVersion => $composableBuilder(
    column: $table.schemaVersion,
    builder: (column) => column,
  );

  GeneratedColumn<String> get payloadJson => $composableBuilder(
    column: $table.payloadJson,
    builder: (column) => column,
  );

  GeneratedColumn<String> get payloadDigest => $composableBuilder(
    column: $table.payloadDigest,
    builder: (column) => column,
  );

  GeneratedColumn<String> get occurredAtIso => $composableBuilder(
    column: $table.occurredAtIso,
    builder: (column) => column,
  );

  GeneratedColumn<String> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);

  GeneratedColumn<int> get attempts =>
      $composableBuilder(column: $table.attempts, builder: (column) => column);

  GeneratedColumn<String> get leaseOwner => $composableBuilder(
    column: $table.leaseOwner,
    builder: (column) => column,
  );

  GeneratedColumn<String> get leaseToken => $composableBuilder(
    column: $table.leaseToken,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get leaseUntil => $composableBuilder(
    column: $table.leaseUntil,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get nextAttemptAt => $composableBuilder(
    column: $table.nextAttemptAt,
    builder: (column) => column,
  );

  GeneratedColumn<String> get lastError =>
      $composableBuilder(column: $table.lastError, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get acceptedAt => $composableBuilder(
    column: $table.acceptedAt,
    builder: (column) => column,
  );

  GeneratedColumn<String> get serverReceiptId => $composableBuilder(
    column: $table.serverReceiptId,
    builder: (column) => column,
  );
}

class $$SyncOutboxTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $SyncOutboxTable,
          OutboxRow,
          $$SyncOutboxTableFilterComposer,
          $$SyncOutboxTableOrderingComposer,
          $$SyncOutboxTableAnnotationComposer,
          $$SyncOutboxTableCreateCompanionBuilder,
          $$SyncOutboxTableUpdateCompanionBuilder,
          (
            OutboxRow,
            BaseReferences<_$AppDatabase, $SyncOutboxTable, OutboxRow>,
          ),
          OutboxRow,
          PrefetchHooks Function()
        > {
  $$SyncOutboxTableTableManager(_$AppDatabase db, $SyncOutboxTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SyncOutboxTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SyncOutboxTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SyncOutboxTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> organizationId = const Value.absent(),
                Value<String> branchId = const Value.absent(),
                Value<String> id = const Value.absent(),
                Value<String> deviceId = const Value.absent(),
                Value<String> actorId = const Value.absent(),
                Value<String> documentId = const Value.absent(),
                Value<String> eventType = const Value.absent(),
                Value<int> schemaVersion = const Value.absent(),
                Value<String> payloadJson = const Value.absent(),
                Value<String> payloadDigest = const Value.absent(),
                Value<String> occurredAtIso = const Value.absent(),
                Value<String> status = const Value.absent(),
                Value<int> attempts = const Value.absent(),
                Value<String?> leaseOwner = const Value.absent(),
                Value<String?> leaseToken = const Value.absent(),
                Value<DateTime?> leaseUntil = const Value.absent(),
                Value<DateTime?> nextAttemptAt = const Value.absent(),
                Value<String?> lastError = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime?> acceptedAt = const Value.absent(),
                Value<String?> serverReceiptId = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SyncOutboxCompanion(
                organizationId: organizationId,
                branchId: branchId,
                id: id,
                deviceId: deviceId,
                actorId: actorId,
                documentId: documentId,
                eventType: eventType,
                schemaVersion: schemaVersion,
                payloadJson: payloadJson,
                payloadDigest: payloadDigest,
                occurredAtIso: occurredAtIso,
                status: status,
                attempts: attempts,
                leaseOwner: leaseOwner,
                leaseToken: leaseToken,
                leaseUntil: leaseUntil,
                nextAttemptAt: nextAttemptAt,
                lastError: lastError,
                createdAt: createdAt,
                acceptedAt: acceptedAt,
                serverReceiptId: serverReceiptId,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String organizationId,
                required String branchId,
                required String id,
                required String deviceId,
                required String actorId,
                required String documentId,
                required String eventType,
                Value<int> schemaVersion = const Value.absent(),
                required String payloadJson,
                required String payloadDigest,
                required String occurredAtIso,
                Value<String> status = const Value.absent(),
                Value<int> attempts = const Value.absent(),
                Value<String?> leaseOwner = const Value.absent(),
                Value<String?> leaseToken = const Value.absent(),
                Value<DateTime?> leaseUntil = const Value.absent(),
                Value<DateTime?> nextAttemptAt = const Value.absent(),
                Value<String?> lastError = const Value.absent(),
                required DateTime createdAt,
                Value<DateTime?> acceptedAt = const Value.absent(),
                Value<String?> serverReceiptId = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SyncOutboxCompanion.insert(
                organizationId: organizationId,
                branchId: branchId,
                id: id,
                deviceId: deviceId,
                actorId: actorId,
                documentId: documentId,
                eventType: eventType,
                schemaVersion: schemaVersion,
                payloadJson: payloadJson,
                payloadDigest: payloadDigest,
                occurredAtIso: occurredAtIso,
                status: status,
                attempts: attempts,
                leaseOwner: leaseOwner,
                leaseToken: leaseToken,
                leaseUntil: leaseUntil,
                nextAttemptAt: nextAttemptAt,
                lastError: lastError,
                createdAt: createdAt,
                acceptedAt: acceptedAt,
                serverReceiptId: serverReceiptId,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$SyncOutboxTable, OutboxRow>(table),
                  BaseReferences<_$AppDatabase, $SyncOutboxTable, OutboxRow>(
                    db,
                    table,
                    e,
                  ),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$SyncOutboxTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $SyncOutboxTable,
      OutboxRow,
      $$SyncOutboxTableFilterComposer,
      $$SyncOutboxTableOrderingComposer,
      $$SyncOutboxTableAnnotationComposer,
      $$SyncOutboxTableCreateCompanionBuilder,
      $$SyncOutboxTableUpdateCompanionBuilder,
      (OutboxRow, BaseReferences<_$AppDatabase, $SyncOutboxTable, OutboxRow>),
      OutboxRow,
      PrefetchHooks Function()
    >;
typedef $$SyncCursorsTableCreateCompanionBuilder =
    SyncCursorsCompanion Function({
      required String organizationId,
      required String branchId,
      required String id,
      required String cursor,
      required DateTime updatedAt,
      Value<int> rowid,
    });
typedef $$SyncCursorsTableUpdateCompanionBuilder =
    SyncCursorsCompanion Function({
      Value<String> organizationId,
      Value<String> branchId,
      Value<String> id,
      Value<String> cursor,
      Value<DateTime> updatedAt,
      Value<int> rowid,
    });

class $$SyncCursorsTableFilterComposer
    extends Composer<_$AppDatabase, $SyncCursorsTable> {
  $$SyncCursorsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get organizationId => $composableBuilder(
    column: $table.organizationId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get branchId => $composableBuilder(
    column: $table.branchId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get cursor => $composableBuilder(
    column: $table.cursor,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$SyncCursorsTableOrderingComposer
    extends Composer<_$AppDatabase, $SyncCursorsTable> {
  $$SyncCursorsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get organizationId => $composableBuilder(
    column: $table.organizationId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get branchId => $composableBuilder(
    column: $table.branchId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get cursor => $composableBuilder(
    column: $table.cursor,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$SyncCursorsTableAnnotationComposer
    extends Composer<_$AppDatabase, $SyncCursorsTable> {
  $$SyncCursorsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get organizationId => $composableBuilder(
    column: $table.organizationId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get branchId =>
      $composableBuilder(column: $table.branchId, builder: (column) => column);

  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get cursor =>
      $composableBuilder(column: $table.cursor, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$SyncCursorsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $SyncCursorsTable,
          CursorRow,
          $$SyncCursorsTableFilterComposer,
          $$SyncCursorsTableOrderingComposer,
          $$SyncCursorsTableAnnotationComposer,
          $$SyncCursorsTableCreateCompanionBuilder,
          $$SyncCursorsTableUpdateCompanionBuilder,
          (
            CursorRow,
            BaseReferences<_$AppDatabase, $SyncCursorsTable, CursorRow>,
          ),
          CursorRow,
          PrefetchHooks Function()
        > {
  $$SyncCursorsTableTableManager(_$AppDatabase db, $SyncCursorsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SyncCursorsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SyncCursorsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SyncCursorsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> organizationId = const Value.absent(),
                Value<String> branchId = const Value.absent(),
                Value<String> id = const Value.absent(),
                Value<String> cursor = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SyncCursorsCompanion(
                organizationId: organizationId,
                branchId: branchId,
                id: id,
                cursor: cursor,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String organizationId,
                required String branchId,
                required String id,
                required String cursor,
                required DateTime updatedAt,
                Value<int> rowid = const Value.absent(),
              }) => SyncCursorsCompanion.insert(
                organizationId: organizationId,
                branchId: branchId,
                id: id,
                cursor: cursor,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$SyncCursorsTable, CursorRow>(table),
                  BaseReferences<_$AppDatabase, $SyncCursorsTable, CursorRow>(
                    db,
                    table,
                    e,
                  ),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$SyncCursorsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $SyncCursorsTable,
      CursorRow,
      $$SyncCursorsTableFilterComposer,
      $$SyncCursorsTableOrderingComposer,
      $$SyncCursorsTableAnnotationComposer,
      $$SyncCursorsTableCreateCompanionBuilder,
      $$SyncCursorsTableUpdateCompanionBuilder,
      (CursorRow, BaseReferences<_$AppDatabase, $SyncCursorsTable, CursorRow>),
      CursorRow,
      PrefetchHooks Function()
    >;
typedef $$OfflineEventAuthorizationsTableCreateCompanionBuilder =
    OfflineEventAuthorizationsCompanion Function({
      required String organizationId,
      required String branchId,
      required String id,
      required String actorId,
      required String deviceId,
      required String grantId,
      required int sequence,
      required String authorizationJson,
      required String signature,
      Value<int> rowid,
    });
typedef $$OfflineEventAuthorizationsTableUpdateCompanionBuilder =
    OfflineEventAuthorizationsCompanion Function({
      Value<String> organizationId,
      Value<String> branchId,
      Value<String> id,
      Value<String> actorId,
      Value<String> deviceId,
      Value<String> grantId,
      Value<int> sequence,
      Value<String> authorizationJson,
      Value<String> signature,
      Value<int> rowid,
    });

class $$OfflineEventAuthorizationsTableFilterComposer
    extends Composer<_$AppDatabase, $OfflineEventAuthorizationsTable> {
  $$OfflineEventAuthorizationsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get organizationId => $composableBuilder(
    column: $table.organizationId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get branchId => $composableBuilder(
    column: $table.branchId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get actorId => $composableBuilder(
    column: $table.actorId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get deviceId => $composableBuilder(
    column: $table.deviceId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get grantId => $composableBuilder(
    column: $table.grantId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get sequence => $composableBuilder(
    column: $table.sequence,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get authorizationJson => $composableBuilder(
    column: $table.authorizationJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get signature => $composableBuilder(
    column: $table.signature,
    builder: (column) => ColumnFilters(column),
  );
}

class $$OfflineEventAuthorizationsTableOrderingComposer
    extends Composer<_$AppDatabase, $OfflineEventAuthorizationsTable> {
  $$OfflineEventAuthorizationsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get organizationId => $composableBuilder(
    column: $table.organizationId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get branchId => $composableBuilder(
    column: $table.branchId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get actorId => $composableBuilder(
    column: $table.actorId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get deviceId => $composableBuilder(
    column: $table.deviceId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get grantId => $composableBuilder(
    column: $table.grantId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get sequence => $composableBuilder(
    column: $table.sequence,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get authorizationJson => $composableBuilder(
    column: $table.authorizationJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get signature => $composableBuilder(
    column: $table.signature,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$OfflineEventAuthorizationsTableAnnotationComposer
    extends Composer<_$AppDatabase, $OfflineEventAuthorizationsTable> {
  $$OfflineEventAuthorizationsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get organizationId => $composableBuilder(
    column: $table.organizationId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get branchId =>
      $composableBuilder(column: $table.branchId, builder: (column) => column);

  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get actorId =>
      $composableBuilder(column: $table.actorId, builder: (column) => column);

  GeneratedColumn<String> get deviceId =>
      $composableBuilder(column: $table.deviceId, builder: (column) => column);

  GeneratedColumn<String> get grantId =>
      $composableBuilder(column: $table.grantId, builder: (column) => column);

  GeneratedColumn<int> get sequence =>
      $composableBuilder(column: $table.sequence, builder: (column) => column);

  GeneratedColumn<String> get authorizationJson => $composableBuilder(
    column: $table.authorizationJson,
    builder: (column) => column,
  );

  GeneratedColumn<String> get signature =>
      $composableBuilder(column: $table.signature, builder: (column) => column);
}

class $$OfflineEventAuthorizationsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $OfflineEventAuthorizationsTable,
          OfflineAuthorizationRow,
          $$OfflineEventAuthorizationsTableFilterComposer,
          $$OfflineEventAuthorizationsTableOrderingComposer,
          $$OfflineEventAuthorizationsTableAnnotationComposer,
          $$OfflineEventAuthorizationsTableCreateCompanionBuilder,
          $$OfflineEventAuthorizationsTableUpdateCompanionBuilder,
          (
            OfflineAuthorizationRow,
            BaseReferences<
              _$AppDatabase,
              $OfflineEventAuthorizationsTable,
              OfflineAuthorizationRow
            >,
          ),
          OfflineAuthorizationRow,
          PrefetchHooks Function()
        > {
  $$OfflineEventAuthorizationsTableTableManager(
    _$AppDatabase db,
    $OfflineEventAuthorizationsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$OfflineEventAuthorizationsTableFilterComposer(
                $db: db,
                $table: table,
              ),
          createOrderingComposer: () =>
              $$OfflineEventAuthorizationsTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$OfflineEventAuthorizationsTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> organizationId = const Value.absent(),
                Value<String> branchId = const Value.absent(),
                Value<String> id = const Value.absent(),
                Value<String> actorId = const Value.absent(),
                Value<String> deviceId = const Value.absent(),
                Value<String> grantId = const Value.absent(),
                Value<int> sequence = const Value.absent(),
                Value<String> authorizationJson = const Value.absent(),
                Value<String> signature = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => OfflineEventAuthorizationsCompanion(
                organizationId: organizationId,
                branchId: branchId,
                id: id,
                actorId: actorId,
                deviceId: deviceId,
                grantId: grantId,
                sequence: sequence,
                authorizationJson: authorizationJson,
                signature: signature,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String organizationId,
                required String branchId,
                required String id,
                required String actorId,
                required String deviceId,
                required String grantId,
                required int sequence,
                required String authorizationJson,
                required String signature,
                Value<int> rowid = const Value.absent(),
              }) => OfflineEventAuthorizationsCompanion.insert(
                organizationId: organizationId,
                branchId: branchId,
                id: id,
                actorId: actorId,
                deviceId: deviceId,
                grantId: grantId,
                sequence: sequence,
                authorizationJson: authorizationJson,
                signature: signature,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<
                    $OfflineEventAuthorizationsTable,
                    OfflineAuthorizationRow
                  >(table),
                  BaseReferences<
                    _$AppDatabase,
                    $OfflineEventAuthorizationsTable,
                    OfflineAuthorizationRow
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$OfflineEventAuthorizationsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $OfflineEventAuthorizationsTable,
      OfflineAuthorizationRow,
      $$OfflineEventAuthorizationsTableFilterComposer,
      $$OfflineEventAuthorizationsTableOrderingComposer,
      $$OfflineEventAuthorizationsTableAnnotationComposer,
      $$OfflineEventAuthorizationsTableCreateCompanionBuilder,
      $$OfflineEventAuthorizationsTableUpdateCompanionBuilder,
      (
        OfflineAuthorizationRow,
        BaseReferences<
          _$AppDatabase,
          $OfflineEventAuthorizationsTable,
          OfflineAuthorizationRow
        >,
      ),
      OfflineAuthorizationRow,
      PrefetchHooks Function()
    >;
typedef $$OfflineCacheRecordsTableCreateCompanionBuilder =
    OfflineCacheRecordsCompanion Function({
      required String organizationId,
      required String branchId,
      required String id,
      required String actorId,
      required String deviceId,
      required String kind,
      required int revision,
      Value<bool> deleted,
      Value<String?> valueJson,
      Value<int> rowid,
    });
typedef $$OfflineCacheRecordsTableUpdateCompanionBuilder =
    OfflineCacheRecordsCompanion Function({
      Value<String> organizationId,
      Value<String> branchId,
      Value<String> id,
      Value<String> actorId,
      Value<String> deviceId,
      Value<String> kind,
      Value<int> revision,
      Value<bool> deleted,
      Value<String?> valueJson,
      Value<int> rowid,
    });

class $$OfflineCacheRecordsTableFilterComposer
    extends Composer<_$AppDatabase, $OfflineCacheRecordsTable> {
  $$OfflineCacheRecordsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get organizationId => $composableBuilder(
    column: $table.organizationId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get branchId => $composableBuilder(
    column: $table.branchId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get actorId => $composableBuilder(
    column: $table.actorId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get deviceId => $composableBuilder(
    column: $table.deviceId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get revision => $composableBuilder(
    column: $table.revision,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get deleted => $composableBuilder(
    column: $table.deleted,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get valueJson => $composableBuilder(
    column: $table.valueJson,
    builder: (column) => ColumnFilters(column),
  );
}

class $$OfflineCacheRecordsTableOrderingComposer
    extends Composer<_$AppDatabase, $OfflineCacheRecordsTable> {
  $$OfflineCacheRecordsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get organizationId => $composableBuilder(
    column: $table.organizationId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get branchId => $composableBuilder(
    column: $table.branchId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get actorId => $composableBuilder(
    column: $table.actorId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get deviceId => $composableBuilder(
    column: $table.deviceId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get revision => $composableBuilder(
    column: $table.revision,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get deleted => $composableBuilder(
    column: $table.deleted,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get valueJson => $composableBuilder(
    column: $table.valueJson,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$OfflineCacheRecordsTableAnnotationComposer
    extends Composer<_$AppDatabase, $OfflineCacheRecordsTable> {
  $$OfflineCacheRecordsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get organizationId => $composableBuilder(
    column: $table.organizationId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get branchId =>
      $composableBuilder(column: $table.branchId, builder: (column) => column);

  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get actorId =>
      $composableBuilder(column: $table.actorId, builder: (column) => column);

  GeneratedColumn<String> get deviceId =>
      $composableBuilder(column: $table.deviceId, builder: (column) => column);

  GeneratedColumn<String> get kind =>
      $composableBuilder(column: $table.kind, builder: (column) => column);

  GeneratedColumn<int> get revision =>
      $composableBuilder(column: $table.revision, builder: (column) => column);

  GeneratedColumn<bool> get deleted =>
      $composableBuilder(column: $table.deleted, builder: (column) => column);

  GeneratedColumn<String> get valueJson =>
      $composableBuilder(column: $table.valueJson, builder: (column) => column);
}

class $$OfflineCacheRecordsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $OfflineCacheRecordsTable,
          OfflineCacheRow,
          $$OfflineCacheRecordsTableFilterComposer,
          $$OfflineCacheRecordsTableOrderingComposer,
          $$OfflineCacheRecordsTableAnnotationComposer,
          $$OfflineCacheRecordsTableCreateCompanionBuilder,
          $$OfflineCacheRecordsTableUpdateCompanionBuilder,
          (
            OfflineCacheRow,
            BaseReferences<
              _$AppDatabase,
              $OfflineCacheRecordsTable,
              OfflineCacheRow
            >,
          ),
          OfflineCacheRow,
          PrefetchHooks Function()
        > {
  $$OfflineCacheRecordsTableTableManager(
    _$AppDatabase db,
    $OfflineCacheRecordsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$OfflineCacheRecordsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$OfflineCacheRecordsTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$OfflineCacheRecordsTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> organizationId = const Value.absent(),
                Value<String> branchId = const Value.absent(),
                Value<String> id = const Value.absent(),
                Value<String> actorId = const Value.absent(),
                Value<String> deviceId = const Value.absent(),
                Value<String> kind = const Value.absent(),
                Value<int> revision = const Value.absent(),
                Value<bool> deleted = const Value.absent(),
                Value<String?> valueJson = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => OfflineCacheRecordsCompanion(
                organizationId: organizationId,
                branchId: branchId,
                id: id,
                actorId: actorId,
                deviceId: deviceId,
                kind: kind,
                revision: revision,
                deleted: deleted,
                valueJson: valueJson,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String organizationId,
                required String branchId,
                required String id,
                required String actorId,
                required String deviceId,
                required String kind,
                required int revision,
                Value<bool> deleted = const Value.absent(),
                Value<String?> valueJson = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => OfflineCacheRecordsCompanion.insert(
                organizationId: organizationId,
                branchId: branchId,
                id: id,
                actorId: actorId,
                deviceId: deviceId,
                kind: kind,
                revision: revision,
                deleted: deleted,
                valueJson: valueJson,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$OfflineCacheRecordsTable, OfflineCacheRow>(
                    table,
                  ),
                  BaseReferences<
                    _$AppDatabase,
                    $OfflineCacheRecordsTable,
                    OfflineCacheRow
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$OfflineCacheRecordsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $OfflineCacheRecordsTable,
      OfflineCacheRow,
      $$OfflineCacheRecordsTableFilterComposer,
      $$OfflineCacheRecordsTableOrderingComposer,
      $$OfflineCacheRecordsTableAnnotationComposer,
      $$OfflineCacheRecordsTableCreateCompanionBuilder,
      $$OfflineCacheRecordsTableUpdateCompanionBuilder,
      (
        OfflineCacheRow,
        BaseReferences<
          _$AppDatabase,
          $OfflineCacheRecordsTable,
          OfflineCacheRow
        >,
      ),
      OfflineCacheRow,
      PrefetchHooks Function()
    >;
typedef $$OfflineCacheStatesTableCreateCompanionBuilder =
    OfflineCacheStatesCompanion Function({
      required String organizationId,
      required String branchId,
      required String id,
      required String actorId,
      required String deviceId,
      required String cursor,
      required DateTime serverTime,
      required DateTime observedAt,
      Value<bool> completeSnapshot,
      Value<String?> grantId,
      Value<int> rowid,
    });
typedef $$OfflineCacheStatesTableUpdateCompanionBuilder =
    OfflineCacheStatesCompanion Function({
      Value<String> organizationId,
      Value<String> branchId,
      Value<String> id,
      Value<String> actorId,
      Value<String> deviceId,
      Value<String> cursor,
      Value<DateTime> serverTime,
      Value<DateTime> observedAt,
      Value<bool> completeSnapshot,
      Value<String?> grantId,
      Value<int> rowid,
    });

class $$OfflineCacheStatesTableFilterComposer
    extends Composer<_$AppDatabase, $OfflineCacheStatesTable> {
  $$OfflineCacheStatesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get organizationId => $composableBuilder(
    column: $table.organizationId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get branchId => $composableBuilder(
    column: $table.branchId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get actorId => $composableBuilder(
    column: $table.actorId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get deviceId => $composableBuilder(
    column: $table.deviceId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get cursor => $composableBuilder(
    column: $table.cursor,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get serverTime => $composableBuilder(
    column: $table.serverTime,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get observedAt => $composableBuilder(
    column: $table.observedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get completeSnapshot => $composableBuilder(
    column: $table.completeSnapshot,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get grantId => $composableBuilder(
    column: $table.grantId,
    builder: (column) => ColumnFilters(column),
  );
}

class $$OfflineCacheStatesTableOrderingComposer
    extends Composer<_$AppDatabase, $OfflineCacheStatesTable> {
  $$OfflineCacheStatesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get organizationId => $composableBuilder(
    column: $table.organizationId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get branchId => $composableBuilder(
    column: $table.branchId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get actorId => $composableBuilder(
    column: $table.actorId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get deviceId => $composableBuilder(
    column: $table.deviceId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get cursor => $composableBuilder(
    column: $table.cursor,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get serverTime => $composableBuilder(
    column: $table.serverTime,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get observedAt => $composableBuilder(
    column: $table.observedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get completeSnapshot => $composableBuilder(
    column: $table.completeSnapshot,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get grantId => $composableBuilder(
    column: $table.grantId,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$OfflineCacheStatesTableAnnotationComposer
    extends Composer<_$AppDatabase, $OfflineCacheStatesTable> {
  $$OfflineCacheStatesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get organizationId => $composableBuilder(
    column: $table.organizationId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get branchId =>
      $composableBuilder(column: $table.branchId, builder: (column) => column);

  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get actorId =>
      $composableBuilder(column: $table.actorId, builder: (column) => column);

  GeneratedColumn<String> get deviceId =>
      $composableBuilder(column: $table.deviceId, builder: (column) => column);

  GeneratedColumn<String> get cursor =>
      $composableBuilder(column: $table.cursor, builder: (column) => column);

  GeneratedColumn<DateTime> get serverTime => $composableBuilder(
    column: $table.serverTime,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get observedAt => $composableBuilder(
    column: $table.observedAt,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get completeSnapshot => $composableBuilder(
    column: $table.completeSnapshot,
    builder: (column) => column,
  );

  GeneratedColumn<String> get grantId =>
      $composableBuilder(column: $table.grantId, builder: (column) => column);
}

class $$OfflineCacheStatesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $OfflineCacheStatesTable,
          OfflineCacheStateRow,
          $$OfflineCacheStatesTableFilterComposer,
          $$OfflineCacheStatesTableOrderingComposer,
          $$OfflineCacheStatesTableAnnotationComposer,
          $$OfflineCacheStatesTableCreateCompanionBuilder,
          $$OfflineCacheStatesTableUpdateCompanionBuilder,
          (
            OfflineCacheStateRow,
            BaseReferences<
              _$AppDatabase,
              $OfflineCacheStatesTable,
              OfflineCacheStateRow
            >,
          ),
          OfflineCacheStateRow,
          PrefetchHooks Function()
        > {
  $$OfflineCacheStatesTableTableManager(
    _$AppDatabase db,
    $OfflineCacheStatesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$OfflineCacheStatesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$OfflineCacheStatesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$OfflineCacheStatesTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> organizationId = const Value.absent(),
                Value<String> branchId = const Value.absent(),
                Value<String> id = const Value.absent(),
                Value<String> actorId = const Value.absent(),
                Value<String> deviceId = const Value.absent(),
                Value<String> cursor = const Value.absent(),
                Value<DateTime> serverTime = const Value.absent(),
                Value<DateTime> observedAt = const Value.absent(),
                Value<bool> completeSnapshot = const Value.absent(),
                Value<String?> grantId = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => OfflineCacheStatesCompanion(
                organizationId: organizationId,
                branchId: branchId,
                id: id,
                actorId: actorId,
                deviceId: deviceId,
                cursor: cursor,
                serverTime: serverTime,
                observedAt: observedAt,
                completeSnapshot: completeSnapshot,
                grantId: grantId,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String organizationId,
                required String branchId,
                required String id,
                required String actorId,
                required String deviceId,
                required String cursor,
                required DateTime serverTime,
                required DateTime observedAt,
                Value<bool> completeSnapshot = const Value.absent(),
                Value<String?> grantId = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => OfflineCacheStatesCompanion.insert(
                organizationId: organizationId,
                branchId: branchId,
                id: id,
                actorId: actorId,
                deviceId: deviceId,
                cursor: cursor,
                serverTime: serverTime,
                observedAt: observedAt,
                completeSnapshot: completeSnapshot,
                grantId: grantId,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$OfflineCacheStatesTable, OfflineCacheStateRow>(
                    table,
                  ),
                  BaseReferences<
                    _$AppDatabase,
                    $OfflineCacheStatesTable,
                    OfflineCacheStateRow
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$OfflineCacheStatesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $OfflineCacheStatesTable,
      OfflineCacheStateRow,
      $$OfflineCacheStatesTableFilterComposer,
      $$OfflineCacheStatesTableOrderingComposer,
      $$OfflineCacheStatesTableAnnotationComposer,
      $$OfflineCacheStatesTableCreateCompanionBuilder,
      $$OfflineCacheStatesTableUpdateCompanionBuilder,
      (
        OfflineCacheStateRow,
        BaseReferences<
          _$AppDatabase,
          $OfflineCacheStatesTable,
          OfflineCacheStateRow
        >,
      ),
      OfflineCacheStateRow,
      PrefetchHooks Function()
    >;
typedef $$OfflineStockEffectsTableCreateCompanionBuilder =
    OfflineStockEffectsCompanion Function({
      required String organizationId,
      required String branchId,
      required String id,
      required String actorId,
      required String deviceId,
      required String eventId,
      required String productId,
      required int observedRevision,
      required int quantityDelta,
      Value<int> rowid,
    });
typedef $$OfflineStockEffectsTableUpdateCompanionBuilder =
    OfflineStockEffectsCompanion Function({
      Value<String> organizationId,
      Value<String> branchId,
      Value<String> id,
      Value<String> actorId,
      Value<String> deviceId,
      Value<String> eventId,
      Value<String> productId,
      Value<int> observedRevision,
      Value<int> quantityDelta,
      Value<int> rowid,
    });

class $$OfflineStockEffectsTableFilterComposer
    extends Composer<_$AppDatabase, $OfflineStockEffectsTable> {
  $$OfflineStockEffectsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get organizationId => $composableBuilder(
    column: $table.organizationId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get branchId => $composableBuilder(
    column: $table.branchId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get actorId => $composableBuilder(
    column: $table.actorId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get deviceId => $composableBuilder(
    column: $table.deviceId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get eventId => $composableBuilder(
    column: $table.eventId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get productId => $composableBuilder(
    column: $table.productId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get observedRevision => $composableBuilder(
    column: $table.observedRevision,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get quantityDelta => $composableBuilder(
    column: $table.quantityDelta,
    builder: (column) => ColumnFilters(column),
  );
}

class $$OfflineStockEffectsTableOrderingComposer
    extends Composer<_$AppDatabase, $OfflineStockEffectsTable> {
  $$OfflineStockEffectsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get organizationId => $composableBuilder(
    column: $table.organizationId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get branchId => $composableBuilder(
    column: $table.branchId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get actorId => $composableBuilder(
    column: $table.actorId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get deviceId => $composableBuilder(
    column: $table.deviceId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get eventId => $composableBuilder(
    column: $table.eventId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get productId => $composableBuilder(
    column: $table.productId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get observedRevision => $composableBuilder(
    column: $table.observedRevision,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get quantityDelta => $composableBuilder(
    column: $table.quantityDelta,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$OfflineStockEffectsTableAnnotationComposer
    extends Composer<_$AppDatabase, $OfflineStockEffectsTable> {
  $$OfflineStockEffectsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get organizationId => $composableBuilder(
    column: $table.organizationId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get branchId =>
      $composableBuilder(column: $table.branchId, builder: (column) => column);

  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get actorId =>
      $composableBuilder(column: $table.actorId, builder: (column) => column);

  GeneratedColumn<String> get deviceId =>
      $composableBuilder(column: $table.deviceId, builder: (column) => column);

  GeneratedColumn<String> get eventId =>
      $composableBuilder(column: $table.eventId, builder: (column) => column);

  GeneratedColumn<String> get productId =>
      $composableBuilder(column: $table.productId, builder: (column) => column);

  GeneratedColumn<int> get observedRevision => $composableBuilder(
    column: $table.observedRevision,
    builder: (column) => column,
  );

  GeneratedColumn<int> get quantityDelta => $composableBuilder(
    column: $table.quantityDelta,
    builder: (column) => column,
  );
}

class $$OfflineStockEffectsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $OfflineStockEffectsTable,
          OfflineStockEffectRow,
          $$OfflineStockEffectsTableFilterComposer,
          $$OfflineStockEffectsTableOrderingComposer,
          $$OfflineStockEffectsTableAnnotationComposer,
          $$OfflineStockEffectsTableCreateCompanionBuilder,
          $$OfflineStockEffectsTableUpdateCompanionBuilder,
          (
            OfflineStockEffectRow,
            BaseReferences<
              _$AppDatabase,
              $OfflineStockEffectsTable,
              OfflineStockEffectRow
            >,
          ),
          OfflineStockEffectRow,
          PrefetchHooks Function()
        > {
  $$OfflineStockEffectsTableTableManager(
    _$AppDatabase db,
    $OfflineStockEffectsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$OfflineStockEffectsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$OfflineStockEffectsTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$OfflineStockEffectsTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> organizationId = const Value.absent(),
                Value<String> branchId = const Value.absent(),
                Value<String> id = const Value.absent(),
                Value<String> actorId = const Value.absent(),
                Value<String> deviceId = const Value.absent(),
                Value<String> eventId = const Value.absent(),
                Value<String> productId = const Value.absent(),
                Value<int> observedRevision = const Value.absent(),
                Value<int> quantityDelta = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => OfflineStockEffectsCompanion(
                organizationId: organizationId,
                branchId: branchId,
                id: id,
                actorId: actorId,
                deviceId: deviceId,
                eventId: eventId,
                productId: productId,
                observedRevision: observedRevision,
                quantityDelta: quantityDelta,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String organizationId,
                required String branchId,
                required String id,
                required String actorId,
                required String deviceId,
                required String eventId,
                required String productId,
                required int observedRevision,
                required int quantityDelta,
                Value<int> rowid = const Value.absent(),
              }) => OfflineStockEffectsCompanion.insert(
                organizationId: organizationId,
                branchId: branchId,
                id: id,
                actorId: actorId,
                deviceId: deviceId,
                eventId: eventId,
                productId: productId,
                observedRevision: observedRevision,
                quantityDelta: quantityDelta,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$OfflineStockEffectsTable, OfflineStockEffectRow>(
                    table,
                  ),
                  BaseReferences<
                    _$AppDatabase,
                    $OfflineStockEffectsTable,
                    OfflineStockEffectRow
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$OfflineStockEffectsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $OfflineStockEffectsTable,
      OfflineStockEffectRow,
      $$OfflineStockEffectsTableFilterComposer,
      $$OfflineStockEffectsTableOrderingComposer,
      $$OfflineStockEffectsTableAnnotationComposer,
      $$OfflineStockEffectsTableCreateCompanionBuilder,
      $$OfflineStockEffectsTableUpdateCompanionBuilder,
      (
        OfflineStockEffectRow,
        BaseReferences<
          _$AppDatabase,
          $OfflineStockEffectsTable,
          OfflineStockEffectRow
        >,
      ),
      OfflineStockEffectRow,
      PrefetchHooks Function()
    >;
typedef $$OfflineAcceptanceLinksTableCreateCompanionBuilder =
    OfflineAcceptanceLinksCompanion Function({
      required String organizationId,
      required String branchId,
      required String id,
      required String actorId,
      required String deviceId,
      required String grantId,
      required int sequence,
      required String documentId,
      required String eventDigest,
      required String serverReceiptId,
      required String acceptedAtIso,
      required String receiptJson,
      Value<String?> reconciliationCode,
      Value<int> rowid,
    });
typedef $$OfflineAcceptanceLinksTableUpdateCompanionBuilder =
    OfflineAcceptanceLinksCompanion Function({
      Value<String> organizationId,
      Value<String> branchId,
      Value<String> id,
      Value<String> actorId,
      Value<String> deviceId,
      Value<String> grantId,
      Value<int> sequence,
      Value<String> documentId,
      Value<String> eventDigest,
      Value<String> serverReceiptId,
      Value<String> acceptedAtIso,
      Value<String> receiptJson,
      Value<String?> reconciliationCode,
      Value<int> rowid,
    });

class $$OfflineAcceptanceLinksTableFilterComposer
    extends Composer<_$AppDatabase, $OfflineAcceptanceLinksTable> {
  $$OfflineAcceptanceLinksTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get organizationId => $composableBuilder(
    column: $table.organizationId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get branchId => $composableBuilder(
    column: $table.branchId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get actorId => $composableBuilder(
    column: $table.actorId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get deviceId => $composableBuilder(
    column: $table.deviceId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get grantId => $composableBuilder(
    column: $table.grantId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get sequence => $composableBuilder(
    column: $table.sequence,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get documentId => $composableBuilder(
    column: $table.documentId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get eventDigest => $composableBuilder(
    column: $table.eventDigest,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get serverReceiptId => $composableBuilder(
    column: $table.serverReceiptId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get acceptedAtIso => $composableBuilder(
    column: $table.acceptedAtIso,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get receiptJson => $composableBuilder(
    column: $table.receiptJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get reconciliationCode => $composableBuilder(
    column: $table.reconciliationCode,
    builder: (column) => ColumnFilters(column),
  );
}

class $$OfflineAcceptanceLinksTableOrderingComposer
    extends Composer<_$AppDatabase, $OfflineAcceptanceLinksTable> {
  $$OfflineAcceptanceLinksTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get organizationId => $composableBuilder(
    column: $table.organizationId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get branchId => $composableBuilder(
    column: $table.branchId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get actorId => $composableBuilder(
    column: $table.actorId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get deviceId => $composableBuilder(
    column: $table.deviceId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get grantId => $composableBuilder(
    column: $table.grantId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get sequence => $composableBuilder(
    column: $table.sequence,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get documentId => $composableBuilder(
    column: $table.documentId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get eventDigest => $composableBuilder(
    column: $table.eventDigest,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get serverReceiptId => $composableBuilder(
    column: $table.serverReceiptId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get acceptedAtIso => $composableBuilder(
    column: $table.acceptedAtIso,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get receiptJson => $composableBuilder(
    column: $table.receiptJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get reconciliationCode => $composableBuilder(
    column: $table.reconciliationCode,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$OfflineAcceptanceLinksTableAnnotationComposer
    extends Composer<_$AppDatabase, $OfflineAcceptanceLinksTable> {
  $$OfflineAcceptanceLinksTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get organizationId => $composableBuilder(
    column: $table.organizationId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get branchId =>
      $composableBuilder(column: $table.branchId, builder: (column) => column);

  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get actorId =>
      $composableBuilder(column: $table.actorId, builder: (column) => column);

  GeneratedColumn<String> get deviceId =>
      $composableBuilder(column: $table.deviceId, builder: (column) => column);

  GeneratedColumn<String> get grantId =>
      $composableBuilder(column: $table.grantId, builder: (column) => column);

  GeneratedColumn<int> get sequence =>
      $composableBuilder(column: $table.sequence, builder: (column) => column);

  GeneratedColumn<String> get documentId => $composableBuilder(
    column: $table.documentId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get eventDigest => $composableBuilder(
    column: $table.eventDigest,
    builder: (column) => column,
  );

  GeneratedColumn<String> get serverReceiptId => $composableBuilder(
    column: $table.serverReceiptId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get acceptedAtIso => $composableBuilder(
    column: $table.acceptedAtIso,
    builder: (column) => column,
  );

  GeneratedColumn<String> get receiptJson => $composableBuilder(
    column: $table.receiptJson,
    builder: (column) => column,
  );

  GeneratedColumn<String> get reconciliationCode => $composableBuilder(
    column: $table.reconciliationCode,
    builder: (column) => column,
  );
}

class $$OfflineAcceptanceLinksTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $OfflineAcceptanceLinksTable,
          OfflineAcceptanceRow,
          $$OfflineAcceptanceLinksTableFilterComposer,
          $$OfflineAcceptanceLinksTableOrderingComposer,
          $$OfflineAcceptanceLinksTableAnnotationComposer,
          $$OfflineAcceptanceLinksTableCreateCompanionBuilder,
          $$OfflineAcceptanceLinksTableUpdateCompanionBuilder,
          (
            OfflineAcceptanceRow,
            BaseReferences<
              _$AppDatabase,
              $OfflineAcceptanceLinksTable,
              OfflineAcceptanceRow
            >,
          ),
          OfflineAcceptanceRow,
          PrefetchHooks Function()
        > {
  $$OfflineAcceptanceLinksTableTableManager(
    _$AppDatabase db,
    $OfflineAcceptanceLinksTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$OfflineAcceptanceLinksTableFilterComposer(
                $db: db,
                $table: table,
              ),
          createOrderingComposer: () =>
              $$OfflineAcceptanceLinksTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$OfflineAcceptanceLinksTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> organizationId = const Value.absent(),
                Value<String> branchId = const Value.absent(),
                Value<String> id = const Value.absent(),
                Value<String> actorId = const Value.absent(),
                Value<String> deviceId = const Value.absent(),
                Value<String> grantId = const Value.absent(),
                Value<int> sequence = const Value.absent(),
                Value<String> documentId = const Value.absent(),
                Value<String> eventDigest = const Value.absent(),
                Value<String> serverReceiptId = const Value.absent(),
                Value<String> acceptedAtIso = const Value.absent(),
                Value<String> receiptJson = const Value.absent(),
                Value<String?> reconciliationCode = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => OfflineAcceptanceLinksCompanion(
                organizationId: organizationId,
                branchId: branchId,
                id: id,
                actorId: actorId,
                deviceId: deviceId,
                grantId: grantId,
                sequence: sequence,
                documentId: documentId,
                eventDigest: eventDigest,
                serverReceiptId: serverReceiptId,
                acceptedAtIso: acceptedAtIso,
                receiptJson: receiptJson,
                reconciliationCode: reconciliationCode,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String organizationId,
                required String branchId,
                required String id,
                required String actorId,
                required String deviceId,
                required String grantId,
                required int sequence,
                required String documentId,
                required String eventDigest,
                required String serverReceiptId,
                required String acceptedAtIso,
                required String receiptJson,
                Value<String?> reconciliationCode = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => OfflineAcceptanceLinksCompanion.insert(
                organizationId: organizationId,
                branchId: branchId,
                id: id,
                actorId: actorId,
                deviceId: deviceId,
                grantId: grantId,
                sequence: sequence,
                documentId: documentId,
                eventDigest: eventDigest,
                serverReceiptId: serverReceiptId,
                acceptedAtIso: acceptedAtIso,
                receiptJson: receiptJson,
                reconciliationCode: reconciliationCode,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<
                    $OfflineAcceptanceLinksTable,
                    OfflineAcceptanceRow
                  >(table),
                  BaseReferences<
                    _$AppDatabase,
                    $OfflineAcceptanceLinksTable,
                    OfflineAcceptanceRow
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$OfflineAcceptanceLinksTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $OfflineAcceptanceLinksTable,
      OfflineAcceptanceRow,
      $$OfflineAcceptanceLinksTableFilterComposer,
      $$OfflineAcceptanceLinksTableOrderingComposer,
      $$OfflineAcceptanceLinksTableAnnotationComposer,
      $$OfflineAcceptanceLinksTableCreateCompanionBuilder,
      $$OfflineAcceptanceLinksTableUpdateCompanionBuilder,
      (
        OfflineAcceptanceRow,
        BaseReferences<
          _$AppDatabase,
          $OfflineAcceptanceLinksTable,
          OfflineAcceptanceRow
        >,
      ),
      OfflineAcceptanceRow,
      PrefetchHooks Function()
    >;
typedef $$OfflineStockAcceptancesTableCreateCompanionBuilder =
    OfflineStockAcceptancesCompanion Function({
      required String organizationId,
      required String branchId,
      required String id,
      required String actorId,
      required String deviceId,
      required String eventId,
      required String productId,
      required int revision,
      Value<int> rowid,
    });
typedef $$OfflineStockAcceptancesTableUpdateCompanionBuilder =
    OfflineStockAcceptancesCompanion Function({
      Value<String> organizationId,
      Value<String> branchId,
      Value<String> id,
      Value<String> actorId,
      Value<String> deviceId,
      Value<String> eventId,
      Value<String> productId,
      Value<int> revision,
      Value<int> rowid,
    });

class $$OfflineStockAcceptancesTableFilterComposer
    extends Composer<_$AppDatabase, $OfflineStockAcceptancesTable> {
  $$OfflineStockAcceptancesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get organizationId => $composableBuilder(
    column: $table.organizationId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get branchId => $composableBuilder(
    column: $table.branchId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get actorId => $composableBuilder(
    column: $table.actorId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get deviceId => $composableBuilder(
    column: $table.deviceId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get eventId => $composableBuilder(
    column: $table.eventId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get productId => $composableBuilder(
    column: $table.productId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get revision => $composableBuilder(
    column: $table.revision,
    builder: (column) => ColumnFilters(column),
  );
}

class $$OfflineStockAcceptancesTableOrderingComposer
    extends Composer<_$AppDatabase, $OfflineStockAcceptancesTable> {
  $$OfflineStockAcceptancesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get organizationId => $composableBuilder(
    column: $table.organizationId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get branchId => $composableBuilder(
    column: $table.branchId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get actorId => $composableBuilder(
    column: $table.actorId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get deviceId => $composableBuilder(
    column: $table.deviceId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get eventId => $composableBuilder(
    column: $table.eventId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get productId => $composableBuilder(
    column: $table.productId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get revision => $composableBuilder(
    column: $table.revision,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$OfflineStockAcceptancesTableAnnotationComposer
    extends Composer<_$AppDatabase, $OfflineStockAcceptancesTable> {
  $$OfflineStockAcceptancesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get organizationId => $composableBuilder(
    column: $table.organizationId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get branchId =>
      $composableBuilder(column: $table.branchId, builder: (column) => column);

  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get actorId =>
      $composableBuilder(column: $table.actorId, builder: (column) => column);

  GeneratedColumn<String> get deviceId =>
      $composableBuilder(column: $table.deviceId, builder: (column) => column);

  GeneratedColumn<String> get eventId =>
      $composableBuilder(column: $table.eventId, builder: (column) => column);

  GeneratedColumn<String> get productId =>
      $composableBuilder(column: $table.productId, builder: (column) => column);

  GeneratedColumn<int> get revision =>
      $composableBuilder(column: $table.revision, builder: (column) => column);
}

class $$OfflineStockAcceptancesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $OfflineStockAcceptancesTable,
          OfflineStockAcceptanceRow,
          $$OfflineStockAcceptancesTableFilterComposer,
          $$OfflineStockAcceptancesTableOrderingComposer,
          $$OfflineStockAcceptancesTableAnnotationComposer,
          $$OfflineStockAcceptancesTableCreateCompanionBuilder,
          $$OfflineStockAcceptancesTableUpdateCompanionBuilder,
          (
            OfflineStockAcceptanceRow,
            BaseReferences<
              _$AppDatabase,
              $OfflineStockAcceptancesTable,
              OfflineStockAcceptanceRow
            >,
          ),
          OfflineStockAcceptanceRow,
          PrefetchHooks Function()
        > {
  $$OfflineStockAcceptancesTableTableManager(
    _$AppDatabase db,
    $OfflineStockAcceptancesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$OfflineStockAcceptancesTableFilterComposer(
                $db: db,
                $table: table,
              ),
          createOrderingComposer: () =>
              $$OfflineStockAcceptancesTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$OfflineStockAcceptancesTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> organizationId = const Value.absent(),
                Value<String> branchId = const Value.absent(),
                Value<String> id = const Value.absent(),
                Value<String> actorId = const Value.absent(),
                Value<String> deviceId = const Value.absent(),
                Value<String> eventId = const Value.absent(),
                Value<String> productId = const Value.absent(),
                Value<int> revision = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => OfflineStockAcceptancesCompanion(
                organizationId: organizationId,
                branchId: branchId,
                id: id,
                actorId: actorId,
                deviceId: deviceId,
                eventId: eventId,
                productId: productId,
                revision: revision,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String organizationId,
                required String branchId,
                required String id,
                required String actorId,
                required String deviceId,
                required String eventId,
                required String productId,
                required int revision,
                Value<int> rowid = const Value.absent(),
              }) => OfflineStockAcceptancesCompanion.insert(
                organizationId: organizationId,
                branchId: branchId,
                id: id,
                actorId: actorId,
                deviceId: deviceId,
                eventId: eventId,
                productId: productId,
                revision: revision,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<
                    $OfflineStockAcceptancesTable,
                    OfflineStockAcceptanceRow
                  >(table),
                  BaseReferences<
                    _$AppDatabase,
                    $OfflineStockAcceptancesTable,
                    OfflineStockAcceptanceRow
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$OfflineStockAcceptancesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $OfflineStockAcceptancesTable,
      OfflineStockAcceptanceRow,
      $$OfflineStockAcceptancesTableFilterComposer,
      $$OfflineStockAcceptancesTableOrderingComposer,
      $$OfflineStockAcceptancesTableAnnotationComposer,
      $$OfflineStockAcceptancesTableCreateCompanionBuilder,
      $$OfflineStockAcceptancesTableUpdateCompanionBuilder,
      (
        OfflineStockAcceptanceRow,
        BaseReferences<
          _$AppDatabase,
          $OfflineStockAcceptancesTable,
          OfflineStockAcceptanceRow
        >,
      ),
      OfflineStockAcceptanceRow,
      PrefetchHooks Function()
    >;
typedef $$OfflinePreparationsTableCreateCompanionBuilder =
    OfflinePreparationsCompanion Function({
      required String organizationId,
      required String branchId,
      required String id,
      required String actorId,
      required String deviceId,
      required String grantJson,
      required String snapshotJson,
      required DateTime preparedAt,
      Value<int> rowid,
    });
typedef $$OfflinePreparationsTableUpdateCompanionBuilder =
    OfflinePreparationsCompanion Function({
      Value<String> organizationId,
      Value<String> branchId,
      Value<String> id,
      Value<String> actorId,
      Value<String> deviceId,
      Value<String> grantJson,
      Value<String> snapshotJson,
      Value<DateTime> preparedAt,
      Value<int> rowid,
    });

class $$OfflinePreparationsTableFilterComposer
    extends Composer<_$AppDatabase, $OfflinePreparationsTable> {
  $$OfflinePreparationsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get organizationId => $composableBuilder(
    column: $table.organizationId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get branchId => $composableBuilder(
    column: $table.branchId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get actorId => $composableBuilder(
    column: $table.actorId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get deviceId => $composableBuilder(
    column: $table.deviceId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get grantJson => $composableBuilder(
    column: $table.grantJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get snapshotJson => $composableBuilder(
    column: $table.snapshotJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get preparedAt => $composableBuilder(
    column: $table.preparedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$OfflinePreparationsTableOrderingComposer
    extends Composer<_$AppDatabase, $OfflinePreparationsTable> {
  $$OfflinePreparationsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get organizationId => $composableBuilder(
    column: $table.organizationId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get branchId => $composableBuilder(
    column: $table.branchId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get actorId => $composableBuilder(
    column: $table.actorId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get deviceId => $composableBuilder(
    column: $table.deviceId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get grantJson => $composableBuilder(
    column: $table.grantJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get snapshotJson => $composableBuilder(
    column: $table.snapshotJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get preparedAt => $composableBuilder(
    column: $table.preparedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$OfflinePreparationsTableAnnotationComposer
    extends Composer<_$AppDatabase, $OfflinePreparationsTable> {
  $$OfflinePreparationsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get organizationId => $composableBuilder(
    column: $table.organizationId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get branchId =>
      $composableBuilder(column: $table.branchId, builder: (column) => column);

  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get actorId =>
      $composableBuilder(column: $table.actorId, builder: (column) => column);

  GeneratedColumn<String> get deviceId =>
      $composableBuilder(column: $table.deviceId, builder: (column) => column);

  GeneratedColumn<String> get grantJson =>
      $composableBuilder(column: $table.grantJson, builder: (column) => column);

  GeneratedColumn<String> get snapshotJson => $composableBuilder(
    column: $table.snapshotJson,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get preparedAt => $composableBuilder(
    column: $table.preparedAt,
    builder: (column) => column,
  );
}

class $$OfflinePreparationsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $OfflinePreparationsTable,
          OfflinePreparationRow,
          $$OfflinePreparationsTableFilterComposer,
          $$OfflinePreparationsTableOrderingComposer,
          $$OfflinePreparationsTableAnnotationComposer,
          $$OfflinePreparationsTableCreateCompanionBuilder,
          $$OfflinePreparationsTableUpdateCompanionBuilder,
          (
            OfflinePreparationRow,
            BaseReferences<
              _$AppDatabase,
              $OfflinePreparationsTable,
              OfflinePreparationRow
            >,
          ),
          OfflinePreparationRow,
          PrefetchHooks Function()
        > {
  $$OfflinePreparationsTableTableManager(
    _$AppDatabase db,
    $OfflinePreparationsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$OfflinePreparationsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$OfflinePreparationsTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$OfflinePreparationsTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> organizationId = const Value.absent(),
                Value<String> branchId = const Value.absent(),
                Value<String> id = const Value.absent(),
                Value<String> actorId = const Value.absent(),
                Value<String> deviceId = const Value.absent(),
                Value<String> grantJson = const Value.absent(),
                Value<String> snapshotJson = const Value.absent(),
                Value<DateTime> preparedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => OfflinePreparationsCompanion(
                organizationId: organizationId,
                branchId: branchId,
                id: id,
                actorId: actorId,
                deviceId: deviceId,
                grantJson: grantJson,
                snapshotJson: snapshotJson,
                preparedAt: preparedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String organizationId,
                required String branchId,
                required String id,
                required String actorId,
                required String deviceId,
                required String grantJson,
                required String snapshotJson,
                required DateTime preparedAt,
                Value<int> rowid = const Value.absent(),
              }) => OfflinePreparationsCompanion.insert(
                organizationId: organizationId,
                branchId: branchId,
                id: id,
                actorId: actorId,
                deviceId: deviceId,
                grantJson: grantJson,
                snapshotJson: snapshotJson,
                preparedAt: preparedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$OfflinePreparationsTable, OfflinePreparationRow>(
                    table,
                  ),
                  BaseReferences<
                    _$AppDatabase,
                    $OfflinePreparationsTable,
                    OfflinePreparationRow
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$OfflinePreparationsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $OfflinePreparationsTable,
      OfflinePreparationRow,
      $$OfflinePreparationsTableFilterComposer,
      $$OfflinePreparationsTableOrderingComposer,
      $$OfflinePreparationsTableAnnotationComposer,
      $$OfflinePreparationsTableCreateCompanionBuilder,
      $$OfflinePreparationsTableUpdateCompanionBuilder,
      (
        OfflinePreparationRow,
        BaseReferences<
          _$AppDatabase,
          $OfflinePreparationsTable,
          OfflinePreparationRow
        >,
      ),
      OfflinePreparationRow,
      PrefetchHooks Function()
    >;
typedef $$OfflineGrantReleasesTableCreateCompanionBuilder =
    OfflineGrantReleasesCompanion Function({
      required String organizationId,
      required String branchId,
      required String id,
      required String actorId,
      required String deviceId,
      required int finalSequence,
      required DateTime releasedAt,
      Value<int> rowid,
    });
typedef $$OfflineGrantReleasesTableUpdateCompanionBuilder =
    OfflineGrantReleasesCompanion Function({
      Value<String> organizationId,
      Value<String> branchId,
      Value<String> id,
      Value<String> actorId,
      Value<String> deviceId,
      Value<int> finalSequence,
      Value<DateTime> releasedAt,
      Value<int> rowid,
    });

class $$OfflineGrantReleasesTableFilterComposer
    extends Composer<_$AppDatabase, $OfflineGrantReleasesTable> {
  $$OfflineGrantReleasesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get organizationId => $composableBuilder(
    column: $table.organizationId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get branchId => $composableBuilder(
    column: $table.branchId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get actorId => $composableBuilder(
    column: $table.actorId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get deviceId => $composableBuilder(
    column: $table.deviceId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get finalSequence => $composableBuilder(
    column: $table.finalSequence,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get releasedAt => $composableBuilder(
    column: $table.releasedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$OfflineGrantReleasesTableOrderingComposer
    extends Composer<_$AppDatabase, $OfflineGrantReleasesTable> {
  $$OfflineGrantReleasesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get organizationId => $composableBuilder(
    column: $table.organizationId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get branchId => $composableBuilder(
    column: $table.branchId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get actorId => $composableBuilder(
    column: $table.actorId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get deviceId => $composableBuilder(
    column: $table.deviceId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get finalSequence => $composableBuilder(
    column: $table.finalSequence,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get releasedAt => $composableBuilder(
    column: $table.releasedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$OfflineGrantReleasesTableAnnotationComposer
    extends Composer<_$AppDatabase, $OfflineGrantReleasesTable> {
  $$OfflineGrantReleasesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get organizationId => $composableBuilder(
    column: $table.organizationId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get branchId =>
      $composableBuilder(column: $table.branchId, builder: (column) => column);

  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get actorId =>
      $composableBuilder(column: $table.actorId, builder: (column) => column);

  GeneratedColumn<String> get deviceId =>
      $composableBuilder(column: $table.deviceId, builder: (column) => column);

  GeneratedColumn<int> get finalSequence => $composableBuilder(
    column: $table.finalSequence,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get releasedAt => $composableBuilder(
    column: $table.releasedAt,
    builder: (column) => column,
  );
}

class $$OfflineGrantReleasesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $OfflineGrantReleasesTable,
          OfflineGrantReleaseRow,
          $$OfflineGrantReleasesTableFilterComposer,
          $$OfflineGrantReleasesTableOrderingComposer,
          $$OfflineGrantReleasesTableAnnotationComposer,
          $$OfflineGrantReleasesTableCreateCompanionBuilder,
          $$OfflineGrantReleasesTableUpdateCompanionBuilder,
          (
            OfflineGrantReleaseRow,
            BaseReferences<
              _$AppDatabase,
              $OfflineGrantReleasesTable,
              OfflineGrantReleaseRow
            >,
          ),
          OfflineGrantReleaseRow,
          PrefetchHooks Function()
        > {
  $$OfflineGrantReleasesTableTableManager(
    _$AppDatabase db,
    $OfflineGrantReleasesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$OfflineGrantReleasesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$OfflineGrantReleasesTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$OfflineGrantReleasesTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> organizationId = const Value.absent(),
                Value<String> branchId = const Value.absent(),
                Value<String> id = const Value.absent(),
                Value<String> actorId = const Value.absent(),
                Value<String> deviceId = const Value.absent(),
                Value<int> finalSequence = const Value.absent(),
                Value<DateTime> releasedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => OfflineGrantReleasesCompanion(
                organizationId: organizationId,
                branchId: branchId,
                id: id,
                actorId: actorId,
                deviceId: deviceId,
                finalSequence: finalSequence,
                releasedAt: releasedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String organizationId,
                required String branchId,
                required String id,
                required String actorId,
                required String deviceId,
                required int finalSequence,
                required DateTime releasedAt,
                Value<int> rowid = const Value.absent(),
              }) => OfflineGrantReleasesCompanion.insert(
                organizationId: organizationId,
                branchId: branchId,
                id: id,
                actorId: actorId,
                deviceId: deviceId,
                finalSequence: finalSequence,
                releasedAt: releasedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<
                    $OfflineGrantReleasesTable,
                    OfflineGrantReleaseRow
                  >(table),
                  BaseReferences<
                    _$AppDatabase,
                    $OfflineGrantReleasesTable,
                    OfflineGrantReleaseRow
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$OfflineGrantReleasesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $OfflineGrantReleasesTable,
      OfflineGrantReleaseRow,
      $$OfflineGrantReleasesTableFilterComposer,
      $$OfflineGrantReleasesTableOrderingComposer,
      $$OfflineGrantReleasesTableAnnotationComposer,
      $$OfflineGrantReleasesTableCreateCompanionBuilder,
      $$OfflineGrantReleasesTableUpdateCompanionBuilder,
      (
        OfflineGrantReleaseRow,
        BaseReferences<
          _$AppDatabase,
          $OfflineGrantReleasesTable,
          OfflineGrantReleaseRow
        >,
      ),
      OfflineGrantReleaseRow,
      PrefetchHooks Function()
    >;

class $AppDatabaseManager {
  final _$AppDatabase _db;
  $AppDatabaseManager(this._db);
  $$LocalCategoriesTableTableManager get localCategories =>
      $$LocalCategoriesTableTableManager(_db, _db.localCategories);
  $$LocalProductsTableTableManager get localProducts =>
      $$LocalProductsTableTableManager(_db, _db.localProducts);
  $$LocalProductPricesTableTableManager get localProductPrices =>
      $$LocalProductPricesTableTableManager(_db, _db.localProductPrices);
  $$LocalInventorySnapshotsTableTableManager get localInventorySnapshots =>
      $$LocalInventorySnapshotsTableTableManager(
        _db,
        _db.localInventorySnapshots,
      );
  $$LocalCustomersTableTableManager get localCustomers =>
      $$LocalCustomersTableTableManager(_db, _db.localCustomers);
  $$LocalShiftsTableTableManager get localShifts =>
      $$LocalShiftsTableTableManager(_db, _db.localShifts);
  $$LocalSalesTableTableManager get localSales =>
      $$LocalSalesTableTableManager(_db, _db.localSales);
  $$LocalSaleItemsTableTableManager get localSaleItems =>
      $$LocalSaleItemsTableTableManager(_db, _db.localSaleItems);
  $$LocalPaymentsTableTableManager get localPayments =>
      $$LocalPaymentsTableTableManager(_db, _db.localPayments);
  $$SyncOutboxTableTableManager get syncOutbox =>
      $$SyncOutboxTableTableManager(_db, _db.syncOutbox);
  $$SyncCursorsTableTableManager get syncCursors =>
      $$SyncCursorsTableTableManager(_db, _db.syncCursors);
  $$OfflineEventAuthorizationsTableTableManager
  get offlineEventAuthorizations =>
      $$OfflineEventAuthorizationsTableTableManager(
        _db,
        _db.offlineEventAuthorizations,
      );
  $$OfflineCacheRecordsTableTableManager get offlineCacheRecords =>
      $$OfflineCacheRecordsTableTableManager(_db, _db.offlineCacheRecords);
  $$OfflineCacheStatesTableTableManager get offlineCacheStates =>
      $$OfflineCacheStatesTableTableManager(_db, _db.offlineCacheStates);
  $$OfflineStockEffectsTableTableManager get offlineStockEffects =>
      $$OfflineStockEffectsTableTableManager(_db, _db.offlineStockEffects);
  $$OfflineAcceptanceLinksTableTableManager get offlineAcceptanceLinks =>
      $$OfflineAcceptanceLinksTableTableManager(
        _db,
        _db.offlineAcceptanceLinks,
      );
  $$OfflineStockAcceptancesTableTableManager get offlineStockAcceptances =>
      $$OfflineStockAcceptancesTableTableManager(
        _db,
        _db.offlineStockAcceptances,
      );
  $$OfflinePreparationsTableTableManager get offlinePreparations =>
      $$OfflinePreparationsTableTableManager(_db, _db.offlinePreparations);
  $$OfflineGrantReleasesTableTableManager get offlineGrantReleases =>
      $$OfflineGrantReleasesTableTableManager(_db, _db.offlineGrantReleases);
}
