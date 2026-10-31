// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'app_database.dart';

// ignore_for_file: type=lint
class $PersonsTable extends Persons with TableInfo<$PersonsTable, PersonRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $PersonsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _avatarFaceIdMeta = const VerificationMeta(
    'avatarFaceId',
  );
  @override
  late final GeneratedColumn<int> avatarFaceId = GeneratedColumn<int>(
    'avatar_face_id',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<int> createdAt = GeneratedColumn<int>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _hiddenMeta = const VerificationMeta('hidden');
  @override
  late final GeneratedColumn<bool> hidden = GeneratedColumn<bool>(
    'hidden',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("hidden" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _favoriteMeta = const VerificationMeta(
    'favorite',
  );
  @override
  late final GeneratedColumn<bool> favorite = GeneratedColumn<bool>(
    'favorite',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("favorite" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _pinnedMeta = const VerificationMeta('pinned');
  @override
  late final GeneratedColumn<bool> pinned = GeneratedColumn<bool>(
    'pinned',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("pinned" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _groupingLockedMeta = const VerificationMeta(
    'groupingLocked',
  );
  @override
  late final GeneratedColumn<bool> groupingLocked = GeneratedColumn<bool>(
    'grouping_locked',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("grouping_locked" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    name,
    avatarFaceId,
    createdAt,
    hidden,
    favorite,
    pinned,
    groupingLocked,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'persons';
  @override
  VerificationContext validateIntegrity(
    Insertable<PersonRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    }
    if (data.containsKey('avatar_face_id')) {
      context.handle(
        _avatarFaceIdMeta,
        avatarFaceId.isAcceptableOrUnknown(
          data['avatar_face_id']!,
          _avatarFaceIdMeta,
        ),
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
    if (data.containsKey('hidden')) {
      context.handle(
        _hiddenMeta,
        hidden.isAcceptableOrUnknown(data['hidden']!, _hiddenMeta),
      );
    }
    if (data.containsKey('favorite')) {
      context.handle(
        _favoriteMeta,
        favorite.isAcceptableOrUnknown(data['favorite']!, _favoriteMeta),
      );
    }
    if (data.containsKey('pinned')) {
      context.handle(
        _pinnedMeta,
        pinned.isAcceptableOrUnknown(data['pinned']!, _pinnedMeta),
      );
    }
    if (data.containsKey('grouping_locked')) {
      context.handle(
        _groupingLockedMeta,
        groupingLocked.isAcceptableOrUnknown(
          data['grouping_locked']!,
          _groupingLockedMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  PersonRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return PersonRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      ),
      avatarFaceId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}avatar_face_id'],
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}created_at'],
      )!,
      hidden: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}hidden'],
      )!,
      favorite: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}favorite'],
      )!,
      pinned: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}pinned'],
      )!,
      groupingLocked: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}grouping_locked'],
      )!,
    );
  }

  @override
  $PersonsTable createAlias(String alias) {
    return $PersonsTable(attachedDatabase, alias);
  }
}

class PersonRow extends DataClass implements Insertable<PersonRow> {
  final int id;
  final String? name;
  final int? avatarFaceId;
  final int createdAt;
  final bool hidden;
  final bool favorite;
  final bool pinned;
  final bool groupingLocked;
  const PersonRow({
    required this.id,
    this.name,
    this.avatarFaceId,
    required this.createdAt,
    required this.hidden,
    required this.favorite,
    required this.pinned,
    required this.groupingLocked,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    if (!nullToAbsent || name != null) {
      map['name'] = Variable<String>(name);
    }
    if (!nullToAbsent || avatarFaceId != null) {
      map['avatar_face_id'] = Variable<int>(avatarFaceId);
    }
    map['created_at'] = Variable<int>(createdAt);
    map['hidden'] = Variable<bool>(hidden);
    map['favorite'] = Variable<bool>(favorite);
    map['pinned'] = Variable<bool>(pinned);
    map['grouping_locked'] = Variable<bool>(groupingLocked);
    return map;
  }

  PersonsCompanion toCompanion(bool nullToAbsent) {
    return PersonsCompanion(
      id: Value(id),
      name: name == null && nullToAbsent ? const Value.absent() : Value(name),
      avatarFaceId: avatarFaceId == null && nullToAbsent
          ? const Value.absent()
          : Value(avatarFaceId),
      createdAt: Value(createdAt),
      hidden: Value(hidden),
      favorite: Value(favorite),
      pinned: Value(pinned),
      groupingLocked: Value(groupingLocked),
    );
  }

  factory PersonRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return PersonRow(
      id: serializer.fromJson<int>(json['id']),
      name: serializer.fromJson<String?>(json['name']),
      avatarFaceId: serializer.fromJson<int?>(json['avatarFaceId']),
      createdAt: serializer.fromJson<int>(json['createdAt']),
      hidden: serializer.fromJson<bool>(json['hidden']),
      favorite: serializer.fromJson<bool>(json['favorite']),
      pinned: serializer.fromJson<bool>(json['pinned']),
      groupingLocked: serializer.fromJson<bool>(json['groupingLocked']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'name': serializer.toJson<String?>(name),
      'avatarFaceId': serializer.toJson<int?>(avatarFaceId),
      'createdAt': serializer.toJson<int>(createdAt),
      'hidden': serializer.toJson<bool>(hidden),
      'favorite': serializer.toJson<bool>(favorite),
      'pinned': serializer.toJson<bool>(pinned),
      'groupingLocked': serializer.toJson<bool>(groupingLocked),
    };
  }

  PersonRow copyWith({
    int? id,
    Value<String?> name = const Value.absent(),
    Value<int?> avatarFaceId = const Value.absent(),
    int? createdAt,
    bool? hidden,
    bool? favorite,
    bool? pinned,
    bool? groupingLocked,
  }) => PersonRow(
    id: id ?? this.id,
    name: name.present ? name.value : this.name,
    avatarFaceId: avatarFaceId.present ? avatarFaceId.value : this.avatarFaceId,
    createdAt: createdAt ?? this.createdAt,
    hidden: hidden ?? this.hidden,
    favorite: favorite ?? this.favorite,
    pinned: pinned ?? this.pinned,
    groupingLocked: groupingLocked ?? this.groupingLocked,
  );
  PersonRow copyWithCompanion(PersonsCompanion data) {
    return PersonRow(
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      avatarFaceId: data.avatarFaceId.present
          ? data.avatarFaceId.value
          : this.avatarFaceId,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      hidden: data.hidden.present ? data.hidden.value : this.hidden,
      favorite: data.favorite.present ? data.favorite.value : this.favorite,
      pinned: data.pinned.present ? data.pinned.value : this.pinned,
      groupingLocked: data.groupingLocked.present
          ? data.groupingLocked.value
          : this.groupingLocked,
    );
  }

  @override
  String toString() {
    return (StringBuffer('PersonRow(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('avatarFaceId: $avatarFaceId, ')
          ..write('createdAt: $createdAt, ')
          ..write('hidden: $hidden, ')
          ..write('favorite: $favorite, ')
          ..write('pinned: $pinned, ')
          ..write('groupingLocked: $groupingLocked')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    name,
    avatarFaceId,
    createdAt,
    hidden,
    favorite,
    pinned,
    groupingLocked,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is PersonRow &&
          other.id == this.id &&
          other.name == this.name &&
          other.avatarFaceId == this.avatarFaceId &&
          other.createdAt == this.createdAt &&
          other.hidden == this.hidden &&
          other.favorite == this.favorite &&
          other.pinned == this.pinned &&
          other.groupingLocked == this.groupingLocked);
}

class PersonsCompanion extends UpdateCompanion<PersonRow> {
  final Value<int> id;
  final Value<String?> name;
  final Value<int?> avatarFaceId;
  final Value<int> createdAt;
  final Value<bool> hidden;
  final Value<bool> favorite;
  final Value<bool> pinned;
  final Value<bool> groupingLocked;
  const PersonsCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.avatarFaceId = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.hidden = const Value.absent(),
    this.favorite = const Value.absent(),
    this.pinned = const Value.absent(),
    this.groupingLocked = const Value.absent(),
  });
  PersonsCompanion.insert({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.avatarFaceId = const Value.absent(),
    required int createdAt,
    this.hidden = const Value.absent(),
    this.favorite = const Value.absent(),
    this.pinned = const Value.absent(),
    this.groupingLocked = const Value.absent(),
  }) : createdAt = Value(createdAt);
  static Insertable<PersonRow> custom({
    Expression<int>? id,
    Expression<String>? name,
    Expression<int>? avatarFaceId,
    Expression<int>? createdAt,
    Expression<bool>? hidden,
    Expression<bool>? favorite,
    Expression<bool>? pinned,
    Expression<bool>? groupingLocked,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (avatarFaceId != null) 'avatar_face_id': avatarFaceId,
      if (createdAt != null) 'created_at': createdAt,
      if (hidden != null) 'hidden': hidden,
      if (favorite != null) 'favorite': favorite,
      if (pinned != null) 'pinned': pinned,
      if (groupingLocked != null) 'grouping_locked': groupingLocked,
    });
  }

  PersonsCompanion copyWith({
    Value<int>? id,
    Value<String?>? name,
    Value<int?>? avatarFaceId,
    Value<int>? createdAt,
    Value<bool>? hidden,
    Value<bool>? favorite,
    Value<bool>? pinned,
    Value<bool>? groupingLocked,
  }) {
    return PersonsCompanion(
      id: id ?? this.id,
      name: name ?? this.name,
      avatarFaceId: avatarFaceId ?? this.avatarFaceId,
      createdAt: createdAt ?? this.createdAt,
      hidden: hidden ?? this.hidden,
      favorite: favorite ?? this.favorite,
      pinned: pinned ?? this.pinned,
      groupingLocked: groupingLocked ?? this.groupingLocked,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (avatarFaceId.present) {
      map['avatar_face_id'] = Variable<int>(avatarFaceId.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<int>(createdAt.value);
    }
    if (hidden.present) {
      map['hidden'] = Variable<bool>(hidden.value);
    }
    if (favorite.present) {
      map['favorite'] = Variable<bool>(favorite.value);
    }
    if (pinned.present) {
      map['pinned'] = Variable<bool>(pinned.value);
    }
    if (groupingLocked.present) {
      map['grouping_locked'] = Variable<bool>(groupingLocked.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('PersonsCompanion(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('avatarFaceId: $avatarFaceId, ')
          ..write('createdAt: $createdAt, ')
          ..write('hidden: $hidden, ')
          ..write('favorite: $favorite, ')
          ..write('pinned: $pinned, ')
          ..write('groupingLocked: $groupingLocked')
          ..write(')'))
        .toString();
  }
}

class $MediaTable extends Media with TableInfo<$MediaTable, MediaRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $MediaTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _assetIdMeta = const VerificationMeta(
    'assetId',
  );
  @override
  late final GeneratedColumn<String> assetId = GeneratedColumn<String>(
    'asset_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways('UNIQUE'),
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
  static const VerificationMeta _sizeBytesMeta = const VerificationMeta(
    'sizeBytes',
  );
  @override
  late final GeneratedColumn<int> sizeBytes = GeneratedColumn<int>(
    'size_bytes',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _modifiedAtMeta = const VerificationMeta(
    'modifiedAt',
  );
  @override
  late final GeneratedColumn<int> modifiedAt = GeneratedColumn<int>(
    'modified_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _widthMeta = const VerificationMeta('width');
  @override
  late final GeneratedColumn<int> width = GeneratedColumn<int>(
    'width',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _heightMeta = const VerificationMeta('height');
  @override
  late final GeneratedColumn<int> height = GeneratedColumn<int>(
    'height',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _durationMsMeta = const VerificationMeta(
    'durationMs',
  );
  @override
  late final GeneratedColumn<int> durationMs = GeneratedColumn<int>(
    'duration_ms',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _scanStatusMeta = const VerificationMeta(
    'scanStatus',
  );
  @override
  late final GeneratedColumn<String> scanStatus = GeneratedColumn<String>(
    'scan_status',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('pending'),
  );
  static const VerificationMeta _scanVersionMeta = const VerificationMeta(
    'scanVersion',
  );
  @override
  late final GeneratedColumn<int> scanVersion = GeneratedColumn<int>(
    'scan_version',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _lastScannedFrameMeta = const VerificationMeta(
    'lastScannedFrame',
  );
  @override
  late final GeneratedColumn<int> lastScannedFrame = GeneratedColumn<int>(
    'last_scanned_frame',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _scannedAtMeta = const VerificationMeta(
    'scannedAt',
  );
  @override
  late final GeneratedColumn<int> scannedAt = GeneratedColumn<int>(
    'scanned_at',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _takenAtMeta = const VerificationMeta(
    'takenAt',
  );
  @override
  late final GeneratedColumn<int> takenAt = GeneratedColumn<int>(
    'taken_at',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _scanAttemptsMeta = const VerificationMeta(
    'scanAttempts',
  );
  @override
  late final GeneratedColumn<int> scanAttempts = GeneratedColumn<int>(
    'scan_attempts',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _scanErrorMeta = const VerificationMeta(
    'scanError',
  );
  @override
  late final GeneratedColumn<String> scanError = GeneratedColumn<String>(
    'scan_error',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _illustratedMeta = const VerificationMeta(
    'illustrated',
  );
  @override
  late final GeneratedColumn<bool> illustrated = GeneratedColumn<bool>(
    'illustrated',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("illustrated" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    assetId,
    kind,
    sizeBytes,
    modifiedAt,
    width,
    height,
    durationMs,
    scanStatus,
    scanVersion,
    lastScannedFrame,
    scannedAt,
    takenAt,
    scanAttempts,
    scanError,
    illustrated,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'media';
  @override
  VerificationContext validateIntegrity(
    Insertable<MediaRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('asset_id')) {
      context.handle(
        _assetIdMeta,
        assetId.isAcceptableOrUnknown(data['asset_id']!, _assetIdMeta),
      );
    } else if (isInserting) {
      context.missing(_assetIdMeta);
    }
    if (data.containsKey('kind')) {
      context.handle(
        _kindMeta,
        kind.isAcceptableOrUnknown(data['kind']!, _kindMeta),
      );
    } else if (isInserting) {
      context.missing(_kindMeta);
    }
    if (data.containsKey('size_bytes')) {
      context.handle(
        _sizeBytesMeta,
        sizeBytes.isAcceptableOrUnknown(data['size_bytes']!, _sizeBytesMeta),
      );
    }
    if (data.containsKey('modified_at')) {
      context.handle(
        _modifiedAtMeta,
        modifiedAt.isAcceptableOrUnknown(data['modified_at']!, _modifiedAtMeta),
      );
    }
    if (data.containsKey('width')) {
      context.handle(
        _widthMeta,
        width.isAcceptableOrUnknown(data['width']!, _widthMeta),
      );
    }
    if (data.containsKey('height')) {
      context.handle(
        _heightMeta,
        height.isAcceptableOrUnknown(data['height']!, _heightMeta),
      );
    }
    if (data.containsKey('duration_ms')) {
      context.handle(
        _durationMsMeta,
        durationMs.isAcceptableOrUnknown(data['duration_ms']!, _durationMsMeta),
      );
    }
    if (data.containsKey('scan_status')) {
      context.handle(
        _scanStatusMeta,
        scanStatus.isAcceptableOrUnknown(data['scan_status']!, _scanStatusMeta),
      );
    }
    if (data.containsKey('scan_version')) {
      context.handle(
        _scanVersionMeta,
        scanVersion.isAcceptableOrUnknown(
          data['scan_version']!,
          _scanVersionMeta,
        ),
      );
    }
    if (data.containsKey('last_scanned_frame')) {
      context.handle(
        _lastScannedFrameMeta,
        lastScannedFrame.isAcceptableOrUnknown(
          data['last_scanned_frame']!,
          _lastScannedFrameMeta,
        ),
      );
    }
    if (data.containsKey('scanned_at')) {
      context.handle(
        _scannedAtMeta,
        scannedAt.isAcceptableOrUnknown(data['scanned_at']!, _scannedAtMeta),
      );
    }
    if (data.containsKey('taken_at')) {
      context.handle(
        _takenAtMeta,
        takenAt.isAcceptableOrUnknown(data['taken_at']!, _takenAtMeta),
      );
    }
    if (data.containsKey('scan_attempts')) {
      context.handle(
        _scanAttemptsMeta,
        scanAttempts.isAcceptableOrUnknown(
          data['scan_attempts']!,
          _scanAttemptsMeta,
        ),
      );
    }
    if (data.containsKey('scan_error')) {
      context.handle(
        _scanErrorMeta,
        scanError.isAcceptableOrUnknown(data['scan_error']!, _scanErrorMeta),
      );
    }
    if (data.containsKey('illustrated')) {
      context.handle(
        _illustratedMeta,
        illustrated.isAcceptableOrUnknown(
          data['illustrated']!,
          _illustratedMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  MediaRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return MediaRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      assetId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}asset_id'],
      )!,
      kind: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}kind'],
      )!,
      sizeBytes: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}size_bytes'],
      )!,
      modifiedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}modified_at'],
      )!,
      width: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}width'],
      ),
      height: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}height'],
      ),
      durationMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}duration_ms'],
      ),
      scanStatus: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}scan_status'],
      )!,
      scanVersion: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}scan_version'],
      )!,
      lastScannedFrame: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}last_scanned_frame'],
      )!,
      scannedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}scanned_at'],
      ),
      takenAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}taken_at'],
      ),
      scanAttempts: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}scan_attempts'],
      )!,
      scanError: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}scan_error'],
      ),
      illustrated: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}illustrated'],
      )!,
    );
  }

  @override
  $MediaTable createAlias(String alias) {
    return $MediaTable(attachedDatabase, alias);
  }
}

class MediaRow extends DataClass implements Insertable<MediaRow> {
  final int id;
  final String assetId;
  final String kind;
  final int sizeBytes;
  final int modifiedAt;
  final int? width;
  final int? height;
  final int? durationMs;
  final String scanStatus;
  final int scanVersion;
  final int lastScannedFrame;
  final int? scannedAt;
  final int? takenAt;
  final int scanAttempts;
  final String? scanError;
  final bool illustrated;
  const MediaRow({
    required this.id,
    required this.assetId,
    required this.kind,
    required this.sizeBytes,
    required this.modifiedAt,
    this.width,
    this.height,
    this.durationMs,
    required this.scanStatus,
    required this.scanVersion,
    required this.lastScannedFrame,
    this.scannedAt,
    this.takenAt,
    required this.scanAttempts,
    this.scanError,
    required this.illustrated,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['asset_id'] = Variable<String>(assetId);
    map['kind'] = Variable<String>(kind);
    map['size_bytes'] = Variable<int>(sizeBytes);
    map['modified_at'] = Variable<int>(modifiedAt);
    if (!nullToAbsent || width != null) {
      map['width'] = Variable<int>(width);
    }
    if (!nullToAbsent || height != null) {
      map['height'] = Variable<int>(height);
    }
    if (!nullToAbsent || durationMs != null) {
      map['duration_ms'] = Variable<int>(durationMs);
    }
    map['scan_status'] = Variable<String>(scanStatus);
    map['scan_version'] = Variable<int>(scanVersion);
    map['last_scanned_frame'] = Variable<int>(lastScannedFrame);
    if (!nullToAbsent || scannedAt != null) {
      map['scanned_at'] = Variable<int>(scannedAt);
    }
    if (!nullToAbsent || takenAt != null) {
      map['taken_at'] = Variable<int>(takenAt);
    }
    map['scan_attempts'] = Variable<int>(scanAttempts);
    if (!nullToAbsent || scanError != null) {
      map['scan_error'] = Variable<String>(scanError);
    }
    map['illustrated'] = Variable<bool>(illustrated);
    return map;
  }

  MediaCompanion toCompanion(bool nullToAbsent) {
    return MediaCompanion(
      id: Value(id),
      assetId: Value(assetId),
      kind: Value(kind),
      sizeBytes: Value(sizeBytes),
      modifiedAt: Value(modifiedAt),
      width: width == null && nullToAbsent
          ? const Value.absent()
          : Value(width),
      height: height == null && nullToAbsent
          ? const Value.absent()
          : Value(height),
      durationMs: durationMs == null && nullToAbsent
          ? const Value.absent()
          : Value(durationMs),
      scanStatus: Value(scanStatus),
      scanVersion: Value(scanVersion),
      lastScannedFrame: Value(lastScannedFrame),
      scannedAt: scannedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(scannedAt),
      takenAt: takenAt == null && nullToAbsent
          ? const Value.absent()
          : Value(takenAt),
      scanAttempts: Value(scanAttempts),
      scanError: scanError == null && nullToAbsent
          ? const Value.absent()
          : Value(scanError),
      illustrated: Value(illustrated),
    );
  }

  factory MediaRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return MediaRow(
      id: serializer.fromJson<int>(json['id']),
      assetId: serializer.fromJson<String>(json['assetId']),
      kind: serializer.fromJson<String>(json['kind']),
      sizeBytes: serializer.fromJson<int>(json['sizeBytes']),
      modifiedAt: serializer.fromJson<int>(json['modifiedAt']),
      width: serializer.fromJson<int?>(json['width']),
      height: serializer.fromJson<int?>(json['height']),
      durationMs: serializer.fromJson<int?>(json['durationMs']),
      scanStatus: serializer.fromJson<String>(json['scanStatus']),
      scanVersion: serializer.fromJson<int>(json['scanVersion']),
      lastScannedFrame: serializer.fromJson<int>(json['lastScannedFrame']),
      scannedAt: serializer.fromJson<int?>(json['scannedAt']),
      takenAt: serializer.fromJson<int?>(json['takenAt']),
      scanAttempts: serializer.fromJson<int>(json['scanAttempts']),
      scanError: serializer.fromJson<String?>(json['scanError']),
      illustrated: serializer.fromJson<bool>(json['illustrated']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'assetId': serializer.toJson<String>(assetId),
      'kind': serializer.toJson<String>(kind),
      'sizeBytes': serializer.toJson<int>(sizeBytes),
      'modifiedAt': serializer.toJson<int>(modifiedAt),
      'width': serializer.toJson<int?>(width),
      'height': serializer.toJson<int?>(height),
      'durationMs': serializer.toJson<int?>(durationMs),
      'scanStatus': serializer.toJson<String>(scanStatus),
      'scanVersion': serializer.toJson<int>(scanVersion),
      'lastScannedFrame': serializer.toJson<int>(lastScannedFrame),
      'scannedAt': serializer.toJson<int?>(scannedAt),
      'takenAt': serializer.toJson<int?>(takenAt),
      'scanAttempts': serializer.toJson<int>(scanAttempts),
      'scanError': serializer.toJson<String?>(scanError),
      'illustrated': serializer.toJson<bool>(illustrated),
    };
  }

  MediaRow copyWith({
    int? id,
    String? assetId,
    String? kind,
    int? sizeBytes,
    int? modifiedAt,
    Value<int?> width = const Value.absent(),
    Value<int?> height = const Value.absent(),
    Value<int?> durationMs = const Value.absent(),
    String? scanStatus,
    int? scanVersion,
    int? lastScannedFrame,
    Value<int?> scannedAt = const Value.absent(),
    Value<int?> takenAt = const Value.absent(),
    int? scanAttempts,
    Value<String?> scanError = const Value.absent(),
    bool? illustrated,
  }) => MediaRow(
    id: id ?? this.id,
    assetId: assetId ?? this.assetId,
    kind: kind ?? this.kind,
    sizeBytes: sizeBytes ?? this.sizeBytes,
    modifiedAt: modifiedAt ?? this.modifiedAt,
    width: width.present ? width.value : this.width,
    height: height.present ? height.value : this.height,
    durationMs: durationMs.present ? durationMs.value : this.durationMs,
    scanStatus: scanStatus ?? this.scanStatus,
    scanVersion: scanVersion ?? this.scanVersion,
    lastScannedFrame: lastScannedFrame ?? this.lastScannedFrame,
    scannedAt: scannedAt.present ? scannedAt.value : this.scannedAt,
    takenAt: takenAt.present ? takenAt.value : this.takenAt,
    scanAttempts: scanAttempts ?? this.scanAttempts,
    scanError: scanError.present ? scanError.value : this.scanError,
    illustrated: illustrated ?? this.illustrated,
  );
  MediaRow copyWithCompanion(MediaCompanion data) {
    return MediaRow(
      id: data.id.present ? data.id.value : this.id,
      assetId: data.assetId.present ? data.assetId.value : this.assetId,
      kind: data.kind.present ? data.kind.value : this.kind,
      sizeBytes: data.sizeBytes.present ? data.sizeBytes.value : this.sizeBytes,
      modifiedAt: data.modifiedAt.present
          ? data.modifiedAt.value
          : this.modifiedAt,
      width: data.width.present ? data.width.value : this.width,
      height: data.height.present ? data.height.value : this.height,
      durationMs: data.durationMs.present
          ? data.durationMs.value
          : this.durationMs,
      scanStatus: data.scanStatus.present
          ? data.scanStatus.value
          : this.scanStatus,
      scanVersion: data.scanVersion.present
          ? data.scanVersion.value
          : this.scanVersion,
      lastScannedFrame: data.lastScannedFrame.present
          ? data.lastScannedFrame.value
          : this.lastScannedFrame,
      scannedAt: data.scannedAt.present ? data.scannedAt.value : this.scannedAt,
      takenAt: data.takenAt.present ? data.takenAt.value : this.takenAt,
      scanAttempts: data.scanAttempts.present
          ? data.scanAttempts.value
          : this.scanAttempts,
      scanError: data.scanError.present ? data.scanError.value : this.scanError,
      illustrated: data.illustrated.present
          ? data.illustrated.value
          : this.illustrated,
    );
  }

  @override
  String toString() {
    return (StringBuffer('MediaRow(')
          ..write('id: $id, ')
          ..write('assetId: $assetId, ')
          ..write('kind: $kind, ')
          ..write('sizeBytes: $sizeBytes, ')
          ..write('modifiedAt: $modifiedAt, ')
          ..write('width: $width, ')
          ..write('height: $height, ')
          ..write('durationMs: $durationMs, ')
          ..write('scanStatus: $scanStatus, ')
          ..write('scanVersion: $scanVersion, ')
          ..write('lastScannedFrame: $lastScannedFrame, ')
          ..write('scannedAt: $scannedAt, ')
          ..write('takenAt: $takenAt, ')
          ..write('scanAttempts: $scanAttempts, ')
          ..write('scanError: $scanError, ')
          ..write('illustrated: $illustrated')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    assetId,
    kind,
    sizeBytes,
    modifiedAt,
    width,
    height,
    durationMs,
    scanStatus,
    scanVersion,
    lastScannedFrame,
    scannedAt,
    takenAt,
    scanAttempts,
    scanError,
    illustrated,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is MediaRow &&
          other.id == this.id &&
          other.assetId == this.assetId &&
          other.kind == this.kind &&
          other.sizeBytes == this.sizeBytes &&
          other.modifiedAt == this.modifiedAt &&
          other.width == this.width &&
          other.height == this.height &&
          other.durationMs == this.durationMs &&
          other.scanStatus == this.scanStatus &&
          other.scanVersion == this.scanVersion &&
          other.lastScannedFrame == this.lastScannedFrame &&
          other.scannedAt == this.scannedAt &&
          other.takenAt == this.takenAt &&
          other.scanAttempts == this.scanAttempts &&
          other.scanError == this.scanError &&
          other.illustrated == this.illustrated);
}

class MediaCompanion extends UpdateCompanion<MediaRow> {
  final Value<int> id;
  final Value<String> assetId;
  final Value<String> kind;
  final Value<int> sizeBytes;
  final Value<int> modifiedAt;
  final Value<int?> width;
  final Value<int?> height;
  final Value<int?> durationMs;
  final Value<String> scanStatus;
  final Value<int> scanVersion;
  final Value<int> lastScannedFrame;
  final Value<int?> scannedAt;
  final Value<int?> takenAt;
  final Value<int> scanAttempts;
  final Value<String?> scanError;
  final Value<bool> illustrated;
  const MediaCompanion({
    this.id = const Value.absent(),
    this.assetId = const Value.absent(),
    this.kind = const Value.absent(),
    this.sizeBytes = const Value.absent(),
    this.modifiedAt = const Value.absent(),
    this.width = const Value.absent(),
    this.height = const Value.absent(),
    this.durationMs = const Value.absent(),
    this.scanStatus = const Value.absent(),
    this.scanVersion = const Value.absent(),
    this.lastScannedFrame = const Value.absent(),
    this.scannedAt = const Value.absent(),
    this.takenAt = const Value.absent(),
    this.scanAttempts = const Value.absent(),
    this.scanError = const Value.absent(),
    this.illustrated = const Value.absent(),
  });
  MediaCompanion.insert({
    this.id = const Value.absent(),
    required String assetId,
    required String kind,
    this.sizeBytes = const Value.absent(),
    this.modifiedAt = const Value.absent(),
    this.width = const Value.absent(),
    this.height = const Value.absent(),
    this.durationMs = const Value.absent(),
    this.scanStatus = const Value.absent(),
    this.scanVersion = const Value.absent(),
    this.lastScannedFrame = const Value.absent(),
    this.scannedAt = const Value.absent(),
    this.takenAt = const Value.absent(),
    this.scanAttempts = const Value.absent(),
    this.scanError = const Value.absent(),
    this.illustrated = const Value.absent(),
  }) : assetId = Value(assetId),
       kind = Value(kind);
  static Insertable<MediaRow> custom({
    Expression<int>? id,
    Expression<String>? assetId,
    Expression<String>? kind,
    Expression<int>? sizeBytes,
    Expression<int>? modifiedAt,
    Expression<int>? width,
    Expression<int>? height,
    Expression<int>? durationMs,
    Expression<String>? scanStatus,
    Expression<int>? scanVersion,
    Expression<int>? lastScannedFrame,
    Expression<int>? scannedAt,
    Expression<int>? takenAt,
    Expression<int>? scanAttempts,
    Expression<String>? scanError,
    Expression<bool>? illustrated,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (assetId != null) 'asset_id': assetId,
      if (kind != null) 'kind': kind,
      if (sizeBytes != null) 'size_bytes': sizeBytes,
      if (modifiedAt != null) 'modified_at': modifiedAt,
      if (width != null) 'width': width,
      if (height != null) 'height': height,
      if (durationMs != null) 'duration_ms': durationMs,
      if (scanStatus != null) 'scan_status': scanStatus,
      if (scanVersion != null) 'scan_version': scanVersion,
      if (lastScannedFrame != null) 'last_scanned_frame': lastScannedFrame,
      if (scannedAt != null) 'scanned_at': scannedAt,
      if (takenAt != null) 'taken_at': takenAt,
      if (scanAttempts != null) 'scan_attempts': scanAttempts,
      if (scanError != null) 'scan_error': scanError,
      if (illustrated != null) 'illustrated': illustrated,
    });
  }

  MediaCompanion copyWith({
    Value<int>? id,
    Value<String>? assetId,
    Value<String>? kind,
    Value<int>? sizeBytes,
    Value<int>? modifiedAt,
    Value<int?>? width,
    Value<int?>? height,
    Value<int?>? durationMs,
    Value<String>? scanStatus,
    Value<int>? scanVersion,
    Value<int>? lastScannedFrame,
    Value<int?>? scannedAt,
    Value<int?>? takenAt,
    Value<int>? scanAttempts,
    Value<String?>? scanError,
    Value<bool>? illustrated,
  }) {
    return MediaCompanion(
      id: id ?? this.id,
      assetId: assetId ?? this.assetId,
      kind: kind ?? this.kind,
      sizeBytes: sizeBytes ?? this.sizeBytes,
      modifiedAt: modifiedAt ?? this.modifiedAt,
      width: width ?? this.width,
      height: height ?? this.height,
      durationMs: durationMs ?? this.durationMs,
      scanStatus: scanStatus ?? this.scanStatus,
      scanVersion: scanVersion ?? this.scanVersion,
      lastScannedFrame: lastScannedFrame ?? this.lastScannedFrame,
      scannedAt: scannedAt ?? this.scannedAt,
      takenAt: takenAt ?? this.takenAt,
      scanAttempts: scanAttempts ?? this.scanAttempts,
      scanError: scanError ?? this.scanError,
      illustrated: illustrated ?? this.illustrated,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (assetId.present) {
      map['asset_id'] = Variable<String>(assetId.value);
    }
    if (kind.present) {
      map['kind'] = Variable<String>(kind.value);
    }
    if (sizeBytes.present) {
      map['size_bytes'] = Variable<int>(sizeBytes.value);
    }
    if (modifiedAt.present) {
      map['modified_at'] = Variable<int>(modifiedAt.value);
    }
    if (width.present) {
      map['width'] = Variable<int>(width.value);
    }
    if (height.present) {
      map['height'] = Variable<int>(height.value);
    }
    if (durationMs.present) {
      map['duration_ms'] = Variable<int>(durationMs.value);
    }
    if (scanStatus.present) {
      map['scan_status'] = Variable<String>(scanStatus.value);
    }
    if (scanVersion.present) {
      map['scan_version'] = Variable<int>(scanVersion.value);
    }
    if (lastScannedFrame.present) {
      map['last_scanned_frame'] = Variable<int>(lastScannedFrame.value);
    }
    if (scannedAt.present) {
      map['scanned_at'] = Variable<int>(scannedAt.value);
    }
    if (takenAt.present) {
      map['taken_at'] = Variable<int>(takenAt.value);
    }
    if (scanAttempts.present) {
      map['scan_attempts'] = Variable<int>(scanAttempts.value);
    }
    if (scanError.present) {
      map['scan_error'] = Variable<String>(scanError.value);
    }
    if (illustrated.present) {
      map['illustrated'] = Variable<bool>(illustrated.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('MediaCompanion(')
          ..write('id: $id, ')
          ..write('assetId: $assetId, ')
          ..write('kind: $kind, ')
          ..write('sizeBytes: $sizeBytes, ')
          ..write('modifiedAt: $modifiedAt, ')
          ..write('width: $width, ')
          ..write('height: $height, ')
          ..write('durationMs: $durationMs, ')
          ..write('scanStatus: $scanStatus, ')
          ..write('scanVersion: $scanVersion, ')
          ..write('lastScannedFrame: $lastScannedFrame, ')
          ..write('scannedAt: $scannedAt, ')
          ..write('takenAt: $takenAt, ')
          ..write('scanAttempts: $scanAttempts, ')
          ..write('scanError: $scanError, ')
          ..write('illustrated: $illustrated')
          ..write(')'))
        .toString();
  }
}

class $FacesTable extends Faces with TableInfo<$FacesTable, FaceRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $FacesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _mediaIdMeta = const VerificationMeta(
    'mediaId',
  );
  @override
  late final GeneratedColumn<int> mediaId = GeneratedColumn<int>(
    'media_id',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES media (id) ON DELETE CASCADE',
    ),
  );
  static const VerificationMeta _personIdMeta = const VerificationMeta(
    'personId',
  );
  @override
  late final GeneratedColumn<int> personId = GeneratedColumn<int>(
    'person_id',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES persons (id) ON DELETE SET NULL',
    ),
  );
  static const VerificationMeta _modelIdMeta = const VerificationMeta(
    'modelId',
  );
  @override
  late final GeneratedColumn<String> modelId = GeneratedColumn<String>(
    'model_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _embeddingMeta = const VerificationMeta(
    'embedding',
  );
  @override
  late final GeneratedColumn<Uint8List> embedding = GeneratedColumn<Uint8List>(
    'embedding',
    aliasedName,
    false,
    type: DriftSqlType.blob,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _qualityScoreMeta = const VerificationMeta(
    'qualityScore',
  );
  @override
  late final GeneratedColumn<double> qualityScore = GeneratedColumn<double>(
    'quality_score',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _qualityVersionMeta = const VerificationMeta(
    'qualityVersion',
  );
  @override
  late final GeneratedColumn<int> qualityVersion = GeneratedColumn<int>(
    'quality_version',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _detScoreMeta = const VerificationMeta(
    'detScore',
  );
  @override
  late final GeneratedColumn<double> detScore = GeneratedColumn<double>(
    'det_score',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _facePxMeta = const VerificationMeta('facePx');
  @override
  late final GeneratedColumn<double> facePx = GeneratedColumn<double>(
    'face_px',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _sharpnessMeta = const VerificationMeta(
    'sharpness',
  );
  @override
  late final GeneratedColumn<double> sharpness = GeneratedColumn<double>(
    'sharpness',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _embeddingNormMeta = const VerificationMeta(
    'embeddingNorm',
  );
  @override
  late final GeneratedColumn<double> embeddingNorm = GeneratedColumn<double>(
    'embedding_norm',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _yawMeta = const VerificationMeta('yaw');
  @override
  late final GeneratedColumn<double> yaw = GeneratedColumn<double>(
    'yaw',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _pitchMeta = const VerificationMeta('pitch');
  @override
  late final GeneratedColumn<double> pitch = GeneratedColumn<double>(
    'pitch',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _rollMeta = const VerificationMeta('roll');
  @override
  late final GeneratedColumn<double> roll = GeneratedColumn<double>(
    'roll',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _bboxXMeta = const VerificationMeta('bboxX');
  @override
  late final GeneratedColumn<double> bboxX = GeneratedColumn<double>(
    'bbox_x',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _bboxYMeta = const VerificationMeta('bboxY');
  @override
  late final GeneratedColumn<double> bboxY = GeneratedColumn<double>(
    'bbox_y',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _bboxWMeta = const VerificationMeta('bboxW');
  @override
  late final GeneratedColumn<double> bboxW = GeneratedColumn<double>(
    'bbox_w',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _bboxHMeta = const VerificationMeta('bboxH');
  @override
  late final GeneratedColumn<double> bboxH = GeneratedColumn<double>(
    'bbox_h',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _kpsMeta = const VerificationMeta('kps');
  @override
  late final GeneratedColumn<String> kps = GeneratedColumn<String>(
    'kps',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _frameNumberMeta = const VerificationMeta(
    'frameNumber',
  );
  @override
  late final GeneratedColumn<int> frameNumber = GeneratedColumn<int>(
    'frame_number',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _timestampMsMeta = const VerificationMeta(
    'timestampMs',
  );
  @override
  late final GeneratedColumn<int> timestampMs = GeneratedColumn<int>(
    'timestamp_ms',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _cropPathMeta = const VerificationMeta(
    'cropPath',
  );
  @override
  late final GeneratedColumn<String> cropPath = GeneratedColumn<String>(
    'crop_path',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _reviewDismissedMeta = const VerificationMeta(
    'reviewDismissed',
  );
  @override
  late final GeneratedColumn<bool> reviewDismissed = GeneratedColumn<bool>(
    'review_dismissed',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("review_dismissed" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<int> createdAt = GeneratedColumn<int>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _hiddenMeta = const VerificationMeta('hidden');
  @override
  late final GeneratedColumn<bool> hidden = GeneratedColumn<bool>(
    'hidden',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("hidden" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    mediaId,
    personId,
    modelId,
    embedding,
    qualityScore,
    qualityVersion,
    detScore,
    facePx,
    sharpness,
    embeddingNorm,
    yaw,
    pitch,
    roll,
    bboxX,
    bboxY,
    bboxW,
    bboxH,
    kps,
    frameNumber,
    timestampMs,
    cropPath,
    reviewDismissed,
    createdAt,
    hidden,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'faces';
  @override
  VerificationContext validateIntegrity(
    Insertable<FaceRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('media_id')) {
      context.handle(
        _mediaIdMeta,
        mediaId.isAcceptableOrUnknown(data['media_id']!, _mediaIdMeta),
      );
    }
    if (data.containsKey('person_id')) {
      context.handle(
        _personIdMeta,
        personId.isAcceptableOrUnknown(data['person_id']!, _personIdMeta),
      );
    }
    if (data.containsKey('model_id')) {
      context.handle(
        _modelIdMeta,
        modelId.isAcceptableOrUnknown(data['model_id']!, _modelIdMeta),
      );
    } else if (isInserting) {
      context.missing(_modelIdMeta);
    }
    if (data.containsKey('embedding')) {
      context.handle(
        _embeddingMeta,
        embedding.isAcceptableOrUnknown(data['embedding']!, _embeddingMeta),
      );
    } else if (isInserting) {
      context.missing(_embeddingMeta);
    }
    if (data.containsKey('quality_score')) {
      context.handle(
        _qualityScoreMeta,
        qualityScore.isAcceptableOrUnknown(
          data['quality_score']!,
          _qualityScoreMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_qualityScoreMeta);
    }
    if (data.containsKey('quality_version')) {
      context.handle(
        _qualityVersionMeta,
        qualityVersion.isAcceptableOrUnknown(
          data['quality_version']!,
          _qualityVersionMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_qualityVersionMeta);
    }
    if (data.containsKey('det_score')) {
      context.handle(
        _detScoreMeta,
        detScore.isAcceptableOrUnknown(data['det_score']!, _detScoreMeta),
      );
    } else if (isInserting) {
      context.missing(_detScoreMeta);
    }
    if (data.containsKey('face_px')) {
      context.handle(
        _facePxMeta,
        facePx.isAcceptableOrUnknown(data['face_px']!, _facePxMeta),
      );
    } else if (isInserting) {
      context.missing(_facePxMeta);
    }
    if (data.containsKey('sharpness')) {
      context.handle(
        _sharpnessMeta,
        sharpness.isAcceptableOrUnknown(data['sharpness']!, _sharpnessMeta),
      );
    } else if (isInserting) {
      context.missing(_sharpnessMeta);
    }
    if (data.containsKey('embedding_norm')) {
      context.handle(
        _embeddingNormMeta,
        embeddingNorm.isAcceptableOrUnknown(
          data['embedding_norm']!,
          _embeddingNormMeta,
        ),
      );
    }
    if (data.containsKey('yaw')) {
      context.handle(
        _yawMeta,
        yaw.isAcceptableOrUnknown(data['yaw']!, _yawMeta),
      );
    }
    if (data.containsKey('pitch')) {
      context.handle(
        _pitchMeta,
        pitch.isAcceptableOrUnknown(data['pitch']!, _pitchMeta),
      );
    }
    if (data.containsKey('roll')) {
      context.handle(
        _rollMeta,
        roll.isAcceptableOrUnknown(data['roll']!, _rollMeta),
      );
    }
    if (data.containsKey('bbox_x')) {
      context.handle(
        _bboxXMeta,
        bboxX.isAcceptableOrUnknown(data['bbox_x']!, _bboxXMeta),
      );
    } else if (isInserting) {
      context.missing(_bboxXMeta);
    }
    if (data.containsKey('bbox_y')) {
      context.handle(
        _bboxYMeta,
        bboxY.isAcceptableOrUnknown(data['bbox_y']!, _bboxYMeta),
      );
    } else if (isInserting) {
      context.missing(_bboxYMeta);
    }
    if (data.containsKey('bbox_w')) {
      context.handle(
        _bboxWMeta,
        bboxW.isAcceptableOrUnknown(data['bbox_w']!, _bboxWMeta),
      );
    } else if (isInserting) {
      context.missing(_bboxWMeta);
    }
    if (data.containsKey('bbox_h')) {
      context.handle(
        _bboxHMeta,
        bboxH.isAcceptableOrUnknown(data['bbox_h']!, _bboxHMeta),
      );
    } else if (isInserting) {
      context.missing(_bboxHMeta);
    }
    if (data.containsKey('kps')) {
      context.handle(
        _kpsMeta,
        kps.isAcceptableOrUnknown(data['kps']!, _kpsMeta),
      );
    }
    if (data.containsKey('frame_number')) {
      context.handle(
        _frameNumberMeta,
        frameNumber.isAcceptableOrUnknown(
          data['frame_number']!,
          _frameNumberMeta,
        ),
      );
    }
    if (data.containsKey('timestamp_ms')) {
      context.handle(
        _timestampMsMeta,
        timestampMs.isAcceptableOrUnknown(
          data['timestamp_ms']!,
          _timestampMsMeta,
        ),
      );
    }
    if (data.containsKey('crop_path')) {
      context.handle(
        _cropPathMeta,
        cropPath.isAcceptableOrUnknown(data['crop_path']!, _cropPathMeta),
      );
    }
    if (data.containsKey('review_dismissed')) {
      context.handle(
        _reviewDismissedMeta,
        reviewDismissed.isAcceptableOrUnknown(
          data['review_dismissed']!,
          _reviewDismissedMeta,
        ),
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
    if (data.containsKey('hidden')) {
      context.handle(
        _hiddenMeta,
        hidden.isAcceptableOrUnknown(data['hidden']!, _hiddenMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  FaceRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return FaceRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      mediaId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}media_id'],
      ),
      personId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}person_id'],
      ),
      modelId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}model_id'],
      )!,
      embedding: attachedDatabase.typeMapping.read(
        DriftSqlType.blob,
        data['${effectivePrefix}embedding'],
      )!,
      qualityScore: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}quality_score'],
      )!,
      qualityVersion: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}quality_version'],
      )!,
      detScore: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}det_score'],
      )!,
      facePx: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}face_px'],
      )!,
      sharpness: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}sharpness'],
      )!,
      embeddingNorm: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}embedding_norm'],
      ),
      yaw: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}yaw'],
      ),
      pitch: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}pitch'],
      ),
      roll: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}roll'],
      ),
      bboxX: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}bbox_x'],
      )!,
      bboxY: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}bbox_y'],
      )!,
      bboxW: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}bbox_w'],
      )!,
      bboxH: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}bbox_h'],
      )!,
      kps: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}kps'],
      ),
      frameNumber: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}frame_number'],
      ),
      timestampMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}timestamp_ms'],
      ),
      cropPath: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}crop_path'],
      ),
      reviewDismissed: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}review_dismissed'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}created_at'],
      )!,
      hidden: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}hidden'],
      )!,
    );
  }

  @override
  $FacesTable createAlias(String alias) {
    return $FacesTable(attachedDatabase, alias);
  }
}

class FaceRow extends DataClass implements Insertable<FaceRow> {
  final int id;
  final int? mediaId;
  final int? personId;
  final String modelId;
  final Uint8List embedding;
  final double qualityScore;
  final int qualityVersion;
  final double detScore;
  final double facePx;
  final double sharpness;
  final double? embeddingNorm;
  final double? yaw;
  final double? pitch;
  final double? roll;
  final double bboxX;
  final double bboxY;
  final double bboxW;
  final double bboxH;
  final String? kps;
  final int? frameNumber;
  final int? timestampMs;
  final String? cropPath;
  final bool reviewDismissed;
  final int createdAt;
  final bool hidden;
  const FaceRow({
    required this.id,
    this.mediaId,
    this.personId,
    required this.modelId,
    required this.embedding,
    required this.qualityScore,
    required this.qualityVersion,
    required this.detScore,
    required this.facePx,
    required this.sharpness,
    this.embeddingNorm,
    this.yaw,
    this.pitch,
    this.roll,
    required this.bboxX,
    required this.bboxY,
    required this.bboxW,
    required this.bboxH,
    this.kps,
    this.frameNumber,
    this.timestampMs,
    this.cropPath,
    required this.reviewDismissed,
    required this.createdAt,
    required this.hidden,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    if (!nullToAbsent || mediaId != null) {
      map['media_id'] = Variable<int>(mediaId);
    }
    if (!nullToAbsent || personId != null) {
      map['person_id'] = Variable<int>(personId);
    }
    map['model_id'] = Variable<String>(modelId);
    map['embedding'] = Variable<Uint8List>(embedding);
    map['quality_score'] = Variable<double>(qualityScore);
    map['quality_version'] = Variable<int>(qualityVersion);
    map['det_score'] = Variable<double>(detScore);
    map['face_px'] = Variable<double>(facePx);
    map['sharpness'] = Variable<double>(sharpness);
    if (!nullToAbsent || embeddingNorm != null) {
      map['embedding_norm'] = Variable<double>(embeddingNorm);
    }
    if (!nullToAbsent || yaw != null) {
      map['yaw'] = Variable<double>(yaw);
    }
    if (!nullToAbsent || pitch != null) {
      map['pitch'] = Variable<double>(pitch);
    }
    if (!nullToAbsent || roll != null) {
      map['roll'] = Variable<double>(roll);
    }
    map['bbox_x'] = Variable<double>(bboxX);
    map['bbox_y'] = Variable<double>(bboxY);
    map['bbox_w'] = Variable<double>(bboxW);
    map['bbox_h'] = Variable<double>(bboxH);
    if (!nullToAbsent || kps != null) {
      map['kps'] = Variable<String>(kps);
    }
    if (!nullToAbsent || frameNumber != null) {
      map['frame_number'] = Variable<int>(frameNumber);
    }
    if (!nullToAbsent || timestampMs != null) {
      map['timestamp_ms'] = Variable<int>(timestampMs);
    }
    if (!nullToAbsent || cropPath != null) {
      map['crop_path'] = Variable<String>(cropPath);
    }
    map['review_dismissed'] = Variable<bool>(reviewDismissed);
    map['created_at'] = Variable<int>(createdAt);
    map['hidden'] = Variable<bool>(hidden);
    return map;
  }

  FacesCompanion toCompanion(bool nullToAbsent) {
    return FacesCompanion(
      id: Value(id),
      mediaId: mediaId == null && nullToAbsent
          ? const Value.absent()
          : Value(mediaId),
      personId: personId == null && nullToAbsent
          ? const Value.absent()
          : Value(personId),
      modelId: Value(modelId),
      embedding: Value(embedding),
      qualityScore: Value(qualityScore),
      qualityVersion: Value(qualityVersion),
      detScore: Value(detScore),
      facePx: Value(facePx),
      sharpness: Value(sharpness),
      embeddingNorm: embeddingNorm == null && nullToAbsent
          ? const Value.absent()
          : Value(embeddingNorm),
      yaw: yaw == null && nullToAbsent ? const Value.absent() : Value(yaw),
      pitch: pitch == null && nullToAbsent
          ? const Value.absent()
          : Value(pitch),
      roll: roll == null && nullToAbsent ? const Value.absent() : Value(roll),
      bboxX: Value(bboxX),
      bboxY: Value(bboxY),
      bboxW: Value(bboxW),
      bboxH: Value(bboxH),
      kps: kps == null && nullToAbsent ? const Value.absent() : Value(kps),
      frameNumber: frameNumber == null && nullToAbsent
          ? const Value.absent()
          : Value(frameNumber),
      timestampMs: timestampMs == null && nullToAbsent
          ? const Value.absent()
          : Value(timestampMs),
      cropPath: cropPath == null && nullToAbsent
          ? const Value.absent()
          : Value(cropPath),
      reviewDismissed: Value(reviewDismissed),
      createdAt: Value(createdAt),
      hidden: Value(hidden),
    );
  }

  factory FaceRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return FaceRow(
      id: serializer.fromJson<int>(json['id']),
      mediaId: serializer.fromJson<int?>(json['mediaId']),
      personId: serializer.fromJson<int?>(json['personId']),
      modelId: serializer.fromJson<String>(json['modelId']),
      embedding: serializer.fromJson<Uint8List>(json['embedding']),
      qualityScore: serializer.fromJson<double>(json['qualityScore']),
      qualityVersion: serializer.fromJson<int>(json['qualityVersion']),
      detScore: serializer.fromJson<double>(json['detScore']),
      facePx: serializer.fromJson<double>(json['facePx']),
      sharpness: serializer.fromJson<double>(json['sharpness']),
      embeddingNorm: serializer.fromJson<double?>(json['embeddingNorm']),
      yaw: serializer.fromJson<double?>(json['yaw']),
      pitch: serializer.fromJson<double?>(json['pitch']),
      roll: serializer.fromJson<double?>(json['roll']),
      bboxX: serializer.fromJson<double>(json['bboxX']),
      bboxY: serializer.fromJson<double>(json['bboxY']),
      bboxW: serializer.fromJson<double>(json['bboxW']),
      bboxH: serializer.fromJson<double>(json['bboxH']),
      kps: serializer.fromJson<String?>(json['kps']),
      frameNumber: serializer.fromJson<int?>(json['frameNumber']),
      timestampMs: serializer.fromJson<int?>(json['timestampMs']),
      cropPath: serializer.fromJson<String?>(json['cropPath']),
      reviewDismissed: serializer.fromJson<bool>(json['reviewDismissed']),
      createdAt: serializer.fromJson<int>(json['createdAt']),
      hidden: serializer.fromJson<bool>(json['hidden']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'mediaId': serializer.toJson<int?>(mediaId),
      'personId': serializer.toJson<int?>(personId),
      'modelId': serializer.toJson<String>(modelId),
      'embedding': serializer.toJson<Uint8List>(embedding),
      'qualityScore': serializer.toJson<double>(qualityScore),
      'qualityVersion': serializer.toJson<int>(qualityVersion),
      'detScore': serializer.toJson<double>(detScore),
      'facePx': serializer.toJson<double>(facePx),
      'sharpness': serializer.toJson<double>(sharpness),
      'embeddingNorm': serializer.toJson<double?>(embeddingNorm),
      'yaw': serializer.toJson<double?>(yaw),
      'pitch': serializer.toJson<double?>(pitch),
      'roll': serializer.toJson<double?>(roll),
      'bboxX': serializer.toJson<double>(bboxX),
      'bboxY': serializer.toJson<double>(bboxY),
      'bboxW': serializer.toJson<double>(bboxW),
      'bboxH': serializer.toJson<double>(bboxH),
      'kps': serializer.toJson<String?>(kps),
      'frameNumber': serializer.toJson<int?>(frameNumber),
      'timestampMs': serializer.toJson<int?>(timestampMs),
      'cropPath': serializer.toJson<String?>(cropPath),
      'reviewDismissed': serializer.toJson<bool>(reviewDismissed),
      'createdAt': serializer.toJson<int>(createdAt),
      'hidden': serializer.toJson<bool>(hidden),
    };
  }

  FaceRow copyWith({
    int? id,
    Value<int?> mediaId = const Value.absent(),
    Value<int?> personId = const Value.absent(),
    String? modelId,
    Uint8List? embedding,
    double? qualityScore,
    int? qualityVersion,
    double? detScore,
    double? facePx,
    double? sharpness,
    Value<double?> embeddingNorm = const Value.absent(),
    Value<double?> yaw = const Value.absent(),
    Value<double?> pitch = const Value.absent(),
    Value<double?> roll = const Value.absent(),
    double? bboxX,
    double? bboxY,
    double? bboxW,
    double? bboxH,
    Value<String?> kps = const Value.absent(),
    Value<int?> frameNumber = const Value.absent(),
    Value<int?> timestampMs = const Value.absent(),
    Value<String?> cropPath = const Value.absent(),
    bool? reviewDismissed,
    int? createdAt,
    bool? hidden,
  }) => FaceRow(
    id: id ?? this.id,
    mediaId: mediaId.present ? mediaId.value : this.mediaId,
    personId: personId.present ? personId.value : this.personId,
    modelId: modelId ?? this.modelId,
    embedding: embedding ?? this.embedding,
    qualityScore: qualityScore ?? this.qualityScore,
    qualityVersion: qualityVersion ?? this.qualityVersion,
    detScore: detScore ?? this.detScore,
    facePx: facePx ?? this.facePx,
    sharpness: sharpness ?? this.sharpness,
    embeddingNorm: embeddingNorm.present
        ? embeddingNorm.value
        : this.embeddingNorm,
    yaw: yaw.present ? yaw.value : this.yaw,
    pitch: pitch.present ? pitch.value : this.pitch,
    roll: roll.present ? roll.value : this.roll,
    bboxX: bboxX ?? this.bboxX,
    bboxY: bboxY ?? this.bboxY,
    bboxW: bboxW ?? this.bboxW,
    bboxH: bboxH ?? this.bboxH,
    kps: kps.present ? kps.value : this.kps,
    frameNumber: frameNumber.present ? frameNumber.value : this.frameNumber,
    timestampMs: timestampMs.present ? timestampMs.value : this.timestampMs,
    cropPath: cropPath.present ? cropPath.value : this.cropPath,
    reviewDismissed: reviewDismissed ?? this.reviewDismissed,
    createdAt: createdAt ?? this.createdAt,
    hidden: hidden ?? this.hidden,
  );
  FaceRow copyWithCompanion(FacesCompanion data) {
    return FaceRow(
      id: data.id.present ? data.id.value : this.id,
      mediaId: data.mediaId.present ? data.mediaId.value : this.mediaId,
      personId: data.personId.present ? data.personId.value : this.personId,
      modelId: data.modelId.present ? data.modelId.value : this.modelId,
      embedding: data.embedding.present ? data.embedding.value : this.embedding,
      qualityScore: data.qualityScore.present
          ? data.qualityScore.value
          : this.qualityScore,
      qualityVersion: data.qualityVersion.present
          ? data.qualityVersion.value
          : this.qualityVersion,
      detScore: data.detScore.present ? data.detScore.value : this.detScore,
      facePx: data.facePx.present ? data.facePx.value : this.facePx,
      sharpness: data.sharpness.present ? data.sharpness.value : this.sharpness,
      embeddingNorm: data.embeddingNorm.present
          ? data.embeddingNorm.value
          : this.embeddingNorm,
      yaw: data.yaw.present ? data.yaw.value : this.yaw,
      pitch: data.pitch.present ? data.pitch.value : this.pitch,
      roll: data.roll.present ? data.roll.value : this.roll,
      bboxX: data.bboxX.present ? data.bboxX.value : this.bboxX,
      bboxY: data.bboxY.present ? data.bboxY.value : this.bboxY,
      bboxW: data.bboxW.present ? data.bboxW.value : this.bboxW,
      bboxH: data.bboxH.present ? data.bboxH.value : this.bboxH,
      kps: data.kps.present ? data.kps.value : this.kps,
      frameNumber: data.frameNumber.present
          ? data.frameNumber.value
          : this.frameNumber,
      timestampMs: data.timestampMs.present
          ? data.timestampMs.value
          : this.timestampMs,
      cropPath: data.cropPath.present ? data.cropPath.value : this.cropPath,
      reviewDismissed: data.reviewDismissed.present
          ? data.reviewDismissed.value
          : this.reviewDismissed,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      hidden: data.hidden.present ? data.hidden.value : this.hidden,
    );
  }

  @override
  String toString() {
    return (StringBuffer('FaceRow(')
          ..write('id: $id, ')
          ..write('mediaId: $mediaId, ')
          ..write('personId: $personId, ')
          ..write('modelId: $modelId, ')
          ..write('embedding: $embedding, ')
          ..write('qualityScore: $qualityScore, ')
          ..write('qualityVersion: $qualityVersion, ')
          ..write('detScore: $detScore, ')
          ..write('facePx: $facePx, ')
          ..write('sharpness: $sharpness, ')
          ..write('embeddingNorm: $embeddingNorm, ')
          ..write('yaw: $yaw, ')
          ..write('pitch: $pitch, ')
          ..write('roll: $roll, ')
          ..write('bboxX: $bboxX, ')
          ..write('bboxY: $bboxY, ')
          ..write('bboxW: $bboxW, ')
          ..write('bboxH: $bboxH, ')
          ..write('kps: $kps, ')
          ..write('frameNumber: $frameNumber, ')
          ..write('timestampMs: $timestampMs, ')
          ..write('cropPath: $cropPath, ')
          ..write('reviewDismissed: $reviewDismissed, ')
          ..write('createdAt: $createdAt, ')
          ..write('hidden: $hidden')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hashAll([
    id,
    mediaId,
    personId,
    modelId,
    $driftBlobEquality.hash(embedding),
    qualityScore,
    qualityVersion,
    detScore,
    facePx,
    sharpness,
    embeddingNorm,
    yaw,
    pitch,
    roll,
    bboxX,
    bboxY,
    bboxW,
    bboxH,
    kps,
    frameNumber,
    timestampMs,
    cropPath,
    reviewDismissed,
    createdAt,
    hidden,
  ]);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is FaceRow &&
          other.id == this.id &&
          other.mediaId == this.mediaId &&
          other.personId == this.personId &&
          other.modelId == this.modelId &&
          $driftBlobEquality.equals(other.embedding, this.embedding) &&
          other.qualityScore == this.qualityScore &&
          other.qualityVersion == this.qualityVersion &&
          other.detScore == this.detScore &&
          other.facePx == this.facePx &&
          other.sharpness == this.sharpness &&
          other.embeddingNorm == this.embeddingNorm &&
          other.yaw == this.yaw &&
          other.pitch == this.pitch &&
          other.roll == this.roll &&
          other.bboxX == this.bboxX &&
          other.bboxY == this.bboxY &&
          other.bboxW == this.bboxW &&
          other.bboxH == this.bboxH &&
          other.kps == this.kps &&
          other.frameNumber == this.frameNumber &&
          other.timestampMs == this.timestampMs &&
          other.cropPath == this.cropPath &&
          other.reviewDismissed == this.reviewDismissed &&
          other.createdAt == this.createdAt &&
          other.hidden == this.hidden);
}

class FacesCompanion extends UpdateCompanion<FaceRow> {
  final Value<int> id;
  final Value<int?> mediaId;
  final Value<int?> personId;
  final Value<String> modelId;
  final Value<Uint8List> embedding;
  final Value<double> qualityScore;
  final Value<int> qualityVersion;
  final Value<double> detScore;
  final Value<double> facePx;
  final Value<double> sharpness;
  final Value<double?> embeddingNorm;
  final Value<double?> yaw;
  final Value<double?> pitch;
  final Value<double?> roll;
  final Value<double> bboxX;
  final Value<double> bboxY;
  final Value<double> bboxW;
  final Value<double> bboxH;
  final Value<String?> kps;
  final Value<int?> frameNumber;
  final Value<int?> timestampMs;
  final Value<String?> cropPath;
  final Value<bool> reviewDismissed;
  final Value<int> createdAt;
  final Value<bool> hidden;
  const FacesCompanion({
    this.id = const Value.absent(),
    this.mediaId = const Value.absent(),
    this.personId = const Value.absent(),
    this.modelId = const Value.absent(),
    this.embedding = const Value.absent(),
    this.qualityScore = const Value.absent(),
    this.qualityVersion = const Value.absent(),
    this.detScore = const Value.absent(),
    this.facePx = const Value.absent(),
    this.sharpness = const Value.absent(),
    this.embeddingNorm = const Value.absent(),
    this.yaw = const Value.absent(),
    this.pitch = const Value.absent(),
    this.roll = const Value.absent(),
    this.bboxX = const Value.absent(),
    this.bboxY = const Value.absent(),
    this.bboxW = const Value.absent(),
    this.bboxH = const Value.absent(),
    this.kps = const Value.absent(),
    this.frameNumber = const Value.absent(),
    this.timestampMs = const Value.absent(),
    this.cropPath = const Value.absent(),
    this.reviewDismissed = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.hidden = const Value.absent(),
  });
  FacesCompanion.insert({
    this.id = const Value.absent(),
    this.mediaId = const Value.absent(),
    this.personId = const Value.absent(),
    required String modelId,
    required Uint8List embedding,
    required double qualityScore,
    required int qualityVersion,
    required double detScore,
    required double facePx,
    required double sharpness,
    this.embeddingNorm = const Value.absent(),
    this.yaw = const Value.absent(),
    this.pitch = const Value.absent(),
    this.roll = const Value.absent(),
    required double bboxX,
    required double bboxY,
    required double bboxW,
    required double bboxH,
    this.kps = const Value.absent(),
    this.frameNumber = const Value.absent(),
    this.timestampMs = const Value.absent(),
    this.cropPath = const Value.absent(),
    this.reviewDismissed = const Value.absent(),
    required int createdAt,
    this.hidden = const Value.absent(),
  }) : modelId = Value(modelId),
       embedding = Value(embedding),
       qualityScore = Value(qualityScore),
       qualityVersion = Value(qualityVersion),
       detScore = Value(detScore),
       facePx = Value(facePx),
       sharpness = Value(sharpness),
       bboxX = Value(bboxX),
       bboxY = Value(bboxY),
       bboxW = Value(bboxW),
       bboxH = Value(bboxH),
       createdAt = Value(createdAt);
  static Insertable<FaceRow> custom({
    Expression<int>? id,
    Expression<int>? mediaId,
    Expression<int>? personId,
    Expression<String>? modelId,
    Expression<Uint8List>? embedding,
    Expression<double>? qualityScore,
    Expression<int>? qualityVersion,
    Expression<double>? detScore,
    Expression<double>? facePx,
    Expression<double>? sharpness,
    Expression<double>? embeddingNorm,
    Expression<double>? yaw,
    Expression<double>? pitch,
    Expression<double>? roll,
    Expression<double>? bboxX,
    Expression<double>? bboxY,
    Expression<double>? bboxW,
    Expression<double>? bboxH,
    Expression<String>? kps,
    Expression<int>? frameNumber,
    Expression<int>? timestampMs,
    Expression<String>? cropPath,
    Expression<bool>? reviewDismissed,
    Expression<int>? createdAt,
    Expression<bool>? hidden,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (mediaId != null) 'media_id': mediaId,
      if (personId != null) 'person_id': personId,
      if (modelId != null) 'model_id': modelId,
      if (embedding != null) 'embedding': embedding,
      if (qualityScore != null) 'quality_score': qualityScore,
      if (qualityVersion != null) 'quality_version': qualityVersion,
      if (detScore != null) 'det_score': detScore,
      if (facePx != null) 'face_px': facePx,
      if (sharpness != null) 'sharpness': sharpness,
      if (embeddingNorm != null) 'embedding_norm': embeddingNorm,
      if (yaw != null) 'yaw': yaw,
      if (pitch != null) 'pitch': pitch,
      if (roll != null) 'roll': roll,
      if (bboxX != null) 'bbox_x': bboxX,
      if (bboxY != null) 'bbox_y': bboxY,
      if (bboxW != null) 'bbox_w': bboxW,
      if (bboxH != null) 'bbox_h': bboxH,
      if (kps != null) 'kps': kps,
      if (frameNumber != null) 'frame_number': frameNumber,
      if (timestampMs != null) 'timestamp_ms': timestampMs,
      if (cropPath != null) 'crop_path': cropPath,
      if (reviewDismissed != null) 'review_dismissed': reviewDismissed,
      if (createdAt != null) 'created_at': createdAt,
      if (hidden != null) 'hidden': hidden,
    });
  }

  FacesCompanion copyWith({
    Value<int>? id,
    Value<int?>? mediaId,
    Value<int?>? personId,
    Value<String>? modelId,
    Value<Uint8List>? embedding,
    Value<double>? qualityScore,
    Value<int>? qualityVersion,
    Value<double>? detScore,
    Value<double>? facePx,
    Value<double>? sharpness,
    Value<double?>? embeddingNorm,
    Value<double?>? yaw,
    Value<double?>? pitch,
    Value<double?>? roll,
    Value<double>? bboxX,
    Value<double>? bboxY,
    Value<double>? bboxW,
    Value<double>? bboxH,
    Value<String?>? kps,
    Value<int?>? frameNumber,
    Value<int?>? timestampMs,
    Value<String?>? cropPath,
    Value<bool>? reviewDismissed,
    Value<int>? createdAt,
    Value<bool>? hidden,
  }) {
    return FacesCompanion(
      id: id ?? this.id,
      mediaId: mediaId ?? this.mediaId,
      personId: personId ?? this.personId,
      modelId: modelId ?? this.modelId,
      embedding: embedding ?? this.embedding,
      qualityScore: qualityScore ?? this.qualityScore,
      qualityVersion: qualityVersion ?? this.qualityVersion,
      detScore: detScore ?? this.detScore,
      facePx: facePx ?? this.facePx,
      sharpness: sharpness ?? this.sharpness,
      embeddingNorm: embeddingNorm ?? this.embeddingNorm,
      yaw: yaw ?? this.yaw,
      pitch: pitch ?? this.pitch,
      roll: roll ?? this.roll,
      bboxX: bboxX ?? this.bboxX,
      bboxY: bboxY ?? this.bboxY,
      bboxW: bboxW ?? this.bboxW,
      bboxH: bboxH ?? this.bboxH,
      kps: kps ?? this.kps,
      frameNumber: frameNumber ?? this.frameNumber,
      timestampMs: timestampMs ?? this.timestampMs,
      cropPath: cropPath ?? this.cropPath,
      reviewDismissed: reviewDismissed ?? this.reviewDismissed,
      createdAt: createdAt ?? this.createdAt,
      hidden: hidden ?? this.hidden,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (mediaId.present) {
      map['media_id'] = Variable<int>(mediaId.value);
    }
    if (personId.present) {
      map['person_id'] = Variable<int>(personId.value);
    }
    if (modelId.present) {
      map['model_id'] = Variable<String>(modelId.value);
    }
    if (embedding.present) {
      map['embedding'] = Variable<Uint8List>(embedding.value);
    }
    if (qualityScore.present) {
      map['quality_score'] = Variable<double>(qualityScore.value);
    }
    if (qualityVersion.present) {
      map['quality_version'] = Variable<int>(qualityVersion.value);
    }
    if (detScore.present) {
      map['det_score'] = Variable<double>(detScore.value);
    }
    if (facePx.present) {
      map['face_px'] = Variable<double>(facePx.value);
    }
    if (sharpness.present) {
      map['sharpness'] = Variable<double>(sharpness.value);
    }
    if (embeddingNorm.present) {
      map['embedding_norm'] = Variable<double>(embeddingNorm.value);
    }
    if (yaw.present) {
      map['yaw'] = Variable<double>(yaw.value);
    }
    if (pitch.present) {
      map['pitch'] = Variable<double>(pitch.value);
    }
    if (roll.present) {
      map['roll'] = Variable<double>(roll.value);
    }
    if (bboxX.present) {
      map['bbox_x'] = Variable<double>(bboxX.value);
    }
    if (bboxY.present) {
      map['bbox_y'] = Variable<double>(bboxY.value);
    }
    if (bboxW.present) {
      map['bbox_w'] = Variable<double>(bboxW.value);
    }
    if (bboxH.present) {
      map['bbox_h'] = Variable<double>(bboxH.value);
    }
    if (kps.present) {
      map['kps'] = Variable<String>(kps.value);
    }
    if (frameNumber.present) {
      map['frame_number'] = Variable<int>(frameNumber.value);
    }
    if (timestampMs.present) {
      map['timestamp_ms'] = Variable<int>(timestampMs.value);
    }
    if (cropPath.present) {
      map['crop_path'] = Variable<String>(cropPath.value);
    }
    if (reviewDismissed.present) {
      map['review_dismissed'] = Variable<bool>(reviewDismissed.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<int>(createdAt.value);
    }
    if (hidden.present) {
      map['hidden'] = Variable<bool>(hidden.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('FacesCompanion(')
          ..write('id: $id, ')
          ..write('mediaId: $mediaId, ')
          ..write('personId: $personId, ')
          ..write('modelId: $modelId, ')
          ..write('embedding: $embedding, ')
          ..write('qualityScore: $qualityScore, ')
          ..write('qualityVersion: $qualityVersion, ')
          ..write('detScore: $detScore, ')
          ..write('facePx: $facePx, ')
          ..write('sharpness: $sharpness, ')
          ..write('embeddingNorm: $embeddingNorm, ')
          ..write('yaw: $yaw, ')
          ..write('pitch: $pitch, ')
          ..write('roll: $roll, ')
          ..write('bboxX: $bboxX, ')
          ..write('bboxY: $bboxY, ')
          ..write('bboxW: $bboxW, ')
          ..write('bboxH: $bboxH, ')
          ..write('kps: $kps, ')
          ..write('frameNumber: $frameNumber, ')
          ..write('timestampMs: $timestampMs, ')
          ..write('cropPath: $cropPath, ')
          ..write('reviewDismissed: $reviewDismissed, ')
          ..write('createdAt: $createdAt, ')
          ..write('hidden: $hidden')
          ..write(')'))
        .toString();
  }
}

class $FaceSuppressionsTable extends FaceSuppressions
    with TableInfo<$FaceSuppressionsTable, FaceSuppressionRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $FaceSuppressionsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _assetIdMeta = const VerificationMeta(
    'assetId',
  );
  @override
  late final GeneratedColumn<String> assetId = GeneratedColumn<String>(
    'asset_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _modelIdMeta = const VerificationMeta(
    'modelId',
  );
  @override
  late final GeneratedColumn<String> modelId = GeneratedColumn<String>(
    'model_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _embeddingMeta = const VerificationMeta(
    'embedding',
  );
  @override
  late final GeneratedColumn<Uint8List> embedding = GeneratedColumn<Uint8List>(
    'embedding',
    aliasedName,
    false,
    type: DriftSqlType.blob,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _occurrencesMeta = const VerificationMeta(
    'occurrences',
  );
  @override
  late final GeneratedColumn<String> occurrences = GeneratedColumn<String>(
    'occurrences',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    assetId,
    modelId,
    embedding,
    occurrences,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'face_suppressions';
  @override
  VerificationContext validateIntegrity(
    Insertable<FaceSuppressionRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('asset_id')) {
      context.handle(
        _assetIdMeta,
        assetId.isAcceptableOrUnknown(data['asset_id']!, _assetIdMeta),
      );
    } else if (isInserting) {
      context.missing(_assetIdMeta);
    }
    if (data.containsKey('model_id')) {
      context.handle(
        _modelIdMeta,
        modelId.isAcceptableOrUnknown(data['model_id']!, _modelIdMeta),
      );
    } else if (isInserting) {
      context.missing(_modelIdMeta);
    }
    if (data.containsKey('embedding')) {
      context.handle(
        _embeddingMeta,
        embedding.isAcceptableOrUnknown(data['embedding']!, _embeddingMeta),
      );
    } else if (isInserting) {
      context.missing(_embeddingMeta);
    }
    if (data.containsKey('occurrences')) {
      context.handle(
        _occurrencesMeta,
        occurrences.isAcceptableOrUnknown(
          data['occurrences']!,
          _occurrencesMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_occurrencesMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  FaceSuppressionRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return FaceSuppressionRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      assetId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}asset_id'],
      )!,
      modelId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}model_id'],
      )!,
      embedding: attachedDatabase.typeMapping.read(
        DriftSqlType.blob,
        data['${effectivePrefix}embedding'],
      )!,
      occurrences: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}occurrences'],
      )!,
    );
  }

  @override
  $FaceSuppressionsTable createAlias(String alias) {
    return $FaceSuppressionsTable(attachedDatabase, alias);
  }
}

class FaceSuppressionRow extends DataClass
    implements Insertable<FaceSuppressionRow> {
  final int id;
  final String assetId;
  final String modelId;
  final Uint8List embedding;
  final String occurrences;
  const FaceSuppressionRow({
    required this.id,
    required this.assetId,
    required this.modelId,
    required this.embedding,
    required this.occurrences,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['asset_id'] = Variable<String>(assetId);
    map['model_id'] = Variable<String>(modelId);
    map['embedding'] = Variable<Uint8List>(embedding);
    map['occurrences'] = Variable<String>(occurrences);
    return map;
  }

  FaceSuppressionsCompanion toCompanion(bool nullToAbsent) {
    return FaceSuppressionsCompanion(
      id: Value(id),
      assetId: Value(assetId),
      modelId: Value(modelId),
      embedding: Value(embedding),
      occurrences: Value(occurrences),
    );
  }

  factory FaceSuppressionRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return FaceSuppressionRow(
      id: serializer.fromJson<int>(json['id']),
      assetId: serializer.fromJson<String>(json['assetId']),
      modelId: serializer.fromJson<String>(json['modelId']),
      embedding: serializer.fromJson<Uint8List>(json['embedding']),
      occurrences: serializer.fromJson<String>(json['occurrences']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'assetId': serializer.toJson<String>(assetId),
      'modelId': serializer.toJson<String>(modelId),
      'embedding': serializer.toJson<Uint8List>(embedding),
      'occurrences': serializer.toJson<String>(occurrences),
    };
  }

  FaceSuppressionRow copyWith({
    int? id,
    String? assetId,
    String? modelId,
    Uint8List? embedding,
    String? occurrences,
  }) => FaceSuppressionRow(
    id: id ?? this.id,
    assetId: assetId ?? this.assetId,
    modelId: modelId ?? this.modelId,
    embedding: embedding ?? this.embedding,
    occurrences: occurrences ?? this.occurrences,
  );
  FaceSuppressionRow copyWithCompanion(FaceSuppressionsCompanion data) {
    return FaceSuppressionRow(
      id: data.id.present ? data.id.value : this.id,
      assetId: data.assetId.present ? data.assetId.value : this.assetId,
      modelId: data.modelId.present ? data.modelId.value : this.modelId,
      embedding: data.embedding.present ? data.embedding.value : this.embedding,
      occurrences: data.occurrences.present
          ? data.occurrences.value
          : this.occurrences,
    );
  }

  @override
  String toString() {
    return (StringBuffer('FaceSuppressionRow(')
          ..write('id: $id, ')
          ..write('assetId: $assetId, ')
          ..write('modelId: $modelId, ')
          ..write('embedding: $embedding, ')
          ..write('occurrences: $occurrences')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    assetId,
    modelId,
    $driftBlobEquality.hash(embedding),
    occurrences,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is FaceSuppressionRow &&
          other.id == this.id &&
          other.assetId == this.assetId &&
          other.modelId == this.modelId &&
          $driftBlobEquality.equals(other.embedding, this.embedding) &&
          other.occurrences == this.occurrences);
}

class FaceSuppressionsCompanion extends UpdateCompanion<FaceSuppressionRow> {
  final Value<int> id;
  final Value<String> assetId;
  final Value<String> modelId;
  final Value<Uint8List> embedding;
  final Value<String> occurrences;
  const FaceSuppressionsCompanion({
    this.id = const Value.absent(),
    this.assetId = const Value.absent(),
    this.modelId = const Value.absent(),
    this.embedding = const Value.absent(),
    this.occurrences = const Value.absent(),
  });
  FaceSuppressionsCompanion.insert({
    this.id = const Value.absent(),
    required String assetId,
    required String modelId,
    required Uint8List embedding,
    required String occurrences,
  }) : assetId = Value(assetId),
       modelId = Value(modelId),
       embedding = Value(embedding),
       occurrences = Value(occurrences);
  static Insertable<FaceSuppressionRow> custom({
    Expression<int>? id,
    Expression<String>? assetId,
    Expression<String>? modelId,
    Expression<Uint8List>? embedding,
    Expression<String>? occurrences,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (assetId != null) 'asset_id': assetId,
      if (modelId != null) 'model_id': modelId,
      if (embedding != null) 'embedding': embedding,
      if (occurrences != null) 'occurrences': occurrences,
    });
  }

  FaceSuppressionsCompanion copyWith({
    Value<int>? id,
    Value<String>? assetId,
    Value<String>? modelId,
    Value<Uint8List>? embedding,
    Value<String>? occurrences,
  }) {
    return FaceSuppressionsCompanion(
      id: id ?? this.id,
      assetId: assetId ?? this.assetId,
      modelId: modelId ?? this.modelId,
      embedding: embedding ?? this.embedding,
      occurrences: occurrences ?? this.occurrences,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (assetId.present) {
      map['asset_id'] = Variable<String>(assetId.value);
    }
    if (modelId.present) {
      map['model_id'] = Variable<String>(modelId.value);
    }
    if (embedding.present) {
      map['embedding'] = Variable<Uint8List>(embedding.value);
    }
    if (occurrences.present) {
      map['occurrences'] = Variable<String>(occurrences.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('FaceSuppressionsCompanion(')
          ..write('id: $id, ')
          ..write('assetId: $assetId, ')
          ..write('modelId: $modelId, ')
          ..write('embedding: $embedding, ')
          ..write('occurrences: $occurrences')
          ..write(')'))
        .toString();
  }
}

class $BodiesTable extends Bodies with TableInfo<$BodiesTable, BodyRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $BodiesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _mediaIdMeta = const VerificationMeta(
    'mediaId',
  );
  @override
  late final GeneratedColumn<int> mediaId = GeneratedColumn<int>(
    'media_id',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES media (id) ON DELETE CASCADE',
    ),
  );
  static const VerificationMeta _faceIdMeta = const VerificationMeta('faceId');
  @override
  late final GeneratedColumn<int> faceId = GeneratedColumn<int>(
    'face_id',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES faces (id) ON DELETE SET NULL',
    ),
  );
  static const VerificationMeta _personIdMeta = const VerificationMeta(
    'personId',
  );
  @override
  late final GeneratedColumn<int> personId = GeneratedColumn<int>(
    'person_id',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES persons (id) ON DELETE SET NULL',
    ),
  );
  static const VerificationMeta _bboxXMeta = const VerificationMeta('bboxX');
  @override
  late final GeneratedColumn<double> bboxX = GeneratedColumn<double>(
    'bbox_x',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _bboxYMeta = const VerificationMeta('bboxY');
  @override
  late final GeneratedColumn<double> bboxY = GeneratedColumn<double>(
    'bbox_y',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _bboxWMeta = const VerificationMeta('bboxW');
  @override
  late final GeneratedColumn<double> bboxW = GeneratedColumn<double>(
    'bbox_w',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _bboxHMeta = const VerificationMeta('bboxH');
  @override
  late final GeneratedColumn<double> bboxH = GeneratedColumn<double>(
    'bbox_h',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _scoreMeta = const VerificationMeta('score');
  @override
  late final GeneratedColumn<double> score = GeneratedColumn<double>(
    'score',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _kptsMeta = const VerificationMeta('kpts');
  @override
  late final GeneratedColumn<String> kpts = GeneratedColumn<String>(
    'kpts',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _extentMeta = const VerificationMeta('extent');
  @override
  late final GeneratedColumn<String> extent = GeneratedColumn<String>(
    'extent',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _appearanceMeta = const VerificationMeta(
    'appearance',
  );
  @override
  late final GeneratedColumn<Uint8List> appearance = GeneratedColumn<Uint8List>(
    'appearance',
    aliasedName,
    true,
    type: DriftSqlType.blob,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _linkMethodMeta = const VerificationMeta(
    'linkMethod',
  );
  @override
  late final GeneratedColumn<String> linkMethod = GeneratedColumn<String>(
    'link_method',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _linkConfidenceMeta = const VerificationMeta(
    'linkConfidence',
  );
  @override
  late final GeneratedColumn<double> linkConfidence = GeneratedColumn<double>(
    'link_confidence',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _weakFaceEmbeddingMeta = const VerificationMeta(
    'weakFaceEmbedding',
  );
  @override
  late final GeneratedColumn<Uint8List> weakFaceEmbedding =
      GeneratedColumn<Uint8List>(
        'weak_face_embedding',
        aliasedName,
        true,
        type: DriftSqlType.blob,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _weakFaceQualityMeta = const VerificationMeta(
    'weakFaceQuality',
  );
  @override
  late final GeneratedColumn<double> weakFaceQuality = GeneratedColumn<double>(
    'weak_face_quality',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _frameNumberMeta = const VerificationMeta(
    'frameNumber',
  );
  @override
  late final GeneratedColumn<int> frameNumber = GeneratedColumn<int>(
    'frame_number',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _timestampMsMeta = const VerificationMeta(
    'timestampMs',
  );
  @override
  late final GeneratedColumn<int> timestampMs = GeneratedColumn<int>(
    'timestamp_ms',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _cropPathMeta = const VerificationMeta(
    'cropPath',
  );
  @override
  late final GeneratedColumn<String> cropPath = GeneratedColumn<String>(
    'crop_path',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<int> createdAt = GeneratedColumn<int>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    mediaId,
    faceId,
    personId,
    bboxX,
    bboxY,
    bboxW,
    bboxH,
    score,
    kpts,
    extent,
    appearance,
    linkMethod,
    linkConfidence,
    weakFaceEmbedding,
    weakFaceQuality,
    frameNumber,
    timestampMs,
    cropPath,
    createdAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'bodies';
  @override
  VerificationContext validateIntegrity(
    Insertable<BodyRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('media_id')) {
      context.handle(
        _mediaIdMeta,
        mediaId.isAcceptableOrUnknown(data['media_id']!, _mediaIdMeta),
      );
    }
    if (data.containsKey('face_id')) {
      context.handle(
        _faceIdMeta,
        faceId.isAcceptableOrUnknown(data['face_id']!, _faceIdMeta),
      );
    }
    if (data.containsKey('person_id')) {
      context.handle(
        _personIdMeta,
        personId.isAcceptableOrUnknown(data['person_id']!, _personIdMeta),
      );
    }
    if (data.containsKey('bbox_x')) {
      context.handle(
        _bboxXMeta,
        bboxX.isAcceptableOrUnknown(data['bbox_x']!, _bboxXMeta),
      );
    } else if (isInserting) {
      context.missing(_bboxXMeta);
    }
    if (data.containsKey('bbox_y')) {
      context.handle(
        _bboxYMeta,
        bboxY.isAcceptableOrUnknown(data['bbox_y']!, _bboxYMeta),
      );
    } else if (isInserting) {
      context.missing(_bboxYMeta);
    }
    if (data.containsKey('bbox_w')) {
      context.handle(
        _bboxWMeta,
        bboxW.isAcceptableOrUnknown(data['bbox_w']!, _bboxWMeta),
      );
    } else if (isInserting) {
      context.missing(_bboxWMeta);
    }
    if (data.containsKey('bbox_h')) {
      context.handle(
        _bboxHMeta,
        bboxH.isAcceptableOrUnknown(data['bbox_h']!, _bboxHMeta),
      );
    } else if (isInserting) {
      context.missing(_bboxHMeta);
    }
    if (data.containsKey('score')) {
      context.handle(
        _scoreMeta,
        score.isAcceptableOrUnknown(data['score']!, _scoreMeta),
      );
    } else if (isInserting) {
      context.missing(_scoreMeta);
    }
    if (data.containsKey('kpts')) {
      context.handle(
        _kptsMeta,
        kpts.isAcceptableOrUnknown(data['kpts']!, _kptsMeta),
      );
    }
    if (data.containsKey('extent')) {
      context.handle(
        _extentMeta,
        extent.isAcceptableOrUnknown(data['extent']!, _extentMeta),
      );
    }
    if (data.containsKey('appearance')) {
      context.handle(
        _appearanceMeta,
        appearance.isAcceptableOrUnknown(data['appearance']!, _appearanceMeta),
      );
    }
    if (data.containsKey('link_method')) {
      context.handle(
        _linkMethodMeta,
        linkMethod.isAcceptableOrUnknown(data['link_method']!, _linkMethodMeta),
      );
    }
    if (data.containsKey('link_confidence')) {
      context.handle(
        _linkConfidenceMeta,
        linkConfidence.isAcceptableOrUnknown(
          data['link_confidence']!,
          _linkConfidenceMeta,
        ),
      );
    }
    if (data.containsKey('weak_face_embedding')) {
      context.handle(
        _weakFaceEmbeddingMeta,
        weakFaceEmbedding.isAcceptableOrUnknown(
          data['weak_face_embedding']!,
          _weakFaceEmbeddingMeta,
        ),
      );
    }
    if (data.containsKey('weak_face_quality')) {
      context.handle(
        _weakFaceQualityMeta,
        weakFaceQuality.isAcceptableOrUnknown(
          data['weak_face_quality']!,
          _weakFaceQualityMeta,
        ),
      );
    }
    if (data.containsKey('frame_number')) {
      context.handle(
        _frameNumberMeta,
        frameNumber.isAcceptableOrUnknown(
          data['frame_number']!,
          _frameNumberMeta,
        ),
      );
    }
    if (data.containsKey('timestamp_ms')) {
      context.handle(
        _timestampMsMeta,
        timestampMs.isAcceptableOrUnknown(
          data['timestamp_ms']!,
          _timestampMsMeta,
        ),
      );
    }
    if (data.containsKey('crop_path')) {
      context.handle(
        _cropPathMeta,
        cropPath.isAcceptableOrUnknown(data['crop_path']!, _cropPathMeta),
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
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  BodyRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return BodyRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      mediaId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}media_id'],
      ),
      faceId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}face_id'],
      ),
      personId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}person_id'],
      ),
      bboxX: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}bbox_x'],
      )!,
      bboxY: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}bbox_y'],
      )!,
      bboxW: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}bbox_w'],
      )!,
      bboxH: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}bbox_h'],
      )!,
      score: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}score'],
      )!,
      kpts: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}kpts'],
      ),
      extent: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}extent'],
      ),
      appearance: attachedDatabase.typeMapping.read(
        DriftSqlType.blob,
        data['${effectivePrefix}appearance'],
      ),
      linkMethod: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}link_method'],
      ),
      linkConfidence: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}link_confidence'],
      ),
      weakFaceEmbedding: attachedDatabase.typeMapping.read(
        DriftSqlType.blob,
        data['${effectivePrefix}weak_face_embedding'],
      ),
      weakFaceQuality: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}weak_face_quality'],
      ),
      frameNumber: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}frame_number'],
      ),
      timestampMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}timestamp_ms'],
      ),
      cropPath: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}crop_path'],
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}created_at'],
      )!,
    );
  }

  @override
  $BodiesTable createAlias(String alias) {
    return $BodiesTable(attachedDatabase, alias);
  }
}

class BodyRow extends DataClass implements Insertable<BodyRow> {
  final int id;
  final int? mediaId;
  final int? faceId;
  final int? personId;
  final double bboxX;
  final double bboxY;
  final double bboxW;
  final double bboxH;
  final double score;
  final String? kpts;
  final String? extent;
  final Uint8List? appearance;
  final String? linkMethod;
  final double? linkConfidence;
  final Uint8List? weakFaceEmbedding;
  final double? weakFaceQuality;
  final int? frameNumber;
  final int? timestampMs;
  final String? cropPath;
  final int createdAt;
  const BodyRow({
    required this.id,
    this.mediaId,
    this.faceId,
    this.personId,
    required this.bboxX,
    required this.bboxY,
    required this.bboxW,
    required this.bboxH,
    required this.score,
    this.kpts,
    this.extent,
    this.appearance,
    this.linkMethod,
    this.linkConfidence,
    this.weakFaceEmbedding,
    this.weakFaceQuality,
    this.frameNumber,
    this.timestampMs,
    this.cropPath,
    required this.createdAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    if (!nullToAbsent || mediaId != null) {
      map['media_id'] = Variable<int>(mediaId);
    }
    if (!nullToAbsent || faceId != null) {
      map['face_id'] = Variable<int>(faceId);
    }
    if (!nullToAbsent || personId != null) {
      map['person_id'] = Variable<int>(personId);
    }
    map['bbox_x'] = Variable<double>(bboxX);
    map['bbox_y'] = Variable<double>(bboxY);
    map['bbox_w'] = Variable<double>(bboxW);
    map['bbox_h'] = Variable<double>(bboxH);
    map['score'] = Variable<double>(score);
    if (!nullToAbsent || kpts != null) {
      map['kpts'] = Variable<String>(kpts);
    }
    if (!nullToAbsent || extent != null) {
      map['extent'] = Variable<String>(extent);
    }
    if (!nullToAbsent || appearance != null) {
      map['appearance'] = Variable<Uint8List>(appearance);
    }
    if (!nullToAbsent || linkMethod != null) {
      map['link_method'] = Variable<String>(linkMethod);
    }
    if (!nullToAbsent || linkConfidence != null) {
      map['link_confidence'] = Variable<double>(linkConfidence);
    }
    if (!nullToAbsent || weakFaceEmbedding != null) {
      map['weak_face_embedding'] = Variable<Uint8List>(weakFaceEmbedding);
    }
    if (!nullToAbsent || weakFaceQuality != null) {
      map['weak_face_quality'] = Variable<double>(weakFaceQuality);
    }
    if (!nullToAbsent || frameNumber != null) {
      map['frame_number'] = Variable<int>(frameNumber);
    }
    if (!nullToAbsent || timestampMs != null) {
      map['timestamp_ms'] = Variable<int>(timestampMs);
    }
    if (!nullToAbsent || cropPath != null) {
      map['crop_path'] = Variable<String>(cropPath);
    }
    map['created_at'] = Variable<int>(createdAt);
    return map;
  }

  BodiesCompanion toCompanion(bool nullToAbsent) {
    return BodiesCompanion(
      id: Value(id),
      mediaId: mediaId == null && nullToAbsent
          ? const Value.absent()
          : Value(mediaId),
      faceId: faceId == null && nullToAbsent
          ? const Value.absent()
          : Value(faceId),
      personId: personId == null && nullToAbsent
          ? const Value.absent()
          : Value(personId),
      bboxX: Value(bboxX),
      bboxY: Value(bboxY),
      bboxW: Value(bboxW),
      bboxH: Value(bboxH),
      score: Value(score),
      kpts: kpts == null && nullToAbsent ? const Value.absent() : Value(kpts),
      extent: extent == null && nullToAbsent
          ? const Value.absent()
          : Value(extent),
      appearance: appearance == null && nullToAbsent
          ? const Value.absent()
          : Value(appearance),
      linkMethod: linkMethod == null && nullToAbsent
          ? const Value.absent()
          : Value(linkMethod),
      linkConfidence: linkConfidence == null && nullToAbsent
          ? const Value.absent()
          : Value(linkConfidence),
      weakFaceEmbedding: weakFaceEmbedding == null && nullToAbsent
          ? const Value.absent()
          : Value(weakFaceEmbedding),
      weakFaceQuality: weakFaceQuality == null && nullToAbsent
          ? const Value.absent()
          : Value(weakFaceQuality),
      frameNumber: frameNumber == null && nullToAbsent
          ? const Value.absent()
          : Value(frameNumber),
      timestampMs: timestampMs == null && nullToAbsent
          ? const Value.absent()
          : Value(timestampMs),
      cropPath: cropPath == null && nullToAbsent
          ? const Value.absent()
          : Value(cropPath),
      createdAt: Value(createdAt),
    );
  }

  factory BodyRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return BodyRow(
      id: serializer.fromJson<int>(json['id']),
      mediaId: serializer.fromJson<int?>(json['mediaId']),
      faceId: serializer.fromJson<int?>(json['faceId']),
      personId: serializer.fromJson<int?>(json['personId']),
      bboxX: serializer.fromJson<double>(json['bboxX']),
      bboxY: serializer.fromJson<double>(json['bboxY']),
      bboxW: serializer.fromJson<double>(json['bboxW']),
      bboxH: serializer.fromJson<double>(json['bboxH']),
      score: serializer.fromJson<double>(json['score']),
      kpts: serializer.fromJson<String?>(json['kpts']),
      extent: serializer.fromJson<String?>(json['extent']),
      appearance: serializer.fromJson<Uint8List?>(json['appearance']),
      linkMethod: serializer.fromJson<String?>(json['linkMethod']),
      linkConfidence: serializer.fromJson<double?>(json['linkConfidence']),
      weakFaceEmbedding: serializer.fromJson<Uint8List?>(
        json['weakFaceEmbedding'],
      ),
      weakFaceQuality: serializer.fromJson<double?>(json['weakFaceQuality']),
      frameNumber: serializer.fromJson<int?>(json['frameNumber']),
      timestampMs: serializer.fromJson<int?>(json['timestampMs']),
      cropPath: serializer.fromJson<String?>(json['cropPath']),
      createdAt: serializer.fromJson<int>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'mediaId': serializer.toJson<int?>(mediaId),
      'faceId': serializer.toJson<int?>(faceId),
      'personId': serializer.toJson<int?>(personId),
      'bboxX': serializer.toJson<double>(bboxX),
      'bboxY': serializer.toJson<double>(bboxY),
      'bboxW': serializer.toJson<double>(bboxW),
      'bboxH': serializer.toJson<double>(bboxH),
      'score': serializer.toJson<double>(score),
      'kpts': serializer.toJson<String?>(kpts),
      'extent': serializer.toJson<String?>(extent),
      'appearance': serializer.toJson<Uint8List?>(appearance),
      'linkMethod': serializer.toJson<String?>(linkMethod),
      'linkConfidence': serializer.toJson<double?>(linkConfidence),
      'weakFaceEmbedding': serializer.toJson<Uint8List?>(weakFaceEmbedding),
      'weakFaceQuality': serializer.toJson<double?>(weakFaceQuality),
      'frameNumber': serializer.toJson<int?>(frameNumber),
      'timestampMs': serializer.toJson<int?>(timestampMs),
      'cropPath': serializer.toJson<String?>(cropPath),
      'createdAt': serializer.toJson<int>(createdAt),
    };
  }

  BodyRow copyWith({
    int? id,
    Value<int?> mediaId = const Value.absent(),
    Value<int?> faceId = const Value.absent(),
    Value<int?> personId = const Value.absent(),
    double? bboxX,
    double? bboxY,
    double? bboxW,
    double? bboxH,
    double? score,
    Value<String?> kpts = const Value.absent(),
    Value<String?> extent = const Value.absent(),
    Value<Uint8List?> appearance = const Value.absent(),
    Value<String?> linkMethod = const Value.absent(),
    Value<double?> linkConfidence = const Value.absent(),
    Value<Uint8List?> weakFaceEmbedding = const Value.absent(),
    Value<double?> weakFaceQuality = const Value.absent(),
    Value<int?> frameNumber = const Value.absent(),
    Value<int?> timestampMs = const Value.absent(),
    Value<String?> cropPath = const Value.absent(),
    int? createdAt,
  }) => BodyRow(
    id: id ?? this.id,
    mediaId: mediaId.present ? mediaId.value : this.mediaId,
    faceId: faceId.present ? faceId.value : this.faceId,
    personId: personId.present ? personId.value : this.personId,
    bboxX: bboxX ?? this.bboxX,
    bboxY: bboxY ?? this.bboxY,
    bboxW: bboxW ?? this.bboxW,
    bboxH: bboxH ?? this.bboxH,
    score: score ?? this.score,
    kpts: kpts.present ? kpts.value : this.kpts,
    extent: extent.present ? extent.value : this.extent,
    appearance: appearance.present ? appearance.value : this.appearance,
    linkMethod: linkMethod.present ? linkMethod.value : this.linkMethod,
    linkConfidence: linkConfidence.present
        ? linkConfidence.value
        : this.linkConfidence,
    weakFaceEmbedding: weakFaceEmbedding.present
        ? weakFaceEmbedding.value
        : this.weakFaceEmbedding,
    weakFaceQuality: weakFaceQuality.present
        ? weakFaceQuality.value
        : this.weakFaceQuality,
    frameNumber: frameNumber.present ? frameNumber.value : this.frameNumber,
    timestampMs: timestampMs.present ? timestampMs.value : this.timestampMs,
    cropPath: cropPath.present ? cropPath.value : this.cropPath,
    createdAt: createdAt ?? this.createdAt,
  );
  BodyRow copyWithCompanion(BodiesCompanion data) {
    return BodyRow(
      id: data.id.present ? data.id.value : this.id,
      mediaId: data.mediaId.present ? data.mediaId.value : this.mediaId,
      faceId: data.faceId.present ? data.faceId.value : this.faceId,
      personId: data.personId.present ? data.personId.value : this.personId,
      bboxX: data.bboxX.present ? data.bboxX.value : this.bboxX,
      bboxY: data.bboxY.present ? data.bboxY.value : this.bboxY,
      bboxW: data.bboxW.present ? data.bboxW.value : this.bboxW,
      bboxH: data.bboxH.present ? data.bboxH.value : this.bboxH,
      score: data.score.present ? data.score.value : this.score,
      kpts: data.kpts.present ? data.kpts.value : this.kpts,
      extent: data.extent.present ? data.extent.value : this.extent,
      appearance: data.appearance.present
          ? data.appearance.value
          : this.appearance,
      linkMethod: data.linkMethod.present
          ? data.linkMethod.value
          : this.linkMethod,
      linkConfidence: data.linkConfidence.present
          ? data.linkConfidence.value
          : this.linkConfidence,
      weakFaceEmbedding: data.weakFaceEmbedding.present
          ? data.weakFaceEmbedding.value
          : this.weakFaceEmbedding,
      weakFaceQuality: data.weakFaceQuality.present
          ? data.weakFaceQuality.value
          : this.weakFaceQuality,
      frameNumber: data.frameNumber.present
          ? data.frameNumber.value
          : this.frameNumber,
      timestampMs: data.timestampMs.present
          ? data.timestampMs.value
          : this.timestampMs,
      cropPath: data.cropPath.present ? data.cropPath.value : this.cropPath,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('BodyRow(')
          ..write('id: $id, ')
          ..write('mediaId: $mediaId, ')
          ..write('faceId: $faceId, ')
          ..write('personId: $personId, ')
          ..write('bboxX: $bboxX, ')
          ..write('bboxY: $bboxY, ')
          ..write('bboxW: $bboxW, ')
          ..write('bboxH: $bboxH, ')
          ..write('score: $score, ')
          ..write('kpts: $kpts, ')
          ..write('extent: $extent, ')
          ..write('appearance: $appearance, ')
          ..write('linkMethod: $linkMethod, ')
          ..write('linkConfidence: $linkConfidence, ')
          ..write('weakFaceEmbedding: $weakFaceEmbedding, ')
          ..write('weakFaceQuality: $weakFaceQuality, ')
          ..write('frameNumber: $frameNumber, ')
          ..write('timestampMs: $timestampMs, ')
          ..write('cropPath: $cropPath, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    mediaId,
    faceId,
    personId,
    bboxX,
    bboxY,
    bboxW,
    bboxH,
    score,
    kpts,
    extent,
    $driftBlobEquality.hash(appearance),
    linkMethod,
    linkConfidence,
    $driftBlobEquality.hash(weakFaceEmbedding),
    weakFaceQuality,
    frameNumber,
    timestampMs,
    cropPath,
    createdAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is BodyRow &&
          other.id == this.id &&
          other.mediaId == this.mediaId &&
          other.faceId == this.faceId &&
          other.personId == this.personId &&
          other.bboxX == this.bboxX &&
          other.bboxY == this.bboxY &&
          other.bboxW == this.bboxW &&
          other.bboxH == this.bboxH &&
          other.score == this.score &&
          other.kpts == this.kpts &&
          other.extent == this.extent &&
          $driftBlobEquality.equals(other.appearance, this.appearance) &&
          other.linkMethod == this.linkMethod &&
          other.linkConfidence == this.linkConfidence &&
          $driftBlobEquality.equals(
            other.weakFaceEmbedding,
            this.weakFaceEmbedding,
          ) &&
          other.weakFaceQuality == this.weakFaceQuality &&
          other.frameNumber == this.frameNumber &&
          other.timestampMs == this.timestampMs &&
          other.cropPath == this.cropPath &&
          other.createdAt == this.createdAt);
}

class BodiesCompanion extends UpdateCompanion<BodyRow> {
  final Value<int> id;
  final Value<int?> mediaId;
  final Value<int?> faceId;
  final Value<int?> personId;
  final Value<double> bboxX;
  final Value<double> bboxY;
  final Value<double> bboxW;
  final Value<double> bboxH;
  final Value<double> score;
  final Value<String?> kpts;
  final Value<String?> extent;
  final Value<Uint8List?> appearance;
  final Value<String?> linkMethod;
  final Value<double?> linkConfidence;
  final Value<Uint8List?> weakFaceEmbedding;
  final Value<double?> weakFaceQuality;
  final Value<int?> frameNumber;
  final Value<int?> timestampMs;
  final Value<String?> cropPath;
  final Value<int> createdAt;
  const BodiesCompanion({
    this.id = const Value.absent(),
    this.mediaId = const Value.absent(),
    this.faceId = const Value.absent(),
    this.personId = const Value.absent(),
    this.bboxX = const Value.absent(),
    this.bboxY = const Value.absent(),
    this.bboxW = const Value.absent(),
    this.bboxH = const Value.absent(),
    this.score = const Value.absent(),
    this.kpts = const Value.absent(),
    this.extent = const Value.absent(),
    this.appearance = const Value.absent(),
    this.linkMethod = const Value.absent(),
    this.linkConfidence = const Value.absent(),
    this.weakFaceEmbedding = const Value.absent(),
    this.weakFaceQuality = const Value.absent(),
    this.frameNumber = const Value.absent(),
    this.timestampMs = const Value.absent(),
    this.cropPath = const Value.absent(),
    this.createdAt = const Value.absent(),
  });
  BodiesCompanion.insert({
    this.id = const Value.absent(),
    this.mediaId = const Value.absent(),
    this.faceId = const Value.absent(),
    this.personId = const Value.absent(),
    required double bboxX,
    required double bboxY,
    required double bboxW,
    required double bboxH,
    required double score,
    this.kpts = const Value.absent(),
    this.extent = const Value.absent(),
    this.appearance = const Value.absent(),
    this.linkMethod = const Value.absent(),
    this.linkConfidence = const Value.absent(),
    this.weakFaceEmbedding = const Value.absent(),
    this.weakFaceQuality = const Value.absent(),
    this.frameNumber = const Value.absent(),
    this.timestampMs = const Value.absent(),
    this.cropPath = const Value.absent(),
    required int createdAt,
  }) : bboxX = Value(bboxX),
       bboxY = Value(bboxY),
       bboxW = Value(bboxW),
       bboxH = Value(bboxH),
       score = Value(score),
       createdAt = Value(createdAt);
  static Insertable<BodyRow> custom({
    Expression<int>? id,
    Expression<int>? mediaId,
    Expression<int>? faceId,
    Expression<int>? personId,
    Expression<double>? bboxX,
    Expression<double>? bboxY,
    Expression<double>? bboxW,
    Expression<double>? bboxH,
    Expression<double>? score,
    Expression<String>? kpts,
    Expression<String>? extent,
    Expression<Uint8List>? appearance,
    Expression<String>? linkMethod,
    Expression<double>? linkConfidence,
    Expression<Uint8List>? weakFaceEmbedding,
    Expression<double>? weakFaceQuality,
    Expression<int>? frameNumber,
    Expression<int>? timestampMs,
    Expression<String>? cropPath,
    Expression<int>? createdAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (mediaId != null) 'media_id': mediaId,
      if (faceId != null) 'face_id': faceId,
      if (personId != null) 'person_id': personId,
      if (bboxX != null) 'bbox_x': bboxX,
      if (bboxY != null) 'bbox_y': bboxY,
      if (bboxW != null) 'bbox_w': bboxW,
      if (bboxH != null) 'bbox_h': bboxH,
      if (score != null) 'score': score,
      if (kpts != null) 'kpts': kpts,
      if (extent != null) 'extent': extent,
      if (appearance != null) 'appearance': appearance,
      if (linkMethod != null) 'link_method': linkMethod,
      if (linkConfidence != null) 'link_confidence': linkConfidence,
      if (weakFaceEmbedding != null) 'weak_face_embedding': weakFaceEmbedding,
      if (weakFaceQuality != null) 'weak_face_quality': weakFaceQuality,
      if (frameNumber != null) 'frame_number': frameNumber,
      if (timestampMs != null) 'timestamp_ms': timestampMs,
      if (cropPath != null) 'crop_path': cropPath,
      if (createdAt != null) 'created_at': createdAt,
    });
  }

  BodiesCompanion copyWith({
    Value<int>? id,
    Value<int?>? mediaId,
    Value<int?>? faceId,
    Value<int?>? personId,
    Value<double>? bboxX,
    Value<double>? bboxY,
    Value<double>? bboxW,
    Value<double>? bboxH,
    Value<double>? score,
    Value<String?>? kpts,
    Value<String?>? extent,
    Value<Uint8List?>? appearance,
    Value<String?>? linkMethod,
    Value<double?>? linkConfidence,
    Value<Uint8List?>? weakFaceEmbedding,
    Value<double?>? weakFaceQuality,
    Value<int?>? frameNumber,
    Value<int?>? timestampMs,
    Value<String?>? cropPath,
    Value<int>? createdAt,
  }) {
    return BodiesCompanion(
      id: id ?? this.id,
      mediaId: mediaId ?? this.mediaId,
      faceId: faceId ?? this.faceId,
      personId: personId ?? this.personId,
      bboxX: bboxX ?? this.bboxX,
      bboxY: bboxY ?? this.bboxY,
      bboxW: bboxW ?? this.bboxW,
      bboxH: bboxH ?? this.bboxH,
      score: score ?? this.score,
      kpts: kpts ?? this.kpts,
      extent: extent ?? this.extent,
      appearance: appearance ?? this.appearance,
      linkMethod: linkMethod ?? this.linkMethod,
      linkConfidence: linkConfidence ?? this.linkConfidence,
      weakFaceEmbedding: weakFaceEmbedding ?? this.weakFaceEmbedding,
      weakFaceQuality: weakFaceQuality ?? this.weakFaceQuality,
      frameNumber: frameNumber ?? this.frameNumber,
      timestampMs: timestampMs ?? this.timestampMs,
      cropPath: cropPath ?? this.cropPath,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (mediaId.present) {
      map['media_id'] = Variable<int>(mediaId.value);
    }
    if (faceId.present) {
      map['face_id'] = Variable<int>(faceId.value);
    }
    if (personId.present) {
      map['person_id'] = Variable<int>(personId.value);
    }
    if (bboxX.present) {
      map['bbox_x'] = Variable<double>(bboxX.value);
    }
    if (bboxY.present) {
      map['bbox_y'] = Variable<double>(bboxY.value);
    }
    if (bboxW.present) {
      map['bbox_w'] = Variable<double>(bboxW.value);
    }
    if (bboxH.present) {
      map['bbox_h'] = Variable<double>(bboxH.value);
    }
    if (score.present) {
      map['score'] = Variable<double>(score.value);
    }
    if (kpts.present) {
      map['kpts'] = Variable<String>(kpts.value);
    }
    if (extent.present) {
      map['extent'] = Variable<String>(extent.value);
    }
    if (appearance.present) {
      map['appearance'] = Variable<Uint8List>(appearance.value);
    }
    if (linkMethod.present) {
      map['link_method'] = Variable<String>(linkMethod.value);
    }
    if (linkConfidence.present) {
      map['link_confidence'] = Variable<double>(linkConfidence.value);
    }
    if (weakFaceEmbedding.present) {
      map['weak_face_embedding'] = Variable<Uint8List>(weakFaceEmbedding.value);
    }
    if (weakFaceQuality.present) {
      map['weak_face_quality'] = Variable<double>(weakFaceQuality.value);
    }
    if (frameNumber.present) {
      map['frame_number'] = Variable<int>(frameNumber.value);
    }
    if (timestampMs.present) {
      map['timestamp_ms'] = Variable<int>(timestampMs.value);
    }
    if (cropPath.present) {
      map['crop_path'] = Variable<String>(cropPath.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<int>(createdAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('BodiesCompanion(')
          ..write('id: $id, ')
          ..write('mediaId: $mediaId, ')
          ..write('faceId: $faceId, ')
          ..write('personId: $personId, ')
          ..write('bboxX: $bboxX, ')
          ..write('bboxY: $bboxY, ')
          ..write('bboxW: $bboxW, ')
          ..write('bboxH: $bboxH, ')
          ..write('score: $score, ')
          ..write('kpts: $kpts, ')
          ..write('extent: $extent, ')
          ..write('appearance: $appearance, ')
          ..write('linkMethod: $linkMethod, ')
          ..write('linkConfidence: $linkConfidence, ')
          ..write('weakFaceEmbedding: $weakFaceEmbedding, ')
          ..write('weakFaceQuality: $weakFaceQuality, ')
          ..write('frameNumber: $frameNumber, ')
          ..write('timestampMs: $timestampMs, ')
          ..write('cropPath: $cropPath, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }
}

class $FaceRejectionsTable extends FaceRejections
    with TableInfo<$FaceRejectionsTable, FaceRejectionRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $FaceRejectionsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _faceIdMeta = const VerificationMeta('faceId');
  @override
  late final GeneratedColumn<int> faceId = GeneratedColumn<int>(
    'face_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES faces (id) ON DELETE CASCADE',
    ),
  );
  static const VerificationMeta _personIdMeta = const VerificationMeta(
    'personId',
  );
  @override
  late final GeneratedColumn<int> personId = GeneratedColumn<int>(
    'person_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES persons (id) ON DELETE CASCADE',
    ),
  );
  @override
  List<GeneratedColumn> get $columns => [faceId, personId];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'face_rejections';
  @override
  VerificationContext validateIntegrity(
    Insertable<FaceRejectionRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('face_id')) {
      context.handle(
        _faceIdMeta,
        faceId.isAcceptableOrUnknown(data['face_id']!, _faceIdMeta),
      );
    } else if (isInserting) {
      context.missing(_faceIdMeta);
    }
    if (data.containsKey('person_id')) {
      context.handle(
        _personIdMeta,
        personId.isAcceptableOrUnknown(data['person_id']!, _personIdMeta),
      );
    } else if (isInserting) {
      context.missing(_personIdMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {faceId, personId};
  @override
  FaceRejectionRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return FaceRejectionRow(
      faceId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}face_id'],
      )!,
      personId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}person_id'],
      )!,
    );
  }

  @override
  $FaceRejectionsTable createAlias(String alias) {
    return $FaceRejectionsTable(attachedDatabase, alias);
  }
}

class FaceRejectionRow extends DataClass
    implements Insertable<FaceRejectionRow> {
  final int faceId;
  final int personId;
  const FaceRejectionRow({required this.faceId, required this.personId});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['face_id'] = Variable<int>(faceId);
    map['person_id'] = Variable<int>(personId);
    return map;
  }

  FaceRejectionsCompanion toCompanion(bool nullToAbsent) {
    return FaceRejectionsCompanion(
      faceId: Value(faceId),
      personId: Value(personId),
    );
  }

  factory FaceRejectionRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return FaceRejectionRow(
      faceId: serializer.fromJson<int>(json['faceId']),
      personId: serializer.fromJson<int>(json['personId']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'faceId': serializer.toJson<int>(faceId),
      'personId': serializer.toJson<int>(personId),
    };
  }

  FaceRejectionRow copyWith({int? faceId, int? personId}) => FaceRejectionRow(
    faceId: faceId ?? this.faceId,
    personId: personId ?? this.personId,
  );
  FaceRejectionRow copyWithCompanion(FaceRejectionsCompanion data) {
    return FaceRejectionRow(
      faceId: data.faceId.present ? data.faceId.value : this.faceId,
      personId: data.personId.present ? data.personId.value : this.personId,
    );
  }

  @override
  String toString() {
    return (StringBuffer('FaceRejectionRow(')
          ..write('faceId: $faceId, ')
          ..write('personId: $personId')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(faceId, personId);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is FaceRejectionRow &&
          other.faceId == this.faceId &&
          other.personId == this.personId);
}

class FaceRejectionsCompanion extends UpdateCompanion<FaceRejectionRow> {
  final Value<int> faceId;
  final Value<int> personId;
  final Value<int> rowid;
  const FaceRejectionsCompanion({
    this.faceId = const Value.absent(),
    this.personId = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  FaceRejectionsCompanion.insert({
    required int faceId,
    required int personId,
    this.rowid = const Value.absent(),
  }) : faceId = Value(faceId),
       personId = Value(personId);
  static Insertable<FaceRejectionRow> custom({
    Expression<int>? faceId,
    Expression<int>? personId,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (faceId != null) 'face_id': faceId,
      if (personId != null) 'person_id': personId,
      if (rowid != null) 'rowid': rowid,
    });
  }

  FaceRejectionsCompanion copyWith({
    Value<int>? faceId,
    Value<int>? personId,
    Value<int>? rowid,
  }) {
    return FaceRejectionsCompanion(
      faceId: faceId ?? this.faceId,
      personId: personId ?? this.personId,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (faceId.present) {
      map['face_id'] = Variable<int>(faceId.value);
    }
    if (personId.present) {
      map['person_id'] = Variable<int>(personId.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('FaceRejectionsCompanion(')
          ..write('faceId: $faceId, ')
          ..write('personId: $personId, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $BodyRejectionsTable extends BodyRejections
    with TableInfo<$BodyRejectionsTable, BodyRejectionRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $BodyRejectionsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _bodyIdMeta = const VerificationMeta('bodyId');
  @override
  late final GeneratedColumn<int> bodyId = GeneratedColumn<int>(
    'body_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES bodies (id) ON DELETE CASCADE',
    ),
  );
  static const VerificationMeta _personIdMeta = const VerificationMeta(
    'personId',
  );
  @override
  late final GeneratedColumn<int> personId = GeneratedColumn<int>(
    'person_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES persons (id) ON DELETE CASCADE',
    ),
  );
  @override
  List<GeneratedColumn> get $columns => [bodyId, personId];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'body_rejections';
  @override
  VerificationContext validateIntegrity(
    Insertable<BodyRejectionRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('body_id')) {
      context.handle(
        _bodyIdMeta,
        bodyId.isAcceptableOrUnknown(data['body_id']!, _bodyIdMeta),
      );
    } else if (isInserting) {
      context.missing(_bodyIdMeta);
    }
    if (data.containsKey('person_id')) {
      context.handle(
        _personIdMeta,
        personId.isAcceptableOrUnknown(data['person_id']!, _personIdMeta),
      );
    } else if (isInserting) {
      context.missing(_personIdMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {bodyId, personId};
  @override
  BodyRejectionRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return BodyRejectionRow(
      bodyId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}body_id'],
      )!,
      personId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}person_id'],
      )!,
    );
  }

  @override
  $BodyRejectionsTable createAlias(String alias) {
    return $BodyRejectionsTable(attachedDatabase, alias);
  }
}

class BodyRejectionRow extends DataClass
    implements Insertable<BodyRejectionRow> {
  final int bodyId;
  final int personId;
  const BodyRejectionRow({required this.bodyId, required this.personId});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['body_id'] = Variable<int>(bodyId);
    map['person_id'] = Variable<int>(personId);
    return map;
  }

  BodyRejectionsCompanion toCompanion(bool nullToAbsent) {
    return BodyRejectionsCompanion(
      bodyId: Value(bodyId),
      personId: Value(personId),
    );
  }

  factory BodyRejectionRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return BodyRejectionRow(
      bodyId: serializer.fromJson<int>(json['bodyId']),
      personId: serializer.fromJson<int>(json['personId']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'bodyId': serializer.toJson<int>(bodyId),
      'personId': serializer.toJson<int>(personId),
    };
  }

  BodyRejectionRow copyWith({int? bodyId, int? personId}) => BodyRejectionRow(
    bodyId: bodyId ?? this.bodyId,
    personId: personId ?? this.personId,
  );
  BodyRejectionRow copyWithCompanion(BodyRejectionsCompanion data) {
    return BodyRejectionRow(
      bodyId: data.bodyId.present ? data.bodyId.value : this.bodyId,
      personId: data.personId.present ? data.personId.value : this.personId,
    );
  }

  @override
  String toString() {
    return (StringBuffer('BodyRejectionRow(')
          ..write('bodyId: $bodyId, ')
          ..write('personId: $personId')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(bodyId, personId);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is BodyRejectionRow &&
          other.bodyId == this.bodyId &&
          other.personId == this.personId);
}

class BodyRejectionsCompanion extends UpdateCompanion<BodyRejectionRow> {
  final Value<int> bodyId;
  final Value<int> personId;
  final Value<int> rowid;
  const BodyRejectionsCompanion({
    this.bodyId = const Value.absent(),
    this.personId = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  BodyRejectionsCompanion.insert({
    required int bodyId,
    required int personId,
    this.rowid = const Value.absent(),
  }) : bodyId = Value(bodyId),
       personId = Value(personId);
  static Insertable<BodyRejectionRow> custom({
    Expression<int>? bodyId,
    Expression<int>? personId,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (bodyId != null) 'body_id': bodyId,
      if (personId != null) 'person_id': personId,
      if (rowid != null) 'rowid': rowid,
    });
  }

  BodyRejectionsCompanion copyWith({
    Value<int>? bodyId,
    Value<int>? personId,
    Value<int>? rowid,
  }) {
    return BodyRejectionsCompanion(
      bodyId: bodyId ?? this.bodyId,
      personId: personId ?? this.personId,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (bodyId.present) {
      map['body_id'] = Variable<int>(bodyId.value);
    }
    if (personId.present) {
      map['person_id'] = Variable<int>(personId.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('BodyRejectionsCompanion(')
          ..write('bodyId: $bodyId, ')
          ..write('personId: $personId, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $PersonDistinctTable extends PersonDistinct
    with TableInfo<$PersonDistinctTable, PersonDistinctRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $PersonDistinctTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _personAMeta = const VerificationMeta(
    'personA',
  );
  @override
  late final GeneratedColumn<int> personA = GeneratedColumn<int>(
    'person_a',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES persons (id) ON DELETE CASCADE',
    ),
  );
  static const VerificationMeta _personBMeta = const VerificationMeta(
    'personB',
  );
  @override
  late final GeneratedColumn<int> personB = GeneratedColumn<int>(
    'person_b',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES persons (id) ON DELETE CASCADE',
    ),
  );
  @override
  List<GeneratedColumn> get $columns => [personA, personB];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'person_distinct';
  @override
  VerificationContext validateIntegrity(
    Insertable<PersonDistinctRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('person_a')) {
      context.handle(
        _personAMeta,
        personA.isAcceptableOrUnknown(data['person_a']!, _personAMeta),
      );
    } else if (isInserting) {
      context.missing(_personAMeta);
    }
    if (data.containsKey('person_b')) {
      context.handle(
        _personBMeta,
        personB.isAcceptableOrUnknown(data['person_b']!, _personBMeta),
      );
    } else if (isInserting) {
      context.missing(_personBMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {personA, personB};
  @override
  PersonDistinctRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return PersonDistinctRow(
      personA: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}person_a'],
      )!,
      personB: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}person_b'],
      )!,
    );
  }

  @override
  $PersonDistinctTable createAlias(String alias) {
    return $PersonDistinctTable(attachedDatabase, alias);
  }
}

class PersonDistinctRow extends DataClass
    implements Insertable<PersonDistinctRow> {
  final int personA;
  final int personB;
  const PersonDistinctRow({required this.personA, required this.personB});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['person_a'] = Variable<int>(personA);
    map['person_b'] = Variable<int>(personB);
    return map;
  }

  PersonDistinctCompanion toCompanion(bool nullToAbsent) {
    return PersonDistinctCompanion(
      personA: Value(personA),
      personB: Value(personB),
    );
  }

  factory PersonDistinctRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return PersonDistinctRow(
      personA: serializer.fromJson<int>(json['personA']),
      personB: serializer.fromJson<int>(json['personB']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'personA': serializer.toJson<int>(personA),
      'personB': serializer.toJson<int>(personB),
    };
  }

  PersonDistinctRow copyWith({int? personA, int? personB}) => PersonDistinctRow(
    personA: personA ?? this.personA,
    personB: personB ?? this.personB,
  );
  PersonDistinctRow copyWithCompanion(PersonDistinctCompanion data) {
    return PersonDistinctRow(
      personA: data.personA.present ? data.personA.value : this.personA,
      personB: data.personB.present ? data.personB.value : this.personB,
    );
  }

  @override
  String toString() {
    return (StringBuffer('PersonDistinctRow(')
          ..write('personA: $personA, ')
          ..write('personB: $personB')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(personA, personB);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is PersonDistinctRow &&
          other.personA == this.personA &&
          other.personB == this.personB);
}

class PersonDistinctCompanion extends UpdateCompanion<PersonDistinctRow> {
  final Value<int> personA;
  final Value<int> personB;
  final Value<int> rowid;
  const PersonDistinctCompanion({
    this.personA = const Value.absent(),
    this.personB = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  PersonDistinctCompanion.insert({
    required int personA,
    required int personB,
    this.rowid = const Value.absent(),
  }) : personA = Value(personA),
       personB = Value(personB);
  static Insertable<PersonDistinctRow> custom({
    Expression<int>? personA,
    Expression<int>? personB,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (personA != null) 'person_a': personA,
      if (personB != null) 'person_b': personB,
      if (rowid != null) 'rowid': rowid,
    });
  }

  PersonDistinctCompanion copyWith({
    Value<int>? personA,
    Value<int>? personB,
    Value<int>? rowid,
  }) {
    return PersonDistinctCompanion(
      personA: personA ?? this.personA,
      personB: personB ?? this.personB,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (personA.present) {
      map['person_a'] = Variable<int>(personA.value);
    }
    if (personB.present) {
      map['person_b'] = Variable<int>(personB.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('PersonDistinctCompanion(')
          ..write('personA: $personA, ')
          ..write('personB: $personB, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ServersTable extends Servers with TableInfo<$ServersTable, ServerRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ServersTable(this.attachedDatabase, [this._alias]);
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
  static const VerificationMeta _hostMeta = const VerificationMeta('host');
  @override
  late final GeneratedColumn<String> host = GeneratedColumn<String>(
    'host',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _portMeta = const VerificationMeta('port');
  @override
  late final GeneratedColumn<int> port = GeneratedColumn<int>(
    'port',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _fingerprintMeta = const VerificationMeta(
    'fingerprint',
  );
  @override
  late final GeneratedColumn<String> fingerprint = GeneratedColumn<String>(
    'fingerprint',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _pairedAtMeta = const VerificationMeta(
    'pairedAt',
  );
  @override
  late final GeneratedColumn<int> pairedAt = GeneratedColumn<int>(
    'paired_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _lastSeenAtMeta = const VerificationMeta(
    'lastSeenAt',
  );
  @override
  late final GeneratedColumn<int> lastSeenAt = GeneratedColumn<int>(
    'last_seen_at',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    name,
    host,
    port,
    fingerprint,
    pairedAt,
    lastSeenAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'servers';
  @override
  VerificationContext validateIntegrity(
    Insertable<ServerRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
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
    if (data.containsKey('host')) {
      context.handle(
        _hostMeta,
        host.isAcceptableOrUnknown(data['host']!, _hostMeta),
      );
    } else if (isInserting) {
      context.missing(_hostMeta);
    }
    if (data.containsKey('port')) {
      context.handle(
        _portMeta,
        port.isAcceptableOrUnknown(data['port']!, _portMeta),
      );
    } else if (isInserting) {
      context.missing(_portMeta);
    }
    if (data.containsKey('fingerprint')) {
      context.handle(
        _fingerprintMeta,
        fingerprint.isAcceptableOrUnknown(
          data['fingerprint']!,
          _fingerprintMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_fingerprintMeta);
    }
    if (data.containsKey('paired_at')) {
      context.handle(
        _pairedAtMeta,
        pairedAt.isAcceptableOrUnknown(data['paired_at']!, _pairedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_pairedAtMeta);
    }
    if (data.containsKey('last_seen_at')) {
      context.handle(
        _lastSeenAtMeta,
        lastSeenAt.isAcceptableOrUnknown(
          data['last_seen_at']!,
          _lastSeenAtMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  ServerRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ServerRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      host: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}host'],
      )!,
      port: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}port'],
      )!,
      fingerprint: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}fingerprint'],
      )!,
      pairedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}paired_at'],
      )!,
      lastSeenAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}last_seen_at'],
      ),
    );
  }

  @override
  $ServersTable createAlias(String alias) {
    return $ServersTable(attachedDatabase, alias);
  }
}

class ServerRow extends DataClass implements Insertable<ServerRow> {
  final String id;
  final String name;
  final String host;
  final int port;
  final String fingerprint;
  final int pairedAt;
  final int? lastSeenAt;
  const ServerRow({
    required this.id,
    required this.name,
    required this.host,
    required this.port,
    required this.fingerprint,
    required this.pairedAt,
    this.lastSeenAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['name'] = Variable<String>(name);
    map['host'] = Variable<String>(host);
    map['port'] = Variable<int>(port);
    map['fingerprint'] = Variable<String>(fingerprint);
    map['paired_at'] = Variable<int>(pairedAt);
    if (!nullToAbsent || lastSeenAt != null) {
      map['last_seen_at'] = Variable<int>(lastSeenAt);
    }
    return map;
  }

  ServersCompanion toCompanion(bool nullToAbsent) {
    return ServersCompanion(
      id: Value(id),
      name: Value(name),
      host: Value(host),
      port: Value(port),
      fingerprint: Value(fingerprint),
      pairedAt: Value(pairedAt),
      lastSeenAt: lastSeenAt == null && nullToAbsent
          ? const Value.absent()
          : Value(lastSeenAt),
    );
  }

  factory ServerRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ServerRow(
      id: serializer.fromJson<String>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      host: serializer.fromJson<String>(json['host']),
      port: serializer.fromJson<int>(json['port']),
      fingerprint: serializer.fromJson<String>(json['fingerprint']),
      pairedAt: serializer.fromJson<int>(json['pairedAt']),
      lastSeenAt: serializer.fromJson<int?>(json['lastSeenAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'name': serializer.toJson<String>(name),
      'host': serializer.toJson<String>(host),
      'port': serializer.toJson<int>(port),
      'fingerprint': serializer.toJson<String>(fingerprint),
      'pairedAt': serializer.toJson<int>(pairedAt),
      'lastSeenAt': serializer.toJson<int?>(lastSeenAt),
    };
  }

  ServerRow copyWith({
    String? id,
    String? name,
    String? host,
    int? port,
    String? fingerprint,
    int? pairedAt,
    Value<int?> lastSeenAt = const Value.absent(),
  }) => ServerRow(
    id: id ?? this.id,
    name: name ?? this.name,
    host: host ?? this.host,
    port: port ?? this.port,
    fingerprint: fingerprint ?? this.fingerprint,
    pairedAt: pairedAt ?? this.pairedAt,
    lastSeenAt: lastSeenAt.present ? lastSeenAt.value : this.lastSeenAt,
  );
  ServerRow copyWithCompanion(ServersCompanion data) {
    return ServerRow(
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      host: data.host.present ? data.host.value : this.host,
      port: data.port.present ? data.port.value : this.port,
      fingerprint: data.fingerprint.present
          ? data.fingerprint.value
          : this.fingerprint,
      pairedAt: data.pairedAt.present ? data.pairedAt.value : this.pairedAt,
      lastSeenAt: data.lastSeenAt.present
          ? data.lastSeenAt.value
          : this.lastSeenAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ServerRow(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('host: $host, ')
          ..write('port: $port, ')
          ..write('fingerprint: $fingerprint, ')
          ..write('pairedAt: $pairedAt, ')
          ..write('lastSeenAt: $lastSeenAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(id, name, host, port, fingerprint, pairedAt, lastSeenAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ServerRow &&
          other.id == this.id &&
          other.name == this.name &&
          other.host == this.host &&
          other.port == this.port &&
          other.fingerprint == this.fingerprint &&
          other.pairedAt == this.pairedAt &&
          other.lastSeenAt == this.lastSeenAt);
}

class ServersCompanion extends UpdateCompanion<ServerRow> {
  final Value<String> id;
  final Value<String> name;
  final Value<String> host;
  final Value<int> port;
  final Value<String> fingerprint;
  final Value<int> pairedAt;
  final Value<int?> lastSeenAt;
  final Value<int> rowid;
  const ServersCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.host = const Value.absent(),
    this.port = const Value.absent(),
    this.fingerprint = const Value.absent(),
    this.pairedAt = const Value.absent(),
    this.lastSeenAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ServersCompanion.insert({
    required String id,
    required String name,
    required String host,
    required int port,
    required String fingerprint,
    required int pairedAt,
    this.lastSeenAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       name = Value(name),
       host = Value(host),
       port = Value(port),
       fingerprint = Value(fingerprint),
       pairedAt = Value(pairedAt);
  static Insertable<ServerRow> custom({
    Expression<String>? id,
    Expression<String>? name,
    Expression<String>? host,
    Expression<int>? port,
    Expression<String>? fingerprint,
    Expression<int>? pairedAt,
    Expression<int>? lastSeenAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (host != null) 'host': host,
      if (port != null) 'port': port,
      if (fingerprint != null) 'fingerprint': fingerprint,
      if (pairedAt != null) 'paired_at': pairedAt,
      if (lastSeenAt != null) 'last_seen_at': lastSeenAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ServersCompanion copyWith({
    Value<String>? id,
    Value<String>? name,
    Value<String>? host,
    Value<int>? port,
    Value<String>? fingerprint,
    Value<int>? pairedAt,
    Value<int?>? lastSeenAt,
    Value<int>? rowid,
  }) {
    return ServersCompanion(
      id: id ?? this.id,
      name: name ?? this.name,
      host: host ?? this.host,
      port: port ?? this.port,
      fingerprint: fingerprint ?? this.fingerprint,
      pairedAt: pairedAt ?? this.pairedAt,
      lastSeenAt: lastSeenAt ?? this.lastSeenAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (host.present) {
      map['host'] = Variable<String>(host.value);
    }
    if (port.present) {
      map['port'] = Variable<int>(port.value);
    }
    if (fingerprint.present) {
      map['fingerprint'] = Variable<String>(fingerprint.value);
    }
    if (pairedAt.present) {
      map['paired_at'] = Variable<int>(pairedAt.value);
    }
    if (lastSeenAt.present) {
      map['last_seen_at'] = Variable<int>(lastSeenAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ServersCompanion(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('host: $host, ')
          ..write('port: $port, ')
          ..write('fingerprint: $fingerprint, ')
          ..write('pairedAt: $pairedAt, ')
          ..write('lastSeenAt: $lastSeenAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $SettingsTable extends Settings
    with TableInfo<$SettingsTable, SettingRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SettingsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _keyMeta = const VerificationMeta('key');
  @override
  late final GeneratedColumn<String> key = GeneratedColumn<String>(
    'key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _valueMeta = const VerificationMeta('value');
  @override
  late final GeneratedColumn<String> value = GeneratedColumn<String>(
    'value',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [key, value];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'settings';
  @override
  VerificationContext validateIntegrity(
    Insertable<SettingRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('key')) {
      context.handle(
        _keyMeta,
        key.isAcceptableOrUnknown(data['key']!, _keyMeta),
      );
    } else if (isInserting) {
      context.missing(_keyMeta);
    }
    if (data.containsKey('value')) {
      context.handle(
        _valueMeta,
        value.isAcceptableOrUnknown(data['value']!, _valueMeta),
      );
    } else if (isInserting) {
      context.missing(_valueMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {key};
  @override
  SettingRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SettingRow(
      key: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}key'],
      )!,
      value: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}value'],
      )!,
    );
  }

  @override
  $SettingsTable createAlias(String alias) {
    return $SettingsTable(attachedDatabase, alias);
  }
}

class SettingRow extends DataClass implements Insertable<SettingRow> {
  final String key;
  final String value;
  const SettingRow({required this.key, required this.value});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['key'] = Variable<String>(key);
    map['value'] = Variable<String>(value);
    return map;
  }

  SettingsCompanion toCompanion(bool nullToAbsent) {
    return SettingsCompanion(key: Value(key), value: Value(value));
  }

  factory SettingRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SettingRow(
      key: serializer.fromJson<String>(json['key']),
      value: serializer.fromJson<String>(json['value']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'key': serializer.toJson<String>(key),
      'value': serializer.toJson<String>(value),
    };
  }

  SettingRow copyWith({String? key, String? value}) =>
      SettingRow(key: key ?? this.key, value: value ?? this.value);
  SettingRow copyWithCompanion(SettingsCompanion data) {
    return SettingRow(
      key: data.key.present ? data.key.value : this.key,
      value: data.value.present ? data.value.value : this.value,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SettingRow(')
          ..write('key: $key, ')
          ..write('value: $value')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(key, value);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SettingRow &&
          other.key == this.key &&
          other.value == this.value);
}

class SettingsCompanion extends UpdateCompanion<SettingRow> {
  final Value<String> key;
  final Value<String> value;
  final Value<int> rowid;
  const SettingsCompanion({
    this.key = const Value.absent(),
    this.value = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SettingsCompanion.insert({
    required String key,
    required String value,
    this.rowid = const Value.absent(),
  }) : key = Value(key),
       value = Value(value);
  static Insertable<SettingRow> custom({
    Expression<String>? key,
    Expression<String>? value,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (key != null) 'key': key,
      if (value != null) 'value': value,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SettingsCompanion copyWith({
    Value<String>? key,
    Value<String>? value,
    Value<int>? rowid,
  }) {
    return SettingsCompanion(
      key: key ?? this.key,
      value: value ?? this.value,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (key.present) {
      map['key'] = Variable<String>(key.value);
    }
    if (value.present) {
      map['value'] = Variable<String>(value.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SettingsCompanion(')
          ..write('key: $key, ')
          ..write('value: $value, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $UploadQueueTable extends UploadQueue
    with TableInfo<$UploadQueueTable, UploadQueueRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $UploadQueueTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _sha256Meta = const VerificationMeta('sha256');
  @override
  late final GeneratedColumn<String> sha256 = GeneratedColumn<String>(
    'sha256',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _localPathMeta = const VerificationMeta(
    'localPath',
  );
  @override
  late final GeneratedColumn<String> localPath = GeneratedColumn<String>(
    'local_path',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _sizeBytesMeta = const VerificationMeta(
    'sizeBytes',
  );
  @override
  late final GeneratedColumn<int> sizeBytes = GeneratedColumn<int>(
    'size_bytes',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _uploadedBytesMeta = const VerificationMeta(
    'uploadedBytes',
  );
  @override
  late final GeneratedColumn<int> uploadedBytes = GeneratedColumn<int>(
    'uploaded_bytes',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _stateMeta = const VerificationMeta('state');
  @override
  late final GeneratedColumn<String> state = GeneratedColumn<String>(
    'state',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('queued'),
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
  late final GeneratedColumn<int> createdAt = GeneratedColumn<int>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    sha256,
    localPath,
    sizeBytes,
    uploadedBytes,
    state,
    attempts,
    lastError,
    createdAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'upload_queue';
  @override
  VerificationContext validateIntegrity(
    Insertable<UploadQueueRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('sha256')) {
      context.handle(
        _sha256Meta,
        sha256.isAcceptableOrUnknown(data['sha256']!, _sha256Meta),
      );
    } else if (isInserting) {
      context.missing(_sha256Meta);
    }
    if (data.containsKey('local_path')) {
      context.handle(
        _localPathMeta,
        localPath.isAcceptableOrUnknown(data['local_path']!, _localPathMeta),
      );
    } else if (isInserting) {
      context.missing(_localPathMeta);
    }
    if (data.containsKey('size_bytes')) {
      context.handle(
        _sizeBytesMeta,
        sizeBytes.isAcceptableOrUnknown(data['size_bytes']!, _sizeBytesMeta),
      );
    } else if (isInserting) {
      context.missing(_sizeBytesMeta);
    }
    if (data.containsKey('uploaded_bytes')) {
      context.handle(
        _uploadedBytesMeta,
        uploadedBytes.isAcceptableOrUnknown(
          data['uploaded_bytes']!,
          _uploadedBytesMeta,
        ),
      );
    }
    if (data.containsKey('state')) {
      context.handle(
        _stateMeta,
        state.isAcceptableOrUnknown(data['state']!, _stateMeta),
      );
    }
    if (data.containsKey('attempts')) {
      context.handle(
        _attemptsMeta,
        attempts.isAcceptableOrUnknown(data['attempts']!, _attemptsMeta),
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
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  UploadQueueRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return UploadQueueRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      sha256: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}sha256'],
      )!,
      localPath: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}local_path'],
      )!,
      sizeBytes: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}size_bytes'],
      )!,
      uploadedBytes: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}uploaded_bytes'],
      )!,
      state: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}state'],
      )!,
      attempts: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}attempts'],
      )!,
      lastError: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}last_error'],
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}created_at'],
      )!,
    );
  }

  @override
  $UploadQueueTable createAlias(String alias) {
    return $UploadQueueTable(attachedDatabase, alias);
  }
}

class UploadQueueRow extends DataClass implements Insertable<UploadQueueRow> {
  final int id;
  final String sha256;
  final String localPath;
  final int sizeBytes;
  final int uploadedBytes;
  final String state;
  final int attempts;
  final String? lastError;
  final int createdAt;
  const UploadQueueRow({
    required this.id,
    required this.sha256,
    required this.localPath,
    required this.sizeBytes,
    required this.uploadedBytes,
    required this.state,
    required this.attempts,
    this.lastError,
    required this.createdAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['sha256'] = Variable<String>(sha256);
    map['local_path'] = Variable<String>(localPath);
    map['size_bytes'] = Variable<int>(sizeBytes);
    map['uploaded_bytes'] = Variable<int>(uploadedBytes);
    map['state'] = Variable<String>(state);
    map['attempts'] = Variable<int>(attempts);
    if (!nullToAbsent || lastError != null) {
      map['last_error'] = Variable<String>(lastError);
    }
    map['created_at'] = Variable<int>(createdAt);
    return map;
  }

  UploadQueueCompanion toCompanion(bool nullToAbsent) {
    return UploadQueueCompanion(
      id: Value(id),
      sha256: Value(sha256),
      localPath: Value(localPath),
      sizeBytes: Value(sizeBytes),
      uploadedBytes: Value(uploadedBytes),
      state: Value(state),
      attempts: Value(attempts),
      lastError: lastError == null && nullToAbsent
          ? const Value.absent()
          : Value(lastError),
      createdAt: Value(createdAt),
    );
  }

  factory UploadQueueRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return UploadQueueRow(
      id: serializer.fromJson<int>(json['id']),
      sha256: serializer.fromJson<String>(json['sha256']),
      localPath: serializer.fromJson<String>(json['localPath']),
      sizeBytes: serializer.fromJson<int>(json['sizeBytes']),
      uploadedBytes: serializer.fromJson<int>(json['uploadedBytes']),
      state: serializer.fromJson<String>(json['state']),
      attempts: serializer.fromJson<int>(json['attempts']),
      lastError: serializer.fromJson<String?>(json['lastError']),
      createdAt: serializer.fromJson<int>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'sha256': serializer.toJson<String>(sha256),
      'localPath': serializer.toJson<String>(localPath),
      'sizeBytes': serializer.toJson<int>(sizeBytes),
      'uploadedBytes': serializer.toJson<int>(uploadedBytes),
      'state': serializer.toJson<String>(state),
      'attempts': serializer.toJson<int>(attempts),
      'lastError': serializer.toJson<String?>(lastError),
      'createdAt': serializer.toJson<int>(createdAt),
    };
  }

  UploadQueueRow copyWith({
    int? id,
    String? sha256,
    String? localPath,
    int? sizeBytes,
    int? uploadedBytes,
    String? state,
    int? attempts,
    Value<String?> lastError = const Value.absent(),
    int? createdAt,
  }) => UploadQueueRow(
    id: id ?? this.id,
    sha256: sha256 ?? this.sha256,
    localPath: localPath ?? this.localPath,
    sizeBytes: sizeBytes ?? this.sizeBytes,
    uploadedBytes: uploadedBytes ?? this.uploadedBytes,
    state: state ?? this.state,
    attempts: attempts ?? this.attempts,
    lastError: lastError.present ? lastError.value : this.lastError,
    createdAt: createdAt ?? this.createdAt,
  );
  UploadQueueRow copyWithCompanion(UploadQueueCompanion data) {
    return UploadQueueRow(
      id: data.id.present ? data.id.value : this.id,
      sha256: data.sha256.present ? data.sha256.value : this.sha256,
      localPath: data.localPath.present ? data.localPath.value : this.localPath,
      sizeBytes: data.sizeBytes.present ? data.sizeBytes.value : this.sizeBytes,
      uploadedBytes: data.uploadedBytes.present
          ? data.uploadedBytes.value
          : this.uploadedBytes,
      state: data.state.present ? data.state.value : this.state,
      attempts: data.attempts.present ? data.attempts.value : this.attempts,
      lastError: data.lastError.present ? data.lastError.value : this.lastError,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('UploadQueueRow(')
          ..write('id: $id, ')
          ..write('sha256: $sha256, ')
          ..write('localPath: $localPath, ')
          ..write('sizeBytes: $sizeBytes, ')
          ..write('uploadedBytes: $uploadedBytes, ')
          ..write('state: $state, ')
          ..write('attempts: $attempts, ')
          ..write('lastError: $lastError, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    sha256,
    localPath,
    sizeBytes,
    uploadedBytes,
    state,
    attempts,
    lastError,
    createdAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is UploadQueueRow &&
          other.id == this.id &&
          other.sha256 == this.sha256 &&
          other.localPath == this.localPath &&
          other.sizeBytes == this.sizeBytes &&
          other.uploadedBytes == this.uploadedBytes &&
          other.state == this.state &&
          other.attempts == this.attempts &&
          other.lastError == this.lastError &&
          other.createdAt == this.createdAt);
}

class UploadQueueCompanion extends UpdateCompanion<UploadQueueRow> {
  final Value<int> id;
  final Value<String> sha256;
  final Value<String> localPath;
  final Value<int> sizeBytes;
  final Value<int> uploadedBytes;
  final Value<String> state;
  final Value<int> attempts;
  final Value<String?> lastError;
  final Value<int> createdAt;
  const UploadQueueCompanion({
    this.id = const Value.absent(),
    this.sha256 = const Value.absent(),
    this.localPath = const Value.absent(),
    this.sizeBytes = const Value.absent(),
    this.uploadedBytes = const Value.absent(),
    this.state = const Value.absent(),
    this.attempts = const Value.absent(),
    this.lastError = const Value.absent(),
    this.createdAt = const Value.absent(),
  });
  UploadQueueCompanion.insert({
    this.id = const Value.absent(),
    required String sha256,
    required String localPath,
    required int sizeBytes,
    this.uploadedBytes = const Value.absent(),
    this.state = const Value.absent(),
    this.attempts = const Value.absent(),
    this.lastError = const Value.absent(),
    required int createdAt,
  }) : sha256 = Value(sha256),
       localPath = Value(localPath),
       sizeBytes = Value(sizeBytes),
       createdAt = Value(createdAt);
  static Insertable<UploadQueueRow> custom({
    Expression<int>? id,
    Expression<String>? sha256,
    Expression<String>? localPath,
    Expression<int>? sizeBytes,
    Expression<int>? uploadedBytes,
    Expression<String>? state,
    Expression<int>? attempts,
    Expression<String>? lastError,
    Expression<int>? createdAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (sha256 != null) 'sha256': sha256,
      if (localPath != null) 'local_path': localPath,
      if (sizeBytes != null) 'size_bytes': sizeBytes,
      if (uploadedBytes != null) 'uploaded_bytes': uploadedBytes,
      if (state != null) 'state': state,
      if (attempts != null) 'attempts': attempts,
      if (lastError != null) 'last_error': lastError,
      if (createdAt != null) 'created_at': createdAt,
    });
  }

  UploadQueueCompanion copyWith({
    Value<int>? id,
    Value<String>? sha256,
    Value<String>? localPath,
    Value<int>? sizeBytes,
    Value<int>? uploadedBytes,
    Value<String>? state,
    Value<int>? attempts,
    Value<String?>? lastError,
    Value<int>? createdAt,
  }) {
    return UploadQueueCompanion(
      id: id ?? this.id,
      sha256: sha256 ?? this.sha256,
      localPath: localPath ?? this.localPath,
      sizeBytes: sizeBytes ?? this.sizeBytes,
      uploadedBytes: uploadedBytes ?? this.uploadedBytes,
      state: state ?? this.state,
      attempts: attempts ?? this.attempts,
      lastError: lastError ?? this.lastError,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (sha256.present) {
      map['sha256'] = Variable<String>(sha256.value);
    }
    if (localPath.present) {
      map['local_path'] = Variable<String>(localPath.value);
    }
    if (sizeBytes.present) {
      map['size_bytes'] = Variable<int>(sizeBytes.value);
    }
    if (uploadedBytes.present) {
      map['uploaded_bytes'] = Variable<int>(uploadedBytes.value);
    }
    if (state.present) {
      map['state'] = Variable<String>(state.value);
    }
    if (attempts.present) {
      map['attempts'] = Variable<int>(attempts.value);
    }
    if (lastError.present) {
      map['last_error'] = Variable<String>(lastError.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<int>(createdAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('UploadQueueCompanion(')
          ..write('id: $id, ')
          ..write('sha256: $sha256, ')
          ..write('localPath: $localPath, ')
          ..write('sizeBytes: $sizeBytes, ')
          ..write('uploadedBytes: $uploadedBytes, ')
          ..write('state: $state, ')
          ..write('attempts: $attempts, ')
          ..write('lastError: $lastError, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }
}

class $BlobHintsTable extends BlobHints
    with TableInfo<$BlobHintsTable, BlobHintRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $BlobHintsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _sha256Meta = const VerificationMeta('sha256');
  @override
  late final GeneratedColumn<String> sha256 = GeneratedColumn<String>(
    'sha256',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _serverIdMeta = const VerificationMeta(
    'serverId',
  );
  @override
  late final GeneratedColumn<String> serverId = GeneratedColumn<String>(
    'server_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _sizeBytesMeta = const VerificationMeta(
    'sizeBytes',
  );
  @override
  late final GeneratedColumn<int> sizeBytes = GeneratedColumn<int>(
    'size_bytes',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _lastSeenAtMeta = const VerificationMeta(
    'lastSeenAt',
  );
  @override
  late final GeneratedColumn<int> lastSeenAt = GeneratedColumn<int>(
    'last_seen_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    sha256,
    serverId,
    sizeBytes,
    lastSeenAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'blob_hints';
  @override
  VerificationContext validateIntegrity(
    Insertable<BlobHintRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('sha256')) {
      context.handle(
        _sha256Meta,
        sha256.isAcceptableOrUnknown(data['sha256']!, _sha256Meta),
      );
    } else if (isInserting) {
      context.missing(_sha256Meta);
    }
    if (data.containsKey('server_id')) {
      context.handle(
        _serverIdMeta,
        serverId.isAcceptableOrUnknown(data['server_id']!, _serverIdMeta),
      );
    } else if (isInserting) {
      context.missing(_serverIdMeta);
    }
    if (data.containsKey('size_bytes')) {
      context.handle(
        _sizeBytesMeta,
        sizeBytes.isAcceptableOrUnknown(data['size_bytes']!, _sizeBytesMeta),
      );
    } else if (isInserting) {
      context.missing(_sizeBytesMeta);
    }
    if (data.containsKey('last_seen_at')) {
      context.handle(
        _lastSeenAtMeta,
        lastSeenAt.isAcceptableOrUnknown(
          data['last_seen_at']!,
          _lastSeenAtMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_lastSeenAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {sha256, serverId};
  @override
  BlobHintRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return BlobHintRow(
      sha256: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}sha256'],
      )!,
      serverId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}server_id'],
      )!,
      sizeBytes: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}size_bytes'],
      )!,
      lastSeenAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}last_seen_at'],
      )!,
    );
  }

  @override
  $BlobHintsTable createAlias(String alias) {
    return $BlobHintsTable(attachedDatabase, alias);
  }
}

class BlobHintRow extends DataClass implements Insertable<BlobHintRow> {
  final String sha256;
  final String serverId;
  final int sizeBytes;
  final int lastSeenAt;
  const BlobHintRow({
    required this.sha256,
    required this.serverId,
    required this.sizeBytes,
    required this.lastSeenAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['sha256'] = Variable<String>(sha256);
    map['server_id'] = Variable<String>(serverId);
    map['size_bytes'] = Variable<int>(sizeBytes);
    map['last_seen_at'] = Variable<int>(lastSeenAt);
    return map;
  }

  BlobHintsCompanion toCompanion(bool nullToAbsent) {
    return BlobHintsCompanion(
      sha256: Value(sha256),
      serverId: Value(serverId),
      sizeBytes: Value(sizeBytes),
      lastSeenAt: Value(lastSeenAt),
    );
  }

  factory BlobHintRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return BlobHintRow(
      sha256: serializer.fromJson<String>(json['sha256']),
      serverId: serializer.fromJson<String>(json['serverId']),
      sizeBytes: serializer.fromJson<int>(json['sizeBytes']),
      lastSeenAt: serializer.fromJson<int>(json['lastSeenAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'sha256': serializer.toJson<String>(sha256),
      'serverId': serializer.toJson<String>(serverId),
      'sizeBytes': serializer.toJson<int>(sizeBytes),
      'lastSeenAt': serializer.toJson<int>(lastSeenAt),
    };
  }

  BlobHintRow copyWith({
    String? sha256,
    String? serverId,
    int? sizeBytes,
    int? lastSeenAt,
  }) => BlobHintRow(
    sha256: sha256 ?? this.sha256,
    serverId: serverId ?? this.serverId,
    sizeBytes: sizeBytes ?? this.sizeBytes,
    lastSeenAt: lastSeenAt ?? this.lastSeenAt,
  );
  BlobHintRow copyWithCompanion(BlobHintsCompanion data) {
    return BlobHintRow(
      sha256: data.sha256.present ? data.sha256.value : this.sha256,
      serverId: data.serverId.present ? data.serverId.value : this.serverId,
      sizeBytes: data.sizeBytes.present ? data.sizeBytes.value : this.sizeBytes,
      lastSeenAt: data.lastSeenAt.present
          ? data.lastSeenAt.value
          : this.lastSeenAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('BlobHintRow(')
          ..write('sha256: $sha256, ')
          ..write('serverId: $serverId, ')
          ..write('sizeBytes: $sizeBytes, ')
          ..write('lastSeenAt: $lastSeenAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(sha256, serverId, sizeBytes, lastSeenAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is BlobHintRow &&
          other.sha256 == this.sha256 &&
          other.serverId == this.serverId &&
          other.sizeBytes == this.sizeBytes &&
          other.lastSeenAt == this.lastSeenAt);
}

class BlobHintsCompanion extends UpdateCompanion<BlobHintRow> {
  final Value<String> sha256;
  final Value<String> serverId;
  final Value<int> sizeBytes;
  final Value<int> lastSeenAt;
  final Value<int> rowid;
  const BlobHintsCompanion({
    this.sha256 = const Value.absent(),
    this.serverId = const Value.absent(),
    this.sizeBytes = const Value.absent(),
    this.lastSeenAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  BlobHintsCompanion.insert({
    required String sha256,
    required String serverId,
    required int sizeBytes,
    required int lastSeenAt,
    this.rowid = const Value.absent(),
  }) : sha256 = Value(sha256),
       serverId = Value(serverId),
       sizeBytes = Value(sizeBytes),
       lastSeenAt = Value(lastSeenAt);
  static Insertable<BlobHintRow> custom({
    Expression<String>? sha256,
    Expression<String>? serverId,
    Expression<int>? sizeBytes,
    Expression<int>? lastSeenAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (sha256 != null) 'sha256': sha256,
      if (serverId != null) 'server_id': serverId,
      if (sizeBytes != null) 'size_bytes': sizeBytes,
      if (lastSeenAt != null) 'last_seen_at': lastSeenAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  BlobHintsCompanion copyWith({
    Value<String>? sha256,
    Value<String>? serverId,
    Value<int>? sizeBytes,
    Value<int>? lastSeenAt,
    Value<int>? rowid,
  }) {
    return BlobHintsCompanion(
      sha256: sha256 ?? this.sha256,
      serverId: serverId ?? this.serverId,
      sizeBytes: sizeBytes ?? this.sizeBytes,
      lastSeenAt: lastSeenAt ?? this.lastSeenAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (sha256.present) {
      map['sha256'] = Variable<String>(sha256.value);
    }
    if (serverId.present) {
      map['server_id'] = Variable<String>(serverId.value);
    }
    if (sizeBytes.present) {
      map['size_bytes'] = Variable<int>(sizeBytes.value);
    }
    if (lastSeenAt.present) {
      map['last_seen_at'] = Variable<int>(lastSeenAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('BlobHintsCompanion(')
          ..write('sha256: $sha256, ')
          ..write('serverId: $serverId, ')
          ..write('sizeBytes: $sizeBytes, ')
          ..write('lastSeenAt: $lastSeenAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $MediaDetectionsTable extends MediaDetections
    with TableInfo<$MediaDetectionsTable, DetectionRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $MediaDetectionsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _mediaIdMeta = const VerificationMeta(
    'mediaId',
  );
  @override
  late final GeneratedColumn<int> mediaId = GeneratedColumn<int>(
    'media_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES media (id) ON DELETE CASCADE',
    ),
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
  static const VerificationMeta _refIdMeta = const VerificationMeta('refId');
  @override
  late final GeneratedColumn<int> refId = GeneratedColumn<int>(
    'ref_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _xMeta = const VerificationMeta('x');
  @override
  late final GeneratedColumn<double> x = GeneratedColumn<double>(
    'x',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _yMeta = const VerificationMeta('y');
  @override
  late final GeneratedColumn<double> y = GeneratedColumn<double>(
    'y',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _wMeta = const VerificationMeta('w');
  @override
  late final GeneratedColumn<double> w = GeneratedColumn<double>(
    'w',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _hMeta = const VerificationMeta('h');
  @override
  late final GeneratedColumn<double> h = GeneratedColumn<double>(
    'h',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _frameNumberMeta = const VerificationMeta(
    'frameNumber',
  );
  @override
  late final GeneratedColumn<int> frameNumber = GeneratedColumn<int>(
    'frame_number',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _timestampMsMeta = const VerificationMeta(
    'timestampMs',
  );
  @override
  late final GeneratedColumn<int> timestampMs = GeneratedColumn<int>(
    'timestamp_ms',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    mediaId,
    kind,
    refId,
    x,
    y,
    w,
    h,
    frameNumber,
    timestampMs,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'media_detections';
  @override
  VerificationContext validateIntegrity(
    Insertable<DetectionRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('media_id')) {
      context.handle(
        _mediaIdMeta,
        mediaId.isAcceptableOrUnknown(data['media_id']!, _mediaIdMeta),
      );
    } else if (isInserting) {
      context.missing(_mediaIdMeta);
    }
    if (data.containsKey('kind')) {
      context.handle(
        _kindMeta,
        kind.isAcceptableOrUnknown(data['kind']!, _kindMeta),
      );
    } else if (isInserting) {
      context.missing(_kindMeta);
    }
    if (data.containsKey('ref_id')) {
      context.handle(
        _refIdMeta,
        refId.isAcceptableOrUnknown(data['ref_id']!, _refIdMeta),
      );
    } else if (isInserting) {
      context.missing(_refIdMeta);
    }
    if (data.containsKey('x')) {
      context.handle(_xMeta, x.isAcceptableOrUnknown(data['x']!, _xMeta));
    } else if (isInserting) {
      context.missing(_xMeta);
    }
    if (data.containsKey('y')) {
      context.handle(_yMeta, y.isAcceptableOrUnknown(data['y']!, _yMeta));
    } else if (isInserting) {
      context.missing(_yMeta);
    }
    if (data.containsKey('w')) {
      context.handle(_wMeta, w.isAcceptableOrUnknown(data['w']!, _wMeta));
    } else if (isInserting) {
      context.missing(_wMeta);
    }
    if (data.containsKey('h')) {
      context.handle(_hMeta, h.isAcceptableOrUnknown(data['h']!, _hMeta));
    } else if (isInserting) {
      context.missing(_hMeta);
    }
    if (data.containsKey('frame_number')) {
      context.handle(
        _frameNumberMeta,
        frameNumber.isAcceptableOrUnknown(
          data['frame_number']!,
          _frameNumberMeta,
        ),
      );
    }
    if (data.containsKey('timestamp_ms')) {
      context.handle(
        _timestampMsMeta,
        timestampMs.isAcceptableOrUnknown(
          data['timestamp_ms']!,
          _timestampMsMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  DetectionRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return DetectionRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      mediaId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}media_id'],
      )!,
      kind: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}kind'],
      )!,
      refId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}ref_id'],
      )!,
      x: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}x'],
      )!,
      y: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}y'],
      )!,
      w: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}w'],
      )!,
      h: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}h'],
      )!,
      frameNumber: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}frame_number'],
      ),
      timestampMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}timestamp_ms'],
      ),
    );
  }

  @override
  $MediaDetectionsTable createAlias(String alias) {
    return $MediaDetectionsTable(attachedDatabase, alias);
  }
}

class DetectionRow extends DataClass implements Insertable<DetectionRow> {
  final int id;
  final int mediaId;
  final String kind;
  final int refId;
  final double x;
  final double y;
  final double w;
  final double h;
  final int? frameNumber;
  final int? timestampMs;
  const DetectionRow({
    required this.id,
    required this.mediaId,
    required this.kind,
    required this.refId,
    required this.x,
    required this.y,
    required this.w,
    required this.h,
    this.frameNumber,
    this.timestampMs,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['media_id'] = Variable<int>(mediaId);
    map['kind'] = Variable<String>(kind);
    map['ref_id'] = Variable<int>(refId);
    map['x'] = Variable<double>(x);
    map['y'] = Variable<double>(y);
    map['w'] = Variable<double>(w);
    map['h'] = Variable<double>(h);
    if (!nullToAbsent || frameNumber != null) {
      map['frame_number'] = Variable<int>(frameNumber);
    }
    if (!nullToAbsent || timestampMs != null) {
      map['timestamp_ms'] = Variable<int>(timestampMs);
    }
    return map;
  }

  MediaDetectionsCompanion toCompanion(bool nullToAbsent) {
    return MediaDetectionsCompanion(
      id: Value(id),
      mediaId: Value(mediaId),
      kind: Value(kind),
      refId: Value(refId),
      x: Value(x),
      y: Value(y),
      w: Value(w),
      h: Value(h),
      frameNumber: frameNumber == null && nullToAbsent
          ? const Value.absent()
          : Value(frameNumber),
      timestampMs: timestampMs == null && nullToAbsent
          ? const Value.absent()
          : Value(timestampMs),
    );
  }

  factory DetectionRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return DetectionRow(
      id: serializer.fromJson<int>(json['id']),
      mediaId: serializer.fromJson<int>(json['mediaId']),
      kind: serializer.fromJson<String>(json['kind']),
      refId: serializer.fromJson<int>(json['refId']),
      x: serializer.fromJson<double>(json['x']),
      y: serializer.fromJson<double>(json['y']),
      w: serializer.fromJson<double>(json['w']),
      h: serializer.fromJson<double>(json['h']),
      frameNumber: serializer.fromJson<int?>(json['frameNumber']),
      timestampMs: serializer.fromJson<int?>(json['timestampMs']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'mediaId': serializer.toJson<int>(mediaId),
      'kind': serializer.toJson<String>(kind),
      'refId': serializer.toJson<int>(refId),
      'x': serializer.toJson<double>(x),
      'y': serializer.toJson<double>(y),
      'w': serializer.toJson<double>(w),
      'h': serializer.toJson<double>(h),
      'frameNumber': serializer.toJson<int?>(frameNumber),
      'timestampMs': serializer.toJson<int?>(timestampMs),
    };
  }

  DetectionRow copyWith({
    int? id,
    int? mediaId,
    String? kind,
    int? refId,
    double? x,
    double? y,
    double? w,
    double? h,
    Value<int?> frameNumber = const Value.absent(),
    Value<int?> timestampMs = const Value.absent(),
  }) => DetectionRow(
    id: id ?? this.id,
    mediaId: mediaId ?? this.mediaId,
    kind: kind ?? this.kind,
    refId: refId ?? this.refId,
    x: x ?? this.x,
    y: y ?? this.y,
    w: w ?? this.w,
    h: h ?? this.h,
    frameNumber: frameNumber.present ? frameNumber.value : this.frameNumber,
    timestampMs: timestampMs.present ? timestampMs.value : this.timestampMs,
  );
  DetectionRow copyWithCompanion(MediaDetectionsCompanion data) {
    return DetectionRow(
      id: data.id.present ? data.id.value : this.id,
      mediaId: data.mediaId.present ? data.mediaId.value : this.mediaId,
      kind: data.kind.present ? data.kind.value : this.kind,
      refId: data.refId.present ? data.refId.value : this.refId,
      x: data.x.present ? data.x.value : this.x,
      y: data.y.present ? data.y.value : this.y,
      w: data.w.present ? data.w.value : this.w,
      h: data.h.present ? data.h.value : this.h,
      frameNumber: data.frameNumber.present
          ? data.frameNumber.value
          : this.frameNumber,
      timestampMs: data.timestampMs.present
          ? data.timestampMs.value
          : this.timestampMs,
    );
  }

  @override
  String toString() {
    return (StringBuffer('DetectionRow(')
          ..write('id: $id, ')
          ..write('mediaId: $mediaId, ')
          ..write('kind: $kind, ')
          ..write('refId: $refId, ')
          ..write('x: $x, ')
          ..write('y: $y, ')
          ..write('w: $w, ')
          ..write('h: $h, ')
          ..write('frameNumber: $frameNumber, ')
          ..write('timestampMs: $timestampMs')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    mediaId,
    kind,
    refId,
    x,
    y,
    w,
    h,
    frameNumber,
    timestampMs,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is DetectionRow &&
          other.id == this.id &&
          other.mediaId == this.mediaId &&
          other.kind == this.kind &&
          other.refId == this.refId &&
          other.x == this.x &&
          other.y == this.y &&
          other.w == this.w &&
          other.h == this.h &&
          other.frameNumber == this.frameNumber &&
          other.timestampMs == this.timestampMs);
}

class MediaDetectionsCompanion extends UpdateCompanion<DetectionRow> {
  final Value<int> id;
  final Value<int> mediaId;
  final Value<String> kind;
  final Value<int> refId;
  final Value<double> x;
  final Value<double> y;
  final Value<double> w;
  final Value<double> h;
  final Value<int?> frameNumber;
  final Value<int?> timestampMs;
  const MediaDetectionsCompanion({
    this.id = const Value.absent(),
    this.mediaId = const Value.absent(),
    this.kind = const Value.absent(),
    this.refId = const Value.absent(),
    this.x = const Value.absent(),
    this.y = const Value.absent(),
    this.w = const Value.absent(),
    this.h = const Value.absent(),
    this.frameNumber = const Value.absent(),
    this.timestampMs = const Value.absent(),
  });
  MediaDetectionsCompanion.insert({
    this.id = const Value.absent(),
    required int mediaId,
    required String kind,
    required int refId,
    required double x,
    required double y,
    required double w,
    required double h,
    this.frameNumber = const Value.absent(),
    this.timestampMs = const Value.absent(),
  }) : mediaId = Value(mediaId),
       kind = Value(kind),
       refId = Value(refId),
       x = Value(x),
       y = Value(y),
       w = Value(w),
       h = Value(h);
  static Insertable<DetectionRow> custom({
    Expression<int>? id,
    Expression<int>? mediaId,
    Expression<String>? kind,
    Expression<int>? refId,
    Expression<double>? x,
    Expression<double>? y,
    Expression<double>? w,
    Expression<double>? h,
    Expression<int>? frameNumber,
    Expression<int>? timestampMs,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (mediaId != null) 'media_id': mediaId,
      if (kind != null) 'kind': kind,
      if (refId != null) 'ref_id': refId,
      if (x != null) 'x': x,
      if (y != null) 'y': y,
      if (w != null) 'w': w,
      if (h != null) 'h': h,
      if (frameNumber != null) 'frame_number': frameNumber,
      if (timestampMs != null) 'timestamp_ms': timestampMs,
    });
  }

  MediaDetectionsCompanion copyWith({
    Value<int>? id,
    Value<int>? mediaId,
    Value<String>? kind,
    Value<int>? refId,
    Value<double>? x,
    Value<double>? y,
    Value<double>? w,
    Value<double>? h,
    Value<int?>? frameNumber,
    Value<int?>? timestampMs,
  }) {
    return MediaDetectionsCompanion(
      id: id ?? this.id,
      mediaId: mediaId ?? this.mediaId,
      kind: kind ?? this.kind,
      refId: refId ?? this.refId,
      x: x ?? this.x,
      y: y ?? this.y,
      w: w ?? this.w,
      h: h ?? this.h,
      frameNumber: frameNumber ?? this.frameNumber,
      timestampMs: timestampMs ?? this.timestampMs,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (mediaId.present) {
      map['media_id'] = Variable<int>(mediaId.value);
    }
    if (kind.present) {
      map['kind'] = Variable<String>(kind.value);
    }
    if (refId.present) {
      map['ref_id'] = Variable<int>(refId.value);
    }
    if (x.present) {
      map['x'] = Variable<double>(x.value);
    }
    if (y.present) {
      map['y'] = Variable<double>(y.value);
    }
    if (w.present) {
      map['w'] = Variable<double>(w.value);
    }
    if (h.present) {
      map['h'] = Variable<double>(h.value);
    }
    if (frameNumber.present) {
      map['frame_number'] = Variable<int>(frameNumber.value);
    }
    if (timestampMs.present) {
      map['timestamp_ms'] = Variable<int>(timestampMs.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('MediaDetectionsCompanion(')
          ..write('id: $id, ')
          ..write('mediaId: $mediaId, ')
          ..write('kind: $kind, ')
          ..write('refId: $refId, ')
          ..write('x: $x, ')
          ..write('y: $y, ')
          ..write('w: $w, ')
          ..write('h: $h, ')
          ..write('frameNumber: $frameNumber, ')
          ..write('timestampMs: $timestampMs')
          ..write(')'))
        .toString();
  }
}

class $ReviewMatchesTable extends ReviewMatches
    with TableInfo<$ReviewMatchesTable, ReviewMatchRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ReviewMatchesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _faceIdMeta = const VerificationMeta('faceId');
  @override
  late final GeneratedColumn<int> faceId = GeneratedColumn<int>(
    'face_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES faces (id) ON DELETE CASCADE',
    ),
  );
  static const VerificationMeta _personIdMeta = const VerificationMeta(
    'personId',
  );
  @override
  late final GeneratedColumn<int> personId = GeneratedColumn<int>(
    'person_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES persons (id) ON DELETE CASCADE',
    ),
  );
  static const VerificationMeta _scoreMeta = const VerificationMeta('score');
  @override
  late final GeneratedColumn<double> score = GeneratedColumn<double>(
    'score',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _marginMeta = const VerificationMeta('margin');
  @override
  late final GeneratedColumn<double> margin = GeneratedColumn<double>(
    'margin',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _decisionMeta = const VerificationMeta(
    'decision',
  );
  @override
  late final GeneratedColumn<String> decision = GeneratedColumn<String>(
    'decision',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    faceId,
    personId,
    score,
    margin,
    decision,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'review_matches';
  @override
  VerificationContext validateIntegrity(
    Insertable<ReviewMatchRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('face_id')) {
      context.handle(
        _faceIdMeta,
        faceId.isAcceptableOrUnknown(data['face_id']!, _faceIdMeta),
      );
    }
    if (data.containsKey('person_id')) {
      context.handle(
        _personIdMeta,
        personId.isAcceptableOrUnknown(data['person_id']!, _personIdMeta),
      );
    } else if (isInserting) {
      context.missing(_personIdMeta);
    }
    if (data.containsKey('score')) {
      context.handle(
        _scoreMeta,
        score.isAcceptableOrUnknown(data['score']!, _scoreMeta),
      );
    } else if (isInserting) {
      context.missing(_scoreMeta);
    }
    if (data.containsKey('margin')) {
      context.handle(
        _marginMeta,
        margin.isAcceptableOrUnknown(data['margin']!, _marginMeta),
      );
    } else if (isInserting) {
      context.missing(_marginMeta);
    }
    if (data.containsKey('decision')) {
      context.handle(
        _decisionMeta,
        decision.isAcceptableOrUnknown(data['decision']!, _decisionMeta),
      );
    } else if (isInserting) {
      context.missing(_decisionMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {faceId};
  @override
  ReviewMatchRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ReviewMatchRow(
      faceId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}face_id'],
      )!,
      personId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}person_id'],
      )!,
      score: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}score'],
      )!,
      margin: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}margin'],
      )!,
      decision: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}decision'],
      )!,
    );
  }

  @override
  $ReviewMatchesTable createAlias(String alias) {
    return $ReviewMatchesTable(attachedDatabase, alias);
  }
}

class ReviewMatchRow extends DataClass implements Insertable<ReviewMatchRow> {
  final int faceId;
  final int personId;
  final double score;
  final double margin;
  final String decision;
  const ReviewMatchRow({
    required this.faceId,
    required this.personId,
    required this.score,
    required this.margin,
    required this.decision,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['face_id'] = Variable<int>(faceId);
    map['person_id'] = Variable<int>(personId);
    map['score'] = Variable<double>(score);
    map['margin'] = Variable<double>(margin);
    map['decision'] = Variable<String>(decision);
    return map;
  }

  ReviewMatchesCompanion toCompanion(bool nullToAbsent) {
    return ReviewMatchesCompanion(
      faceId: Value(faceId),
      personId: Value(personId),
      score: Value(score),
      margin: Value(margin),
      decision: Value(decision),
    );
  }

  factory ReviewMatchRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ReviewMatchRow(
      faceId: serializer.fromJson<int>(json['faceId']),
      personId: serializer.fromJson<int>(json['personId']),
      score: serializer.fromJson<double>(json['score']),
      margin: serializer.fromJson<double>(json['margin']),
      decision: serializer.fromJson<String>(json['decision']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'faceId': serializer.toJson<int>(faceId),
      'personId': serializer.toJson<int>(personId),
      'score': serializer.toJson<double>(score),
      'margin': serializer.toJson<double>(margin),
      'decision': serializer.toJson<String>(decision),
    };
  }

  ReviewMatchRow copyWith({
    int? faceId,
    int? personId,
    double? score,
    double? margin,
    String? decision,
  }) => ReviewMatchRow(
    faceId: faceId ?? this.faceId,
    personId: personId ?? this.personId,
    score: score ?? this.score,
    margin: margin ?? this.margin,
    decision: decision ?? this.decision,
  );
  ReviewMatchRow copyWithCompanion(ReviewMatchesCompanion data) {
    return ReviewMatchRow(
      faceId: data.faceId.present ? data.faceId.value : this.faceId,
      personId: data.personId.present ? data.personId.value : this.personId,
      score: data.score.present ? data.score.value : this.score,
      margin: data.margin.present ? data.margin.value : this.margin,
      decision: data.decision.present ? data.decision.value : this.decision,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ReviewMatchRow(')
          ..write('faceId: $faceId, ')
          ..write('personId: $personId, ')
          ..write('score: $score, ')
          ..write('margin: $margin, ')
          ..write('decision: $decision')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(faceId, personId, score, margin, decision);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ReviewMatchRow &&
          other.faceId == this.faceId &&
          other.personId == this.personId &&
          other.score == this.score &&
          other.margin == this.margin &&
          other.decision == this.decision);
}

class ReviewMatchesCompanion extends UpdateCompanion<ReviewMatchRow> {
  final Value<int> faceId;
  final Value<int> personId;
  final Value<double> score;
  final Value<double> margin;
  final Value<String> decision;
  const ReviewMatchesCompanion({
    this.faceId = const Value.absent(),
    this.personId = const Value.absent(),
    this.score = const Value.absent(),
    this.margin = const Value.absent(),
    this.decision = const Value.absent(),
  });
  ReviewMatchesCompanion.insert({
    this.faceId = const Value.absent(),
    required int personId,
    required double score,
    required double margin,
    required String decision,
  }) : personId = Value(personId),
       score = Value(score),
       margin = Value(margin),
       decision = Value(decision);
  static Insertable<ReviewMatchRow> custom({
    Expression<int>? faceId,
    Expression<int>? personId,
    Expression<double>? score,
    Expression<double>? margin,
    Expression<String>? decision,
  }) {
    return RawValuesInsertable({
      if (faceId != null) 'face_id': faceId,
      if (personId != null) 'person_id': personId,
      if (score != null) 'score': score,
      if (margin != null) 'margin': margin,
      if (decision != null) 'decision': decision,
    });
  }

  ReviewMatchesCompanion copyWith({
    Value<int>? faceId,
    Value<int>? personId,
    Value<double>? score,
    Value<double>? margin,
    Value<String>? decision,
  }) {
    return ReviewMatchesCompanion(
      faceId: faceId ?? this.faceId,
      personId: personId ?? this.personId,
      score: score ?? this.score,
      margin: margin ?? this.margin,
      decision: decision ?? this.decision,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (faceId.present) {
      map['face_id'] = Variable<int>(faceId.value);
    }
    if (personId.present) {
      map['person_id'] = Variable<int>(personId.value);
    }
    if (score.present) {
      map['score'] = Variable<double>(score.value);
    }
    if (margin.present) {
      map['margin'] = Variable<double>(margin.value);
    }
    if (decision.present) {
      map['decision'] = Variable<String>(decision.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ReviewMatchesCompanion(')
          ..write('faceId: $faceId, ')
          ..write('personId: $personId, ')
          ..write('score: $score, ')
          ..write('margin: $margin, ')
          ..write('decision: $decision')
          ..write(')'))
        .toString();
  }
}

class $ReviewGroupsTable extends ReviewGroups
    with TableInfo<$ReviewGroupsTable, ReviewGroupRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ReviewGroupsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _faceIdsMeta = const VerificationMeta(
    'faceIds',
  );
  @override
  late final GeneratedColumn<String> faceIds = GeneratedColumn<String>(
    'face_ids',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _cohesionMeta = const VerificationMeta(
    'cohesion',
  );
  @override
  late final GeneratedColumn<double> cohesion = GeneratedColumn<double>(
    'cohesion',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _qualityMeta = const VerificationMeta(
    'quality',
  );
  @override
  late final GeneratedColumn<double> quality = GeneratedColumn<double>(
    'quality',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _autoCreateMeta = const VerificationMeta(
    'autoCreate',
  );
  @override
  late final GeneratedColumn<bool> autoCreate = GeneratedColumn<bool>(
    'auto_create',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("auto_create" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    faceIds,
    cohesion,
    quality,
    autoCreate,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'review_groups';
  @override
  VerificationContext validateIntegrity(
    Insertable<ReviewGroupRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('face_ids')) {
      context.handle(
        _faceIdsMeta,
        faceIds.isAcceptableOrUnknown(data['face_ids']!, _faceIdsMeta),
      );
    } else if (isInserting) {
      context.missing(_faceIdsMeta);
    }
    if (data.containsKey('cohesion')) {
      context.handle(
        _cohesionMeta,
        cohesion.isAcceptableOrUnknown(data['cohesion']!, _cohesionMeta),
      );
    } else if (isInserting) {
      context.missing(_cohesionMeta);
    }
    if (data.containsKey('quality')) {
      context.handle(
        _qualityMeta,
        quality.isAcceptableOrUnknown(data['quality']!, _qualityMeta),
      );
    } else if (isInserting) {
      context.missing(_qualityMeta);
    }
    if (data.containsKey('auto_create')) {
      context.handle(
        _autoCreateMeta,
        autoCreate.isAcceptableOrUnknown(data['auto_create']!, _autoCreateMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  ReviewGroupRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ReviewGroupRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      faceIds: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}face_ids'],
      )!,
      cohesion: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}cohesion'],
      )!,
      quality: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}quality'],
      )!,
      autoCreate: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}auto_create'],
      )!,
    );
  }

  @override
  $ReviewGroupsTable createAlias(String alias) {
    return $ReviewGroupsTable(attachedDatabase, alias);
  }
}

class ReviewGroupRow extends DataClass implements Insertable<ReviewGroupRow> {
  final int id;
  final String faceIds;
  final double cohesion;
  final double quality;
  final bool autoCreate;
  const ReviewGroupRow({
    required this.id,
    required this.faceIds,
    required this.cohesion,
    required this.quality,
    required this.autoCreate,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['face_ids'] = Variable<String>(faceIds);
    map['cohesion'] = Variable<double>(cohesion);
    map['quality'] = Variable<double>(quality);
    map['auto_create'] = Variable<bool>(autoCreate);
    return map;
  }

  ReviewGroupsCompanion toCompanion(bool nullToAbsent) {
    return ReviewGroupsCompanion(
      id: Value(id),
      faceIds: Value(faceIds),
      cohesion: Value(cohesion),
      quality: Value(quality),
      autoCreate: Value(autoCreate),
    );
  }

  factory ReviewGroupRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ReviewGroupRow(
      id: serializer.fromJson<int>(json['id']),
      faceIds: serializer.fromJson<String>(json['faceIds']),
      cohesion: serializer.fromJson<double>(json['cohesion']),
      quality: serializer.fromJson<double>(json['quality']),
      autoCreate: serializer.fromJson<bool>(json['autoCreate']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'faceIds': serializer.toJson<String>(faceIds),
      'cohesion': serializer.toJson<double>(cohesion),
      'quality': serializer.toJson<double>(quality),
      'autoCreate': serializer.toJson<bool>(autoCreate),
    };
  }

  ReviewGroupRow copyWith({
    int? id,
    String? faceIds,
    double? cohesion,
    double? quality,
    bool? autoCreate,
  }) => ReviewGroupRow(
    id: id ?? this.id,
    faceIds: faceIds ?? this.faceIds,
    cohesion: cohesion ?? this.cohesion,
    quality: quality ?? this.quality,
    autoCreate: autoCreate ?? this.autoCreate,
  );
  ReviewGroupRow copyWithCompanion(ReviewGroupsCompanion data) {
    return ReviewGroupRow(
      id: data.id.present ? data.id.value : this.id,
      faceIds: data.faceIds.present ? data.faceIds.value : this.faceIds,
      cohesion: data.cohesion.present ? data.cohesion.value : this.cohesion,
      quality: data.quality.present ? data.quality.value : this.quality,
      autoCreate: data.autoCreate.present
          ? data.autoCreate.value
          : this.autoCreate,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ReviewGroupRow(')
          ..write('id: $id, ')
          ..write('faceIds: $faceIds, ')
          ..write('cohesion: $cohesion, ')
          ..write('quality: $quality, ')
          ..write('autoCreate: $autoCreate')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, faceIds, cohesion, quality, autoCreate);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ReviewGroupRow &&
          other.id == this.id &&
          other.faceIds == this.faceIds &&
          other.cohesion == this.cohesion &&
          other.quality == this.quality &&
          other.autoCreate == this.autoCreate);
}

class ReviewGroupsCompanion extends UpdateCompanion<ReviewGroupRow> {
  final Value<int> id;
  final Value<String> faceIds;
  final Value<double> cohesion;
  final Value<double> quality;
  final Value<bool> autoCreate;
  const ReviewGroupsCompanion({
    this.id = const Value.absent(),
    this.faceIds = const Value.absent(),
    this.cohesion = const Value.absent(),
    this.quality = const Value.absent(),
    this.autoCreate = const Value.absent(),
  });
  ReviewGroupsCompanion.insert({
    this.id = const Value.absent(),
    required String faceIds,
    required double cohesion,
    required double quality,
    this.autoCreate = const Value.absent(),
  }) : faceIds = Value(faceIds),
       cohesion = Value(cohesion),
       quality = Value(quality);
  static Insertable<ReviewGroupRow> custom({
    Expression<int>? id,
    Expression<String>? faceIds,
    Expression<double>? cohesion,
    Expression<double>? quality,
    Expression<bool>? autoCreate,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (faceIds != null) 'face_ids': faceIds,
      if (cohesion != null) 'cohesion': cohesion,
      if (quality != null) 'quality': quality,
      if (autoCreate != null) 'auto_create': autoCreate,
    });
  }

  ReviewGroupsCompanion copyWith({
    Value<int>? id,
    Value<String>? faceIds,
    Value<double>? cohesion,
    Value<double>? quality,
    Value<bool>? autoCreate,
  }) {
    return ReviewGroupsCompanion(
      id: id ?? this.id,
      faceIds: faceIds ?? this.faceIds,
      cohesion: cohesion ?? this.cohesion,
      quality: quality ?? this.quality,
      autoCreate: autoCreate ?? this.autoCreate,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (faceIds.present) {
      map['face_ids'] = Variable<String>(faceIds.value);
    }
    if (cohesion.present) {
      map['cohesion'] = Variable<double>(cohesion.value);
    }
    if (quality.present) {
      map['quality'] = Variable<double>(quality.value);
    }
    if (autoCreate.present) {
      map['auto_create'] = Variable<bool>(autoCreate.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ReviewGroupsCompanion(')
          ..write('id: $id, ')
          ..write('faceIds: $faceIds, ')
          ..write('cohesion: $cohesion, ')
          ..write('quality: $quality, ')
          ..write('autoCreate: $autoCreate')
          ..write(')'))
        .toString();
  }
}

class $ReviewDuplicatesTable extends ReviewDuplicates
    with TableInfo<$ReviewDuplicatesTable, ReviewDuplicateRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ReviewDuplicatesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _personAMeta = const VerificationMeta(
    'personA',
  );
  @override
  late final GeneratedColumn<int> personA = GeneratedColumn<int>(
    'person_a',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES persons (id) ON DELETE CASCADE',
    ),
  );
  static const VerificationMeta _personBMeta = const VerificationMeta(
    'personB',
  );
  @override
  late final GeneratedColumn<int> personB = GeneratedColumn<int>(
    'person_b',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES persons (id) ON DELETE CASCADE',
    ),
  );
  static const VerificationMeta _scoreMeta = const VerificationMeta('score');
  @override
  late final GeneratedColumn<double> score = GeneratedColumn<double>(
    'score',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [personA, personB, score];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'review_duplicates';
  @override
  VerificationContext validateIntegrity(
    Insertable<ReviewDuplicateRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('person_a')) {
      context.handle(
        _personAMeta,
        personA.isAcceptableOrUnknown(data['person_a']!, _personAMeta),
      );
    } else if (isInserting) {
      context.missing(_personAMeta);
    }
    if (data.containsKey('person_b')) {
      context.handle(
        _personBMeta,
        personB.isAcceptableOrUnknown(data['person_b']!, _personBMeta),
      );
    } else if (isInserting) {
      context.missing(_personBMeta);
    }
    if (data.containsKey('score')) {
      context.handle(
        _scoreMeta,
        score.isAcceptableOrUnknown(data['score']!, _scoreMeta),
      );
    } else if (isInserting) {
      context.missing(_scoreMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {personA, personB};
  @override
  ReviewDuplicateRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ReviewDuplicateRow(
      personA: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}person_a'],
      )!,
      personB: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}person_b'],
      )!,
      score: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}score'],
      )!,
    );
  }

  @override
  $ReviewDuplicatesTable createAlias(String alias) {
    return $ReviewDuplicatesTable(attachedDatabase, alias);
  }
}

class ReviewDuplicateRow extends DataClass
    implements Insertable<ReviewDuplicateRow> {
  final int personA;
  final int personB;
  final double score;
  const ReviewDuplicateRow({
    required this.personA,
    required this.personB,
    required this.score,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['person_a'] = Variable<int>(personA);
    map['person_b'] = Variable<int>(personB);
    map['score'] = Variable<double>(score);
    return map;
  }

  ReviewDuplicatesCompanion toCompanion(bool nullToAbsent) {
    return ReviewDuplicatesCompanion(
      personA: Value(personA),
      personB: Value(personB),
      score: Value(score),
    );
  }

  factory ReviewDuplicateRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ReviewDuplicateRow(
      personA: serializer.fromJson<int>(json['personA']),
      personB: serializer.fromJson<int>(json['personB']),
      score: serializer.fromJson<double>(json['score']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'personA': serializer.toJson<int>(personA),
      'personB': serializer.toJson<int>(personB),
      'score': serializer.toJson<double>(score),
    };
  }

  ReviewDuplicateRow copyWith({int? personA, int? personB, double? score}) =>
      ReviewDuplicateRow(
        personA: personA ?? this.personA,
        personB: personB ?? this.personB,
        score: score ?? this.score,
      );
  ReviewDuplicateRow copyWithCompanion(ReviewDuplicatesCompanion data) {
    return ReviewDuplicateRow(
      personA: data.personA.present ? data.personA.value : this.personA,
      personB: data.personB.present ? data.personB.value : this.personB,
      score: data.score.present ? data.score.value : this.score,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ReviewDuplicateRow(')
          ..write('personA: $personA, ')
          ..write('personB: $personB, ')
          ..write('score: $score')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(personA, personB, score);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ReviewDuplicateRow &&
          other.personA == this.personA &&
          other.personB == this.personB &&
          other.score == this.score);
}

class ReviewDuplicatesCompanion extends UpdateCompanion<ReviewDuplicateRow> {
  final Value<int> personA;
  final Value<int> personB;
  final Value<double> score;
  final Value<int> rowid;
  const ReviewDuplicatesCompanion({
    this.personA = const Value.absent(),
    this.personB = const Value.absent(),
    this.score = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ReviewDuplicatesCompanion.insert({
    required int personA,
    required int personB,
    required double score,
    this.rowid = const Value.absent(),
  }) : personA = Value(personA),
       personB = Value(personB),
       score = Value(score);
  static Insertable<ReviewDuplicateRow> custom({
    Expression<int>? personA,
    Expression<int>? personB,
    Expression<double>? score,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (personA != null) 'person_a': personA,
      if (personB != null) 'person_b': personB,
      if (score != null) 'score': score,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ReviewDuplicatesCompanion copyWith({
    Value<int>? personA,
    Value<int>? personB,
    Value<double>? score,
    Value<int>? rowid,
  }) {
    return ReviewDuplicatesCompanion(
      personA: personA ?? this.personA,
      personB: personB ?? this.personB,
      score: score ?? this.score,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (personA.present) {
      map['person_a'] = Variable<int>(personA.value);
    }
    if (personB.present) {
      map['person_b'] = Variable<int>(personB.value);
    }
    if (score.present) {
      map['score'] = Variable<double>(score.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ReviewDuplicatesCompanion(')
          ..write('personA: $personA, ')
          ..write('personB: $personB, ')
          ..write('score: $score, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ReviewBodyLinksTable extends ReviewBodyLinks
    with TableInfo<$ReviewBodyLinksTable, ReviewBodyLinkRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ReviewBodyLinksTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _bodyIdMeta = const VerificationMeta('bodyId');
  @override
  late final GeneratedColumn<int> bodyId = GeneratedColumn<int>(
    'body_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES bodies (id) ON DELETE CASCADE',
    ),
  );
  static const VerificationMeta _personIdMeta = const VerificationMeta(
    'personId',
  );
  @override
  late final GeneratedColumn<int> personId = GeneratedColumn<int>(
    'person_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES persons (id) ON DELETE CASCADE',
    ),
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
  static const VerificationMeta _confidenceMeta = const VerificationMeta(
    'confidence',
  );
  @override
  late final GeneratedColumn<double> confidence = GeneratedColumn<double>(
    'confidence',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [bodyId, personId, method, confidence];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'review_body_links';
  @override
  VerificationContext validateIntegrity(
    Insertable<ReviewBodyLinkRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('body_id')) {
      context.handle(
        _bodyIdMeta,
        bodyId.isAcceptableOrUnknown(data['body_id']!, _bodyIdMeta),
      );
    }
    if (data.containsKey('person_id')) {
      context.handle(
        _personIdMeta,
        personId.isAcceptableOrUnknown(data['person_id']!, _personIdMeta),
      );
    } else if (isInserting) {
      context.missing(_personIdMeta);
    }
    if (data.containsKey('method')) {
      context.handle(
        _methodMeta,
        method.isAcceptableOrUnknown(data['method']!, _methodMeta),
      );
    } else if (isInserting) {
      context.missing(_methodMeta);
    }
    if (data.containsKey('confidence')) {
      context.handle(
        _confidenceMeta,
        confidence.isAcceptableOrUnknown(data['confidence']!, _confidenceMeta),
      );
    } else if (isInserting) {
      context.missing(_confidenceMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {bodyId};
  @override
  ReviewBodyLinkRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ReviewBodyLinkRow(
      bodyId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}body_id'],
      )!,
      personId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}person_id'],
      )!,
      method: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}method'],
      )!,
      confidence: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}confidence'],
      )!,
    );
  }

  @override
  $ReviewBodyLinksTable createAlias(String alias) {
    return $ReviewBodyLinksTable(attachedDatabase, alias);
  }
}

class ReviewBodyLinkRow extends DataClass
    implements Insertable<ReviewBodyLinkRow> {
  final int bodyId;
  final int personId;
  final String method;
  final double confidence;
  const ReviewBodyLinkRow({
    required this.bodyId,
    required this.personId,
    required this.method,
    required this.confidence,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['body_id'] = Variable<int>(bodyId);
    map['person_id'] = Variable<int>(personId);
    map['method'] = Variable<String>(method);
    map['confidence'] = Variable<double>(confidence);
    return map;
  }

  ReviewBodyLinksCompanion toCompanion(bool nullToAbsent) {
    return ReviewBodyLinksCompanion(
      bodyId: Value(bodyId),
      personId: Value(personId),
      method: Value(method),
      confidence: Value(confidence),
    );
  }

  factory ReviewBodyLinkRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ReviewBodyLinkRow(
      bodyId: serializer.fromJson<int>(json['bodyId']),
      personId: serializer.fromJson<int>(json['personId']),
      method: serializer.fromJson<String>(json['method']),
      confidence: serializer.fromJson<double>(json['confidence']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'bodyId': serializer.toJson<int>(bodyId),
      'personId': serializer.toJson<int>(personId),
      'method': serializer.toJson<String>(method),
      'confidence': serializer.toJson<double>(confidence),
    };
  }

  ReviewBodyLinkRow copyWith({
    int? bodyId,
    int? personId,
    String? method,
    double? confidence,
  }) => ReviewBodyLinkRow(
    bodyId: bodyId ?? this.bodyId,
    personId: personId ?? this.personId,
    method: method ?? this.method,
    confidence: confidence ?? this.confidence,
  );
  ReviewBodyLinkRow copyWithCompanion(ReviewBodyLinksCompanion data) {
    return ReviewBodyLinkRow(
      bodyId: data.bodyId.present ? data.bodyId.value : this.bodyId,
      personId: data.personId.present ? data.personId.value : this.personId,
      method: data.method.present ? data.method.value : this.method,
      confidence: data.confidence.present
          ? data.confidence.value
          : this.confidence,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ReviewBodyLinkRow(')
          ..write('bodyId: $bodyId, ')
          ..write('personId: $personId, ')
          ..write('method: $method, ')
          ..write('confidence: $confidence')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(bodyId, personId, method, confidence);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ReviewBodyLinkRow &&
          other.bodyId == this.bodyId &&
          other.personId == this.personId &&
          other.method == this.method &&
          other.confidence == this.confidence);
}

class ReviewBodyLinksCompanion extends UpdateCompanion<ReviewBodyLinkRow> {
  final Value<int> bodyId;
  final Value<int> personId;
  final Value<String> method;
  final Value<double> confidence;
  const ReviewBodyLinksCompanion({
    this.bodyId = const Value.absent(),
    this.personId = const Value.absent(),
    this.method = const Value.absent(),
    this.confidence = const Value.absent(),
  });
  ReviewBodyLinksCompanion.insert({
    this.bodyId = const Value.absent(),
    required int personId,
    required String method,
    required double confidence,
  }) : personId = Value(personId),
       method = Value(method),
       confidence = Value(confidence);
  static Insertable<ReviewBodyLinkRow> custom({
    Expression<int>? bodyId,
    Expression<int>? personId,
    Expression<String>? method,
    Expression<double>? confidence,
  }) {
    return RawValuesInsertable({
      if (bodyId != null) 'body_id': bodyId,
      if (personId != null) 'person_id': personId,
      if (method != null) 'method': method,
      if (confidence != null) 'confidence': confidence,
    });
  }

  ReviewBodyLinksCompanion copyWith({
    Value<int>? bodyId,
    Value<int>? personId,
    Value<String>? method,
    Value<double>? confidence,
  }) {
    return ReviewBodyLinksCompanion(
      bodyId: bodyId ?? this.bodyId,
      personId: personId ?? this.personId,
      method: method ?? this.method,
      confidence: confidence ?? this.confidence,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (bodyId.present) {
      map['body_id'] = Variable<int>(bodyId.value);
    }
    if (personId.present) {
      map['person_id'] = Variable<int>(personId.value);
    }
    if (method.present) {
      map['method'] = Variable<String>(method.value);
    }
    if (confidence.present) {
      map['confidence'] = Variable<double>(confidence.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ReviewBodyLinksCompanion(')
          ..write('bodyId: $bodyId, ')
          ..write('personId: $personId, ')
          ..write('method: $method, ')
          ..write('confidence: $confidence')
          ..write(')'))
        .toString();
  }
}

class $ReviewSnoozesTable extends ReviewSnoozes
    with TableInfo<$ReviewSnoozesTable, ReviewSnoozeRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ReviewSnoozesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _questionKeyMeta = const VerificationMeta(
    'questionKey',
  );
  @override
  late final GeneratedColumn<String> questionKey = GeneratedColumn<String>(
    'question_key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _scoreMeta = const VerificationMeta('score');
  @override
  late final GeneratedColumn<double> score = GeneratedColumn<double>(
    'score',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _evidenceMeta = const VerificationMeta(
    'evidence',
  );
  @override
  late final GeneratedColumn<int> evidence = GeneratedColumn<int>(
    'evidence',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _snoozedAtMeta = const VerificationMeta(
    'snoozedAt',
  );
  @override
  late final GeneratedColumn<int> snoozedAt = GeneratedColumn<int>(
    'snoozed_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    questionKey,
    score,
    evidence,
    snoozedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'review_snoozes';
  @override
  VerificationContext validateIntegrity(
    Insertable<ReviewSnoozeRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('question_key')) {
      context.handle(
        _questionKeyMeta,
        questionKey.isAcceptableOrUnknown(
          data['question_key']!,
          _questionKeyMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_questionKeyMeta);
    }
    if (data.containsKey('score')) {
      context.handle(
        _scoreMeta,
        score.isAcceptableOrUnknown(data['score']!, _scoreMeta),
      );
    } else if (isInserting) {
      context.missing(_scoreMeta);
    }
    if (data.containsKey('evidence')) {
      context.handle(
        _evidenceMeta,
        evidence.isAcceptableOrUnknown(data['evidence']!, _evidenceMeta),
      );
    } else if (isInserting) {
      context.missing(_evidenceMeta);
    }
    if (data.containsKey('snoozed_at')) {
      context.handle(
        _snoozedAtMeta,
        snoozedAt.isAcceptableOrUnknown(data['snoozed_at']!, _snoozedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_snoozedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {questionKey};
  @override
  ReviewSnoozeRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ReviewSnoozeRow(
      questionKey: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}question_key'],
      )!,
      score: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}score'],
      )!,
      evidence: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}evidence'],
      )!,
      snoozedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}snoozed_at'],
      )!,
    );
  }

  @override
  $ReviewSnoozesTable createAlias(String alias) {
    return $ReviewSnoozesTable(attachedDatabase, alias);
  }
}

class ReviewSnoozeRow extends DataClass implements Insertable<ReviewSnoozeRow> {
  final String questionKey;
  final double score;
  final int evidence;
  final int snoozedAt;
  const ReviewSnoozeRow({
    required this.questionKey,
    required this.score,
    required this.evidence,
    required this.snoozedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['question_key'] = Variable<String>(questionKey);
    map['score'] = Variable<double>(score);
    map['evidence'] = Variable<int>(evidence);
    map['snoozed_at'] = Variable<int>(snoozedAt);
    return map;
  }

  ReviewSnoozesCompanion toCompanion(bool nullToAbsent) {
    return ReviewSnoozesCompanion(
      questionKey: Value(questionKey),
      score: Value(score),
      evidence: Value(evidence),
      snoozedAt: Value(snoozedAt),
    );
  }

  factory ReviewSnoozeRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ReviewSnoozeRow(
      questionKey: serializer.fromJson<String>(json['questionKey']),
      score: serializer.fromJson<double>(json['score']),
      evidence: serializer.fromJson<int>(json['evidence']),
      snoozedAt: serializer.fromJson<int>(json['snoozedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'questionKey': serializer.toJson<String>(questionKey),
      'score': serializer.toJson<double>(score),
      'evidence': serializer.toJson<int>(evidence),
      'snoozedAt': serializer.toJson<int>(snoozedAt),
    };
  }

  ReviewSnoozeRow copyWith({
    String? questionKey,
    double? score,
    int? evidence,
    int? snoozedAt,
  }) => ReviewSnoozeRow(
    questionKey: questionKey ?? this.questionKey,
    score: score ?? this.score,
    evidence: evidence ?? this.evidence,
    snoozedAt: snoozedAt ?? this.snoozedAt,
  );
  ReviewSnoozeRow copyWithCompanion(ReviewSnoozesCompanion data) {
    return ReviewSnoozeRow(
      questionKey: data.questionKey.present
          ? data.questionKey.value
          : this.questionKey,
      score: data.score.present ? data.score.value : this.score,
      evidence: data.evidence.present ? data.evidence.value : this.evidence,
      snoozedAt: data.snoozedAt.present ? data.snoozedAt.value : this.snoozedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ReviewSnoozeRow(')
          ..write('questionKey: $questionKey, ')
          ..write('score: $score, ')
          ..write('evidence: $evidence, ')
          ..write('snoozedAt: $snoozedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(questionKey, score, evidence, snoozedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ReviewSnoozeRow &&
          other.questionKey == this.questionKey &&
          other.score == this.score &&
          other.evidence == this.evidence &&
          other.snoozedAt == this.snoozedAt);
}

class ReviewSnoozesCompanion extends UpdateCompanion<ReviewSnoozeRow> {
  final Value<String> questionKey;
  final Value<double> score;
  final Value<int> evidence;
  final Value<int> snoozedAt;
  final Value<int> rowid;
  const ReviewSnoozesCompanion({
    this.questionKey = const Value.absent(),
    this.score = const Value.absent(),
    this.evidence = const Value.absent(),
    this.snoozedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ReviewSnoozesCompanion.insert({
    required String questionKey,
    required double score,
    required int evidence,
    required int snoozedAt,
    this.rowid = const Value.absent(),
  }) : questionKey = Value(questionKey),
       score = Value(score),
       evidence = Value(evidence),
       snoozedAt = Value(snoozedAt);
  static Insertable<ReviewSnoozeRow> custom({
    Expression<String>? questionKey,
    Expression<double>? score,
    Expression<int>? evidence,
    Expression<int>? snoozedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (questionKey != null) 'question_key': questionKey,
      if (score != null) 'score': score,
      if (evidence != null) 'evidence': evidence,
      if (snoozedAt != null) 'snoozed_at': snoozedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ReviewSnoozesCompanion copyWith({
    Value<String>? questionKey,
    Value<double>? score,
    Value<int>? evidence,
    Value<int>? snoozedAt,
    Value<int>? rowid,
  }) {
    return ReviewSnoozesCompanion(
      questionKey: questionKey ?? this.questionKey,
      score: score ?? this.score,
      evidence: evidence ?? this.evidence,
      snoozedAt: snoozedAt ?? this.snoozedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (questionKey.present) {
      map['question_key'] = Variable<String>(questionKey.value);
    }
    if (score.present) {
      map['score'] = Variable<double>(score.value);
    }
    if (evidence.present) {
      map['evidence'] = Variable<int>(evidence.value);
    }
    if (snoozedAt.present) {
      map['snoozed_at'] = Variable<int>(snoozedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ReviewSnoozesCompanion(')
          ..write('questionKey: $questionKey, ')
          ..write('score: $score, ')
          ..write('evidence: $evidence, ')
          ..write('snoozedAt: $snoozedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $JobsTable extends Jobs with TableInfo<$JobsTable, JobRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $JobsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _serverIdMeta = const VerificationMeta(
    'serverId',
  );
  @override
  late final GeneratedColumn<String> serverId = GeneratedColumn<String>(
    'server_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _remoteIdMeta = const VerificationMeta(
    'remoteId',
  );
  @override
  late final GeneratedColumn<String> remoteId = GeneratedColumn<String>(
    'remote_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _typeMeta = const VerificationMeta('type');
  @override
  late final GeneratedColumn<String> type = GeneratedColumn<String>(
    'type',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _requestJsonMeta = const VerificationMeta(
    'requestJson',
  );
  @override
  late final GeneratedColumn<String> requestJson = GeneratedColumn<String>(
    'request_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _inputFilesMeta = const VerificationMeta(
    'inputFiles',
  );
  @override
  late final GeneratedColumn<String> inputFiles = GeneratedColumn<String>(
    'input_files',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('{}'),
  );
  static const VerificationMeta _detailsJsonMeta = const VerificationMeta(
    'detailsJson',
  );
  @override
  late final GeneratedColumn<String> detailsJson = GeneratedColumn<String>(
    'details_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('{}'),
  );
  static const VerificationMeta _targetPathMeta = const VerificationMeta(
    'targetPath',
  );
  @override
  late final GeneratedColumn<String> targetPath = GeneratedColumn<String>(
    'target_path',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _targetShaMeta = const VerificationMeta(
    'targetSha',
  );
  @override
  late final GeneratedColumn<String> targetSha = GeneratedColumn<String>(
    'target_sha',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _targetSizeMeta = const VerificationMeta(
    'targetSize',
  );
  @override
  late final GeneratedColumn<int> targetSize = GeneratedColumn<int>(
    'target_size',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _personIdMeta = const VerificationMeta(
    'personId',
  );
  @override
  late final GeneratedColumn<int> personId = GeneratedColumn<int>(
    'person_id',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES persons (id) ON DELETE SET NULL',
    ),
  );
  static const VerificationMeta _statusMeta = const VerificationMeta('status');
  @override
  late final GeneratedColumn<String> status = GeneratedColumn<String>(
    'status',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _progressMeta = const VerificationMeta(
    'progress',
  );
  @override
  late final GeneratedColumn<double> progress = GeneratedColumn<double>(
    'progress',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _messageMeta = const VerificationMeta(
    'message',
  );
  @override
  late final GeneratedColumn<String> message = GeneratedColumn<String>(
    'message',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _errorMeta = const VerificationMeta('error');
  @override
  late final GeneratedColumn<String> error = GeneratedColumn<String>(
    'error',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _acknowledgedMeta = const VerificationMeta(
    'acknowledged',
  );
  @override
  late final GeneratedColumn<bool> acknowledged = GeneratedColumn<bool>(
    'acknowledged',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("acknowledged" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<int> createdAt = GeneratedColumn<int>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<int> updatedAt = GeneratedColumn<int>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    serverId,
    remoteId,
    type,
    requestJson,
    inputFiles,
    detailsJson,
    targetPath,
    targetSha,
    targetSize,
    personId,
    status,
    progress,
    message,
    error,
    acknowledged,
    createdAt,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'jobs';
  @override
  VerificationContext validateIntegrity(
    Insertable<JobRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('server_id')) {
      context.handle(
        _serverIdMeta,
        serverId.isAcceptableOrUnknown(data['server_id']!, _serverIdMeta),
      );
    } else if (isInserting) {
      context.missing(_serverIdMeta);
    }
    if (data.containsKey('remote_id')) {
      context.handle(
        _remoteIdMeta,
        remoteId.isAcceptableOrUnknown(data['remote_id']!, _remoteIdMeta),
      );
    }
    if (data.containsKey('type')) {
      context.handle(
        _typeMeta,
        type.isAcceptableOrUnknown(data['type']!, _typeMeta),
      );
    } else if (isInserting) {
      context.missing(_typeMeta);
    }
    if (data.containsKey('request_json')) {
      context.handle(
        _requestJsonMeta,
        requestJson.isAcceptableOrUnknown(
          data['request_json']!,
          _requestJsonMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_requestJsonMeta);
    }
    if (data.containsKey('input_files')) {
      context.handle(
        _inputFilesMeta,
        inputFiles.isAcceptableOrUnknown(data['input_files']!, _inputFilesMeta),
      );
    }
    if (data.containsKey('details_json')) {
      context.handle(
        _detailsJsonMeta,
        detailsJson.isAcceptableOrUnknown(
          data['details_json']!,
          _detailsJsonMeta,
        ),
      );
    }
    if (data.containsKey('target_path')) {
      context.handle(
        _targetPathMeta,
        targetPath.isAcceptableOrUnknown(data['target_path']!, _targetPathMeta),
      );
    } else if (isInserting) {
      context.missing(_targetPathMeta);
    }
    if (data.containsKey('target_sha')) {
      context.handle(
        _targetShaMeta,
        targetSha.isAcceptableOrUnknown(data['target_sha']!, _targetShaMeta),
      );
    } else if (isInserting) {
      context.missing(_targetShaMeta);
    }
    if (data.containsKey('target_size')) {
      context.handle(
        _targetSizeMeta,
        targetSize.isAcceptableOrUnknown(data['target_size']!, _targetSizeMeta),
      );
    } else if (isInserting) {
      context.missing(_targetSizeMeta);
    }
    if (data.containsKey('person_id')) {
      context.handle(
        _personIdMeta,
        personId.isAcceptableOrUnknown(data['person_id']!, _personIdMeta),
      );
    }
    if (data.containsKey('status')) {
      context.handle(
        _statusMeta,
        status.isAcceptableOrUnknown(data['status']!, _statusMeta),
      );
    } else if (isInserting) {
      context.missing(_statusMeta);
    }
    if (data.containsKey('progress')) {
      context.handle(
        _progressMeta,
        progress.isAcceptableOrUnknown(data['progress']!, _progressMeta),
      );
    }
    if (data.containsKey('message')) {
      context.handle(
        _messageMeta,
        message.isAcceptableOrUnknown(data['message']!, _messageMeta),
      );
    }
    if (data.containsKey('error')) {
      context.handle(
        _errorMeta,
        error.isAcceptableOrUnknown(data['error']!, _errorMeta),
      );
    }
    if (data.containsKey('acknowledged')) {
      context.handle(
        _acknowledgedMeta,
        acknowledged.isAcceptableOrUnknown(
          data['acknowledged']!,
          _acknowledgedMeta,
        ),
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
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  JobRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return JobRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      serverId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}server_id'],
      )!,
      remoteId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}remote_id'],
      ),
      type: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}type'],
      )!,
      requestJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}request_json'],
      )!,
      inputFiles: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}input_files'],
      )!,
      detailsJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}details_json'],
      )!,
      targetPath: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}target_path'],
      )!,
      targetSha: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}target_sha'],
      )!,
      targetSize: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}target_size'],
      )!,
      personId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}person_id'],
      ),
      status: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}status'],
      )!,
      progress: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}progress'],
      )!,
      message: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}message'],
      ),
      error: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}error'],
      ),
      acknowledged: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}acknowledged'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $JobsTable createAlias(String alias) {
    return $JobsTable(attachedDatabase, alias);
  }
}

class JobRow extends DataClass implements Insertable<JobRow> {
  final String id;
  final String serverId;
  final String? remoteId;
  final String type;
  final String requestJson;
  final String inputFiles;
  final String detailsJson;
  final String targetPath;
  final String targetSha;
  final int targetSize;
  final int? personId;
  final String status;
  final double progress;
  final String? message;
  final String? error;
  final bool acknowledged;
  final int createdAt;
  final int updatedAt;
  const JobRow({
    required this.id,
    required this.serverId,
    this.remoteId,
    required this.type,
    required this.requestJson,
    required this.inputFiles,
    required this.detailsJson,
    required this.targetPath,
    required this.targetSha,
    required this.targetSize,
    this.personId,
    required this.status,
    required this.progress,
    this.message,
    this.error,
    required this.acknowledged,
    required this.createdAt,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['server_id'] = Variable<String>(serverId);
    if (!nullToAbsent || remoteId != null) {
      map['remote_id'] = Variable<String>(remoteId);
    }
    map['type'] = Variable<String>(type);
    map['request_json'] = Variable<String>(requestJson);
    map['input_files'] = Variable<String>(inputFiles);
    map['details_json'] = Variable<String>(detailsJson);
    map['target_path'] = Variable<String>(targetPath);
    map['target_sha'] = Variable<String>(targetSha);
    map['target_size'] = Variable<int>(targetSize);
    if (!nullToAbsent || personId != null) {
      map['person_id'] = Variable<int>(personId);
    }
    map['status'] = Variable<String>(status);
    map['progress'] = Variable<double>(progress);
    if (!nullToAbsent || message != null) {
      map['message'] = Variable<String>(message);
    }
    if (!nullToAbsent || error != null) {
      map['error'] = Variable<String>(error);
    }
    map['acknowledged'] = Variable<bool>(acknowledged);
    map['created_at'] = Variable<int>(createdAt);
    map['updated_at'] = Variable<int>(updatedAt);
    return map;
  }

  JobsCompanion toCompanion(bool nullToAbsent) {
    return JobsCompanion(
      id: Value(id),
      serverId: Value(serverId),
      remoteId: remoteId == null && nullToAbsent
          ? const Value.absent()
          : Value(remoteId),
      type: Value(type),
      requestJson: Value(requestJson),
      inputFiles: Value(inputFiles),
      detailsJson: Value(detailsJson),
      targetPath: Value(targetPath),
      targetSha: Value(targetSha),
      targetSize: Value(targetSize),
      personId: personId == null && nullToAbsent
          ? const Value.absent()
          : Value(personId),
      status: Value(status),
      progress: Value(progress),
      message: message == null && nullToAbsent
          ? const Value.absent()
          : Value(message),
      error: error == null && nullToAbsent
          ? const Value.absent()
          : Value(error),
      acknowledged: Value(acknowledged),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
    );
  }

  factory JobRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return JobRow(
      id: serializer.fromJson<String>(json['id']),
      serverId: serializer.fromJson<String>(json['serverId']),
      remoteId: serializer.fromJson<String?>(json['remoteId']),
      type: serializer.fromJson<String>(json['type']),
      requestJson: serializer.fromJson<String>(json['requestJson']),
      inputFiles: serializer.fromJson<String>(json['inputFiles']),
      detailsJson: serializer.fromJson<String>(json['detailsJson']),
      targetPath: serializer.fromJson<String>(json['targetPath']),
      targetSha: serializer.fromJson<String>(json['targetSha']),
      targetSize: serializer.fromJson<int>(json['targetSize']),
      personId: serializer.fromJson<int?>(json['personId']),
      status: serializer.fromJson<String>(json['status']),
      progress: serializer.fromJson<double>(json['progress']),
      message: serializer.fromJson<String?>(json['message']),
      error: serializer.fromJson<String?>(json['error']),
      acknowledged: serializer.fromJson<bool>(json['acknowledged']),
      createdAt: serializer.fromJson<int>(json['createdAt']),
      updatedAt: serializer.fromJson<int>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'serverId': serializer.toJson<String>(serverId),
      'remoteId': serializer.toJson<String?>(remoteId),
      'type': serializer.toJson<String>(type),
      'requestJson': serializer.toJson<String>(requestJson),
      'inputFiles': serializer.toJson<String>(inputFiles),
      'detailsJson': serializer.toJson<String>(detailsJson),
      'targetPath': serializer.toJson<String>(targetPath),
      'targetSha': serializer.toJson<String>(targetSha),
      'targetSize': serializer.toJson<int>(targetSize),
      'personId': serializer.toJson<int?>(personId),
      'status': serializer.toJson<String>(status),
      'progress': serializer.toJson<double>(progress),
      'message': serializer.toJson<String?>(message),
      'error': serializer.toJson<String?>(error),
      'acknowledged': serializer.toJson<bool>(acknowledged),
      'createdAt': serializer.toJson<int>(createdAt),
      'updatedAt': serializer.toJson<int>(updatedAt),
    };
  }

  JobRow copyWith({
    String? id,
    String? serverId,
    Value<String?> remoteId = const Value.absent(),
    String? type,
    String? requestJson,
    String? inputFiles,
    String? detailsJson,
    String? targetPath,
    String? targetSha,
    int? targetSize,
    Value<int?> personId = const Value.absent(),
    String? status,
    double? progress,
    Value<String?> message = const Value.absent(),
    Value<String?> error = const Value.absent(),
    bool? acknowledged,
    int? createdAt,
    int? updatedAt,
  }) => JobRow(
    id: id ?? this.id,
    serverId: serverId ?? this.serverId,
    remoteId: remoteId.present ? remoteId.value : this.remoteId,
    type: type ?? this.type,
    requestJson: requestJson ?? this.requestJson,
    inputFiles: inputFiles ?? this.inputFiles,
    detailsJson: detailsJson ?? this.detailsJson,
    targetPath: targetPath ?? this.targetPath,
    targetSha: targetSha ?? this.targetSha,
    targetSize: targetSize ?? this.targetSize,
    personId: personId.present ? personId.value : this.personId,
    status: status ?? this.status,
    progress: progress ?? this.progress,
    message: message.present ? message.value : this.message,
    error: error.present ? error.value : this.error,
    acknowledged: acknowledged ?? this.acknowledged,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  JobRow copyWithCompanion(JobsCompanion data) {
    return JobRow(
      id: data.id.present ? data.id.value : this.id,
      serverId: data.serverId.present ? data.serverId.value : this.serverId,
      remoteId: data.remoteId.present ? data.remoteId.value : this.remoteId,
      type: data.type.present ? data.type.value : this.type,
      requestJson: data.requestJson.present
          ? data.requestJson.value
          : this.requestJson,
      inputFiles: data.inputFiles.present
          ? data.inputFiles.value
          : this.inputFiles,
      detailsJson: data.detailsJson.present
          ? data.detailsJson.value
          : this.detailsJson,
      targetPath: data.targetPath.present
          ? data.targetPath.value
          : this.targetPath,
      targetSha: data.targetSha.present ? data.targetSha.value : this.targetSha,
      targetSize: data.targetSize.present
          ? data.targetSize.value
          : this.targetSize,
      personId: data.personId.present ? data.personId.value : this.personId,
      status: data.status.present ? data.status.value : this.status,
      progress: data.progress.present ? data.progress.value : this.progress,
      message: data.message.present ? data.message.value : this.message,
      error: data.error.present ? data.error.value : this.error,
      acknowledged: data.acknowledged.present
          ? data.acknowledged.value
          : this.acknowledged,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('JobRow(')
          ..write('id: $id, ')
          ..write('serverId: $serverId, ')
          ..write('remoteId: $remoteId, ')
          ..write('type: $type, ')
          ..write('requestJson: $requestJson, ')
          ..write('inputFiles: $inputFiles, ')
          ..write('detailsJson: $detailsJson, ')
          ..write('targetPath: $targetPath, ')
          ..write('targetSha: $targetSha, ')
          ..write('targetSize: $targetSize, ')
          ..write('personId: $personId, ')
          ..write('status: $status, ')
          ..write('progress: $progress, ')
          ..write('message: $message, ')
          ..write('error: $error, ')
          ..write('acknowledged: $acknowledged, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    serverId,
    remoteId,
    type,
    requestJson,
    inputFiles,
    detailsJson,
    targetPath,
    targetSha,
    targetSize,
    personId,
    status,
    progress,
    message,
    error,
    acknowledged,
    createdAt,
    updatedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is JobRow &&
          other.id == this.id &&
          other.serverId == this.serverId &&
          other.remoteId == this.remoteId &&
          other.type == this.type &&
          other.requestJson == this.requestJson &&
          other.inputFiles == this.inputFiles &&
          other.detailsJson == this.detailsJson &&
          other.targetPath == this.targetPath &&
          other.targetSha == this.targetSha &&
          other.targetSize == this.targetSize &&
          other.personId == this.personId &&
          other.status == this.status &&
          other.progress == this.progress &&
          other.message == this.message &&
          other.error == this.error &&
          other.acknowledged == this.acknowledged &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt);
}

class JobsCompanion extends UpdateCompanion<JobRow> {
  final Value<String> id;
  final Value<String> serverId;
  final Value<String?> remoteId;
  final Value<String> type;
  final Value<String> requestJson;
  final Value<String> inputFiles;
  final Value<String> detailsJson;
  final Value<String> targetPath;
  final Value<String> targetSha;
  final Value<int> targetSize;
  final Value<int?> personId;
  final Value<String> status;
  final Value<double> progress;
  final Value<String?> message;
  final Value<String?> error;
  final Value<bool> acknowledged;
  final Value<int> createdAt;
  final Value<int> updatedAt;
  final Value<int> rowid;
  const JobsCompanion({
    this.id = const Value.absent(),
    this.serverId = const Value.absent(),
    this.remoteId = const Value.absent(),
    this.type = const Value.absent(),
    this.requestJson = const Value.absent(),
    this.inputFiles = const Value.absent(),
    this.detailsJson = const Value.absent(),
    this.targetPath = const Value.absent(),
    this.targetSha = const Value.absent(),
    this.targetSize = const Value.absent(),
    this.personId = const Value.absent(),
    this.status = const Value.absent(),
    this.progress = const Value.absent(),
    this.message = const Value.absent(),
    this.error = const Value.absent(),
    this.acknowledged = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  JobsCompanion.insert({
    required String id,
    required String serverId,
    this.remoteId = const Value.absent(),
    required String type,
    required String requestJson,
    this.inputFiles = const Value.absent(),
    this.detailsJson = const Value.absent(),
    required String targetPath,
    required String targetSha,
    required int targetSize,
    this.personId = const Value.absent(),
    required String status,
    this.progress = const Value.absent(),
    this.message = const Value.absent(),
    this.error = const Value.absent(),
    this.acknowledged = const Value.absent(),
    required int createdAt,
    required int updatedAt,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       serverId = Value(serverId),
       type = Value(type),
       requestJson = Value(requestJson),
       targetPath = Value(targetPath),
       targetSha = Value(targetSha),
       targetSize = Value(targetSize),
       status = Value(status),
       createdAt = Value(createdAt),
       updatedAt = Value(updatedAt);
  static Insertable<JobRow> custom({
    Expression<String>? id,
    Expression<String>? serverId,
    Expression<String>? remoteId,
    Expression<String>? type,
    Expression<String>? requestJson,
    Expression<String>? inputFiles,
    Expression<String>? detailsJson,
    Expression<String>? targetPath,
    Expression<String>? targetSha,
    Expression<int>? targetSize,
    Expression<int>? personId,
    Expression<String>? status,
    Expression<double>? progress,
    Expression<String>? message,
    Expression<String>? error,
    Expression<bool>? acknowledged,
    Expression<int>? createdAt,
    Expression<int>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (serverId != null) 'server_id': serverId,
      if (remoteId != null) 'remote_id': remoteId,
      if (type != null) 'type': type,
      if (requestJson != null) 'request_json': requestJson,
      if (inputFiles != null) 'input_files': inputFiles,
      if (detailsJson != null) 'details_json': detailsJson,
      if (targetPath != null) 'target_path': targetPath,
      if (targetSha != null) 'target_sha': targetSha,
      if (targetSize != null) 'target_size': targetSize,
      if (personId != null) 'person_id': personId,
      if (status != null) 'status': status,
      if (progress != null) 'progress': progress,
      if (message != null) 'message': message,
      if (error != null) 'error': error,
      if (acknowledged != null) 'acknowledged': acknowledged,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  JobsCompanion copyWith({
    Value<String>? id,
    Value<String>? serverId,
    Value<String?>? remoteId,
    Value<String>? type,
    Value<String>? requestJson,
    Value<String>? inputFiles,
    Value<String>? detailsJson,
    Value<String>? targetPath,
    Value<String>? targetSha,
    Value<int>? targetSize,
    Value<int?>? personId,
    Value<String>? status,
    Value<double>? progress,
    Value<String?>? message,
    Value<String?>? error,
    Value<bool>? acknowledged,
    Value<int>? createdAt,
    Value<int>? updatedAt,
    Value<int>? rowid,
  }) {
    return JobsCompanion(
      id: id ?? this.id,
      serverId: serverId ?? this.serverId,
      remoteId: remoteId ?? this.remoteId,
      type: type ?? this.type,
      requestJson: requestJson ?? this.requestJson,
      inputFiles: inputFiles ?? this.inputFiles,
      detailsJson: detailsJson ?? this.detailsJson,
      targetPath: targetPath ?? this.targetPath,
      targetSha: targetSha ?? this.targetSha,
      targetSize: targetSize ?? this.targetSize,
      personId: personId ?? this.personId,
      status: status ?? this.status,
      progress: progress ?? this.progress,
      message: message ?? this.message,
      error: error ?? this.error,
      acknowledged: acknowledged ?? this.acknowledged,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (serverId.present) {
      map['server_id'] = Variable<String>(serverId.value);
    }
    if (remoteId.present) {
      map['remote_id'] = Variable<String>(remoteId.value);
    }
    if (type.present) {
      map['type'] = Variable<String>(type.value);
    }
    if (requestJson.present) {
      map['request_json'] = Variable<String>(requestJson.value);
    }
    if (inputFiles.present) {
      map['input_files'] = Variable<String>(inputFiles.value);
    }
    if (detailsJson.present) {
      map['details_json'] = Variable<String>(detailsJson.value);
    }
    if (targetPath.present) {
      map['target_path'] = Variable<String>(targetPath.value);
    }
    if (targetSha.present) {
      map['target_sha'] = Variable<String>(targetSha.value);
    }
    if (targetSize.present) {
      map['target_size'] = Variable<int>(targetSize.value);
    }
    if (personId.present) {
      map['person_id'] = Variable<int>(personId.value);
    }
    if (status.present) {
      map['status'] = Variable<String>(status.value);
    }
    if (progress.present) {
      map['progress'] = Variable<double>(progress.value);
    }
    if (message.present) {
      map['message'] = Variable<String>(message.value);
    }
    if (error.present) {
      map['error'] = Variable<String>(error.value);
    }
    if (acknowledged.present) {
      map['acknowledged'] = Variable<bool>(acknowledged.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<int>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<int>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('JobsCompanion(')
          ..write('id: $id, ')
          ..write('serverId: $serverId, ')
          ..write('remoteId: $remoteId, ')
          ..write('type: $type, ')
          ..write('requestJson: $requestJson, ')
          ..write('inputFiles: $inputFiles, ')
          ..write('detailsJson: $detailsJson, ')
          ..write('targetPath: $targetPath, ')
          ..write('targetSha: $targetSha, ')
          ..write('targetSize: $targetSize, ')
          ..write('personId: $personId, ')
          ..write('status: $status, ')
          ..write('progress: $progress, ')
          ..write('message: $message, ')
          ..write('error: $error, ')
          ..write('acknowledged: $acknowledged, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ResultsTable extends Results with TableInfo<$ResultsTable, ResultRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ResultsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _typeMeta = const VerificationMeta('type');
  @override
  late final GeneratedColumn<String> type = GeneratedColumn<String>(
    'type',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _pathMeta = const VerificationMeta('path');
  @override
  late final GeneratedColumn<String> path = GeneratedColumn<String>(
    'path',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _originalPathMeta = const VerificationMeta(
    'originalPath',
  );
  @override
  late final GeneratedColumn<String> originalPath = GeneratedColumn<String>(
    'original_path',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _mimeMeta = const VerificationMeta('mime');
  @override
  late final GeneratedColumn<String> mime = GeneratedColumn<String>(
    'mime',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _sizeBytesMeta = const VerificationMeta(
    'sizeBytes',
  );
  @override
  late final GeneratedColumn<int> sizeBytes = GeneratedColumn<int>(
    'size_bytes',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _sha256Meta = const VerificationMeta('sha256');
  @override
  late final GeneratedColumn<String> sha256 = GeneratedColumn<String>(
    'sha256',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _personIdMeta = const VerificationMeta(
    'personId',
  );
  @override
  late final GeneratedColumn<int> personId = GeneratedColumn<int>(
    'person_id',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES persons (id) ON DELETE SET NULL',
    ),
  );
  static const VerificationMeta _favouriteMeta = const VerificationMeta(
    'favourite',
  );
  @override
  late final GeneratedColumn<bool> favourite = GeneratedColumn<bool>(
    'favourite',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("favourite" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<int> createdAt = GeneratedColumn<int>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    type,
    path,
    originalPath,
    mime,
    sizeBytes,
    sha256,
    personId,
    favourite,
    createdAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'results';
  @override
  VerificationContext validateIntegrity(
    Insertable<ResultRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('type')) {
      context.handle(
        _typeMeta,
        type.isAcceptableOrUnknown(data['type']!, _typeMeta),
      );
    } else if (isInserting) {
      context.missing(_typeMeta);
    }
    if (data.containsKey('path')) {
      context.handle(
        _pathMeta,
        path.isAcceptableOrUnknown(data['path']!, _pathMeta),
      );
    } else if (isInserting) {
      context.missing(_pathMeta);
    }
    if (data.containsKey('original_path')) {
      context.handle(
        _originalPathMeta,
        originalPath.isAcceptableOrUnknown(
          data['original_path']!,
          _originalPathMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_originalPathMeta);
    }
    if (data.containsKey('mime')) {
      context.handle(
        _mimeMeta,
        mime.isAcceptableOrUnknown(data['mime']!, _mimeMeta),
      );
    } else if (isInserting) {
      context.missing(_mimeMeta);
    }
    if (data.containsKey('size_bytes')) {
      context.handle(
        _sizeBytesMeta,
        sizeBytes.isAcceptableOrUnknown(data['size_bytes']!, _sizeBytesMeta),
      );
    } else if (isInserting) {
      context.missing(_sizeBytesMeta);
    }
    if (data.containsKey('sha256')) {
      context.handle(
        _sha256Meta,
        sha256.isAcceptableOrUnknown(data['sha256']!, _sha256Meta),
      );
    } else if (isInserting) {
      context.missing(_sha256Meta);
    }
    if (data.containsKey('person_id')) {
      context.handle(
        _personIdMeta,
        personId.isAcceptableOrUnknown(data['person_id']!, _personIdMeta),
      );
    }
    if (data.containsKey('favourite')) {
      context.handle(
        _favouriteMeta,
        favourite.isAcceptableOrUnknown(data['favourite']!, _favouriteMeta),
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
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  ResultRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ResultRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      type: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}type'],
      )!,
      path: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}path'],
      )!,
      originalPath: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}original_path'],
      )!,
      mime: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}mime'],
      )!,
      sizeBytes: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}size_bytes'],
      )!,
      sha256: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}sha256'],
      )!,
      personId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}person_id'],
      ),
      favourite: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}favourite'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}created_at'],
      )!,
    );
  }

  @override
  $ResultsTable createAlias(String alias) {
    return $ResultsTable(attachedDatabase, alias);
  }
}

class ResultRow extends DataClass implements Insertable<ResultRow> {
  final String id;
  final String type;
  final String path;
  final String originalPath;
  final String mime;
  final int sizeBytes;
  final String sha256;
  final int? personId;
  final bool favourite;
  final int createdAt;
  const ResultRow({
    required this.id,
    required this.type,
    required this.path,
    required this.originalPath,
    required this.mime,
    required this.sizeBytes,
    required this.sha256,
    this.personId,
    required this.favourite,
    required this.createdAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['type'] = Variable<String>(type);
    map['path'] = Variable<String>(path);
    map['original_path'] = Variable<String>(originalPath);
    map['mime'] = Variable<String>(mime);
    map['size_bytes'] = Variable<int>(sizeBytes);
    map['sha256'] = Variable<String>(sha256);
    if (!nullToAbsent || personId != null) {
      map['person_id'] = Variable<int>(personId);
    }
    map['favourite'] = Variable<bool>(favourite);
    map['created_at'] = Variable<int>(createdAt);
    return map;
  }

  ResultsCompanion toCompanion(bool nullToAbsent) {
    return ResultsCompanion(
      id: Value(id),
      type: Value(type),
      path: Value(path),
      originalPath: Value(originalPath),
      mime: Value(mime),
      sizeBytes: Value(sizeBytes),
      sha256: Value(sha256),
      personId: personId == null && nullToAbsent
          ? const Value.absent()
          : Value(personId),
      favourite: Value(favourite),
      createdAt: Value(createdAt),
    );
  }

  factory ResultRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ResultRow(
      id: serializer.fromJson<String>(json['id']),
      type: serializer.fromJson<String>(json['type']),
      path: serializer.fromJson<String>(json['path']),
      originalPath: serializer.fromJson<String>(json['originalPath']),
      mime: serializer.fromJson<String>(json['mime']),
      sizeBytes: serializer.fromJson<int>(json['sizeBytes']),
      sha256: serializer.fromJson<String>(json['sha256']),
      personId: serializer.fromJson<int?>(json['personId']),
      favourite: serializer.fromJson<bool>(json['favourite']),
      createdAt: serializer.fromJson<int>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'type': serializer.toJson<String>(type),
      'path': serializer.toJson<String>(path),
      'originalPath': serializer.toJson<String>(originalPath),
      'mime': serializer.toJson<String>(mime),
      'sizeBytes': serializer.toJson<int>(sizeBytes),
      'sha256': serializer.toJson<String>(sha256),
      'personId': serializer.toJson<int?>(personId),
      'favourite': serializer.toJson<bool>(favourite),
      'createdAt': serializer.toJson<int>(createdAt),
    };
  }

  ResultRow copyWith({
    String? id,
    String? type,
    String? path,
    String? originalPath,
    String? mime,
    int? sizeBytes,
    String? sha256,
    Value<int?> personId = const Value.absent(),
    bool? favourite,
    int? createdAt,
  }) => ResultRow(
    id: id ?? this.id,
    type: type ?? this.type,
    path: path ?? this.path,
    originalPath: originalPath ?? this.originalPath,
    mime: mime ?? this.mime,
    sizeBytes: sizeBytes ?? this.sizeBytes,
    sha256: sha256 ?? this.sha256,
    personId: personId.present ? personId.value : this.personId,
    favourite: favourite ?? this.favourite,
    createdAt: createdAt ?? this.createdAt,
  );
  ResultRow copyWithCompanion(ResultsCompanion data) {
    return ResultRow(
      id: data.id.present ? data.id.value : this.id,
      type: data.type.present ? data.type.value : this.type,
      path: data.path.present ? data.path.value : this.path,
      originalPath: data.originalPath.present
          ? data.originalPath.value
          : this.originalPath,
      mime: data.mime.present ? data.mime.value : this.mime,
      sizeBytes: data.sizeBytes.present ? data.sizeBytes.value : this.sizeBytes,
      sha256: data.sha256.present ? data.sha256.value : this.sha256,
      personId: data.personId.present ? data.personId.value : this.personId,
      favourite: data.favourite.present ? data.favourite.value : this.favourite,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ResultRow(')
          ..write('id: $id, ')
          ..write('type: $type, ')
          ..write('path: $path, ')
          ..write('originalPath: $originalPath, ')
          ..write('mime: $mime, ')
          ..write('sizeBytes: $sizeBytes, ')
          ..write('sha256: $sha256, ')
          ..write('personId: $personId, ')
          ..write('favourite: $favourite, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    type,
    path,
    originalPath,
    mime,
    sizeBytes,
    sha256,
    personId,
    favourite,
    createdAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ResultRow &&
          other.id == this.id &&
          other.type == this.type &&
          other.path == this.path &&
          other.originalPath == this.originalPath &&
          other.mime == this.mime &&
          other.sizeBytes == this.sizeBytes &&
          other.sha256 == this.sha256 &&
          other.personId == this.personId &&
          other.favourite == this.favourite &&
          other.createdAt == this.createdAt);
}

class ResultsCompanion extends UpdateCompanion<ResultRow> {
  final Value<String> id;
  final Value<String> type;
  final Value<String> path;
  final Value<String> originalPath;
  final Value<String> mime;
  final Value<int> sizeBytes;
  final Value<String> sha256;
  final Value<int?> personId;
  final Value<bool> favourite;
  final Value<int> createdAt;
  final Value<int> rowid;
  const ResultsCompanion({
    this.id = const Value.absent(),
    this.type = const Value.absent(),
    this.path = const Value.absent(),
    this.originalPath = const Value.absent(),
    this.mime = const Value.absent(),
    this.sizeBytes = const Value.absent(),
    this.sha256 = const Value.absent(),
    this.personId = const Value.absent(),
    this.favourite = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ResultsCompanion.insert({
    required String id,
    required String type,
    required String path,
    required String originalPath,
    required String mime,
    required int sizeBytes,
    required String sha256,
    this.personId = const Value.absent(),
    this.favourite = const Value.absent(),
    required int createdAt,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       type = Value(type),
       path = Value(path),
       originalPath = Value(originalPath),
       mime = Value(mime),
       sizeBytes = Value(sizeBytes),
       sha256 = Value(sha256),
       createdAt = Value(createdAt);
  static Insertable<ResultRow> custom({
    Expression<String>? id,
    Expression<String>? type,
    Expression<String>? path,
    Expression<String>? originalPath,
    Expression<String>? mime,
    Expression<int>? sizeBytes,
    Expression<String>? sha256,
    Expression<int>? personId,
    Expression<bool>? favourite,
    Expression<int>? createdAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (type != null) 'type': type,
      if (path != null) 'path': path,
      if (originalPath != null) 'original_path': originalPath,
      if (mime != null) 'mime': mime,
      if (sizeBytes != null) 'size_bytes': sizeBytes,
      if (sha256 != null) 'sha256': sha256,
      if (personId != null) 'person_id': personId,
      if (favourite != null) 'favourite': favourite,
      if (createdAt != null) 'created_at': createdAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ResultsCompanion copyWith({
    Value<String>? id,
    Value<String>? type,
    Value<String>? path,
    Value<String>? originalPath,
    Value<String>? mime,
    Value<int>? sizeBytes,
    Value<String>? sha256,
    Value<int?>? personId,
    Value<bool>? favourite,
    Value<int>? createdAt,
    Value<int>? rowid,
  }) {
    return ResultsCompanion(
      id: id ?? this.id,
      type: type ?? this.type,
      path: path ?? this.path,
      originalPath: originalPath ?? this.originalPath,
      mime: mime ?? this.mime,
      sizeBytes: sizeBytes ?? this.sizeBytes,
      sha256: sha256 ?? this.sha256,
      personId: personId ?? this.personId,
      favourite: favourite ?? this.favourite,
      createdAt: createdAt ?? this.createdAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (type.present) {
      map['type'] = Variable<String>(type.value);
    }
    if (path.present) {
      map['path'] = Variable<String>(path.value);
    }
    if (originalPath.present) {
      map['original_path'] = Variable<String>(originalPath.value);
    }
    if (mime.present) {
      map['mime'] = Variable<String>(mime.value);
    }
    if (sizeBytes.present) {
      map['size_bytes'] = Variable<int>(sizeBytes.value);
    }
    if (sha256.present) {
      map['sha256'] = Variable<String>(sha256.value);
    }
    if (personId.present) {
      map['person_id'] = Variable<int>(personId.value);
    }
    if (favourite.present) {
      map['favourite'] = Variable<bool>(favourite.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<int>(createdAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ResultsCompanion(')
          ..write('id: $id, ')
          ..write('type: $type, ')
          ..write('path: $path, ')
          ..write('originalPath: $originalPath, ')
          ..write('mime: $mime, ')
          ..write('sizeBytes: $sizeBytes, ')
          ..write('sha256: $sha256, ')
          ..write('personId: $personId, ')
          ..write('favourite: $favourite, ')
          ..write('createdAt: $createdAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $DatasetsTable extends Datasets
    with TableInfo<$DatasetsTable, DatasetRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $DatasetsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _personIdMeta = const VerificationMeta(
    'personId',
  );
  @override
  late final GeneratedColumn<int> personId = GeneratedColumn<int>(
    'person_id',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES persons (id) ON DELETE SET NULL',
    ),
  );
  static const VerificationMeta _triggerWordMeta = const VerificationMeta(
    'triggerWord',
  );
  @override
  late final GeneratedColumn<String> triggerWord = GeneratedColumn<String>(
    'trigger_word',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _repeatsMeta = const VerificationMeta(
    'repeats',
  );
  @override
  late final GeneratedColumn<int> repeats = GeneratedColumn<int>(
    'repeats',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(20),
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<int> createdAt = GeneratedColumn<int>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    personId,
    triggerWord,
    repeats,
    createdAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'datasets';
  @override
  VerificationContext validateIntegrity(
    Insertable<DatasetRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('person_id')) {
      context.handle(
        _personIdMeta,
        personId.isAcceptableOrUnknown(data['person_id']!, _personIdMeta),
      );
    }
    if (data.containsKey('trigger_word')) {
      context.handle(
        _triggerWordMeta,
        triggerWord.isAcceptableOrUnknown(
          data['trigger_word']!,
          _triggerWordMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_triggerWordMeta);
    }
    if (data.containsKey('repeats')) {
      context.handle(
        _repeatsMeta,
        repeats.isAcceptableOrUnknown(data['repeats']!, _repeatsMeta),
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
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  DatasetRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return DatasetRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      personId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}person_id'],
      ),
      triggerWord: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}trigger_word'],
      )!,
      repeats: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}repeats'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}created_at'],
      )!,
    );
  }

  @override
  $DatasetsTable createAlias(String alias) {
    return $DatasetsTable(attachedDatabase, alias);
  }
}

class DatasetRow extends DataClass implements Insertable<DatasetRow> {
  final String id;
  final int? personId;
  final String triggerWord;
  final int repeats;
  final int createdAt;
  const DatasetRow({
    required this.id,
    this.personId,
    required this.triggerWord,
    required this.repeats,
    required this.createdAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    if (!nullToAbsent || personId != null) {
      map['person_id'] = Variable<int>(personId);
    }
    map['trigger_word'] = Variable<String>(triggerWord);
    map['repeats'] = Variable<int>(repeats);
    map['created_at'] = Variable<int>(createdAt);
    return map;
  }

  DatasetsCompanion toCompanion(bool nullToAbsent) {
    return DatasetsCompanion(
      id: Value(id),
      personId: personId == null && nullToAbsent
          ? const Value.absent()
          : Value(personId),
      triggerWord: Value(triggerWord),
      repeats: Value(repeats),
      createdAt: Value(createdAt),
    );
  }

  factory DatasetRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return DatasetRow(
      id: serializer.fromJson<String>(json['id']),
      personId: serializer.fromJson<int?>(json['personId']),
      triggerWord: serializer.fromJson<String>(json['triggerWord']),
      repeats: serializer.fromJson<int>(json['repeats']),
      createdAt: serializer.fromJson<int>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'personId': serializer.toJson<int?>(personId),
      'triggerWord': serializer.toJson<String>(triggerWord),
      'repeats': serializer.toJson<int>(repeats),
      'createdAt': serializer.toJson<int>(createdAt),
    };
  }

  DatasetRow copyWith({
    String? id,
    Value<int?> personId = const Value.absent(),
    String? triggerWord,
    int? repeats,
    int? createdAt,
  }) => DatasetRow(
    id: id ?? this.id,
    personId: personId.present ? personId.value : this.personId,
    triggerWord: triggerWord ?? this.triggerWord,
    repeats: repeats ?? this.repeats,
    createdAt: createdAt ?? this.createdAt,
  );
  DatasetRow copyWithCompanion(DatasetsCompanion data) {
    return DatasetRow(
      id: data.id.present ? data.id.value : this.id,
      personId: data.personId.present ? data.personId.value : this.personId,
      triggerWord: data.triggerWord.present
          ? data.triggerWord.value
          : this.triggerWord,
      repeats: data.repeats.present ? data.repeats.value : this.repeats,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('DatasetRow(')
          ..write('id: $id, ')
          ..write('personId: $personId, ')
          ..write('triggerWord: $triggerWord, ')
          ..write('repeats: $repeats, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(id, personId, triggerWord, repeats, createdAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is DatasetRow &&
          other.id == this.id &&
          other.personId == this.personId &&
          other.triggerWord == this.triggerWord &&
          other.repeats == this.repeats &&
          other.createdAt == this.createdAt);
}

class DatasetsCompanion extends UpdateCompanion<DatasetRow> {
  final Value<String> id;
  final Value<int?> personId;
  final Value<String> triggerWord;
  final Value<int> repeats;
  final Value<int> createdAt;
  final Value<int> rowid;
  const DatasetsCompanion({
    this.id = const Value.absent(),
    this.personId = const Value.absent(),
    this.triggerWord = const Value.absent(),
    this.repeats = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  DatasetsCompanion.insert({
    required String id,
    this.personId = const Value.absent(),
    required String triggerWord,
    this.repeats = const Value.absent(),
    required int createdAt,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       triggerWord = Value(triggerWord),
       createdAt = Value(createdAt);
  static Insertable<DatasetRow> custom({
    Expression<String>? id,
    Expression<int>? personId,
    Expression<String>? triggerWord,
    Expression<int>? repeats,
    Expression<int>? createdAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (personId != null) 'person_id': personId,
      if (triggerWord != null) 'trigger_word': triggerWord,
      if (repeats != null) 'repeats': repeats,
      if (createdAt != null) 'created_at': createdAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  DatasetsCompanion copyWith({
    Value<String>? id,
    Value<int?>? personId,
    Value<String>? triggerWord,
    Value<int>? repeats,
    Value<int>? createdAt,
    Value<int>? rowid,
  }) {
    return DatasetsCompanion(
      id: id ?? this.id,
      personId: personId ?? this.personId,
      triggerWord: triggerWord ?? this.triggerWord,
      repeats: repeats ?? this.repeats,
      createdAt: createdAt ?? this.createdAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (personId.present) {
      map['person_id'] = Variable<int>(personId.value);
    }
    if (triggerWord.present) {
      map['trigger_word'] = Variable<String>(triggerWord.value);
    }
    if (repeats.present) {
      map['repeats'] = Variable<int>(repeats.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<int>(createdAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('DatasetsCompanion(')
          ..write('id: $id, ')
          ..write('personId: $personId, ')
          ..write('triggerWord: $triggerWord, ')
          ..write('repeats: $repeats, ')
          ..write('createdAt: $createdAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $DatasetItemsTable extends DatasetItems
    with TableInfo<$DatasetItemsTable, DatasetItemRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $DatasetItemsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _datasetIdMeta = const VerificationMeta(
    'datasetId',
  );
  @override
  late final GeneratedColumn<String> datasetId = GeneratedColumn<String>(
    'dataset_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES datasets (id) ON DELETE CASCADE',
    ),
  );
  static const VerificationMeta _pathMeta = const VerificationMeta('path');
  @override
  late final GeneratedColumn<String> path = GeneratedColumn<String>(
    'path',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _captionMeta = const VerificationMeta(
    'caption',
  );
  @override
  late final GeneratedColumn<String> caption = GeneratedColumn<String>(
    'caption',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _includedMeta = const VerificationMeta(
    'included',
  );
  @override
  late final GeneratedColumn<bool> included = GeneratedColumn<bool>(
    'included',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("included" IN (0, 1))',
    ),
    defaultValue: const Constant(true),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    datasetId,
    path,
    caption,
    included,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'dataset_items';
  @override
  VerificationContext validateIntegrity(
    Insertable<DatasetItemRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('dataset_id')) {
      context.handle(
        _datasetIdMeta,
        datasetId.isAcceptableOrUnknown(data['dataset_id']!, _datasetIdMeta),
      );
    } else if (isInserting) {
      context.missing(_datasetIdMeta);
    }
    if (data.containsKey('path')) {
      context.handle(
        _pathMeta,
        path.isAcceptableOrUnknown(data['path']!, _pathMeta),
      );
    } else if (isInserting) {
      context.missing(_pathMeta);
    }
    if (data.containsKey('caption')) {
      context.handle(
        _captionMeta,
        caption.isAcceptableOrUnknown(data['caption']!, _captionMeta),
      );
    } else if (isInserting) {
      context.missing(_captionMeta);
    }
    if (data.containsKey('included')) {
      context.handle(
        _includedMeta,
        included.isAcceptableOrUnknown(data['included']!, _includedMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  DatasetItemRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return DatasetItemRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      datasetId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}dataset_id'],
      )!,
      path: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}path'],
      )!,
      caption: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}caption'],
      )!,
      included: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}included'],
      )!,
    );
  }

  @override
  $DatasetItemsTable createAlias(String alias) {
    return $DatasetItemsTable(attachedDatabase, alias);
  }
}

class DatasetItemRow extends DataClass implements Insertable<DatasetItemRow> {
  final int id;
  final String datasetId;
  final String path;
  final String caption;
  final bool included;
  const DatasetItemRow({
    required this.id,
    required this.datasetId,
    required this.path,
    required this.caption,
    required this.included,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['dataset_id'] = Variable<String>(datasetId);
    map['path'] = Variable<String>(path);
    map['caption'] = Variable<String>(caption);
    map['included'] = Variable<bool>(included);
    return map;
  }

  DatasetItemsCompanion toCompanion(bool nullToAbsent) {
    return DatasetItemsCompanion(
      id: Value(id),
      datasetId: Value(datasetId),
      path: Value(path),
      caption: Value(caption),
      included: Value(included),
    );
  }

  factory DatasetItemRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return DatasetItemRow(
      id: serializer.fromJson<int>(json['id']),
      datasetId: serializer.fromJson<String>(json['datasetId']),
      path: serializer.fromJson<String>(json['path']),
      caption: serializer.fromJson<String>(json['caption']),
      included: serializer.fromJson<bool>(json['included']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'datasetId': serializer.toJson<String>(datasetId),
      'path': serializer.toJson<String>(path),
      'caption': serializer.toJson<String>(caption),
      'included': serializer.toJson<bool>(included),
    };
  }

  DatasetItemRow copyWith({
    int? id,
    String? datasetId,
    String? path,
    String? caption,
    bool? included,
  }) => DatasetItemRow(
    id: id ?? this.id,
    datasetId: datasetId ?? this.datasetId,
    path: path ?? this.path,
    caption: caption ?? this.caption,
    included: included ?? this.included,
  );
  DatasetItemRow copyWithCompanion(DatasetItemsCompanion data) {
    return DatasetItemRow(
      id: data.id.present ? data.id.value : this.id,
      datasetId: data.datasetId.present ? data.datasetId.value : this.datasetId,
      path: data.path.present ? data.path.value : this.path,
      caption: data.caption.present ? data.caption.value : this.caption,
      included: data.included.present ? data.included.value : this.included,
    );
  }

  @override
  String toString() {
    return (StringBuffer('DatasetItemRow(')
          ..write('id: $id, ')
          ..write('datasetId: $datasetId, ')
          ..write('path: $path, ')
          ..write('caption: $caption, ')
          ..write('included: $included')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, datasetId, path, caption, included);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is DatasetItemRow &&
          other.id == this.id &&
          other.datasetId == this.datasetId &&
          other.path == this.path &&
          other.caption == this.caption &&
          other.included == this.included);
}

class DatasetItemsCompanion extends UpdateCompanion<DatasetItemRow> {
  final Value<int> id;
  final Value<String> datasetId;
  final Value<String> path;
  final Value<String> caption;
  final Value<bool> included;
  const DatasetItemsCompanion({
    this.id = const Value.absent(),
    this.datasetId = const Value.absent(),
    this.path = const Value.absent(),
    this.caption = const Value.absent(),
    this.included = const Value.absent(),
  });
  DatasetItemsCompanion.insert({
    this.id = const Value.absent(),
    required String datasetId,
    required String path,
    required String caption,
    this.included = const Value.absent(),
  }) : datasetId = Value(datasetId),
       path = Value(path),
       caption = Value(caption);
  static Insertable<DatasetItemRow> custom({
    Expression<int>? id,
    Expression<String>? datasetId,
    Expression<String>? path,
    Expression<String>? caption,
    Expression<bool>? included,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (datasetId != null) 'dataset_id': datasetId,
      if (path != null) 'path': path,
      if (caption != null) 'caption': caption,
      if (included != null) 'included': included,
    });
  }

  DatasetItemsCompanion copyWith({
    Value<int>? id,
    Value<String>? datasetId,
    Value<String>? path,
    Value<String>? caption,
    Value<bool>? included,
  }) {
    return DatasetItemsCompanion(
      id: id ?? this.id,
      datasetId: datasetId ?? this.datasetId,
      path: path ?? this.path,
      caption: caption ?? this.caption,
      included: included ?? this.included,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (datasetId.present) {
      map['dataset_id'] = Variable<String>(datasetId.value);
    }
    if (path.present) {
      map['path'] = Variable<String>(path.value);
    }
    if (caption.present) {
      map['caption'] = Variable<String>(caption.value);
    }
    if (included.present) {
      map['included'] = Variable<bool>(included.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('DatasetItemsCompanion(')
          ..write('id: $id, ')
          ..write('datasetId: $datasetId, ')
          ..write('path: $path, ')
          ..write('caption: $caption, ')
          ..write('included: $included')
          ..write(')'))
        .toString();
  }
}

class $LorasTable extends Loras with TableInfo<$LorasTable, LoraRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $LorasTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _personIdMeta = const VerificationMeta(
    'personId',
  );
  @override
  late final GeneratedColumn<int> personId = GeneratedColumn<int>(
    'person_id',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES persons (id) ON DELETE SET NULL',
    ),
  );
  static const VerificationMeta _pathMeta = const VerificationMeta('path');
  @override
  late final GeneratedColumn<String> path = GeneratedColumn<String>(
    'path',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _triggerWordMeta = const VerificationMeta(
    'triggerWord',
  );
  @override
  late final GeneratedColumn<String> triggerWord = GeneratedColumn<String>(
    'trigger_word',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _identityJsonMeta = const VerificationMeta(
    'identityJson',
  );
  @override
  late final GeneratedColumn<String> identityJson = GeneratedColumn<String>(
    'identity_json',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<int> createdAt = GeneratedColumn<int>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    personId,
    path,
    triggerWord,
    identityJson,
    createdAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'loras';
  @override
  VerificationContext validateIntegrity(
    Insertable<LoraRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('person_id')) {
      context.handle(
        _personIdMeta,
        personId.isAcceptableOrUnknown(data['person_id']!, _personIdMeta),
      );
    }
    if (data.containsKey('path')) {
      context.handle(
        _pathMeta,
        path.isAcceptableOrUnknown(data['path']!, _pathMeta),
      );
    } else if (isInserting) {
      context.missing(_pathMeta);
    }
    if (data.containsKey('trigger_word')) {
      context.handle(
        _triggerWordMeta,
        triggerWord.isAcceptableOrUnknown(
          data['trigger_word']!,
          _triggerWordMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_triggerWordMeta);
    }
    if (data.containsKey('identity_json')) {
      context.handle(
        _identityJsonMeta,
        identityJson.isAcceptableOrUnknown(
          data['identity_json']!,
          _identityJsonMeta,
        ),
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
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  LoraRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return LoraRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      personId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}person_id'],
      ),
      path: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}path'],
      )!,
      triggerWord: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}trigger_word'],
      )!,
      identityJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}identity_json'],
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}created_at'],
      )!,
    );
  }

  @override
  $LorasTable createAlias(String alias) {
    return $LorasTable(attachedDatabase, alias);
  }
}

class LoraRow extends DataClass implements Insertable<LoraRow> {
  final String id;
  final int? personId;
  final String path;
  final String triggerWord;
  final String? identityJson;
  final int createdAt;
  const LoraRow({
    required this.id,
    this.personId,
    required this.path,
    required this.triggerWord,
    this.identityJson,
    required this.createdAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    if (!nullToAbsent || personId != null) {
      map['person_id'] = Variable<int>(personId);
    }
    map['path'] = Variable<String>(path);
    map['trigger_word'] = Variable<String>(triggerWord);
    if (!nullToAbsent || identityJson != null) {
      map['identity_json'] = Variable<String>(identityJson);
    }
    map['created_at'] = Variable<int>(createdAt);
    return map;
  }

  LorasCompanion toCompanion(bool nullToAbsent) {
    return LorasCompanion(
      id: Value(id),
      personId: personId == null && nullToAbsent
          ? const Value.absent()
          : Value(personId),
      path: Value(path),
      triggerWord: Value(triggerWord),
      identityJson: identityJson == null && nullToAbsent
          ? const Value.absent()
          : Value(identityJson),
      createdAt: Value(createdAt),
    );
  }

  factory LoraRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return LoraRow(
      id: serializer.fromJson<String>(json['id']),
      personId: serializer.fromJson<int?>(json['personId']),
      path: serializer.fromJson<String>(json['path']),
      triggerWord: serializer.fromJson<String>(json['triggerWord']),
      identityJson: serializer.fromJson<String?>(json['identityJson']),
      createdAt: serializer.fromJson<int>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'personId': serializer.toJson<int?>(personId),
      'path': serializer.toJson<String>(path),
      'triggerWord': serializer.toJson<String>(triggerWord),
      'identityJson': serializer.toJson<String?>(identityJson),
      'createdAt': serializer.toJson<int>(createdAt),
    };
  }

  LoraRow copyWith({
    String? id,
    Value<int?> personId = const Value.absent(),
    String? path,
    String? triggerWord,
    Value<String?> identityJson = const Value.absent(),
    int? createdAt,
  }) => LoraRow(
    id: id ?? this.id,
    personId: personId.present ? personId.value : this.personId,
    path: path ?? this.path,
    triggerWord: triggerWord ?? this.triggerWord,
    identityJson: identityJson.present ? identityJson.value : this.identityJson,
    createdAt: createdAt ?? this.createdAt,
  );
  LoraRow copyWithCompanion(LorasCompanion data) {
    return LoraRow(
      id: data.id.present ? data.id.value : this.id,
      personId: data.personId.present ? data.personId.value : this.personId,
      path: data.path.present ? data.path.value : this.path,
      triggerWord: data.triggerWord.present
          ? data.triggerWord.value
          : this.triggerWord,
      identityJson: data.identityJson.present
          ? data.identityJson.value
          : this.identityJson,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('LoraRow(')
          ..write('id: $id, ')
          ..write('personId: $personId, ')
          ..write('path: $path, ')
          ..write('triggerWord: $triggerWord, ')
          ..write('identityJson: $identityJson, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(id, personId, path, triggerWord, identityJson, createdAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is LoraRow &&
          other.id == this.id &&
          other.personId == this.personId &&
          other.path == this.path &&
          other.triggerWord == this.triggerWord &&
          other.identityJson == this.identityJson &&
          other.createdAt == this.createdAt);
}

class LorasCompanion extends UpdateCompanion<LoraRow> {
  final Value<String> id;
  final Value<int?> personId;
  final Value<String> path;
  final Value<String> triggerWord;
  final Value<String?> identityJson;
  final Value<int> createdAt;
  final Value<int> rowid;
  const LorasCompanion({
    this.id = const Value.absent(),
    this.personId = const Value.absent(),
    this.path = const Value.absent(),
    this.triggerWord = const Value.absent(),
    this.identityJson = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  LorasCompanion.insert({
    required String id,
    this.personId = const Value.absent(),
    required String path,
    required String triggerWord,
    this.identityJson = const Value.absent(),
    required int createdAt,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       path = Value(path),
       triggerWord = Value(triggerWord),
       createdAt = Value(createdAt);
  static Insertable<LoraRow> custom({
    Expression<String>? id,
    Expression<int>? personId,
    Expression<String>? path,
    Expression<String>? triggerWord,
    Expression<String>? identityJson,
    Expression<int>? createdAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (personId != null) 'person_id': personId,
      if (path != null) 'path': path,
      if (triggerWord != null) 'trigger_word': triggerWord,
      if (identityJson != null) 'identity_json': identityJson,
      if (createdAt != null) 'created_at': createdAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  LorasCompanion copyWith({
    Value<String>? id,
    Value<int?>? personId,
    Value<String>? path,
    Value<String>? triggerWord,
    Value<String?>? identityJson,
    Value<int>? createdAt,
    Value<int>? rowid,
  }) {
    return LorasCompanion(
      id: id ?? this.id,
      personId: personId ?? this.personId,
      path: path ?? this.path,
      triggerWord: triggerWord ?? this.triggerWord,
      identityJson: identityJson ?? this.identityJson,
      createdAt: createdAt ?? this.createdAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (personId.present) {
      map['person_id'] = Variable<int>(personId.value);
    }
    if (path.present) {
      map['path'] = Variable<String>(path.value);
    }
    if (triggerWord.present) {
      map['trigger_word'] = Variable<String>(triggerWord.value);
    }
    if (identityJson.present) {
      map['identity_json'] = Variable<String>(identityJson.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<int>(createdAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('LorasCompanion(')
          ..write('id: $id, ')
          ..write('personId: $personId, ')
          ..write('path: $path, ')
          ..write('triggerWord: $triggerWord, ')
          ..write('identityJson: $identityJson, ')
          ..write('createdAt: $createdAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $IdentitySetsTable extends IdentitySets
    with TableInfo<$IdentitySetsTable, IdentitySetRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $IdentitySetsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _personIdMeta = const VerificationMeta(
    'personId',
  );
  @override
  late final GeneratedColumn<int> personId = GeneratedColumn<int>(
    'person_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES persons (id) ON DELETE CASCADE',
    ),
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    additionalChecks: GeneratedColumn.checkTextLength(
      minTextLength: 1,
      maxTextLength: 80,
    ),
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _modelIdMeta = const VerificationMeta(
    'modelId',
  );
  @override
  late final GeneratedColumn<String> modelId = GeneratedColumn<String>(
    'model_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<int> createdAt = GeneratedColumn<int>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    personId,
    name,
    modelId,
    createdAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'identity_sets';
  @override
  VerificationContext validateIntegrity(
    Insertable<IdentitySetRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('person_id')) {
      context.handle(
        _personIdMeta,
        personId.isAcceptableOrUnknown(data['person_id']!, _personIdMeta),
      );
    } else if (isInserting) {
      context.missing(_personIdMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('model_id')) {
      context.handle(
        _modelIdMeta,
        modelId.isAcceptableOrUnknown(data['model_id']!, _modelIdMeta),
      );
    } else if (isInserting) {
      context.missing(_modelIdMeta);
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
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  IdentitySetRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return IdentitySetRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      personId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}person_id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      modelId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}model_id'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}created_at'],
      )!,
    );
  }

  @override
  $IdentitySetsTable createAlias(String alias) {
    return $IdentitySetsTable(attachedDatabase, alias);
  }
}

class IdentitySetRow extends DataClass implements Insertable<IdentitySetRow> {
  final int id;
  final int personId;
  final String name;
  final String modelId;
  final int createdAt;
  const IdentitySetRow({
    required this.id,
    required this.personId,
    required this.name,
    required this.modelId,
    required this.createdAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['person_id'] = Variable<int>(personId);
    map['name'] = Variable<String>(name);
    map['model_id'] = Variable<String>(modelId);
    map['created_at'] = Variable<int>(createdAt);
    return map;
  }

  IdentitySetsCompanion toCompanion(bool nullToAbsent) {
    return IdentitySetsCompanion(
      id: Value(id),
      personId: Value(personId),
      name: Value(name),
      modelId: Value(modelId),
      createdAt: Value(createdAt),
    );
  }

  factory IdentitySetRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return IdentitySetRow(
      id: serializer.fromJson<int>(json['id']),
      personId: serializer.fromJson<int>(json['personId']),
      name: serializer.fromJson<String>(json['name']),
      modelId: serializer.fromJson<String>(json['modelId']),
      createdAt: serializer.fromJson<int>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'personId': serializer.toJson<int>(personId),
      'name': serializer.toJson<String>(name),
      'modelId': serializer.toJson<String>(modelId),
      'createdAt': serializer.toJson<int>(createdAt),
    };
  }

  IdentitySetRow copyWith({
    int? id,
    int? personId,
    String? name,
    String? modelId,
    int? createdAt,
  }) => IdentitySetRow(
    id: id ?? this.id,
    personId: personId ?? this.personId,
    name: name ?? this.name,
    modelId: modelId ?? this.modelId,
    createdAt: createdAt ?? this.createdAt,
  );
  IdentitySetRow copyWithCompanion(IdentitySetsCompanion data) {
    return IdentitySetRow(
      id: data.id.present ? data.id.value : this.id,
      personId: data.personId.present ? data.personId.value : this.personId,
      name: data.name.present ? data.name.value : this.name,
      modelId: data.modelId.present ? data.modelId.value : this.modelId,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('IdentitySetRow(')
          ..write('id: $id, ')
          ..write('personId: $personId, ')
          ..write('name: $name, ')
          ..write('modelId: $modelId, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, personId, name, modelId, createdAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is IdentitySetRow &&
          other.id == this.id &&
          other.personId == this.personId &&
          other.name == this.name &&
          other.modelId == this.modelId &&
          other.createdAt == this.createdAt);
}

class IdentitySetsCompanion extends UpdateCompanion<IdentitySetRow> {
  final Value<int> id;
  final Value<int> personId;
  final Value<String> name;
  final Value<String> modelId;
  final Value<int> createdAt;
  const IdentitySetsCompanion({
    this.id = const Value.absent(),
    this.personId = const Value.absent(),
    this.name = const Value.absent(),
    this.modelId = const Value.absent(),
    this.createdAt = const Value.absent(),
  });
  IdentitySetsCompanion.insert({
    this.id = const Value.absent(),
    required int personId,
    required String name,
    required String modelId,
    required int createdAt,
  }) : personId = Value(personId),
       name = Value(name),
       modelId = Value(modelId),
       createdAt = Value(createdAt);
  static Insertable<IdentitySetRow> custom({
    Expression<int>? id,
    Expression<int>? personId,
    Expression<String>? name,
    Expression<String>? modelId,
    Expression<int>? createdAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (personId != null) 'person_id': personId,
      if (name != null) 'name': name,
      if (modelId != null) 'model_id': modelId,
      if (createdAt != null) 'created_at': createdAt,
    });
  }

  IdentitySetsCompanion copyWith({
    Value<int>? id,
    Value<int>? personId,
    Value<String>? name,
    Value<String>? modelId,
    Value<int>? createdAt,
  }) {
    return IdentitySetsCompanion(
      id: id ?? this.id,
      personId: personId ?? this.personId,
      name: name ?? this.name,
      modelId: modelId ?? this.modelId,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (personId.present) {
      map['person_id'] = Variable<int>(personId.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (modelId.present) {
      map['model_id'] = Variable<String>(modelId.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<int>(createdAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('IdentitySetsCompanion(')
          ..write('id: $id, ')
          ..write('personId: $personId, ')
          ..write('name: $name, ')
          ..write('modelId: $modelId, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }
}

class $IdentitySetFacesTable extends IdentitySetFaces
    with TableInfo<$IdentitySetFacesTable, IdentitySetFaceRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $IdentitySetFacesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _setIdMeta = const VerificationMeta('setId');
  @override
  late final GeneratedColumn<int> setId = GeneratedColumn<int>(
    'set_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES identity_sets (id) ON DELETE CASCADE',
    ),
  );
  static const VerificationMeta _faceIdMeta = const VerificationMeta('faceId');
  @override
  late final GeneratedColumn<int> faceId = GeneratedColumn<int>(
    'face_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES faces (id) ON DELETE CASCADE',
    ),
  );
  @override
  List<GeneratedColumn> get $columns => [setId, faceId];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'identity_set_faces';
  @override
  VerificationContext validateIntegrity(
    Insertable<IdentitySetFaceRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('set_id')) {
      context.handle(
        _setIdMeta,
        setId.isAcceptableOrUnknown(data['set_id']!, _setIdMeta),
      );
    } else if (isInserting) {
      context.missing(_setIdMeta);
    }
    if (data.containsKey('face_id')) {
      context.handle(
        _faceIdMeta,
        faceId.isAcceptableOrUnknown(data['face_id']!, _faceIdMeta),
      );
    } else if (isInserting) {
      context.missing(_faceIdMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {setId, faceId};
  @override
  IdentitySetFaceRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return IdentitySetFaceRow(
      setId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}set_id'],
      )!,
      faceId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}face_id'],
      )!,
    );
  }

  @override
  $IdentitySetFacesTable createAlias(String alias) {
    return $IdentitySetFacesTable(attachedDatabase, alias);
  }
}

class IdentitySetFaceRow extends DataClass
    implements Insertable<IdentitySetFaceRow> {
  final int setId;
  final int faceId;
  const IdentitySetFaceRow({required this.setId, required this.faceId});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['set_id'] = Variable<int>(setId);
    map['face_id'] = Variable<int>(faceId);
    return map;
  }

  IdentitySetFacesCompanion toCompanion(bool nullToAbsent) {
    return IdentitySetFacesCompanion(
      setId: Value(setId),
      faceId: Value(faceId),
    );
  }

  factory IdentitySetFaceRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return IdentitySetFaceRow(
      setId: serializer.fromJson<int>(json['setId']),
      faceId: serializer.fromJson<int>(json['faceId']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'setId': serializer.toJson<int>(setId),
      'faceId': serializer.toJson<int>(faceId),
    };
  }

  IdentitySetFaceRow copyWith({int? setId, int? faceId}) => IdentitySetFaceRow(
    setId: setId ?? this.setId,
    faceId: faceId ?? this.faceId,
  );
  IdentitySetFaceRow copyWithCompanion(IdentitySetFacesCompanion data) {
    return IdentitySetFaceRow(
      setId: data.setId.present ? data.setId.value : this.setId,
      faceId: data.faceId.present ? data.faceId.value : this.faceId,
    );
  }

  @override
  String toString() {
    return (StringBuffer('IdentitySetFaceRow(')
          ..write('setId: $setId, ')
          ..write('faceId: $faceId')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(setId, faceId);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is IdentitySetFaceRow &&
          other.setId == this.setId &&
          other.faceId == this.faceId);
}

class IdentitySetFacesCompanion extends UpdateCompanion<IdentitySetFaceRow> {
  final Value<int> setId;
  final Value<int> faceId;
  final Value<int> rowid;
  const IdentitySetFacesCompanion({
    this.setId = const Value.absent(),
    this.faceId = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  IdentitySetFacesCompanion.insert({
    required int setId,
    required int faceId,
    this.rowid = const Value.absent(),
  }) : setId = Value(setId),
       faceId = Value(faceId);
  static Insertable<IdentitySetFaceRow> custom({
    Expression<int>? setId,
    Expression<int>? faceId,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (setId != null) 'set_id': setId,
      if (faceId != null) 'face_id': faceId,
      if (rowid != null) 'rowid': rowid,
    });
  }

  IdentitySetFacesCompanion copyWith({
    Value<int>? setId,
    Value<int>? faceId,
    Value<int>? rowid,
  }) {
    return IdentitySetFacesCompanion(
      setId: setId ?? this.setId,
      faceId: faceId ?? this.faceId,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (setId.present) {
      map['set_id'] = Variable<int>(setId.value);
    }
    if (faceId.present) {
      map['face_id'] = Variable<int>(faceId.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('IdentitySetFacesCompanion(')
          ..write('setId: $setId, ')
          ..write('faceId: $faceId, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $JobEventsTable extends JobEvents
    with TableInfo<$JobEventsTable, JobEventRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $JobEventsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _jobIdMeta = const VerificationMeta('jobId');
  @override
  late final GeneratedColumn<String> jobId = GeneratedColumn<String>(
    'job_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES jobs (id) ON DELETE CASCADE',
    ),
  );
  static const VerificationMeta _statusMeta = const VerificationMeta('status');
  @override
  late final GeneratedColumn<String> status = GeneratedColumn<String>(
    'status',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _messageMeta = const VerificationMeta(
    'message',
  );
  @override
  late final GeneratedColumn<String> message = GeneratedColumn<String>(
    'message',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<int> createdAt = GeneratedColumn<int>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [id, jobId, status, message, createdAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'job_events';
  @override
  VerificationContext validateIntegrity(
    Insertable<JobEventRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('job_id')) {
      context.handle(
        _jobIdMeta,
        jobId.isAcceptableOrUnknown(data['job_id']!, _jobIdMeta),
      );
    } else if (isInserting) {
      context.missing(_jobIdMeta);
    }
    if (data.containsKey('status')) {
      context.handle(
        _statusMeta,
        status.isAcceptableOrUnknown(data['status']!, _statusMeta),
      );
    } else if (isInserting) {
      context.missing(_statusMeta);
    }
    if (data.containsKey('message')) {
      context.handle(
        _messageMeta,
        message.isAcceptableOrUnknown(data['message']!, _messageMeta),
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
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  JobEventRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return JobEventRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      jobId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}job_id'],
      )!,
      status: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}status'],
      )!,
      message: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}message'],
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}created_at'],
      )!,
    );
  }

  @override
  $JobEventsTable createAlias(String alias) {
    return $JobEventsTable(attachedDatabase, alias);
  }
}

class JobEventRow extends DataClass implements Insertable<JobEventRow> {
  final int id;
  final String jobId;
  final String status;
  final String? message;
  final int createdAt;
  const JobEventRow({
    required this.id,
    required this.jobId,
    required this.status,
    this.message,
    required this.createdAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['job_id'] = Variable<String>(jobId);
    map['status'] = Variable<String>(status);
    if (!nullToAbsent || message != null) {
      map['message'] = Variable<String>(message);
    }
    map['created_at'] = Variable<int>(createdAt);
    return map;
  }

  JobEventsCompanion toCompanion(bool nullToAbsent) {
    return JobEventsCompanion(
      id: Value(id),
      jobId: Value(jobId),
      status: Value(status),
      message: message == null && nullToAbsent
          ? const Value.absent()
          : Value(message),
      createdAt: Value(createdAt),
    );
  }

  factory JobEventRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return JobEventRow(
      id: serializer.fromJson<int>(json['id']),
      jobId: serializer.fromJson<String>(json['jobId']),
      status: serializer.fromJson<String>(json['status']),
      message: serializer.fromJson<String?>(json['message']),
      createdAt: serializer.fromJson<int>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'jobId': serializer.toJson<String>(jobId),
      'status': serializer.toJson<String>(status),
      'message': serializer.toJson<String?>(message),
      'createdAt': serializer.toJson<int>(createdAt),
    };
  }

  JobEventRow copyWith({
    int? id,
    String? jobId,
    String? status,
    Value<String?> message = const Value.absent(),
    int? createdAt,
  }) => JobEventRow(
    id: id ?? this.id,
    jobId: jobId ?? this.jobId,
    status: status ?? this.status,
    message: message.present ? message.value : this.message,
    createdAt: createdAt ?? this.createdAt,
  );
  JobEventRow copyWithCompanion(JobEventsCompanion data) {
    return JobEventRow(
      id: data.id.present ? data.id.value : this.id,
      jobId: data.jobId.present ? data.jobId.value : this.jobId,
      status: data.status.present ? data.status.value : this.status,
      message: data.message.present ? data.message.value : this.message,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('JobEventRow(')
          ..write('id: $id, ')
          ..write('jobId: $jobId, ')
          ..write('status: $status, ')
          ..write('message: $message, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, jobId, status, message, createdAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is JobEventRow &&
          other.id == this.id &&
          other.jobId == this.jobId &&
          other.status == this.status &&
          other.message == this.message &&
          other.createdAt == this.createdAt);
}

class JobEventsCompanion extends UpdateCompanion<JobEventRow> {
  final Value<int> id;
  final Value<String> jobId;
  final Value<String> status;
  final Value<String?> message;
  final Value<int> createdAt;
  const JobEventsCompanion({
    this.id = const Value.absent(),
    this.jobId = const Value.absent(),
    this.status = const Value.absent(),
    this.message = const Value.absent(),
    this.createdAt = const Value.absent(),
  });
  JobEventsCompanion.insert({
    this.id = const Value.absent(),
    required String jobId,
    required String status,
    this.message = const Value.absent(),
    required int createdAt,
  }) : jobId = Value(jobId),
       status = Value(status),
       createdAt = Value(createdAt);
  static Insertable<JobEventRow> custom({
    Expression<int>? id,
    Expression<String>? jobId,
    Expression<String>? status,
    Expression<String>? message,
    Expression<int>? createdAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (jobId != null) 'job_id': jobId,
      if (status != null) 'status': status,
      if (message != null) 'message': message,
      if (createdAt != null) 'created_at': createdAt,
    });
  }

  JobEventsCompanion copyWith({
    Value<int>? id,
    Value<String>? jobId,
    Value<String>? status,
    Value<String?>? message,
    Value<int>? createdAt,
  }) {
    return JobEventsCompanion(
      id: id ?? this.id,
      jobId: jobId ?? this.jobId,
      status: status ?? this.status,
      message: message ?? this.message,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (jobId.present) {
      map['job_id'] = Variable<String>(jobId.value);
    }
    if (status.present) {
      map['status'] = Variable<String>(status.value);
    }
    if (message.present) {
      map['message'] = Variable<String>(message.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<int>(createdAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('JobEventsCompanion(')
          ..write('id: $id, ')
          ..write('jobId: $jobId, ')
          ..write('status: $status, ')
          ..write('message: $message, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }
}

class $CharacterIdentitiesTable extends CharacterIdentities
    with TableInfo<$CharacterIdentitiesTable, CharacterIdentityRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CharacterIdentitiesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<int> createdAt = GeneratedColumn<int>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [id, name, createdAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'character_identities';
  @override
  VerificationContext validateIntegrity(
    Insertable<CharacterIdentityRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
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
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  CharacterIdentityRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return CharacterIdentityRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}created_at'],
      )!,
    );
  }

  @override
  $CharacterIdentitiesTable createAlias(String alias) {
    return $CharacterIdentitiesTable(attachedDatabase, alias);
  }
}

class CharacterIdentityRow extends DataClass
    implements Insertable<CharacterIdentityRow> {
  final int id;
  final String? name;
  final int createdAt;
  const CharacterIdentityRow({
    required this.id,
    this.name,
    required this.createdAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    if (!nullToAbsent || name != null) {
      map['name'] = Variable<String>(name);
    }
    map['created_at'] = Variable<int>(createdAt);
    return map;
  }

  CharacterIdentitiesCompanion toCompanion(bool nullToAbsent) {
    return CharacterIdentitiesCompanion(
      id: Value(id),
      name: name == null && nullToAbsent ? const Value.absent() : Value(name),
      createdAt: Value(createdAt),
    );
  }

  factory CharacterIdentityRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return CharacterIdentityRow(
      id: serializer.fromJson<int>(json['id']),
      name: serializer.fromJson<String?>(json['name']),
      createdAt: serializer.fromJson<int>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'name': serializer.toJson<String?>(name),
      'createdAt': serializer.toJson<int>(createdAt),
    };
  }

  CharacterIdentityRow copyWith({
    int? id,
    Value<String?> name = const Value.absent(),
    int? createdAt,
  }) => CharacterIdentityRow(
    id: id ?? this.id,
    name: name.present ? name.value : this.name,
    createdAt: createdAt ?? this.createdAt,
  );
  CharacterIdentityRow copyWithCompanion(CharacterIdentitiesCompanion data) {
    return CharacterIdentityRow(
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('CharacterIdentityRow(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, name, createdAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CharacterIdentityRow &&
          other.id == this.id &&
          other.name == this.name &&
          other.createdAt == this.createdAt);
}

class CharacterIdentitiesCompanion
    extends UpdateCompanion<CharacterIdentityRow> {
  final Value<int> id;
  final Value<String?> name;
  final Value<int> createdAt;
  const CharacterIdentitiesCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.createdAt = const Value.absent(),
  });
  CharacterIdentitiesCompanion.insert({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    required int createdAt,
  }) : createdAt = Value(createdAt);
  static Insertable<CharacterIdentityRow> custom({
    Expression<int>? id,
    Expression<String>? name,
    Expression<int>? createdAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (createdAt != null) 'created_at': createdAt,
    });
  }

  CharacterIdentitiesCompanion copyWith({
    Value<int>? id,
    Value<String?>? name,
    Value<int>? createdAt,
  }) {
    return CharacterIdentitiesCompanion(
      id: id ?? this.id,
      name: name ?? this.name,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<int>(createdAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CharacterIdentitiesCompanion(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }
}

class $CharacterSamplesTable extends CharacterSamples
    with TableInfo<$CharacterSamplesTable, CharacterSampleRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CharacterSamplesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _identityIdMeta = const VerificationMeta(
    'identityId',
  );
  @override
  late final GeneratedColumn<int> identityId = GeneratedColumn<int>(
    'identity_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES character_identities (id) ON DELETE CASCADE',
    ),
  );
  static const VerificationMeta _mediaIdMeta = const VerificationMeta(
    'mediaId',
  );
  @override
  late final GeneratedColumn<int> mediaId = GeneratedColumn<int>(
    'media_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES media (id) ON DELETE CASCADE',
    ),
  );
  static const VerificationMeta _modelIdMeta = const VerificationMeta(
    'modelId',
  );
  @override
  late final GeneratedColumn<String> modelId = GeneratedColumn<String>(
    'model_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _descriptorMeta = const VerificationMeta(
    'descriptor',
  );
  @override
  late final GeneratedColumn<Uint8List> descriptor = GeneratedColumn<Uint8List>(
    'descriptor',
    aliasedName,
    false,
    type: DriftSqlType.blob,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _bboxXMeta = const VerificationMeta('bboxX');
  @override
  late final GeneratedColumn<double> bboxX = GeneratedColumn<double>(
    'bbox_x',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _bboxYMeta = const VerificationMeta('bboxY');
  @override
  late final GeneratedColumn<double> bboxY = GeneratedColumn<double>(
    'bbox_y',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _bboxWMeta = const VerificationMeta('bboxW');
  @override
  late final GeneratedColumn<double> bboxW = GeneratedColumn<double>(
    'bbox_w',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _bboxHMeta = const VerificationMeta('bboxH');
  @override
  late final GeneratedColumn<double> bboxH = GeneratedColumn<double>(
    'bbox_h',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _scoreMeta = const VerificationMeta('score');
  @override
  late final GeneratedColumn<double> score = GeneratedColumn<double>(
    'score',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _frameNumberMeta = const VerificationMeta(
    'frameNumber',
  );
  @override
  late final GeneratedColumn<int> frameNumber = GeneratedColumn<int>(
    'frame_number',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _timestampMsMeta = const VerificationMeta(
    'timestampMs',
  );
  @override
  late final GeneratedColumn<int> timestampMs = GeneratedColumn<int>(
    'timestamp_ms',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _cropPathMeta = const VerificationMeta(
    'cropPath',
  );
  @override
  late final GeneratedColumn<String> cropPath = GeneratedColumn<String>(
    'crop_path',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<int> createdAt = GeneratedColumn<int>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    identityId,
    mediaId,
    modelId,
    descriptor,
    bboxX,
    bboxY,
    bboxW,
    bboxH,
    score,
    frameNumber,
    timestampMs,
    cropPath,
    createdAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'character_samples';
  @override
  VerificationContext validateIntegrity(
    Insertable<CharacterSampleRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('identity_id')) {
      context.handle(
        _identityIdMeta,
        identityId.isAcceptableOrUnknown(data['identity_id']!, _identityIdMeta),
      );
    } else if (isInserting) {
      context.missing(_identityIdMeta);
    }
    if (data.containsKey('media_id')) {
      context.handle(
        _mediaIdMeta,
        mediaId.isAcceptableOrUnknown(data['media_id']!, _mediaIdMeta),
      );
    } else if (isInserting) {
      context.missing(_mediaIdMeta);
    }
    if (data.containsKey('model_id')) {
      context.handle(
        _modelIdMeta,
        modelId.isAcceptableOrUnknown(data['model_id']!, _modelIdMeta),
      );
    } else if (isInserting) {
      context.missing(_modelIdMeta);
    }
    if (data.containsKey('descriptor')) {
      context.handle(
        _descriptorMeta,
        descriptor.isAcceptableOrUnknown(data['descriptor']!, _descriptorMeta),
      );
    } else if (isInserting) {
      context.missing(_descriptorMeta);
    }
    if (data.containsKey('bbox_x')) {
      context.handle(
        _bboxXMeta,
        bboxX.isAcceptableOrUnknown(data['bbox_x']!, _bboxXMeta),
      );
    } else if (isInserting) {
      context.missing(_bboxXMeta);
    }
    if (data.containsKey('bbox_y')) {
      context.handle(
        _bboxYMeta,
        bboxY.isAcceptableOrUnknown(data['bbox_y']!, _bboxYMeta),
      );
    } else if (isInserting) {
      context.missing(_bboxYMeta);
    }
    if (data.containsKey('bbox_w')) {
      context.handle(
        _bboxWMeta,
        bboxW.isAcceptableOrUnknown(data['bbox_w']!, _bboxWMeta),
      );
    } else if (isInserting) {
      context.missing(_bboxWMeta);
    }
    if (data.containsKey('bbox_h')) {
      context.handle(
        _bboxHMeta,
        bboxH.isAcceptableOrUnknown(data['bbox_h']!, _bboxHMeta),
      );
    } else if (isInserting) {
      context.missing(_bboxHMeta);
    }
    if (data.containsKey('score')) {
      context.handle(
        _scoreMeta,
        score.isAcceptableOrUnknown(data['score']!, _scoreMeta),
      );
    } else if (isInserting) {
      context.missing(_scoreMeta);
    }
    if (data.containsKey('frame_number')) {
      context.handle(
        _frameNumberMeta,
        frameNumber.isAcceptableOrUnknown(
          data['frame_number']!,
          _frameNumberMeta,
        ),
      );
    }
    if (data.containsKey('timestamp_ms')) {
      context.handle(
        _timestampMsMeta,
        timestampMs.isAcceptableOrUnknown(
          data['timestamp_ms']!,
          _timestampMsMeta,
        ),
      );
    }
    if (data.containsKey('crop_path')) {
      context.handle(
        _cropPathMeta,
        cropPath.isAcceptableOrUnknown(data['crop_path']!, _cropPathMeta),
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
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  CharacterSampleRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return CharacterSampleRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      identityId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}identity_id'],
      )!,
      mediaId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}media_id'],
      )!,
      modelId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}model_id'],
      )!,
      descriptor: attachedDatabase.typeMapping.read(
        DriftSqlType.blob,
        data['${effectivePrefix}descriptor'],
      )!,
      bboxX: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}bbox_x'],
      )!,
      bboxY: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}bbox_y'],
      )!,
      bboxW: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}bbox_w'],
      )!,
      bboxH: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}bbox_h'],
      )!,
      score: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}score'],
      )!,
      frameNumber: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}frame_number'],
      ),
      timestampMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}timestamp_ms'],
      ),
      cropPath: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}crop_path'],
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}created_at'],
      )!,
    );
  }

  @override
  $CharacterSamplesTable createAlias(String alias) {
    return $CharacterSamplesTable(attachedDatabase, alias);
  }
}

class CharacterSampleRow extends DataClass
    implements Insertable<CharacterSampleRow> {
  final int id;
  final int identityId;
  final int mediaId;
  final String modelId;
  final Uint8List descriptor;
  final double bboxX;
  final double bboxY;
  final double bboxW;
  final double bboxH;
  final double score;
  final int? frameNumber;
  final int? timestampMs;
  final String? cropPath;
  final int createdAt;
  const CharacterSampleRow({
    required this.id,
    required this.identityId,
    required this.mediaId,
    required this.modelId,
    required this.descriptor,
    required this.bboxX,
    required this.bboxY,
    required this.bboxW,
    required this.bboxH,
    required this.score,
    this.frameNumber,
    this.timestampMs,
    this.cropPath,
    required this.createdAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['identity_id'] = Variable<int>(identityId);
    map['media_id'] = Variable<int>(mediaId);
    map['model_id'] = Variable<String>(modelId);
    map['descriptor'] = Variable<Uint8List>(descriptor);
    map['bbox_x'] = Variable<double>(bboxX);
    map['bbox_y'] = Variable<double>(bboxY);
    map['bbox_w'] = Variable<double>(bboxW);
    map['bbox_h'] = Variable<double>(bboxH);
    map['score'] = Variable<double>(score);
    if (!nullToAbsent || frameNumber != null) {
      map['frame_number'] = Variable<int>(frameNumber);
    }
    if (!nullToAbsent || timestampMs != null) {
      map['timestamp_ms'] = Variable<int>(timestampMs);
    }
    if (!nullToAbsent || cropPath != null) {
      map['crop_path'] = Variable<String>(cropPath);
    }
    map['created_at'] = Variable<int>(createdAt);
    return map;
  }

  CharacterSamplesCompanion toCompanion(bool nullToAbsent) {
    return CharacterSamplesCompanion(
      id: Value(id),
      identityId: Value(identityId),
      mediaId: Value(mediaId),
      modelId: Value(modelId),
      descriptor: Value(descriptor),
      bboxX: Value(bboxX),
      bboxY: Value(bboxY),
      bboxW: Value(bboxW),
      bboxH: Value(bboxH),
      score: Value(score),
      frameNumber: frameNumber == null && nullToAbsent
          ? const Value.absent()
          : Value(frameNumber),
      timestampMs: timestampMs == null && nullToAbsent
          ? const Value.absent()
          : Value(timestampMs),
      cropPath: cropPath == null && nullToAbsent
          ? const Value.absent()
          : Value(cropPath),
      createdAt: Value(createdAt),
    );
  }

  factory CharacterSampleRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return CharacterSampleRow(
      id: serializer.fromJson<int>(json['id']),
      identityId: serializer.fromJson<int>(json['identityId']),
      mediaId: serializer.fromJson<int>(json['mediaId']),
      modelId: serializer.fromJson<String>(json['modelId']),
      descriptor: serializer.fromJson<Uint8List>(json['descriptor']),
      bboxX: serializer.fromJson<double>(json['bboxX']),
      bboxY: serializer.fromJson<double>(json['bboxY']),
      bboxW: serializer.fromJson<double>(json['bboxW']),
      bboxH: serializer.fromJson<double>(json['bboxH']),
      score: serializer.fromJson<double>(json['score']),
      frameNumber: serializer.fromJson<int?>(json['frameNumber']),
      timestampMs: serializer.fromJson<int?>(json['timestampMs']),
      cropPath: serializer.fromJson<String?>(json['cropPath']),
      createdAt: serializer.fromJson<int>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'identityId': serializer.toJson<int>(identityId),
      'mediaId': serializer.toJson<int>(mediaId),
      'modelId': serializer.toJson<String>(modelId),
      'descriptor': serializer.toJson<Uint8List>(descriptor),
      'bboxX': serializer.toJson<double>(bboxX),
      'bboxY': serializer.toJson<double>(bboxY),
      'bboxW': serializer.toJson<double>(bboxW),
      'bboxH': serializer.toJson<double>(bboxH),
      'score': serializer.toJson<double>(score),
      'frameNumber': serializer.toJson<int?>(frameNumber),
      'timestampMs': serializer.toJson<int?>(timestampMs),
      'cropPath': serializer.toJson<String?>(cropPath),
      'createdAt': serializer.toJson<int>(createdAt),
    };
  }

  CharacterSampleRow copyWith({
    int? id,
    int? identityId,
    int? mediaId,
    String? modelId,
    Uint8List? descriptor,
    double? bboxX,
    double? bboxY,
    double? bboxW,
    double? bboxH,
    double? score,
    Value<int?> frameNumber = const Value.absent(),
    Value<int?> timestampMs = const Value.absent(),
    Value<String?> cropPath = const Value.absent(),
    int? createdAt,
  }) => CharacterSampleRow(
    id: id ?? this.id,
    identityId: identityId ?? this.identityId,
    mediaId: mediaId ?? this.mediaId,
    modelId: modelId ?? this.modelId,
    descriptor: descriptor ?? this.descriptor,
    bboxX: bboxX ?? this.bboxX,
    bboxY: bboxY ?? this.bboxY,
    bboxW: bboxW ?? this.bboxW,
    bboxH: bboxH ?? this.bboxH,
    score: score ?? this.score,
    frameNumber: frameNumber.present ? frameNumber.value : this.frameNumber,
    timestampMs: timestampMs.present ? timestampMs.value : this.timestampMs,
    cropPath: cropPath.present ? cropPath.value : this.cropPath,
    createdAt: createdAt ?? this.createdAt,
  );
  CharacterSampleRow copyWithCompanion(CharacterSamplesCompanion data) {
    return CharacterSampleRow(
      id: data.id.present ? data.id.value : this.id,
      identityId: data.identityId.present
          ? data.identityId.value
          : this.identityId,
      mediaId: data.mediaId.present ? data.mediaId.value : this.mediaId,
      modelId: data.modelId.present ? data.modelId.value : this.modelId,
      descriptor: data.descriptor.present
          ? data.descriptor.value
          : this.descriptor,
      bboxX: data.bboxX.present ? data.bboxX.value : this.bboxX,
      bboxY: data.bboxY.present ? data.bboxY.value : this.bboxY,
      bboxW: data.bboxW.present ? data.bboxW.value : this.bboxW,
      bboxH: data.bboxH.present ? data.bboxH.value : this.bboxH,
      score: data.score.present ? data.score.value : this.score,
      frameNumber: data.frameNumber.present
          ? data.frameNumber.value
          : this.frameNumber,
      timestampMs: data.timestampMs.present
          ? data.timestampMs.value
          : this.timestampMs,
      cropPath: data.cropPath.present ? data.cropPath.value : this.cropPath,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('CharacterSampleRow(')
          ..write('id: $id, ')
          ..write('identityId: $identityId, ')
          ..write('mediaId: $mediaId, ')
          ..write('modelId: $modelId, ')
          ..write('descriptor: $descriptor, ')
          ..write('bboxX: $bboxX, ')
          ..write('bboxY: $bboxY, ')
          ..write('bboxW: $bboxW, ')
          ..write('bboxH: $bboxH, ')
          ..write('score: $score, ')
          ..write('frameNumber: $frameNumber, ')
          ..write('timestampMs: $timestampMs, ')
          ..write('cropPath: $cropPath, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    identityId,
    mediaId,
    modelId,
    $driftBlobEquality.hash(descriptor),
    bboxX,
    bboxY,
    bboxW,
    bboxH,
    score,
    frameNumber,
    timestampMs,
    cropPath,
    createdAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CharacterSampleRow &&
          other.id == this.id &&
          other.identityId == this.identityId &&
          other.mediaId == this.mediaId &&
          other.modelId == this.modelId &&
          $driftBlobEquality.equals(other.descriptor, this.descriptor) &&
          other.bboxX == this.bboxX &&
          other.bboxY == this.bboxY &&
          other.bboxW == this.bboxW &&
          other.bboxH == this.bboxH &&
          other.score == this.score &&
          other.frameNumber == this.frameNumber &&
          other.timestampMs == this.timestampMs &&
          other.cropPath == this.cropPath &&
          other.createdAt == this.createdAt);
}

class CharacterSamplesCompanion extends UpdateCompanion<CharacterSampleRow> {
  final Value<int> id;
  final Value<int> identityId;
  final Value<int> mediaId;
  final Value<String> modelId;
  final Value<Uint8List> descriptor;
  final Value<double> bboxX;
  final Value<double> bboxY;
  final Value<double> bboxW;
  final Value<double> bboxH;
  final Value<double> score;
  final Value<int?> frameNumber;
  final Value<int?> timestampMs;
  final Value<String?> cropPath;
  final Value<int> createdAt;
  const CharacterSamplesCompanion({
    this.id = const Value.absent(),
    this.identityId = const Value.absent(),
    this.mediaId = const Value.absent(),
    this.modelId = const Value.absent(),
    this.descriptor = const Value.absent(),
    this.bboxX = const Value.absent(),
    this.bboxY = const Value.absent(),
    this.bboxW = const Value.absent(),
    this.bboxH = const Value.absent(),
    this.score = const Value.absent(),
    this.frameNumber = const Value.absent(),
    this.timestampMs = const Value.absent(),
    this.cropPath = const Value.absent(),
    this.createdAt = const Value.absent(),
  });
  CharacterSamplesCompanion.insert({
    this.id = const Value.absent(),
    required int identityId,
    required int mediaId,
    required String modelId,
    required Uint8List descriptor,
    required double bboxX,
    required double bboxY,
    required double bboxW,
    required double bboxH,
    required double score,
    this.frameNumber = const Value.absent(),
    this.timestampMs = const Value.absent(),
    this.cropPath = const Value.absent(),
    required int createdAt,
  }) : identityId = Value(identityId),
       mediaId = Value(mediaId),
       modelId = Value(modelId),
       descriptor = Value(descriptor),
       bboxX = Value(bboxX),
       bboxY = Value(bboxY),
       bboxW = Value(bboxW),
       bboxH = Value(bboxH),
       score = Value(score),
       createdAt = Value(createdAt);
  static Insertable<CharacterSampleRow> custom({
    Expression<int>? id,
    Expression<int>? identityId,
    Expression<int>? mediaId,
    Expression<String>? modelId,
    Expression<Uint8List>? descriptor,
    Expression<double>? bboxX,
    Expression<double>? bboxY,
    Expression<double>? bboxW,
    Expression<double>? bboxH,
    Expression<double>? score,
    Expression<int>? frameNumber,
    Expression<int>? timestampMs,
    Expression<String>? cropPath,
    Expression<int>? createdAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (identityId != null) 'identity_id': identityId,
      if (mediaId != null) 'media_id': mediaId,
      if (modelId != null) 'model_id': modelId,
      if (descriptor != null) 'descriptor': descriptor,
      if (bboxX != null) 'bbox_x': bboxX,
      if (bboxY != null) 'bbox_y': bboxY,
      if (bboxW != null) 'bbox_w': bboxW,
      if (bboxH != null) 'bbox_h': bboxH,
      if (score != null) 'score': score,
      if (frameNumber != null) 'frame_number': frameNumber,
      if (timestampMs != null) 'timestamp_ms': timestampMs,
      if (cropPath != null) 'crop_path': cropPath,
      if (createdAt != null) 'created_at': createdAt,
    });
  }

  CharacterSamplesCompanion copyWith({
    Value<int>? id,
    Value<int>? identityId,
    Value<int>? mediaId,
    Value<String>? modelId,
    Value<Uint8List>? descriptor,
    Value<double>? bboxX,
    Value<double>? bboxY,
    Value<double>? bboxW,
    Value<double>? bboxH,
    Value<double>? score,
    Value<int?>? frameNumber,
    Value<int?>? timestampMs,
    Value<String?>? cropPath,
    Value<int>? createdAt,
  }) {
    return CharacterSamplesCompanion(
      id: id ?? this.id,
      identityId: identityId ?? this.identityId,
      mediaId: mediaId ?? this.mediaId,
      modelId: modelId ?? this.modelId,
      descriptor: descriptor ?? this.descriptor,
      bboxX: bboxX ?? this.bboxX,
      bboxY: bboxY ?? this.bboxY,
      bboxW: bboxW ?? this.bboxW,
      bboxH: bboxH ?? this.bboxH,
      score: score ?? this.score,
      frameNumber: frameNumber ?? this.frameNumber,
      timestampMs: timestampMs ?? this.timestampMs,
      cropPath: cropPath ?? this.cropPath,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (identityId.present) {
      map['identity_id'] = Variable<int>(identityId.value);
    }
    if (mediaId.present) {
      map['media_id'] = Variable<int>(mediaId.value);
    }
    if (modelId.present) {
      map['model_id'] = Variable<String>(modelId.value);
    }
    if (descriptor.present) {
      map['descriptor'] = Variable<Uint8List>(descriptor.value);
    }
    if (bboxX.present) {
      map['bbox_x'] = Variable<double>(bboxX.value);
    }
    if (bboxY.present) {
      map['bbox_y'] = Variable<double>(bboxY.value);
    }
    if (bboxW.present) {
      map['bbox_w'] = Variable<double>(bboxW.value);
    }
    if (bboxH.present) {
      map['bbox_h'] = Variable<double>(bboxH.value);
    }
    if (score.present) {
      map['score'] = Variable<double>(score.value);
    }
    if (frameNumber.present) {
      map['frame_number'] = Variable<int>(frameNumber.value);
    }
    if (timestampMs.present) {
      map['timestamp_ms'] = Variable<int>(timestampMs.value);
    }
    if (cropPath.present) {
      map['crop_path'] = Variable<String>(cropPath.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<int>(createdAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CharacterSamplesCompanion(')
          ..write('id: $id, ')
          ..write('identityId: $identityId, ')
          ..write('mediaId: $mediaId, ')
          ..write('modelId: $modelId, ')
          ..write('descriptor: $descriptor, ')
          ..write('bboxX: $bboxX, ')
          ..write('bboxY: $bboxY, ')
          ..write('bboxW: $bboxW, ')
          ..write('bboxH: $bboxH, ')
          ..write('score: $score, ')
          ..write('frameNumber: $frameNumber, ')
          ..write('timestampMs: $timestampMs, ')
          ..write('cropPath: $cropPath, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }
}

abstract class _$AppDatabase extends GeneratedDatabase {
  _$AppDatabase(QueryExecutor e) : super(e);
  $AppDatabaseManager get managers => $AppDatabaseManager(this);
  late final $PersonsTable persons = $PersonsTable(this);
  late final $MediaTable media = $MediaTable(this);
  late final $FacesTable faces = $FacesTable(this);
  late final $FaceSuppressionsTable faceSuppressions = $FaceSuppressionsTable(
    this,
  );
  late final $BodiesTable bodies = $BodiesTable(this);
  late final $FaceRejectionsTable faceRejections = $FaceRejectionsTable(this);
  late final $BodyRejectionsTable bodyRejections = $BodyRejectionsTable(this);
  late final $PersonDistinctTable personDistinct = $PersonDistinctTable(this);
  late final $ServersTable servers = $ServersTable(this);
  late final $SettingsTable settings = $SettingsTable(this);
  late final $UploadQueueTable uploadQueue = $UploadQueueTable(this);
  late final $BlobHintsTable blobHints = $BlobHintsTable(this);
  late final $MediaDetectionsTable mediaDetections = $MediaDetectionsTable(
    this,
  );
  late final $ReviewMatchesTable reviewMatches = $ReviewMatchesTable(this);
  late final $ReviewGroupsTable reviewGroups = $ReviewGroupsTable(this);
  late final $ReviewDuplicatesTable reviewDuplicates = $ReviewDuplicatesTable(
    this,
  );
  late final $ReviewBodyLinksTable reviewBodyLinks = $ReviewBodyLinksTable(
    this,
  );
  late final $ReviewSnoozesTable reviewSnoozes = $ReviewSnoozesTable(this);
  late final $JobsTable jobs = $JobsTable(this);
  late final $ResultsTable results = $ResultsTable(this);
  late final $DatasetsTable datasets = $DatasetsTable(this);
  late final $DatasetItemsTable datasetItems = $DatasetItemsTable(this);
  late final $LorasTable loras = $LorasTable(this);
  late final $IdentitySetsTable identitySets = $IdentitySetsTable(this);
  late final $IdentitySetFacesTable identitySetFaces = $IdentitySetFacesTable(
    this,
  );
  late final $JobEventsTable jobEvents = $JobEventsTable(this);
  late final $CharacterIdentitiesTable characterIdentities =
      $CharacterIdentitiesTable(this);
  late final $CharacterSamplesTable characterSamples = $CharacterSamplesTable(
    this,
  );
  late final Index mediaScanStatus = Index(
    'media_scan_status',
    'CREATE INDEX media_scan_status ON media (scan_status)',
  );
  late final Index facesPersonId = Index(
    'faces_person_id',
    'CREATE INDEX faces_person_id ON faces (person_id)',
  );
  late final Index facesMediaId = Index(
    'faces_media_id',
    'CREATE INDEX faces_media_id ON faces (media_id)',
  );
  late final Index faceSuppressionsAsset = Index(
    'face_suppressions_asset',
    'CREATE INDEX face_suppressions_asset ON face_suppressions (asset_id)',
  );
  late final Index bodiesMediaId = Index(
    'bodies_media_id',
    'CREATE INDEX bodies_media_id ON bodies (media_id)',
  );
  late final Index bodiesPersonId = Index(
    'bodies_person_id',
    'CREATE INDEX bodies_person_id ON bodies (person_id)',
  );
  late final Index bodiesFaceId = Index(
    'bodies_face_id',
    'CREATE INDEX bodies_face_id ON bodies (face_id)',
  );
  late final Index faceRejectionsPersonId = Index(
    'face_rejections_person_id',
    'CREATE INDEX face_rejections_person_id ON face_rejections (person_id)',
  );
  late final Index mediaDetectionsMediaId = Index(
    'media_detections_media_id',
    'CREATE INDEX media_detections_media_id ON media_detections (media_id)',
  );
  late final Index mediaDetectionsRef = Index(
    'media_detections_ref',
    'CREATE INDEX media_detections_ref ON media_detections (kind, ref_id)',
  );
  late final Index jobsStatus = Index(
    'jobs_status',
    'CREATE INDEX jobs_status ON jobs (status)',
  );
  late final Index resultsCreatedAt = Index(
    'results_created_at',
    'CREATE INDEX results_created_at ON results (created_at)',
  );
  late final Index characterSamplesIdentity = Index(
    'character_samples_identity',
    'CREATE INDEX character_samples_identity ON character_samples (identity_id)',
  );
  late final Index characterSamplesMedia = Index(
    'character_samples_media',
    'CREATE INDEX character_samples_media ON character_samples (media_id)',
  );
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    persons,
    media,
    faces,
    faceSuppressions,
    bodies,
    faceRejections,
    bodyRejections,
    personDistinct,
    servers,
    settings,
    uploadQueue,
    blobHints,
    mediaDetections,
    reviewMatches,
    reviewGroups,
    reviewDuplicates,
    reviewBodyLinks,
    reviewSnoozes,
    jobs,
    results,
    datasets,
    datasetItems,
    loras,
    identitySets,
    identitySetFaces,
    jobEvents,
    characterIdentities,
    characterSamples,
    mediaScanStatus,
    facesPersonId,
    facesMediaId,
    faceSuppressionsAsset,
    bodiesMediaId,
    bodiesPersonId,
    bodiesFaceId,
    faceRejectionsPersonId,
    mediaDetectionsMediaId,
    mediaDetectionsRef,
    jobsStatus,
    resultsCreatedAt,
    characterSamplesIdentity,
    characterSamplesMedia,
  ];
  @override
  StreamQueryUpdateRules get streamUpdateRules => const StreamQueryUpdateRules([
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'media',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('faces', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'persons',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('faces', kind: UpdateKind.update)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'media',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('bodies', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'faces',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('bodies', kind: UpdateKind.update)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'persons',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('bodies', kind: UpdateKind.update)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'faces',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('face_rejections', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'persons',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('face_rejections', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'bodies',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('body_rejections', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'persons',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('body_rejections', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'persons',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('person_distinct', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'persons',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('person_distinct', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'media',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('media_detections', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'faces',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('review_matches', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'persons',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('review_matches', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'persons',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('review_duplicates', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'persons',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('review_duplicates', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'bodies',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('review_body_links', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'persons',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('review_body_links', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'persons',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('jobs', kind: UpdateKind.update)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'persons',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('results', kind: UpdateKind.update)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'persons',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('datasets', kind: UpdateKind.update)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'datasets',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('dataset_items', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'persons',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('loras', kind: UpdateKind.update)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'persons',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('identity_sets', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'identity_sets',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('identity_set_faces', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'faces',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('identity_set_faces', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'jobs',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('job_events', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'character_identities',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('character_samples', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'media',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('character_samples', kind: UpdateKind.delete)],
    ),
  ]);
}

typedef $$PersonsTableCreateCompanionBuilder =
    PersonsCompanion Function({
      Value<int> id,
      Value<String?> name,
      Value<int?> avatarFaceId,
      required int createdAt,
      Value<bool> hidden,
      Value<bool> favorite,
      Value<bool> pinned,
      Value<bool> groupingLocked,
    });
typedef $$PersonsTableUpdateCompanionBuilder =
    PersonsCompanion Function({
      Value<int> id,
      Value<String?> name,
      Value<int?> avatarFaceId,
      Value<int> createdAt,
      Value<bool> hidden,
      Value<bool> favorite,
      Value<bool> pinned,
      Value<bool> groupingLocked,
    });

final class $$PersonsTableReferences
    extends BaseReferences<_$AppDatabase, $PersonsTable, PersonRow> {
  $$PersonsTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static MultiTypedResultKey<$FacesTable, List<FaceRow>> _facesRefsTable(
    _$AppDatabase db,
  ) => MultiTypedResultKey.fromTable(
    db.faces,
    aliasName: 'persons__id__faces__person_id',
  );

  $$FacesTableProcessedTableManager get facesRefs {
    final manager = $$FacesTableTableManager(
      $_db,
      $_db.faces,
    ).filter((f) => f.personId.id.sqlEquals($_itemColumn<int>('id')!));

    final cache = $_typedResult.readTableOrNull(_facesRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$BodiesTable, List<BodyRow>> _bodiesRefsTable(
    _$AppDatabase db,
  ) => MultiTypedResultKey.fromTable(
    db.bodies,
    aliasName: 'persons__id__bodies__person_id',
  );

  $$BodiesTableProcessedTableManager get bodiesRefs {
    final manager = $$BodiesTableTableManager(
      $_db,
      $_db.bodies,
    ).filter((f) => f.personId.id.sqlEquals($_itemColumn<int>('id')!));

    final cache = $_typedResult.readTableOrNull(_bodiesRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$FaceRejectionsTable, List<FaceRejectionRow>>
  _faceRejectionsRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.faceRejections,
    aliasName: 'persons__id__face_rejections__person_id',
  );

  $$FaceRejectionsTableProcessedTableManager get faceRejectionsRefs {
    final manager = $$FaceRejectionsTableTableManager(
      $_db,
      $_db.faceRejections,
    ).filter((f) => f.personId.id.sqlEquals($_itemColumn<int>('id')!));

    final cache = $_typedResult.readTableOrNull(_faceRejectionsRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$BodyRejectionsTable, List<BodyRejectionRow>>
  _bodyRejectionsRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.bodyRejections,
    aliasName: 'persons__id__body_rejections__person_id',
  );

  $$BodyRejectionsTableProcessedTableManager get bodyRejectionsRefs {
    final manager = $$BodyRejectionsTableTableManager(
      $_db,
      $_db.bodyRejections,
    ).filter((f) => f.personId.id.sqlEquals($_itemColumn<int>('id')!));

    final cache = $_typedResult.readTableOrNull(_bodyRejectionsRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$PersonDistinctTable, List<PersonDistinctRow>>
  _distinctAsATable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.personDistinct,
    aliasName: 'persons__id__person_distinct__person_a',
  );

  $$PersonDistinctTableProcessedTableManager get distinctAsA {
    final manager = $$PersonDistinctTableTableManager(
      $_db,
      $_db.personDistinct,
    ).filter((f) => f.personA.id.sqlEquals($_itemColumn<int>('id')!));

    final cache = $_typedResult.readTableOrNull(_distinctAsATable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$PersonDistinctTable, List<PersonDistinctRow>>
  _distinctAsBTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.personDistinct,
    aliasName: 'persons__id__person_distinct__person_b',
  );

  $$PersonDistinctTableProcessedTableManager get distinctAsB {
    final manager = $$PersonDistinctTableTableManager(
      $_db,
      $_db.personDistinct,
    ).filter((f) => f.personB.id.sqlEquals($_itemColumn<int>('id')!));

    final cache = $_typedResult.readTableOrNull(_distinctAsBTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$ReviewMatchesTable, List<ReviewMatchRow>>
  _reviewMatchesRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.reviewMatches,
    aliasName: 'persons__id__review_matches__person_id',
  );

  $$ReviewMatchesTableProcessedTableManager get reviewMatchesRefs {
    final manager = $$ReviewMatchesTableTableManager(
      $_db,
      $_db.reviewMatches,
    ).filter((f) => f.personId.id.sqlEquals($_itemColumn<int>('id')!));

    final cache = $_typedResult.readTableOrNull(_reviewMatchesRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$ReviewDuplicatesTable, List<ReviewDuplicateRow>>
  _reviewDuplicateAsATable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.reviewDuplicates,
    aliasName: 'persons__id__review_duplicates__person_a',
  );

  $$ReviewDuplicatesTableProcessedTableManager get reviewDuplicateAsA {
    final manager = $$ReviewDuplicatesTableTableManager(
      $_db,
      $_db.reviewDuplicates,
    ).filter((f) => f.personA.id.sqlEquals($_itemColumn<int>('id')!));

    final cache = $_typedResult.readTableOrNull(_reviewDuplicateAsATable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$ReviewDuplicatesTable, List<ReviewDuplicateRow>>
  _reviewDuplicateAsBTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.reviewDuplicates,
    aliasName: 'persons__id__review_duplicates__person_b',
  );

  $$ReviewDuplicatesTableProcessedTableManager get reviewDuplicateAsB {
    final manager = $$ReviewDuplicatesTableTableManager(
      $_db,
      $_db.reviewDuplicates,
    ).filter((f) => f.personB.id.sqlEquals($_itemColumn<int>('id')!));

    final cache = $_typedResult.readTableOrNull(_reviewDuplicateAsBTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$ReviewBodyLinksTable, List<ReviewBodyLinkRow>>
  _reviewBodyLinksRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.reviewBodyLinks,
    aliasName: 'persons__id__review_body_links__person_id',
  );

  $$ReviewBodyLinksTableProcessedTableManager get reviewBodyLinksRefs {
    final manager = $$ReviewBodyLinksTableTableManager(
      $_db,
      $_db.reviewBodyLinks,
    ).filter((f) => f.personId.id.sqlEquals($_itemColumn<int>('id')!));

    final cache = $_typedResult.readTableOrNull(
      _reviewBodyLinksRefsTable($_db),
    );
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$JobsTable, List<JobRow>> _jobsRefsTable(
    _$AppDatabase db,
  ) => MultiTypedResultKey.fromTable(
    db.jobs,
    aliasName: 'persons__id__jobs__person_id',
  );

  $$JobsTableProcessedTableManager get jobsRefs {
    final manager = $$JobsTableTableManager(
      $_db,
      $_db.jobs,
    ).filter((f) => f.personId.id.sqlEquals($_itemColumn<int>('id')!));

    final cache = $_typedResult.readTableOrNull(_jobsRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$ResultsTable, List<ResultRow>> _resultsRefsTable(
    _$AppDatabase db,
  ) => MultiTypedResultKey.fromTable(
    db.results,
    aliasName: 'persons__id__results__person_id',
  );

  $$ResultsTableProcessedTableManager get resultsRefs {
    final manager = $$ResultsTableTableManager(
      $_db,
      $_db.results,
    ).filter((f) => f.personId.id.sqlEquals($_itemColumn<int>('id')!));

    final cache = $_typedResult.readTableOrNull(_resultsRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$DatasetsTable, List<DatasetRow>>
  _datasetsRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.datasets,
    aliasName: 'persons__id__datasets__person_id',
  );

  $$DatasetsTableProcessedTableManager get datasetsRefs {
    final manager = $$DatasetsTableTableManager(
      $_db,
      $_db.datasets,
    ).filter((f) => f.personId.id.sqlEquals($_itemColumn<int>('id')!));

    final cache = $_typedResult.readTableOrNull(_datasetsRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$LorasTable, List<LoraRow>> _lorasRefsTable(
    _$AppDatabase db,
  ) => MultiTypedResultKey.fromTable(
    db.loras,
    aliasName: 'persons__id__loras__person_id',
  );

  $$LorasTableProcessedTableManager get lorasRefs {
    final manager = $$LorasTableTableManager(
      $_db,
      $_db.loras,
    ).filter((f) => f.personId.id.sqlEquals($_itemColumn<int>('id')!));

    final cache = $_typedResult.readTableOrNull(_lorasRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$IdentitySetsTable, List<IdentitySetRow>>
  _identitySetsRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.identitySets,
    aliasName: 'persons__id__identity_sets__person_id',
  );

  $$IdentitySetsTableProcessedTableManager get identitySetsRefs {
    final manager = $$IdentitySetsTableTableManager(
      $_db,
      $_db.identitySets,
    ).filter((f) => f.personId.id.sqlEquals($_itemColumn<int>('id')!));

    final cache = $_typedResult.readTableOrNull(_identitySetsRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$PersonsTableFilterComposer
    extends Composer<_$AppDatabase, $PersonsTable> {
  $$PersonsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get avatarFaceId => $composableBuilder(
    column: $table.avatarFaceId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get hidden => $composableBuilder(
    column: $table.hidden,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get favorite => $composableBuilder(
    column: $table.favorite,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get pinned => $composableBuilder(
    column: $table.pinned,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get groupingLocked => $composableBuilder(
    column: $table.groupingLocked,
    builder: (column) => ColumnFilters(column),
  );

  Expression<bool> facesRefs(
    Expression<bool> Function($$FacesTableFilterComposer f) f,
  ) {
    final $$FacesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.faces,
      getReferencedColumn: (t) => t.personId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$FacesTableFilterComposer(
            $db: $db,
            $table: $db.faces,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> bodiesRefs(
    Expression<bool> Function($$BodiesTableFilterComposer f) f,
  ) {
    final $$BodiesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.bodies,
      getReferencedColumn: (t) => t.personId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$BodiesTableFilterComposer(
            $db: $db,
            $table: $db.bodies,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> faceRejectionsRefs(
    Expression<bool> Function($$FaceRejectionsTableFilterComposer f) f,
  ) {
    final $$FaceRejectionsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.faceRejections,
      getReferencedColumn: (t) => t.personId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$FaceRejectionsTableFilterComposer(
            $db: $db,
            $table: $db.faceRejections,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> bodyRejectionsRefs(
    Expression<bool> Function($$BodyRejectionsTableFilterComposer f) f,
  ) {
    final $$BodyRejectionsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.bodyRejections,
      getReferencedColumn: (t) => t.personId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$BodyRejectionsTableFilterComposer(
            $db: $db,
            $table: $db.bodyRejections,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> distinctAsA(
    Expression<bool> Function($$PersonDistinctTableFilterComposer f) f,
  ) {
    final $$PersonDistinctTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.personDistinct,
      getReferencedColumn: (t) => t.personA,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$PersonDistinctTableFilterComposer(
            $db: $db,
            $table: $db.personDistinct,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> distinctAsB(
    Expression<bool> Function($$PersonDistinctTableFilterComposer f) f,
  ) {
    final $$PersonDistinctTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.personDistinct,
      getReferencedColumn: (t) => t.personB,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$PersonDistinctTableFilterComposer(
            $db: $db,
            $table: $db.personDistinct,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> reviewMatchesRefs(
    Expression<bool> Function($$ReviewMatchesTableFilterComposer f) f,
  ) {
    final $$ReviewMatchesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.reviewMatches,
      getReferencedColumn: (t) => t.personId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ReviewMatchesTableFilterComposer(
            $db: $db,
            $table: $db.reviewMatches,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> reviewDuplicateAsA(
    Expression<bool> Function($$ReviewDuplicatesTableFilterComposer f) f,
  ) {
    final $$ReviewDuplicatesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.reviewDuplicates,
      getReferencedColumn: (t) => t.personA,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ReviewDuplicatesTableFilterComposer(
            $db: $db,
            $table: $db.reviewDuplicates,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> reviewDuplicateAsB(
    Expression<bool> Function($$ReviewDuplicatesTableFilterComposer f) f,
  ) {
    final $$ReviewDuplicatesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.reviewDuplicates,
      getReferencedColumn: (t) => t.personB,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ReviewDuplicatesTableFilterComposer(
            $db: $db,
            $table: $db.reviewDuplicates,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> reviewBodyLinksRefs(
    Expression<bool> Function($$ReviewBodyLinksTableFilterComposer f) f,
  ) {
    final $$ReviewBodyLinksTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.reviewBodyLinks,
      getReferencedColumn: (t) => t.personId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ReviewBodyLinksTableFilterComposer(
            $db: $db,
            $table: $db.reviewBodyLinks,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> jobsRefs(
    Expression<bool> Function($$JobsTableFilterComposer f) f,
  ) {
    final $$JobsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.jobs,
      getReferencedColumn: (t) => t.personId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$JobsTableFilterComposer(
            $db: $db,
            $table: $db.jobs,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> resultsRefs(
    Expression<bool> Function($$ResultsTableFilterComposer f) f,
  ) {
    final $$ResultsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.results,
      getReferencedColumn: (t) => t.personId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ResultsTableFilterComposer(
            $db: $db,
            $table: $db.results,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> datasetsRefs(
    Expression<bool> Function($$DatasetsTableFilterComposer f) f,
  ) {
    final $$DatasetsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.datasets,
      getReferencedColumn: (t) => t.personId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$DatasetsTableFilterComposer(
            $db: $db,
            $table: $db.datasets,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> lorasRefs(
    Expression<bool> Function($$LorasTableFilterComposer f) f,
  ) {
    final $$LorasTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.loras,
      getReferencedColumn: (t) => t.personId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$LorasTableFilterComposer(
            $db: $db,
            $table: $db.loras,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> identitySetsRefs(
    Expression<bool> Function($$IdentitySetsTableFilterComposer f) f,
  ) {
    final $$IdentitySetsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.identitySets,
      getReferencedColumn: (t) => t.personId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$IdentitySetsTableFilterComposer(
            $db: $db,
            $table: $db.identitySets,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$PersonsTableOrderingComposer
    extends Composer<_$AppDatabase, $PersonsTable> {
  $$PersonsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get avatarFaceId => $composableBuilder(
    column: $table.avatarFaceId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get hidden => $composableBuilder(
    column: $table.hidden,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get favorite => $composableBuilder(
    column: $table.favorite,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get pinned => $composableBuilder(
    column: $table.pinned,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get groupingLocked => $composableBuilder(
    column: $table.groupingLocked,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$PersonsTableAnnotationComposer
    extends Composer<_$AppDatabase, $PersonsTable> {
  $$PersonsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<int> get avatarFaceId => $composableBuilder(
    column: $table.avatarFaceId,
    builder: (column) => column,
  );

  GeneratedColumn<int> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<bool> get hidden =>
      $composableBuilder(column: $table.hidden, builder: (column) => column);

  GeneratedColumn<bool> get favorite =>
      $composableBuilder(column: $table.favorite, builder: (column) => column);

  GeneratedColumn<bool> get pinned =>
      $composableBuilder(column: $table.pinned, builder: (column) => column);

  GeneratedColumn<bool> get groupingLocked => $composableBuilder(
    column: $table.groupingLocked,
    builder: (column) => column,
  );

  Expression<T> facesRefs<T extends Object>(
    Expression<T> Function($$FacesTableAnnotationComposer a) f,
  ) {
    final $$FacesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.faces,
      getReferencedColumn: (t) => t.personId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$FacesTableAnnotationComposer(
            $db: $db,
            $table: $db.faces,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> bodiesRefs<T extends Object>(
    Expression<T> Function($$BodiesTableAnnotationComposer a) f,
  ) {
    final $$BodiesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.bodies,
      getReferencedColumn: (t) => t.personId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$BodiesTableAnnotationComposer(
            $db: $db,
            $table: $db.bodies,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> faceRejectionsRefs<T extends Object>(
    Expression<T> Function($$FaceRejectionsTableAnnotationComposer a) f,
  ) {
    final $$FaceRejectionsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.faceRejections,
      getReferencedColumn: (t) => t.personId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$FaceRejectionsTableAnnotationComposer(
            $db: $db,
            $table: $db.faceRejections,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> bodyRejectionsRefs<T extends Object>(
    Expression<T> Function($$BodyRejectionsTableAnnotationComposer a) f,
  ) {
    final $$BodyRejectionsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.bodyRejections,
      getReferencedColumn: (t) => t.personId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$BodyRejectionsTableAnnotationComposer(
            $db: $db,
            $table: $db.bodyRejections,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> distinctAsA<T extends Object>(
    Expression<T> Function($$PersonDistinctTableAnnotationComposer a) f,
  ) {
    final $$PersonDistinctTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.personDistinct,
      getReferencedColumn: (t) => t.personA,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$PersonDistinctTableAnnotationComposer(
            $db: $db,
            $table: $db.personDistinct,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> distinctAsB<T extends Object>(
    Expression<T> Function($$PersonDistinctTableAnnotationComposer a) f,
  ) {
    final $$PersonDistinctTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.personDistinct,
      getReferencedColumn: (t) => t.personB,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$PersonDistinctTableAnnotationComposer(
            $db: $db,
            $table: $db.personDistinct,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> reviewMatchesRefs<T extends Object>(
    Expression<T> Function($$ReviewMatchesTableAnnotationComposer a) f,
  ) {
    final $$ReviewMatchesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.reviewMatches,
      getReferencedColumn: (t) => t.personId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ReviewMatchesTableAnnotationComposer(
            $db: $db,
            $table: $db.reviewMatches,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> reviewDuplicateAsA<T extends Object>(
    Expression<T> Function($$ReviewDuplicatesTableAnnotationComposer a) f,
  ) {
    final $$ReviewDuplicatesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.reviewDuplicates,
      getReferencedColumn: (t) => t.personA,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ReviewDuplicatesTableAnnotationComposer(
            $db: $db,
            $table: $db.reviewDuplicates,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> reviewDuplicateAsB<T extends Object>(
    Expression<T> Function($$ReviewDuplicatesTableAnnotationComposer a) f,
  ) {
    final $$ReviewDuplicatesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.reviewDuplicates,
      getReferencedColumn: (t) => t.personB,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ReviewDuplicatesTableAnnotationComposer(
            $db: $db,
            $table: $db.reviewDuplicates,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> reviewBodyLinksRefs<T extends Object>(
    Expression<T> Function($$ReviewBodyLinksTableAnnotationComposer a) f,
  ) {
    final $$ReviewBodyLinksTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.reviewBodyLinks,
      getReferencedColumn: (t) => t.personId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ReviewBodyLinksTableAnnotationComposer(
            $db: $db,
            $table: $db.reviewBodyLinks,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> jobsRefs<T extends Object>(
    Expression<T> Function($$JobsTableAnnotationComposer a) f,
  ) {
    final $$JobsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.jobs,
      getReferencedColumn: (t) => t.personId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$JobsTableAnnotationComposer(
            $db: $db,
            $table: $db.jobs,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> resultsRefs<T extends Object>(
    Expression<T> Function($$ResultsTableAnnotationComposer a) f,
  ) {
    final $$ResultsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.results,
      getReferencedColumn: (t) => t.personId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ResultsTableAnnotationComposer(
            $db: $db,
            $table: $db.results,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> datasetsRefs<T extends Object>(
    Expression<T> Function($$DatasetsTableAnnotationComposer a) f,
  ) {
    final $$DatasetsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.datasets,
      getReferencedColumn: (t) => t.personId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$DatasetsTableAnnotationComposer(
            $db: $db,
            $table: $db.datasets,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> lorasRefs<T extends Object>(
    Expression<T> Function($$LorasTableAnnotationComposer a) f,
  ) {
    final $$LorasTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.loras,
      getReferencedColumn: (t) => t.personId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$LorasTableAnnotationComposer(
            $db: $db,
            $table: $db.loras,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> identitySetsRefs<T extends Object>(
    Expression<T> Function($$IdentitySetsTableAnnotationComposer a) f,
  ) {
    final $$IdentitySetsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.identitySets,
      getReferencedColumn: (t) => t.personId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$IdentitySetsTableAnnotationComposer(
            $db: $db,
            $table: $db.identitySets,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$PersonsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $PersonsTable,
          PersonRow,
          $$PersonsTableFilterComposer,
          $$PersonsTableOrderingComposer,
          $$PersonsTableAnnotationComposer,
          $$PersonsTableCreateCompanionBuilder,
          $$PersonsTableUpdateCompanionBuilder,
          (PersonRow, $$PersonsTableReferences),
          PersonRow,
          PrefetchHooks Function({
            bool facesRefs,
            bool bodiesRefs,
            bool faceRejectionsRefs,
            bool bodyRejectionsRefs,
            bool distinctAsA,
            bool distinctAsB,
            bool reviewMatchesRefs,
            bool reviewDuplicateAsA,
            bool reviewDuplicateAsB,
            bool reviewBodyLinksRefs,
            bool jobsRefs,
            bool resultsRefs,
            bool datasetsRefs,
            bool lorasRefs,
            bool identitySetsRefs,
          })
        > {
  $$PersonsTableTableManager(_$AppDatabase db, $PersonsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$PersonsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$PersonsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$PersonsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String?> name = const Value.absent(),
                Value<int?> avatarFaceId = const Value.absent(),
                Value<int> createdAt = const Value.absent(),
                Value<bool> hidden = const Value.absent(),
                Value<bool> favorite = const Value.absent(),
                Value<bool> pinned = const Value.absent(),
                Value<bool> groupingLocked = const Value.absent(),
              }) => PersonsCompanion(
                id: id,
                name: name,
                avatarFaceId: avatarFaceId,
                createdAt: createdAt,
                hidden: hidden,
                favorite: favorite,
                pinned: pinned,
                groupingLocked: groupingLocked,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String?> name = const Value.absent(),
                Value<int?> avatarFaceId = const Value.absent(),
                required int createdAt,
                Value<bool> hidden = const Value.absent(),
                Value<bool> favorite = const Value.absent(),
                Value<bool> pinned = const Value.absent(),
                Value<bool> groupingLocked = const Value.absent(),
              }) => PersonsCompanion.insert(
                id: id,
                name: name,
                avatarFaceId: avatarFaceId,
                createdAt: createdAt,
                hidden: hidden,
                favorite: favorite,
                pinned: pinned,
                groupingLocked: groupingLocked,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$PersonsTable, PersonRow>(table),
                  $$PersonsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback:
              ({
                facesRefs = false,
                bodiesRefs = false,
                faceRejectionsRefs = false,
                bodyRejectionsRefs = false,
                distinctAsA = false,
                distinctAsB = false,
                reviewMatchesRefs = false,
                reviewDuplicateAsA = false,
                reviewDuplicateAsB = false,
                reviewBodyLinksRefs = false,
                jobsRefs = false,
                resultsRefs = false,
                datasetsRefs = false,
                lorasRefs = false,
                identitySetsRefs = false,
              }) {
                return PrefetchHooks(
                  db: db,
                  explicitlyWatchedTables: [
                    if (facesRefs) db.faces,
                    if (bodiesRefs) db.bodies,
                    if (faceRejectionsRefs) db.faceRejections,
                    if (bodyRejectionsRefs) db.bodyRejections,
                    if (distinctAsA) db.personDistinct,
                    if (distinctAsB) db.personDistinct,
                    if (reviewMatchesRefs) db.reviewMatches,
                    if (reviewDuplicateAsA) db.reviewDuplicates,
                    if (reviewDuplicateAsB) db.reviewDuplicates,
                    if (reviewBodyLinksRefs) db.reviewBodyLinks,
                    if (jobsRefs) db.jobs,
                    if (resultsRefs) db.results,
                    if (datasetsRefs) db.datasets,
                    if (lorasRefs) db.loras,
                    if (identitySetsRefs) db.identitySets,
                  ],
                  addJoins: null,
                  getPrefetchedDataCallback: (items) async {
                    return [
                      if (facesRefs)
                        await $_getPrefetchedData<
                          PersonRow,
                          $PersonsTable,
                          FaceRow
                        >(
                          currentTable: table,
                          referencedTable: $$PersonsTableReferences
                              ._facesRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$PersonsTableReferences(db, table, p0).facesRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.personId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (bodiesRefs)
                        await $_getPrefetchedData<
                          PersonRow,
                          $PersonsTable,
                          BodyRow
                        >(
                          currentTable: table,
                          referencedTable: $$PersonsTableReferences
                              ._bodiesRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$PersonsTableReferences(
                                db,
                                table,
                                p0,
                              ).bodiesRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.personId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (faceRejectionsRefs)
                        await $_getPrefetchedData<
                          PersonRow,
                          $PersonsTable,
                          FaceRejectionRow
                        >(
                          currentTable: table,
                          referencedTable: $$PersonsTableReferences
                              ._faceRejectionsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$PersonsTableReferences(
                                db,
                                table,
                                p0,
                              ).faceRejectionsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.personId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (bodyRejectionsRefs)
                        await $_getPrefetchedData<
                          PersonRow,
                          $PersonsTable,
                          BodyRejectionRow
                        >(
                          currentTable: table,
                          referencedTable: $$PersonsTableReferences
                              ._bodyRejectionsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$PersonsTableReferences(
                                db,
                                table,
                                p0,
                              ).bodyRejectionsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.personId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (distinctAsA)
                        await $_getPrefetchedData<
                          PersonRow,
                          $PersonsTable,
                          PersonDistinctRow
                        >(
                          currentTable: table,
                          referencedTable: $$PersonsTableReferences
                              ._distinctAsATable(db),
                          managerFromTypedResult: (p0) =>
                              $$PersonsTableReferences(
                                db,
                                table,
                                p0,
                              ).distinctAsA,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.personA == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (distinctAsB)
                        await $_getPrefetchedData<
                          PersonRow,
                          $PersonsTable,
                          PersonDistinctRow
                        >(
                          currentTable: table,
                          referencedTable: $$PersonsTableReferences
                              ._distinctAsBTable(db),
                          managerFromTypedResult: (p0) =>
                              $$PersonsTableReferences(
                                db,
                                table,
                                p0,
                              ).distinctAsB,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.personB == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (reviewMatchesRefs)
                        await $_getPrefetchedData<
                          PersonRow,
                          $PersonsTable,
                          ReviewMatchRow
                        >(
                          currentTable: table,
                          referencedTable: $$PersonsTableReferences
                              ._reviewMatchesRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$PersonsTableReferences(
                                db,
                                table,
                                p0,
                              ).reviewMatchesRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.personId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (reviewDuplicateAsA)
                        await $_getPrefetchedData<
                          PersonRow,
                          $PersonsTable,
                          ReviewDuplicateRow
                        >(
                          currentTable: table,
                          referencedTable: $$PersonsTableReferences
                              ._reviewDuplicateAsATable(db),
                          managerFromTypedResult: (p0) =>
                              $$PersonsTableReferences(
                                db,
                                table,
                                p0,
                              ).reviewDuplicateAsA,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.personA == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (reviewDuplicateAsB)
                        await $_getPrefetchedData<
                          PersonRow,
                          $PersonsTable,
                          ReviewDuplicateRow
                        >(
                          currentTable: table,
                          referencedTable: $$PersonsTableReferences
                              ._reviewDuplicateAsBTable(db),
                          managerFromTypedResult: (p0) =>
                              $$PersonsTableReferences(
                                db,
                                table,
                                p0,
                              ).reviewDuplicateAsB,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.personB == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (reviewBodyLinksRefs)
                        await $_getPrefetchedData<
                          PersonRow,
                          $PersonsTable,
                          ReviewBodyLinkRow
                        >(
                          currentTable: table,
                          referencedTable: $$PersonsTableReferences
                              ._reviewBodyLinksRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$PersonsTableReferences(
                                db,
                                table,
                                p0,
                              ).reviewBodyLinksRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.personId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (jobsRefs)
                        await $_getPrefetchedData<
                          PersonRow,
                          $PersonsTable,
                          JobRow
                        >(
                          currentTable: table,
                          referencedTable: $$PersonsTableReferences
                              ._jobsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$PersonsTableReferences(db, table, p0).jobsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.personId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (resultsRefs)
                        await $_getPrefetchedData<
                          PersonRow,
                          $PersonsTable,
                          ResultRow
                        >(
                          currentTable: table,
                          referencedTable: $$PersonsTableReferences
                              ._resultsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$PersonsTableReferences(
                                db,
                                table,
                                p0,
                              ).resultsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.personId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (datasetsRefs)
                        await $_getPrefetchedData<
                          PersonRow,
                          $PersonsTable,
                          DatasetRow
                        >(
                          currentTable: table,
                          referencedTable: $$PersonsTableReferences
                              ._datasetsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$PersonsTableReferences(
                                db,
                                table,
                                p0,
                              ).datasetsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.personId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (lorasRefs)
                        await $_getPrefetchedData<
                          PersonRow,
                          $PersonsTable,
                          LoraRow
                        >(
                          currentTable: table,
                          referencedTable: $$PersonsTableReferences
                              ._lorasRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$PersonsTableReferences(db, table, p0).lorasRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.personId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (identitySetsRefs)
                        await $_getPrefetchedData<
                          PersonRow,
                          $PersonsTable,
                          IdentitySetRow
                        >(
                          currentTable: table,
                          referencedTable: $$PersonsTableReferences
                              ._identitySetsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$PersonsTableReferences(
                                db,
                                table,
                                p0,
                              ).identitySetsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.personId == item.id,
                              ),
                          typedResults: items,
                        ),
                    ];
                  },
                );
              },
        ),
      );
}

typedef $$PersonsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $PersonsTable,
      PersonRow,
      $$PersonsTableFilterComposer,
      $$PersonsTableOrderingComposer,
      $$PersonsTableAnnotationComposer,
      $$PersonsTableCreateCompanionBuilder,
      $$PersonsTableUpdateCompanionBuilder,
      (PersonRow, $$PersonsTableReferences),
      PersonRow,
      PrefetchHooks Function({
        bool facesRefs,
        bool bodiesRefs,
        bool faceRejectionsRefs,
        bool bodyRejectionsRefs,
        bool distinctAsA,
        bool distinctAsB,
        bool reviewMatchesRefs,
        bool reviewDuplicateAsA,
        bool reviewDuplicateAsB,
        bool reviewBodyLinksRefs,
        bool jobsRefs,
        bool resultsRefs,
        bool datasetsRefs,
        bool lorasRefs,
        bool identitySetsRefs,
      })
    >;
typedef $$MediaTableCreateCompanionBuilder =
    MediaCompanion Function({
      Value<int> id,
      required String assetId,
      required String kind,
      Value<int> sizeBytes,
      Value<int> modifiedAt,
      Value<int?> width,
      Value<int?> height,
      Value<int?> durationMs,
      Value<String> scanStatus,
      Value<int> scanVersion,
      Value<int> lastScannedFrame,
      Value<int?> scannedAt,
      Value<int?> takenAt,
      Value<int> scanAttempts,
      Value<String?> scanError,
      Value<bool> illustrated,
    });
typedef $$MediaTableUpdateCompanionBuilder =
    MediaCompanion Function({
      Value<int> id,
      Value<String> assetId,
      Value<String> kind,
      Value<int> sizeBytes,
      Value<int> modifiedAt,
      Value<int?> width,
      Value<int?> height,
      Value<int?> durationMs,
      Value<String> scanStatus,
      Value<int> scanVersion,
      Value<int> lastScannedFrame,
      Value<int?> scannedAt,
      Value<int?> takenAt,
      Value<int> scanAttempts,
      Value<String?> scanError,
      Value<bool> illustrated,
    });

final class $$MediaTableReferences
    extends BaseReferences<_$AppDatabase, $MediaTable, MediaRow> {
  $$MediaTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static MultiTypedResultKey<$FacesTable, List<FaceRow>> _facesRefsTable(
    _$AppDatabase db,
  ) => MultiTypedResultKey.fromTable(
    db.faces,
    aliasName: 'media__id__faces__media_id',
  );

  $$FacesTableProcessedTableManager get facesRefs {
    final manager = $$FacesTableTableManager(
      $_db,
      $_db.faces,
    ).filter((f) => f.mediaId.id.sqlEquals($_itemColumn<int>('id')!));

    final cache = $_typedResult.readTableOrNull(_facesRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$BodiesTable, List<BodyRow>> _bodiesRefsTable(
    _$AppDatabase db,
  ) => MultiTypedResultKey.fromTable(
    db.bodies,
    aliasName: 'media__id__bodies__media_id',
  );

  $$BodiesTableProcessedTableManager get bodiesRefs {
    final manager = $$BodiesTableTableManager(
      $_db,
      $_db.bodies,
    ).filter((f) => f.mediaId.id.sqlEquals($_itemColumn<int>('id')!));

    final cache = $_typedResult.readTableOrNull(_bodiesRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$MediaDetectionsTable, List<DetectionRow>>
  _mediaDetectionsRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.mediaDetections,
    aliasName: 'media__id__media_detections__media_id',
  );

  $$MediaDetectionsTableProcessedTableManager get mediaDetectionsRefs {
    final manager = $$MediaDetectionsTableTableManager(
      $_db,
      $_db.mediaDetections,
    ).filter((f) => f.mediaId.id.sqlEquals($_itemColumn<int>('id')!));

    final cache = $_typedResult.readTableOrNull(
      _mediaDetectionsRefsTable($_db),
    );
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$CharacterSamplesTable, List<CharacterSampleRow>>
  _characterSamplesRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.characterSamples,
    aliasName: 'media__id__character_samples__media_id',
  );

  $$CharacterSamplesTableProcessedTableManager get characterSamplesRefs {
    final manager = $$CharacterSamplesTableTableManager(
      $_db,
      $_db.characterSamples,
    ).filter((f) => f.mediaId.id.sqlEquals($_itemColumn<int>('id')!));

    final cache = $_typedResult.readTableOrNull(
      _characterSamplesRefsTable($_db),
    );
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$MediaTableFilterComposer extends Composer<_$AppDatabase, $MediaTable> {
  $$MediaTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get assetId => $composableBuilder(
    column: $table.assetId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get sizeBytes => $composableBuilder(
    column: $table.sizeBytes,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get modifiedAt => $composableBuilder(
    column: $table.modifiedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get width => $composableBuilder(
    column: $table.width,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get height => $composableBuilder(
    column: $table.height,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get durationMs => $composableBuilder(
    column: $table.durationMs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get scanStatus => $composableBuilder(
    column: $table.scanStatus,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get scanVersion => $composableBuilder(
    column: $table.scanVersion,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get lastScannedFrame => $composableBuilder(
    column: $table.lastScannedFrame,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get scannedAt => $composableBuilder(
    column: $table.scannedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get takenAt => $composableBuilder(
    column: $table.takenAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get scanAttempts => $composableBuilder(
    column: $table.scanAttempts,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get scanError => $composableBuilder(
    column: $table.scanError,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get illustrated => $composableBuilder(
    column: $table.illustrated,
    builder: (column) => ColumnFilters(column),
  );

  Expression<bool> facesRefs(
    Expression<bool> Function($$FacesTableFilterComposer f) f,
  ) {
    final $$FacesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.faces,
      getReferencedColumn: (t) => t.mediaId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$FacesTableFilterComposer(
            $db: $db,
            $table: $db.faces,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> bodiesRefs(
    Expression<bool> Function($$BodiesTableFilterComposer f) f,
  ) {
    final $$BodiesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.bodies,
      getReferencedColumn: (t) => t.mediaId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$BodiesTableFilterComposer(
            $db: $db,
            $table: $db.bodies,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> mediaDetectionsRefs(
    Expression<bool> Function($$MediaDetectionsTableFilterComposer f) f,
  ) {
    final $$MediaDetectionsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.mediaDetections,
      getReferencedColumn: (t) => t.mediaId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$MediaDetectionsTableFilterComposer(
            $db: $db,
            $table: $db.mediaDetections,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> characterSamplesRefs(
    Expression<bool> Function($$CharacterSamplesTableFilterComposer f) f,
  ) {
    final $$CharacterSamplesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.characterSamples,
      getReferencedColumn: (t) => t.mediaId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$CharacterSamplesTableFilterComposer(
            $db: $db,
            $table: $db.characterSamples,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$MediaTableOrderingComposer
    extends Composer<_$AppDatabase, $MediaTable> {
  $$MediaTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get assetId => $composableBuilder(
    column: $table.assetId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get sizeBytes => $composableBuilder(
    column: $table.sizeBytes,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get modifiedAt => $composableBuilder(
    column: $table.modifiedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get width => $composableBuilder(
    column: $table.width,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get height => $composableBuilder(
    column: $table.height,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get durationMs => $composableBuilder(
    column: $table.durationMs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get scanStatus => $composableBuilder(
    column: $table.scanStatus,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get scanVersion => $composableBuilder(
    column: $table.scanVersion,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get lastScannedFrame => $composableBuilder(
    column: $table.lastScannedFrame,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get scannedAt => $composableBuilder(
    column: $table.scannedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get takenAt => $composableBuilder(
    column: $table.takenAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get scanAttempts => $composableBuilder(
    column: $table.scanAttempts,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get scanError => $composableBuilder(
    column: $table.scanError,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get illustrated => $composableBuilder(
    column: $table.illustrated,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$MediaTableAnnotationComposer
    extends Composer<_$AppDatabase, $MediaTable> {
  $$MediaTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get assetId =>
      $composableBuilder(column: $table.assetId, builder: (column) => column);

  GeneratedColumn<String> get kind =>
      $composableBuilder(column: $table.kind, builder: (column) => column);

  GeneratedColumn<int> get sizeBytes =>
      $composableBuilder(column: $table.sizeBytes, builder: (column) => column);

  GeneratedColumn<int> get modifiedAt => $composableBuilder(
    column: $table.modifiedAt,
    builder: (column) => column,
  );

  GeneratedColumn<int> get width =>
      $composableBuilder(column: $table.width, builder: (column) => column);

  GeneratedColumn<int> get height =>
      $composableBuilder(column: $table.height, builder: (column) => column);

  GeneratedColumn<int> get durationMs => $composableBuilder(
    column: $table.durationMs,
    builder: (column) => column,
  );

  GeneratedColumn<String> get scanStatus => $composableBuilder(
    column: $table.scanStatus,
    builder: (column) => column,
  );

  GeneratedColumn<int> get scanVersion => $composableBuilder(
    column: $table.scanVersion,
    builder: (column) => column,
  );

  GeneratedColumn<int> get lastScannedFrame => $composableBuilder(
    column: $table.lastScannedFrame,
    builder: (column) => column,
  );

  GeneratedColumn<int> get scannedAt =>
      $composableBuilder(column: $table.scannedAt, builder: (column) => column);

  GeneratedColumn<int> get takenAt =>
      $composableBuilder(column: $table.takenAt, builder: (column) => column);

  GeneratedColumn<int> get scanAttempts => $composableBuilder(
    column: $table.scanAttempts,
    builder: (column) => column,
  );

  GeneratedColumn<String> get scanError =>
      $composableBuilder(column: $table.scanError, builder: (column) => column);

  GeneratedColumn<bool> get illustrated => $composableBuilder(
    column: $table.illustrated,
    builder: (column) => column,
  );

  Expression<T> facesRefs<T extends Object>(
    Expression<T> Function($$FacesTableAnnotationComposer a) f,
  ) {
    final $$FacesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.faces,
      getReferencedColumn: (t) => t.mediaId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$FacesTableAnnotationComposer(
            $db: $db,
            $table: $db.faces,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> bodiesRefs<T extends Object>(
    Expression<T> Function($$BodiesTableAnnotationComposer a) f,
  ) {
    final $$BodiesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.bodies,
      getReferencedColumn: (t) => t.mediaId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$BodiesTableAnnotationComposer(
            $db: $db,
            $table: $db.bodies,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> mediaDetectionsRefs<T extends Object>(
    Expression<T> Function($$MediaDetectionsTableAnnotationComposer a) f,
  ) {
    final $$MediaDetectionsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.mediaDetections,
      getReferencedColumn: (t) => t.mediaId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$MediaDetectionsTableAnnotationComposer(
            $db: $db,
            $table: $db.mediaDetections,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> characterSamplesRefs<T extends Object>(
    Expression<T> Function($$CharacterSamplesTableAnnotationComposer a) f,
  ) {
    final $$CharacterSamplesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.characterSamples,
      getReferencedColumn: (t) => t.mediaId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$CharacterSamplesTableAnnotationComposer(
            $db: $db,
            $table: $db.characterSamples,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$MediaTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $MediaTable,
          MediaRow,
          $$MediaTableFilterComposer,
          $$MediaTableOrderingComposer,
          $$MediaTableAnnotationComposer,
          $$MediaTableCreateCompanionBuilder,
          $$MediaTableUpdateCompanionBuilder,
          (MediaRow, $$MediaTableReferences),
          MediaRow,
          PrefetchHooks Function({
            bool facesRefs,
            bool bodiesRefs,
            bool mediaDetectionsRefs,
            bool characterSamplesRefs,
          })
        > {
  $$MediaTableTableManager(_$AppDatabase db, $MediaTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$MediaTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$MediaTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$MediaTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> assetId = const Value.absent(),
                Value<String> kind = const Value.absent(),
                Value<int> sizeBytes = const Value.absent(),
                Value<int> modifiedAt = const Value.absent(),
                Value<int?> width = const Value.absent(),
                Value<int?> height = const Value.absent(),
                Value<int?> durationMs = const Value.absent(),
                Value<String> scanStatus = const Value.absent(),
                Value<int> scanVersion = const Value.absent(),
                Value<int> lastScannedFrame = const Value.absent(),
                Value<int?> scannedAt = const Value.absent(),
                Value<int?> takenAt = const Value.absent(),
                Value<int> scanAttempts = const Value.absent(),
                Value<String?> scanError = const Value.absent(),
                Value<bool> illustrated = const Value.absent(),
              }) => MediaCompanion(
                id: id,
                assetId: assetId,
                kind: kind,
                sizeBytes: sizeBytes,
                modifiedAt: modifiedAt,
                width: width,
                height: height,
                durationMs: durationMs,
                scanStatus: scanStatus,
                scanVersion: scanVersion,
                lastScannedFrame: lastScannedFrame,
                scannedAt: scannedAt,
                takenAt: takenAt,
                scanAttempts: scanAttempts,
                scanError: scanError,
                illustrated: illustrated,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String assetId,
                required String kind,
                Value<int> sizeBytes = const Value.absent(),
                Value<int> modifiedAt = const Value.absent(),
                Value<int?> width = const Value.absent(),
                Value<int?> height = const Value.absent(),
                Value<int?> durationMs = const Value.absent(),
                Value<String> scanStatus = const Value.absent(),
                Value<int> scanVersion = const Value.absent(),
                Value<int> lastScannedFrame = const Value.absent(),
                Value<int?> scannedAt = const Value.absent(),
                Value<int?> takenAt = const Value.absent(),
                Value<int> scanAttempts = const Value.absent(),
                Value<String?> scanError = const Value.absent(),
                Value<bool> illustrated = const Value.absent(),
              }) => MediaCompanion.insert(
                id: id,
                assetId: assetId,
                kind: kind,
                sizeBytes: sizeBytes,
                modifiedAt: modifiedAt,
                width: width,
                height: height,
                durationMs: durationMs,
                scanStatus: scanStatus,
                scanVersion: scanVersion,
                lastScannedFrame: lastScannedFrame,
                scannedAt: scannedAt,
                takenAt: takenAt,
                scanAttempts: scanAttempts,
                scanError: scanError,
                illustrated: illustrated,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$MediaTable, MediaRow>(table),
                  $$MediaTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback:
              ({
                facesRefs = false,
                bodiesRefs = false,
                mediaDetectionsRefs = false,
                characterSamplesRefs = false,
              }) {
                return PrefetchHooks(
                  db: db,
                  explicitlyWatchedTables: [
                    if (facesRefs) db.faces,
                    if (bodiesRefs) db.bodies,
                    if (mediaDetectionsRefs) db.mediaDetections,
                    if (characterSamplesRefs) db.characterSamples,
                  ],
                  addJoins: null,
                  getPrefetchedDataCallback: (items) async {
                    return [
                      if (facesRefs)
                        await $_getPrefetchedData<
                          MediaRow,
                          $MediaTable,
                          FaceRow
                        >(
                          currentTable: table,
                          referencedTable: $$MediaTableReferences
                              ._facesRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$MediaTableReferences(db, table, p0).facesRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.mediaId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (bodiesRefs)
                        await $_getPrefetchedData<
                          MediaRow,
                          $MediaTable,
                          BodyRow
                        >(
                          currentTable: table,
                          referencedTable: $$MediaTableReferences
                              ._bodiesRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$MediaTableReferences(db, table, p0).bodiesRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.mediaId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (mediaDetectionsRefs)
                        await $_getPrefetchedData<
                          MediaRow,
                          $MediaTable,
                          DetectionRow
                        >(
                          currentTable: table,
                          referencedTable: $$MediaTableReferences
                              ._mediaDetectionsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$MediaTableReferences(
                                db,
                                table,
                                p0,
                              ).mediaDetectionsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.mediaId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (characterSamplesRefs)
                        await $_getPrefetchedData<
                          MediaRow,
                          $MediaTable,
                          CharacterSampleRow
                        >(
                          currentTable: table,
                          referencedTable: $$MediaTableReferences
                              ._characterSamplesRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$MediaTableReferences(
                                db,
                                table,
                                p0,
                              ).characterSamplesRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.mediaId == item.id,
                              ),
                          typedResults: items,
                        ),
                    ];
                  },
                );
              },
        ),
      );
}

typedef $$MediaTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $MediaTable,
      MediaRow,
      $$MediaTableFilterComposer,
      $$MediaTableOrderingComposer,
      $$MediaTableAnnotationComposer,
      $$MediaTableCreateCompanionBuilder,
      $$MediaTableUpdateCompanionBuilder,
      (MediaRow, $$MediaTableReferences),
      MediaRow,
      PrefetchHooks Function({
        bool facesRefs,
        bool bodiesRefs,
        bool mediaDetectionsRefs,
        bool characterSamplesRefs,
      })
    >;
typedef $$FacesTableCreateCompanionBuilder =
    FacesCompanion Function({
      Value<int> id,
      Value<int?> mediaId,
      Value<int?> personId,
      required String modelId,
      required Uint8List embedding,
      required double qualityScore,
      required int qualityVersion,
      required double detScore,
      required double facePx,
      required double sharpness,
      Value<double?> embeddingNorm,
      Value<double?> yaw,
      Value<double?> pitch,
      Value<double?> roll,
      required double bboxX,
      required double bboxY,
      required double bboxW,
      required double bboxH,
      Value<String?> kps,
      Value<int?> frameNumber,
      Value<int?> timestampMs,
      Value<String?> cropPath,
      Value<bool> reviewDismissed,
      required int createdAt,
      Value<bool> hidden,
    });
typedef $$FacesTableUpdateCompanionBuilder =
    FacesCompanion Function({
      Value<int> id,
      Value<int?> mediaId,
      Value<int?> personId,
      Value<String> modelId,
      Value<Uint8List> embedding,
      Value<double> qualityScore,
      Value<int> qualityVersion,
      Value<double> detScore,
      Value<double> facePx,
      Value<double> sharpness,
      Value<double?> embeddingNorm,
      Value<double?> yaw,
      Value<double?> pitch,
      Value<double?> roll,
      Value<double> bboxX,
      Value<double> bboxY,
      Value<double> bboxW,
      Value<double> bboxH,
      Value<String?> kps,
      Value<int?> frameNumber,
      Value<int?> timestampMs,
      Value<String?> cropPath,
      Value<bool> reviewDismissed,
      Value<int> createdAt,
      Value<bool> hidden,
    });

final class $$FacesTableReferences
    extends BaseReferences<_$AppDatabase, $FacesTable, FaceRow> {
  $$FacesTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $MediaTable _mediaIdTable(_$AppDatabase db) =>
      db.media.createAlias('faces__media_id__media__id');

  $$MediaTableProcessedTableManager? get mediaId {
    final $_column = $_itemColumn<int>('media_id');
    if ($_column == null) return null;
    final manager = $$MediaTableTableManager(
      $_db,
      $_db.media,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_mediaIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static $PersonsTable _personIdTable(_$AppDatabase db) =>
      db.persons.createAlias('faces__person_id__persons__id');

  $$PersonsTableProcessedTableManager? get personId {
    final $_column = $_itemColumn<int>('person_id');
    if ($_column == null) return null;
    final manager = $$PersonsTableTableManager(
      $_db,
      $_db.persons,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_personIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static MultiTypedResultKey<$BodiesTable, List<BodyRow>> _bodiesRefsTable(
    _$AppDatabase db,
  ) => MultiTypedResultKey.fromTable(
    db.bodies,
    aliasName: 'faces__id__bodies__face_id',
  );

  $$BodiesTableProcessedTableManager get bodiesRefs {
    final manager = $$BodiesTableTableManager(
      $_db,
      $_db.bodies,
    ).filter((f) => f.faceId.id.sqlEquals($_itemColumn<int>('id')!));

    final cache = $_typedResult.readTableOrNull(_bodiesRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$FaceRejectionsTable, List<FaceRejectionRow>>
  _faceRejectionsRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.faceRejections,
    aliasName: 'faces__id__face_rejections__face_id',
  );

  $$FaceRejectionsTableProcessedTableManager get faceRejectionsRefs {
    final manager = $$FaceRejectionsTableTableManager(
      $_db,
      $_db.faceRejections,
    ).filter((f) => f.faceId.id.sqlEquals($_itemColumn<int>('id')!));

    final cache = $_typedResult.readTableOrNull(_faceRejectionsRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$ReviewMatchesTable, List<ReviewMatchRow>>
  _reviewMatchesRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.reviewMatches,
    aliasName: 'faces__id__review_matches__face_id',
  );

  $$ReviewMatchesTableProcessedTableManager get reviewMatchesRefs {
    final manager = $$ReviewMatchesTableTableManager(
      $_db,
      $_db.reviewMatches,
    ).filter((f) => f.faceId.id.sqlEquals($_itemColumn<int>('id')!));

    final cache = $_typedResult.readTableOrNull(_reviewMatchesRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$IdentitySetFacesTable, List<IdentitySetFaceRow>>
  _identitySetFacesRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.identitySetFaces,
    aliasName: 'faces__id__identity_set_faces__face_id',
  );

  $$IdentitySetFacesTableProcessedTableManager get identitySetFacesRefs {
    final manager = $$IdentitySetFacesTableTableManager(
      $_db,
      $_db.identitySetFaces,
    ).filter((f) => f.faceId.id.sqlEquals($_itemColumn<int>('id')!));

    final cache = $_typedResult.readTableOrNull(
      _identitySetFacesRefsTable($_db),
    );
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$FacesTableFilterComposer extends Composer<_$AppDatabase, $FacesTable> {
  $$FacesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get modelId => $composableBuilder(
    column: $table.modelId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<Uint8List> get embedding => $composableBuilder(
    column: $table.embedding,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get qualityScore => $composableBuilder(
    column: $table.qualityScore,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get qualityVersion => $composableBuilder(
    column: $table.qualityVersion,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get detScore => $composableBuilder(
    column: $table.detScore,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get facePx => $composableBuilder(
    column: $table.facePx,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get sharpness => $composableBuilder(
    column: $table.sharpness,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get embeddingNorm => $composableBuilder(
    column: $table.embeddingNorm,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get yaw => $composableBuilder(
    column: $table.yaw,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get pitch => $composableBuilder(
    column: $table.pitch,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get roll => $composableBuilder(
    column: $table.roll,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get bboxX => $composableBuilder(
    column: $table.bboxX,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get bboxY => $composableBuilder(
    column: $table.bboxY,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get bboxW => $composableBuilder(
    column: $table.bboxW,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get bboxH => $composableBuilder(
    column: $table.bboxH,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get kps => $composableBuilder(
    column: $table.kps,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get frameNumber => $composableBuilder(
    column: $table.frameNumber,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get timestampMs => $composableBuilder(
    column: $table.timestampMs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get cropPath => $composableBuilder(
    column: $table.cropPath,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get reviewDismissed => $composableBuilder(
    column: $table.reviewDismissed,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get hidden => $composableBuilder(
    column: $table.hidden,
    builder: (column) => ColumnFilters(column),
  );

  $$MediaTableFilterComposer get mediaId {
    final $$MediaTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.mediaId,
      referencedTable: $db.media,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$MediaTableFilterComposer(
            $db: $db,
            $table: $db.media,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$PersonsTableFilterComposer get personId {
    final $$PersonsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.personId,
      referencedTable: $db.persons,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$PersonsTableFilterComposer(
            $db: $db,
            $table: $db.persons,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  Expression<bool> bodiesRefs(
    Expression<bool> Function($$BodiesTableFilterComposer f) f,
  ) {
    final $$BodiesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.bodies,
      getReferencedColumn: (t) => t.faceId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$BodiesTableFilterComposer(
            $db: $db,
            $table: $db.bodies,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> faceRejectionsRefs(
    Expression<bool> Function($$FaceRejectionsTableFilterComposer f) f,
  ) {
    final $$FaceRejectionsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.faceRejections,
      getReferencedColumn: (t) => t.faceId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$FaceRejectionsTableFilterComposer(
            $db: $db,
            $table: $db.faceRejections,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> reviewMatchesRefs(
    Expression<bool> Function($$ReviewMatchesTableFilterComposer f) f,
  ) {
    final $$ReviewMatchesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.reviewMatches,
      getReferencedColumn: (t) => t.faceId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ReviewMatchesTableFilterComposer(
            $db: $db,
            $table: $db.reviewMatches,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> identitySetFacesRefs(
    Expression<bool> Function($$IdentitySetFacesTableFilterComposer f) f,
  ) {
    final $$IdentitySetFacesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.identitySetFaces,
      getReferencedColumn: (t) => t.faceId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$IdentitySetFacesTableFilterComposer(
            $db: $db,
            $table: $db.identitySetFaces,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$FacesTableOrderingComposer
    extends Composer<_$AppDatabase, $FacesTable> {
  $$FacesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get modelId => $composableBuilder(
    column: $table.modelId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<Uint8List> get embedding => $composableBuilder(
    column: $table.embedding,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get qualityScore => $composableBuilder(
    column: $table.qualityScore,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get qualityVersion => $composableBuilder(
    column: $table.qualityVersion,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get detScore => $composableBuilder(
    column: $table.detScore,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get facePx => $composableBuilder(
    column: $table.facePx,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get sharpness => $composableBuilder(
    column: $table.sharpness,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get embeddingNorm => $composableBuilder(
    column: $table.embeddingNorm,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get yaw => $composableBuilder(
    column: $table.yaw,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get pitch => $composableBuilder(
    column: $table.pitch,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get roll => $composableBuilder(
    column: $table.roll,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get bboxX => $composableBuilder(
    column: $table.bboxX,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get bboxY => $composableBuilder(
    column: $table.bboxY,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get bboxW => $composableBuilder(
    column: $table.bboxW,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get bboxH => $composableBuilder(
    column: $table.bboxH,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get kps => $composableBuilder(
    column: $table.kps,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get frameNumber => $composableBuilder(
    column: $table.frameNumber,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get timestampMs => $composableBuilder(
    column: $table.timestampMs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get cropPath => $composableBuilder(
    column: $table.cropPath,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get reviewDismissed => $composableBuilder(
    column: $table.reviewDismissed,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get hidden => $composableBuilder(
    column: $table.hidden,
    builder: (column) => ColumnOrderings(column),
  );

  $$MediaTableOrderingComposer get mediaId {
    final $$MediaTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.mediaId,
      referencedTable: $db.media,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$MediaTableOrderingComposer(
            $db: $db,
            $table: $db.media,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$PersonsTableOrderingComposer get personId {
    final $$PersonsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.personId,
      referencedTable: $db.persons,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$PersonsTableOrderingComposer(
            $db: $db,
            $table: $db.persons,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$FacesTableAnnotationComposer
    extends Composer<_$AppDatabase, $FacesTable> {
  $$FacesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get modelId =>
      $composableBuilder(column: $table.modelId, builder: (column) => column);

  GeneratedColumn<Uint8List> get embedding =>
      $composableBuilder(column: $table.embedding, builder: (column) => column);

  GeneratedColumn<double> get qualityScore => $composableBuilder(
    column: $table.qualityScore,
    builder: (column) => column,
  );

  GeneratedColumn<int> get qualityVersion => $composableBuilder(
    column: $table.qualityVersion,
    builder: (column) => column,
  );

  GeneratedColumn<double> get detScore =>
      $composableBuilder(column: $table.detScore, builder: (column) => column);

  GeneratedColumn<double> get facePx =>
      $composableBuilder(column: $table.facePx, builder: (column) => column);

  GeneratedColumn<double> get sharpness =>
      $composableBuilder(column: $table.sharpness, builder: (column) => column);

  GeneratedColumn<double> get embeddingNorm => $composableBuilder(
    column: $table.embeddingNorm,
    builder: (column) => column,
  );

  GeneratedColumn<double> get yaw =>
      $composableBuilder(column: $table.yaw, builder: (column) => column);

  GeneratedColumn<double> get pitch =>
      $composableBuilder(column: $table.pitch, builder: (column) => column);

  GeneratedColumn<double> get roll =>
      $composableBuilder(column: $table.roll, builder: (column) => column);

  GeneratedColumn<double> get bboxX =>
      $composableBuilder(column: $table.bboxX, builder: (column) => column);

  GeneratedColumn<double> get bboxY =>
      $composableBuilder(column: $table.bboxY, builder: (column) => column);

  GeneratedColumn<double> get bboxW =>
      $composableBuilder(column: $table.bboxW, builder: (column) => column);

  GeneratedColumn<double> get bboxH =>
      $composableBuilder(column: $table.bboxH, builder: (column) => column);

  GeneratedColumn<String> get kps =>
      $composableBuilder(column: $table.kps, builder: (column) => column);

  GeneratedColumn<int> get frameNumber => $composableBuilder(
    column: $table.frameNumber,
    builder: (column) => column,
  );

  GeneratedColumn<int> get timestampMs => $composableBuilder(
    column: $table.timestampMs,
    builder: (column) => column,
  );

  GeneratedColumn<String> get cropPath =>
      $composableBuilder(column: $table.cropPath, builder: (column) => column);

  GeneratedColumn<bool> get reviewDismissed => $composableBuilder(
    column: $table.reviewDismissed,
    builder: (column) => column,
  );

  GeneratedColumn<int> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<bool> get hidden =>
      $composableBuilder(column: $table.hidden, builder: (column) => column);

  $$MediaTableAnnotationComposer get mediaId {
    final $$MediaTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.mediaId,
      referencedTable: $db.media,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$MediaTableAnnotationComposer(
            $db: $db,
            $table: $db.media,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$PersonsTableAnnotationComposer get personId {
    final $$PersonsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.personId,
      referencedTable: $db.persons,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$PersonsTableAnnotationComposer(
            $db: $db,
            $table: $db.persons,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  Expression<T> bodiesRefs<T extends Object>(
    Expression<T> Function($$BodiesTableAnnotationComposer a) f,
  ) {
    final $$BodiesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.bodies,
      getReferencedColumn: (t) => t.faceId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$BodiesTableAnnotationComposer(
            $db: $db,
            $table: $db.bodies,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> faceRejectionsRefs<T extends Object>(
    Expression<T> Function($$FaceRejectionsTableAnnotationComposer a) f,
  ) {
    final $$FaceRejectionsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.faceRejections,
      getReferencedColumn: (t) => t.faceId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$FaceRejectionsTableAnnotationComposer(
            $db: $db,
            $table: $db.faceRejections,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> reviewMatchesRefs<T extends Object>(
    Expression<T> Function($$ReviewMatchesTableAnnotationComposer a) f,
  ) {
    final $$ReviewMatchesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.reviewMatches,
      getReferencedColumn: (t) => t.faceId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ReviewMatchesTableAnnotationComposer(
            $db: $db,
            $table: $db.reviewMatches,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> identitySetFacesRefs<T extends Object>(
    Expression<T> Function($$IdentitySetFacesTableAnnotationComposer a) f,
  ) {
    final $$IdentitySetFacesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.identitySetFaces,
      getReferencedColumn: (t) => t.faceId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$IdentitySetFacesTableAnnotationComposer(
            $db: $db,
            $table: $db.identitySetFaces,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$FacesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $FacesTable,
          FaceRow,
          $$FacesTableFilterComposer,
          $$FacesTableOrderingComposer,
          $$FacesTableAnnotationComposer,
          $$FacesTableCreateCompanionBuilder,
          $$FacesTableUpdateCompanionBuilder,
          (FaceRow, $$FacesTableReferences),
          FaceRow,
          PrefetchHooks Function({
            bool mediaId,
            bool personId,
            bool bodiesRefs,
            bool faceRejectionsRefs,
            bool reviewMatchesRefs,
            bool identitySetFacesRefs,
          })
        > {
  $$FacesTableTableManager(_$AppDatabase db, $FacesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$FacesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$FacesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$FacesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<int?> mediaId = const Value.absent(),
                Value<int?> personId = const Value.absent(),
                Value<String> modelId = const Value.absent(),
                Value<Uint8List> embedding = const Value.absent(),
                Value<double> qualityScore = const Value.absent(),
                Value<int> qualityVersion = const Value.absent(),
                Value<double> detScore = const Value.absent(),
                Value<double> facePx = const Value.absent(),
                Value<double> sharpness = const Value.absent(),
                Value<double?> embeddingNorm = const Value.absent(),
                Value<double?> yaw = const Value.absent(),
                Value<double?> pitch = const Value.absent(),
                Value<double?> roll = const Value.absent(),
                Value<double> bboxX = const Value.absent(),
                Value<double> bboxY = const Value.absent(),
                Value<double> bboxW = const Value.absent(),
                Value<double> bboxH = const Value.absent(),
                Value<String?> kps = const Value.absent(),
                Value<int?> frameNumber = const Value.absent(),
                Value<int?> timestampMs = const Value.absent(),
                Value<String?> cropPath = const Value.absent(),
                Value<bool> reviewDismissed = const Value.absent(),
                Value<int> createdAt = const Value.absent(),
                Value<bool> hidden = const Value.absent(),
              }) => FacesCompanion(
                id: id,
                mediaId: mediaId,
                personId: personId,
                modelId: modelId,
                embedding: embedding,
                qualityScore: qualityScore,
                qualityVersion: qualityVersion,
                detScore: detScore,
                facePx: facePx,
                sharpness: sharpness,
                embeddingNorm: embeddingNorm,
                yaw: yaw,
                pitch: pitch,
                roll: roll,
                bboxX: bboxX,
                bboxY: bboxY,
                bboxW: bboxW,
                bboxH: bboxH,
                kps: kps,
                frameNumber: frameNumber,
                timestampMs: timestampMs,
                cropPath: cropPath,
                reviewDismissed: reviewDismissed,
                createdAt: createdAt,
                hidden: hidden,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<int?> mediaId = const Value.absent(),
                Value<int?> personId = const Value.absent(),
                required String modelId,
                required Uint8List embedding,
                required double qualityScore,
                required int qualityVersion,
                required double detScore,
                required double facePx,
                required double sharpness,
                Value<double?> embeddingNorm = const Value.absent(),
                Value<double?> yaw = const Value.absent(),
                Value<double?> pitch = const Value.absent(),
                Value<double?> roll = const Value.absent(),
                required double bboxX,
                required double bboxY,
                required double bboxW,
                required double bboxH,
                Value<String?> kps = const Value.absent(),
                Value<int?> frameNumber = const Value.absent(),
                Value<int?> timestampMs = const Value.absent(),
                Value<String?> cropPath = const Value.absent(),
                Value<bool> reviewDismissed = const Value.absent(),
                required int createdAt,
                Value<bool> hidden = const Value.absent(),
              }) => FacesCompanion.insert(
                id: id,
                mediaId: mediaId,
                personId: personId,
                modelId: modelId,
                embedding: embedding,
                qualityScore: qualityScore,
                qualityVersion: qualityVersion,
                detScore: detScore,
                facePx: facePx,
                sharpness: sharpness,
                embeddingNorm: embeddingNorm,
                yaw: yaw,
                pitch: pitch,
                roll: roll,
                bboxX: bboxX,
                bboxY: bboxY,
                bboxW: bboxW,
                bboxH: bboxH,
                kps: kps,
                frameNumber: frameNumber,
                timestampMs: timestampMs,
                cropPath: cropPath,
                reviewDismissed: reviewDismissed,
                createdAt: createdAt,
                hidden: hidden,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$FacesTable, FaceRow>(table),
                  $$FacesTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback:
              ({
                mediaId = false,
                personId = false,
                bodiesRefs = false,
                faceRejectionsRefs = false,
                reviewMatchesRefs = false,
                identitySetFacesRefs = false,
              }) {
                return PrefetchHooks(
                  db: db,
                  explicitlyWatchedTables: [
                    if (bodiesRefs) db.bodies,
                    if (faceRejectionsRefs) db.faceRejections,
                    if (reviewMatchesRefs) db.reviewMatches,
                    if (identitySetFacesRefs) db.identitySetFaces,
                  ],
                  addJoins:
                      <
                        T extends TableManagerState<
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic
                        >
                      >(state) {
                        if (mediaId) {
                          state =
                              state.withJoin(
                                    currentTable: table,
                                    currentColumn: table.mediaId,
                                    referencedTable: $$FacesTableReferences
                                        ._mediaIdTable(db),
                                    referencedColumn: $$FacesTableReferences
                                        ._mediaIdTable(db)
                                        .id,
                                  )
                                  as T;
                        }
                        if (personId) {
                          state =
                              state.withJoin(
                                    currentTable: table,
                                    currentColumn: table.personId,
                                    referencedTable: $$FacesTableReferences
                                        ._personIdTable(db),
                                    referencedColumn: $$FacesTableReferences
                                        ._personIdTable(db)
                                        .id,
                                  )
                                  as T;
                        }

                        return state;
                      },
                  getPrefetchedDataCallback: (items) async {
                    return [
                      if (bodiesRefs)
                        await $_getPrefetchedData<
                          FaceRow,
                          $FacesTable,
                          BodyRow
                        >(
                          currentTable: table,
                          referencedTable: $$FacesTableReferences
                              ._bodiesRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$FacesTableReferences(db, table, p0).bodiesRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.faceId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (faceRejectionsRefs)
                        await $_getPrefetchedData<
                          FaceRow,
                          $FacesTable,
                          FaceRejectionRow
                        >(
                          currentTable: table,
                          referencedTable: $$FacesTableReferences
                              ._faceRejectionsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$FacesTableReferences(
                                db,
                                table,
                                p0,
                              ).faceRejectionsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.faceId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (reviewMatchesRefs)
                        await $_getPrefetchedData<
                          FaceRow,
                          $FacesTable,
                          ReviewMatchRow
                        >(
                          currentTable: table,
                          referencedTable: $$FacesTableReferences
                              ._reviewMatchesRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$FacesTableReferences(
                                db,
                                table,
                                p0,
                              ).reviewMatchesRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.faceId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (identitySetFacesRefs)
                        await $_getPrefetchedData<
                          FaceRow,
                          $FacesTable,
                          IdentitySetFaceRow
                        >(
                          currentTable: table,
                          referencedTable: $$FacesTableReferences
                              ._identitySetFacesRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$FacesTableReferences(
                                db,
                                table,
                                p0,
                              ).identitySetFacesRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.faceId == item.id,
                              ),
                          typedResults: items,
                        ),
                    ];
                  },
                );
              },
        ),
      );
}

typedef $$FacesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $FacesTable,
      FaceRow,
      $$FacesTableFilterComposer,
      $$FacesTableOrderingComposer,
      $$FacesTableAnnotationComposer,
      $$FacesTableCreateCompanionBuilder,
      $$FacesTableUpdateCompanionBuilder,
      (FaceRow, $$FacesTableReferences),
      FaceRow,
      PrefetchHooks Function({
        bool mediaId,
        bool personId,
        bool bodiesRefs,
        bool faceRejectionsRefs,
        bool reviewMatchesRefs,
        bool identitySetFacesRefs,
      })
    >;
typedef $$FaceSuppressionsTableCreateCompanionBuilder =
    FaceSuppressionsCompanion Function({
      Value<int> id,
      required String assetId,
      required String modelId,
      required Uint8List embedding,
      required String occurrences,
    });
typedef $$FaceSuppressionsTableUpdateCompanionBuilder =
    FaceSuppressionsCompanion Function({
      Value<int> id,
      Value<String> assetId,
      Value<String> modelId,
      Value<Uint8List> embedding,
      Value<String> occurrences,
    });

class $$FaceSuppressionsTableFilterComposer
    extends Composer<_$AppDatabase, $FaceSuppressionsTable> {
  $$FaceSuppressionsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get assetId => $composableBuilder(
    column: $table.assetId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get modelId => $composableBuilder(
    column: $table.modelId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<Uint8List> get embedding => $composableBuilder(
    column: $table.embedding,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get occurrences => $composableBuilder(
    column: $table.occurrences,
    builder: (column) => ColumnFilters(column),
  );
}

class $$FaceSuppressionsTableOrderingComposer
    extends Composer<_$AppDatabase, $FaceSuppressionsTable> {
  $$FaceSuppressionsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get assetId => $composableBuilder(
    column: $table.assetId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get modelId => $composableBuilder(
    column: $table.modelId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<Uint8List> get embedding => $composableBuilder(
    column: $table.embedding,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get occurrences => $composableBuilder(
    column: $table.occurrences,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$FaceSuppressionsTableAnnotationComposer
    extends Composer<_$AppDatabase, $FaceSuppressionsTable> {
  $$FaceSuppressionsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get assetId =>
      $composableBuilder(column: $table.assetId, builder: (column) => column);

  GeneratedColumn<String> get modelId =>
      $composableBuilder(column: $table.modelId, builder: (column) => column);

  GeneratedColumn<Uint8List> get embedding =>
      $composableBuilder(column: $table.embedding, builder: (column) => column);

  GeneratedColumn<String> get occurrences => $composableBuilder(
    column: $table.occurrences,
    builder: (column) => column,
  );
}

class $$FaceSuppressionsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $FaceSuppressionsTable,
          FaceSuppressionRow,
          $$FaceSuppressionsTableFilterComposer,
          $$FaceSuppressionsTableOrderingComposer,
          $$FaceSuppressionsTableAnnotationComposer,
          $$FaceSuppressionsTableCreateCompanionBuilder,
          $$FaceSuppressionsTableUpdateCompanionBuilder,
          (
            FaceSuppressionRow,
            BaseReferences<
              _$AppDatabase,
              $FaceSuppressionsTable,
              FaceSuppressionRow
            >,
          ),
          FaceSuppressionRow,
          PrefetchHooks Function()
        > {
  $$FaceSuppressionsTableTableManager(
    _$AppDatabase db,
    $FaceSuppressionsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$FaceSuppressionsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$FaceSuppressionsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$FaceSuppressionsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> assetId = const Value.absent(),
                Value<String> modelId = const Value.absent(),
                Value<Uint8List> embedding = const Value.absent(),
                Value<String> occurrences = const Value.absent(),
              }) => FaceSuppressionsCompanion(
                id: id,
                assetId: assetId,
                modelId: modelId,
                embedding: embedding,
                occurrences: occurrences,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String assetId,
                required String modelId,
                required Uint8List embedding,
                required String occurrences,
              }) => FaceSuppressionsCompanion.insert(
                id: id,
                assetId: assetId,
                modelId: modelId,
                embedding: embedding,
                occurrences: occurrences,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$FaceSuppressionsTable, FaceSuppressionRow>(
                    table,
                  ),
                  BaseReferences<
                    _$AppDatabase,
                    $FaceSuppressionsTable,
                    FaceSuppressionRow
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$FaceSuppressionsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $FaceSuppressionsTable,
      FaceSuppressionRow,
      $$FaceSuppressionsTableFilterComposer,
      $$FaceSuppressionsTableOrderingComposer,
      $$FaceSuppressionsTableAnnotationComposer,
      $$FaceSuppressionsTableCreateCompanionBuilder,
      $$FaceSuppressionsTableUpdateCompanionBuilder,
      (
        FaceSuppressionRow,
        BaseReferences<
          _$AppDatabase,
          $FaceSuppressionsTable,
          FaceSuppressionRow
        >,
      ),
      FaceSuppressionRow,
      PrefetchHooks Function()
    >;
typedef $$BodiesTableCreateCompanionBuilder =
    BodiesCompanion Function({
      Value<int> id,
      Value<int?> mediaId,
      Value<int?> faceId,
      Value<int?> personId,
      required double bboxX,
      required double bboxY,
      required double bboxW,
      required double bboxH,
      required double score,
      Value<String?> kpts,
      Value<String?> extent,
      Value<Uint8List?> appearance,
      Value<String?> linkMethod,
      Value<double?> linkConfidence,
      Value<Uint8List?> weakFaceEmbedding,
      Value<double?> weakFaceQuality,
      Value<int?> frameNumber,
      Value<int?> timestampMs,
      Value<String?> cropPath,
      required int createdAt,
    });
typedef $$BodiesTableUpdateCompanionBuilder =
    BodiesCompanion Function({
      Value<int> id,
      Value<int?> mediaId,
      Value<int?> faceId,
      Value<int?> personId,
      Value<double> bboxX,
      Value<double> bboxY,
      Value<double> bboxW,
      Value<double> bboxH,
      Value<double> score,
      Value<String?> kpts,
      Value<String?> extent,
      Value<Uint8List?> appearance,
      Value<String?> linkMethod,
      Value<double?> linkConfidence,
      Value<Uint8List?> weakFaceEmbedding,
      Value<double?> weakFaceQuality,
      Value<int?> frameNumber,
      Value<int?> timestampMs,
      Value<String?> cropPath,
      Value<int> createdAt,
    });

final class $$BodiesTableReferences
    extends BaseReferences<_$AppDatabase, $BodiesTable, BodyRow> {
  $$BodiesTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $MediaTable _mediaIdTable(_$AppDatabase db) =>
      db.media.createAlias('bodies__media_id__media__id');

  $$MediaTableProcessedTableManager? get mediaId {
    final $_column = $_itemColumn<int>('media_id');
    if ($_column == null) return null;
    final manager = $$MediaTableTableManager(
      $_db,
      $_db.media,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_mediaIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static $FacesTable _faceIdTable(_$AppDatabase db) =>
      db.faces.createAlias('bodies__face_id__faces__id');

  $$FacesTableProcessedTableManager? get faceId {
    final $_column = $_itemColumn<int>('face_id');
    if ($_column == null) return null;
    final manager = $$FacesTableTableManager(
      $_db,
      $_db.faces,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_faceIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static $PersonsTable _personIdTable(_$AppDatabase db) =>
      db.persons.createAlias('bodies__person_id__persons__id');

  $$PersonsTableProcessedTableManager? get personId {
    final $_column = $_itemColumn<int>('person_id');
    if ($_column == null) return null;
    final manager = $$PersonsTableTableManager(
      $_db,
      $_db.persons,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_personIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static MultiTypedResultKey<$BodyRejectionsTable, List<BodyRejectionRow>>
  _bodyRejectionsRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.bodyRejections,
    aliasName: 'bodies__id__body_rejections__body_id',
  );

  $$BodyRejectionsTableProcessedTableManager get bodyRejectionsRefs {
    final manager = $$BodyRejectionsTableTableManager(
      $_db,
      $_db.bodyRejections,
    ).filter((f) => f.bodyId.id.sqlEquals($_itemColumn<int>('id')!));

    final cache = $_typedResult.readTableOrNull(_bodyRejectionsRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$ReviewBodyLinksTable, List<ReviewBodyLinkRow>>
  _reviewBodyLinksRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.reviewBodyLinks,
    aliasName: 'bodies__id__review_body_links__body_id',
  );

  $$ReviewBodyLinksTableProcessedTableManager get reviewBodyLinksRefs {
    final manager = $$ReviewBodyLinksTableTableManager(
      $_db,
      $_db.reviewBodyLinks,
    ).filter((f) => f.bodyId.id.sqlEquals($_itemColumn<int>('id')!));

    final cache = $_typedResult.readTableOrNull(
      _reviewBodyLinksRefsTable($_db),
    );
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$BodiesTableFilterComposer
    extends Composer<_$AppDatabase, $BodiesTable> {
  $$BodiesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get bboxX => $composableBuilder(
    column: $table.bboxX,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get bboxY => $composableBuilder(
    column: $table.bboxY,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get bboxW => $composableBuilder(
    column: $table.bboxW,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get bboxH => $composableBuilder(
    column: $table.bboxH,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get score => $composableBuilder(
    column: $table.score,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get kpts => $composableBuilder(
    column: $table.kpts,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get extent => $composableBuilder(
    column: $table.extent,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<Uint8List> get appearance => $composableBuilder(
    column: $table.appearance,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get linkMethod => $composableBuilder(
    column: $table.linkMethod,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get linkConfidence => $composableBuilder(
    column: $table.linkConfidence,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<Uint8List> get weakFaceEmbedding => $composableBuilder(
    column: $table.weakFaceEmbedding,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get weakFaceQuality => $composableBuilder(
    column: $table.weakFaceQuality,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get frameNumber => $composableBuilder(
    column: $table.frameNumber,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get timestampMs => $composableBuilder(
    column: $table.timestampMs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get cropPath => $composableBuilder(
    column: $table.cropPath,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  $$MediaTableFilterComposer get mediaId {
    final $$MediaTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.mediaId,
      referencedTable: $db.media,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$MediaTableFilterComposer(
            $db: $db,
            $table: $db.media,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$FacesTableFilterComposer get faceId {
    final $$FacesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.faceId,
      referencedTable: $db.faces,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$FacesTableFilterComposer(
            $db: $db,
            $table: $db.faces,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$PersonsTableFilterComposer get personId {
    final $$PersonsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.personId,
      referencedTable: $db.persons,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$PersonsTableFilterComposer(
            $db: $db,
            $table: $db.persons,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  Expression<bool> bodyRejectionsRefs(
    Expression<bool> Function($$BodyRejectionsTableFilterComposer f) f,
  ) {
    final $$BodyRejectionsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.bodyRejections,
      getReferencedColumn: (t) => t.bodyId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$BodyRejectionsTableFilterComposer(
            $db: $db,
            $table: $db.bodyRejections,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> reviewBodyLinksRefs(
    Expression<bool> Function($$ReviewBodyLinksTableFilterComposer f) f,
  ) {
    final $$ReviewBodyLinksTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.reviewBodyLinks,
      getReferencedColumn: (t) => t.bodyId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ReviewBodyLinksTableFilterComposer(
            $db: $db,
            $table: $db.reviewBodyLinks,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$BodiesTableOrderingComposer
    extends Composer<_$AppDatabase, $BodiesTable> {
  $$BodiesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get bboxX => $composableBuilder(
    column: $table.bboxX,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get bboxY => $composableBuilder(
    column: $table.bboxY,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get bboxW => $composableBuilder(
    column: $table.bboxW,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get bboxH => $composableBuilder(
    column: $table.bboxH,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get score => $composableBuilder(
    column: $table.score,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get kpts => $composableBuilder(
    column: $table.kpts,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get extent => $composableBuilder(
    column: $table.extent,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<Uint8List> get appearance => $composableBuilder(
    column: $table.appearance,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get linkMethod => $composableBuilder(
    column: $table.linkMethod,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get linkConfidence => $composableBuilder(
    column: $table.linkConfidence,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<Uint8List> get weakFaceEmbedding => $composableBuilder(
    column: $table.weakFaceEmbedding,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get weakFaceQuality => $composableBuilder(
    column: $table.weakFaceQuality,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get frameNumber => $composableBuilder(
    column: $table.frameNumber,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get timestampMs => $composableBuilder(
    column: $table.timestampMs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get cropPath => $composableBuilder(
    column: $table.cropPath,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  $$MediaTableOrderingComposer get mediaId {
    final $$MediaTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.mediaId,
      referencedTable: $db.media,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$MediaTableOrderingComposer(
            $db: $db,
            $table: $db.media,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$FacesTableOrderingComposer get faceId {
    final $$FacesTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.faceId,
      referencedTable: $db.faces,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$FacesTableOrderingComposer(
            $db: $db,
            $table: $db.faces,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$PersonsTableOrderingComposer get personId {
    final $$PersonsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.personId,
      referencedTable: $db.persons,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$PersonsTableOrderingComposer(
            $db: $db,
            $table: $db.persons,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$BodiesTableAnnotationComposer
    extends Composer<_$AppDatabase, $BodiesTable> {
  $$BodiesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<double> get bboxX =>
      $composableBuilder(column: $table.bboxX, builder: (column) => column);

  GeneratedColumn<double> get bboxY =>
      $composableBuilder(column: $table.bboxY, builder: (column) => column);

  GeneratedColumn<double> get bboxW =>
      $composableBuilder(column: $table.bboxW, builder: (column) => column);

  GeneratedColumn<double> get bboxH =>
      $composableBuilder(column: $table.bboxH, builder: (column) => column);

  GeneratedColumn<double> get score =>
      $composableBuilder(column: $table.score, builder: (column) => column);

  GeneratedColumn<String> get kpts =>
      $composableBuilder(column: $table.kpts, builder: (column) => column);

  GeneratedColumn<String> get extent =>
      $composableBuilder(column: $table.extent, builder: (column) => column);

  GeneratedColumn<Uint8List> get appearance => $composableBuilder(
    column: $table.appearance,
    builder: (column) => column,
  );

  GeneratedColumn<String> get linkMethod => $composableBuilder(
    column: $table.linkMethod,
    builder: (column) => column,
  );

  GeneratedColumn<double> get linkConfidence => $composableBuilder(
    column: $table.linkConfidence,
    builder: (column) => column,
  );

  GeneratedColumn<Uint8List> get weakFaceEmbedding => $composableBuilder(
    column: $table.weakFaceEmbedding,
    builder: (column) => column,
  );

  GeneratedColumn<double> get weakFaceQuality => $composableBuilder(
    column: $table.weakFaceQuality,
    builder: (column) => column,
  );

  GeneratedColumn<int> get frameNumber => $composableBuilder(
    column: $table.frameNumber,
    builder: (column) => column,
  );

  GeneratedColumn<int> get timestampMs => $composableBuilder(
    column: $table.timestampMs,
    builder: (column) => column,
  );

  GeneratedColumn<String> get cropPath =>
      $composableBuilder(column: $table.cropPath, builder: (column) => column);

  GeneratedColumn<int> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  $$MediaTableAnnotationComposer get mediaId {
    final $$MediaTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.mediaId,
      referencedTable: $db.media,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$MediaTableAnnotationComposer(
            $db: $db,
            $table: $db.media,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$FacesTableAnnotationComposer get faceId {
    final $$FacesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.faceId,
      referencedTable: $db.faces,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$FacesTableAnnotationComposer(
            $db: $db,
            $table: $db.faces,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$PersonsTableAnnotationComposer get personId {
    final $$PersonsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.personId,
      referencedTable: $db.persons,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$PersonsTableAnnotationComposer(
            $db: $db,
            $table: $db.persons,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  Expression<T> bodyRejectionsRefs<T extends Object>(
    Expression<T> Function($$BodyRejectionsTableAnnotationComposer a) f,
  ) {
    final $$BodyRejectionsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.bodyRejections,
      getReferencedColumn: (t) => t.bodyId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$BodyRejectionsTableAnnotationComposer(
            $db: $db,
            $table: $db.bodyRejections,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> reviewBodyLinksRefs<T extends Object>(
    Expression<T> Function($$ReviewBodyLinksTableAnnotationComposer a) f,
  ) {
    final $$ReviewBodyLinksTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.reviewBodyLinks,
      getReferencedColumn: (t) => t.bodyId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ReviewBodyLinksTableAnnotationComposer(
            $db: $db,
            $table: $db.reviewBodyLinks,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$BodiesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $BodiesTable,
          BodyRow,
          $$BodiesTableFilterComposer,
          $$BodiesTableOrderingComposer,
          $$BodiesTableAnnotationComposer,
          $$BodiesTableCreateCompanionBuilder,
          $$BodiesTableUpdateCompanionBuilder,
          (BodyRow, $$BodiesTableReferences),
          BodyRow,
          PrefetchHooks Function({
            bool mediaId,
            bool faceId,
            bool personId,
            bool bodyRejectionsRefs,
            bool reviewBodyLinksRefs,
          })
        > {
  $$BodiesTableTableManager(_$AppDatabase db, $BodiesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$BodiesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$BodiesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$BodiesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<int?> mediaId = const Value.absent(),
                Value<int?> faceId = const Value.absent(),
                Value<int?> personId = const Value.absent(),
                Value<double> bboxX = const Value.absent(),
                Value<double> bboxY = const Value.absent(),
                Value<double> bboxW = const Value.absent(),
                Value<double> bboxH = const Value.absent(),
                Value<double> score = const Value.absent(),
                Value<String?> kpts = const Value.absent(),
                Value<String?> extent = const Value.absent(),
                Value<Uint8List?> appearance = const Value.absent(),
                Value<String?> linkMethod = const Value.absent(),
                Value<double?> linkConfidence = const Value.absent(),
                Value<Uint8List?> weakFaceEmbedding = const Value.absent(),
                Value<double?> weakFaceQuality = const Value.absent(),
                Value<int?> frameNumber = const Value.absent(),
                Value<int?> timestampMs = const Value.absent(),
                Value<String?> cropPath = const Value.absent(),
                Value<int> createdAt = const Value.absent(),
              }) => BodiesCompanion(
                id: id,
                mediaId: mediaId,
                faceId: faceId,
                personId: personId,
                bboxX: bboxX,
                bboxY: bboxY,
                bboxW: bboxW,
                bboxH: bboxH,
                score: score,
                kpts: kpts,
                extent: extent,
                appearance: appearance,
                linkMethod: linkMethod,
                linkConfidence: linkConfidence,
                weakFaceEmbedding: weakFaceEmbedding,
                weakFaceQuality: weakFaceQuality,
                frameNumber: frameNumber,
                timestampMs: timestampMs,
                cropPath: cropPath,
                createdAt: createdAt,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<int?> mediaId = const Value.absent(),
                Value<int?> faceId = const Value.absent(),
                Value<int?> personId = const Value.absent(),
                required double bboxX,
                required double bboxY,
                required double bboxW,
                required double bboxH,
                required double score,
                Value<String?> kpts = const Value.absent(),
                Value<String?> extent = const Value.absent(),
                Value<Uint8List?> appearance = const Value.absent(),
                Value<String?> linkMethod = const Value.absent(),
                Value<double?> linkConfidence = const Value.absent(),
                Value<Uint8List?> weakFaceEmbedding = const Value.absent(),
                Value<double?> weakFaceQuality = const Value.absent(),
                Value<int?> frameNumber = const Value.absent(),
                Value<int?> timestampMs = const Value.absent(),
                Value<String?> cropPath = const Value.absent(),
                required int createdAt,
              }) => BodiesCompanion.insert(
                id: id,
                mediaId: mediaId,
                faceId: faceId,
                personId: personId,
                bboxX: bboxX,
                bboxY: bboxY,
                bboxW: bboxW,
                bboxH: bboxH,
                score: score,
                kpts: kpts,
                extent: extent,
                appearance: appearance,
                linkMethod: linkMethod,
                linkConfidence: linkConfidence,
                weakFaceEmbedding: weakFaceEmbedding,
                weakFaceQuality: weakFaceQuality,
                frameNumber: frameNumber,
                timestampMs: timestampMs,
                cropPath: cropPath,
                createdAt: createdAt,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$BodiesTable, BodyRow>(table),
                  $$BodiesTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback:
              ({
                mediaId = false,
                faceId = false,
                personId = false,
                bodyRejectionsRefs = false,
                reviewBodyLinksRefs = false,
              }) {
                return PrefetchHooks(
                  db: db,
                  explicitlyWatchedTables: [
                    if (bodyRejectionsRefs) db.bodyRejections,
                    if (reviewBodyLinksRefs) db.reviewBodyLinks,
                  ],
                  addJoins:
                      <
                        T extends TableManagerState<
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic
                        >
                      >(state) {
                        if (mediaId) {
                          state =
                              state.withJoin(
                                    currentTable: table,
                                    currentColumn: table.mediaId,
                                    referencedTable: $$BodiesTableReferences
                                        ._mediaIdTable(db),
                                    referencedColumn: $$BodiesTableReferences
                                        ._mediaIdTable(db)
                                        .id,
                                  )
                                  as T;
                        }
                        if (faceId) {
                          state =
                              state.withJoin(
                                    currentTable: table,
                                    currentColumn: table.faceId,
                                    referencedTable: $$BodiesTableReferences
                                        ._faceIdTable(db),
                                    referencedColumn: $$BodiesTableReferences
                                        ._faceIdTable(db)
                                        .id,
                                  )
                                  as T;
                        }
                        if (personId) {
                          state =
                              state.withJoin(
                                    currentTable: table,
                                    currentColumn: table.personId,
                                    referencedTable: $$BodiesTableReferences
                                        ._personIdTable(db),
                                    referencedColumn: $$BodiesTableReferences
                                        ._personIdTable(db)
                                        .id,
                                  )
                                  as T;
                        }

                        return state;
                      },
                  getPrefetchedDataCallback: (items) async {
                    return [
                      if (bodyRejectionsRefs)
                        await $_getPrefetchedData<
                          BodyRow,
                          $BodiesTable,
                          BodyRejectionRow
                        >(
                          currentTable: table,
                          referencedTable: $$BodiesTableReferences
                              ._bodyRejectionsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$BodiesTableReferences(
                                db,
                                table,
                                p0,
                              ).bodyRejectionsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.bodyId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (reviewBodyLinksRefs)
                        await $_getPrefetchedData<
                          BodyRow,
                          $BodiesTable,
                          ReviewBodyLinkRow
                        >(
                          currentTable: table,
                          referencedTable: $$BodiesTableReferences
                              ._reviewBodyLinksRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$BodiesTableReferences(
                                db,
                                table,
                                p0,
                              ).reviewBodyLinksRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.bodyId == item.id,
                              ),
                          typedResults: items,
                        ),
                    ];
                  },
                );
              },
        ),
      );
}

typedef $$BodiesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $BodiesTable,
      BodyRow,
      $$BodiesTableFilterComposer,
      $$BodiesTableOrderingComposer,
      $$BodiesTableAnnotationComposer,
      $$BodiesTableCreateCompanionBuilder,
      $$BodiesTableUpdateCompanionBuilder,
      (BodyRow, $$BodiesTableReferences),
      BodyRow,
      PrefetchHooks Function({
        bool mediaId,
        bool faceId,
        bool personId,
        bool bodyRejectionsRefs,
        bool reviewBodyLinksRefs,
      })
    >;
typedef $$FaceRejectionsTableCreateCompanionBuilder =
    FaceRejectionsCompanion Function({
      required int faceId,
      required int personId,
      Value<int> rowid,
    });
typedef $$FaceRejectionsTableUpdateCompanionBuilder =
    FaceRejectionsCompanion Function({
      Value<int> faceId,
      Value<int> personId,
      Value<int> rowid,
    });

final class $$FaceRejectionsTableReferences
    extends
        BaseReferences<_$AppDatabase, $FaceRejectionsTable, FaceRejectionRow> {
  $$FaceRejectionsTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $FacesTable _faceIdTable(_$AppDatabase db) =>
      db.faces.createAlias('face_rejections__face_id__faces__id');

  $$FacesTableProcessedTableManager get faceId {
    final $_column = $_itemColumn<int>('face_id')!;

    final manager = $$FacesTableTableManager(
      $_db,
      $_db.faces,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_faceIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static $PersonsTable _personIdTable(_$AppDatabase db) =>
      db.persons.createAlias('face_rejections__person_id__persons__id');

  $$PersonsTableProcessedTableManager get personId {
    final $_column = $_itemColumn<int>('person_id')!;

    final manager = $$PersonsTableTableManager(
      $_db,
      $_db.persons,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_personIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$FaceRejectionsTableFilterComposer
    extends Composer<_$AppDatabase, $FaceRejectionsTable> {
  $$FaceRejectionsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  $$FacesTableFilterComposer get faceId {
    final $$FacesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.faceId,
      referencedTable: $db.faces,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$FacesTableFilterComposer(
            $db: $db,
            $table: $db.faces,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$PersonsTableFilterComposer get personId {
    final $$PersonsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.personId,
      referencedTable: $db.persons,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$PersonsTableFilterComposer(
            $db: $db,
            $table: $db.persons,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$FaceRejectionsTableOrderingComposer
    extends Composer<_$AppDatabase, $FaceRejectionsTable> {
  $$FaceRejectionsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  $$FacesTableOrderingComposer get faceId {
    final $$FacesTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.faceId,
      referencedTable: $db.faces,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$FacesTableOrderingComposer(
            $db: $db,
            $table: $db.faces,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$PersonsTableOrderingComposer get personId {
    final $$PersonsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.personId,
      referencedTable: $db.persons,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$PersonsTableOrderingComposer(
            $db: $db,
            $table: $db.persons,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$FaceRejectionsTableAnnotationComposer
    extends Composer<_$AppDatabase, $FaceRejectionsTable> {
  $$FaceRejectionsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  $$FacesTableAnnotationComposer get faceId {
    final $$FacesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.faceId,
      referencedTable: $db.faces,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$FacesTableAnnotationComposer(
            $db: $db,
            $table: $db.faces,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$PersonsTableAnnotationComposer get personId {
    final $$PersonsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.personId,
      referencedTable: $db.persons,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$PersonsTableAnnotationComposer(
            $db: $db,
            $table: $db.persons,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$FaceRejectionsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $FaceRejectionsTable,
          FaceRejectionRow,
          $$FaceRejectionsTableFilterComposer,
          $$FaceRejectionsTableOrderingComposer,
          $$FaceRejectionsTableAnnotationComposer,
          $$FaceRejectionsTableCreateCompanionBuilder,
          $$FaceRejectionsTableUpdateCompanionBuilder,
          (FaceRejectionRow, $$FaceRejectionsTableReferences),
          FaceRejectionRow,
          PrefetchHooks Function({bool faceId, bool personId})
        > {
  $$FaceRejectionsTableTableManager(
    _$AppDatabase db,
    $FaceRejectionsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$FaceRejectionsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$FaceRejectionsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$FaceRejectionsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> faceId = const Value.absent(),
                Value<int> personId = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => FaceRejectionsCompanion(
                faceId: faceId,
                personId: personId,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required int faceId,
                required int personId,
                Value<int> rowid = const Value.absent(),
              }) => FaceRejectionsCompanion.insert(
                faceId: faceId,
                personId: personId,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$FaceRejectionsTable, FaceRejectionRow>(table),
                  $$FaceRejectionsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({faceId = false, personId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (faceId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.faceId,
                                referencedTable: $$FaceRejectionsTableReferences
                                    ._faceIdTable(db),
                                referencedColumn:
                                    $$FaceRejectionsTableReferences
                                        ._faceIdTable(db)
                                        .id,
                              )
                              as T;
                    }
                    if (personId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.personId,
                                referencedTable: $$FaceRejectionsTableReferences
                                    ._personIdTable(db),
                                referencedColumn:
                                    $$FaceRejectionsTableReferences
                                        ._personIdTable(db)
                                        .id,
                              )
                              as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$FaceRejectionsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $FaceRejectionsTable,
      FaceRejectionRow,
      $$FaceRejectionsTableFilterComposer,
      $$FaceRejectionsTableOrderingComposer,
      $$FaceRejectionsTableAnnotationComposer,
      $$FaceRejectionsTableCreateCompanionBuilder,
      $$FaceRejectionsTableUpdateCompanionBuilder,
      (FaceRejectionRow, $$FaceRejectionsTableReferences),
      FaceRejectionRow,
      PrefetchHooks Function({bool faceId, bool personId})
    >;
typedef $$BodyRejectionsTableCreateCompanionBuilder =
    BodyRejectionsCompanion Function({
      required int bodyId,
      required int personId,
      Value<int> rowid,
    });
typedef $$BodyRejectionsTableUpdateCompanionBuilder =
    BodyRejectionsCompanion Function({
      Value<int> bodyId,
      Value<int> personId,
      Value<int> rowid,
    });

final class $$BodyRejectionsTableReferences
    extends
        BaseReferences<_$AppDatabase, $BodyRejectionsTable, BodyRejectionRow> {
  $$BodyRejectionsTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $BodiesTable _bodyIdTable(_$AppDatabase db) =>
      db.bodies.createAlias('body_rejections__body_id__bodies__id');

  $$BodiesTableProcessedTableManager get bodyId {
    final $_column = $_itemColumn<int>('body_id')!;

    final manager = $$BodiesTableTableManager(
      $_db,
      $_db.bodies,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_bodyIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static $PersonsTable _personIdTable(_$AppDatabase db) =>
      db.persons.createAlias('body_rejections__person_id__persons__id');

  $$PersonsTableProcessedTableManager get personId {
    final $_column = $_itemColumn<int>('person_id')!;

    final manager = $$PersonsTableTableManager(
      $_db,
      $_db.persons,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_personIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$BodyRejectionsTableFilterComposer
    extends Composer<_$AppDatabase, $BodyRejectionsTable> {
  $$BodyRejectionsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  $$BodiesTableFilterComposer get bodyId {
    final $$BodiesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.bodyId,
      referencedTable: $db.bodies,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$BodiesTableFilterComposer(
            $db: $db,
            $table: $db.bodies,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$PersonsTableFilterComposer get personId {
    final $$PersonsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.personId,
      referencedTable: $db.persons,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$PersonsTableFilterComposer(
            $db: $db,
            $table: $db.persons,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$BodyRejectionsTableOrderingComposer
    extends Composer<_$AppDatabase, $BodyRejectionsTable> {
  $$BodyRejectionsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  $$BodiesTableOrderingComposer get bodyId {
    final $$BodiesTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.bodyId,
      referencedTable: $db.bodies,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$BodiesTableOrderingComposer(
            $db: $db,
            $table: $db.bodies,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$PersonsTableOrderingComposer get personId {
    final $$PersonsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.personId,
      referencedTable: $db.persons,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$PersonsTableOrderingComposer(
            $db: $db,
            $table: $db.persons,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$BodyRejectionsTableAnnotationComposer
    extends Composer<_$AppDatabase, $BodyRejectionsTable> {
  $$BodyRejectionsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  $$BodiesTableAnnotationComposer get bodyId {
    final $$BodiesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.bodyId,
      referencedTable: $db.bodies,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$BodiesTableAnnotationComposer(
            $db: $db,
            $table: $db.bodies,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$PersonsTableAnnotationComposer get personId {
    final $$PersonsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.personId,
      referencedTable: $db.persons,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$PersonsTableAnnotationComposer(
            $db: $db,
            $table: $db.persons,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$BodyRejectionsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $BodyRejectionsTable,
          BodyRejectionRow,
          $$BodyRejectionsTableFilterComposer,
          $$BodyRejectionsTableOrderingComposer,
          $$BodyRejectionsTableAnnotationComposer,
          $$BodyRejectionsTableCreateCompanionBuilder,
          $$BodyRejectionsTableUpdateCompanionBuilder,
          (BodyRejectionRow, $$BodyRejectionsTableReferences),
          BodyRejectionRow,
          PrefetchHooks Function({bool bodyId, bool personId})
        > {
  $$BodyRejectionsTableTableManager(
    _$AppDatabase db,
    $BodyRejectionsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$BodyRejectionsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$BodyRejectionsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$BodyRejectionsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> bodyId = const Value.absent(),
                Value<int> personId = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => BodyRejectionsCompanion(
                bodyId: bodyId,
                personId: personId,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required int bodyId,
                required int personId,
                Value<int> rowid = const Value.absent(),
              }) => BodyRejectionsCompanion.insert(
                bodyId: bodyId,
                personId: personId,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$BodyRejectionsTable, BodyRejectionRow>(table),
                  $$BodyRejectionsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({bodyId = false, personId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (bodyId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.bodyId,
                                referencedTable: $$BodyRejectionsTableReferences
                                    ._bodyIdTable(db),
                                referencedColumn:
                                    $$BodyRejectionsTableReferences
                                        ._bodyIdTable(db)
                                        .id,
                              )
                              as T;
                    }
                    if (personId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.personId,
                                referencedTable: $$BodyRejectionsTableReferences
                                    ._personIdTable(db),
                                referencedColumn:
                                    $$BodyRejectionsTableReferences
                                        ._personIdTable(db)
                                        .id,
                              )
                              as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$BodyRejectionsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $BodyRejectionsTable,
      BodyRejectionRow,
      $$BodyRejectionsTableFilterComposer,
      $$BodyRejectionsTableOrderingComposer,
      $$BodyRejectionsTableAnnotationComposer,
      $$BodyRejectionsTableCreateCompanionBuilder,
      $$BodyRejectionsTableUpdateCompanionBuilder,
      (BodyRejectionRow, $$BodyRejectionsTableReferences),
      BodyRejectionRow,
      PrefetchHooks Function({bool bodyId, bool personId})
    >;
typedef $$PersonDistinctTableCreateCompanionBuilder =
    PersonDistinctCompanion Function({
      required int personA,
      required int personB,
      Value<int> rowid,
    });
typedef $$PersonDistinctTableUpdateCompanionBuilder =
    PersonDistinctCompanion Function({
      Value<int> personA,
      Value<int> personB,
      Value<int> rowid,
    });

final class $$PersonDistinctTableReferences
    extends
        BaseReferences<_$AppDatabase, $PersonDistinctTable, PersonDistinctRow> {
  $$PersonDistinctTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $PersonsTable _personATable(_$AppDatabase db) =>
      db.persons.createAlias('person_distinct__person_a__persons__id');

  $$PersonsTableProcessedTableManager get personA {
    final $_column = $_itemColumn<int>('person_a')!;

    final manager = $$PersonsTableTableManager(
      $_db,
      $_db.persons,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_personATable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static $PersonsTable _personBTable(_$AppDatabase db) =>
      db.persons.createAlias('person_distinct__person_b__persons__id');

  $$PersonsTableProcessedTableManager get personB {
    final $_column = $_itemColumn<int>('person_b')!;

    final manager = $$PersonsTableTableManager(
      $_db,
      $_db.persons,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_personBTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$PersonDistinctTableFilterComposer
    extends Composer<_$AppDatabase, $PersonDistinctTable> {
  $$PersonDistinctTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  $$PersonsTableFilterComposer get personA {
    final $$PersonsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.personA,
      referencedTable: $db.persons,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$PersonsTableFilterComposer(
            $db: $db,
            $table: $db.persons,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$PersonsTableFilterComposer get personB {
    final $$PersonsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.personB,
      referencedTable: $db.persons,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$PersonsTableFilterComposer(
            $db: $db,
            $table: $db.persons,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$PersonDistinctTableOrderingComposer
    extends Composer<_$AppDatabase, $PersonDistinctTable> {
  $$PersonDistinctTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  $$PersonsTableOrderingComposer get personA {
    final $$PersonsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.personA,
      referencedTable: $db.persons,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$PersonsTableOrderingComposer(
            $db: $db,
            $table: $db.persons,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$PersonsTableOrderingComposer get personB {
    final $$PersonsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.personB,
      referencedTable: $db.persons,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$PersonsTableOrderingComposer(
            $db: $db,
            $table: $db.persons,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$PersonDistinctTableAnnotationComposer
    extends Composer<_$AppDatabase, $PersonDistinctTable> {
  $$PersonDistinctTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  $$PersonsTableAnnotationComposer get personA {
    final $$PersonsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.personA,
      referencedTable: $db.persons,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$PersonsTableAnnotationComposer(
            $db: $db,
            $table: $db.persons,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$PersonsTableAnnotationComposer get personB {
    final $$PersonsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.personB,
      referencedTable: $db.persons,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$PersonsTableAnnotationComposer(
            $db: $db,
            $table: $db.persons,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$PersonDistinctTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $PersonDistinctTable,
          PersonDistinctRow,
          $$PersonDistinctTableFilterComposer,
          $$PersonDistinctTableOrderingComposer,
          $$PersonDistinctTableAnnotationComposer,
          $$PersonDistinctTableCreateCompanionBuilder,
          $$PersonDistinctTableUpdateCompanionBuilder,
          (PersonDistinctRow, $$PersonDistinctTableReferences),
          PersonDistinctRow,
          PrefetchHooks Function({bool personA, bool personB})
        > {
  $$PersonDistinctTableTableManager(
    _$AppDatabase db,
    $PersonDistinctTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$PersonDistinctTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$PersonDistinctTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$PersonDistinctTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> personA = const Value.absent(),
                Value<int> personB = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => PersonDistinctCompanion(
                personA: personA,
                personB: personB,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required int personA,
                required int personB,
                Value<int> rowid = const Value.absent(),
              }) => PersonDistinctCompanion.insert(
                personA: personA,
                personB: personB,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$PersonDistinctTable, PersonDistinctRow>(table),
                  $$PersonDistinctTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({personA = false, personB = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (personA) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.personA,
                                referencedTable: $$PersonDistinctTableReferences
                                    ._personATable(db),
                                referencedColumn:
                                    $$PersonDistinctTableReferences
                                        ._personATable(db)
                                        .id,
                              )
                              as T;
                    }
                    if (personB) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.personB,
                                referencedTable: $$PersonDistinctTableReferences
                                    ._personBTable(db),
                                referencedColumn:
                                    $$PersonDistinctTableReferences
                                        ._personBTable(db)
                                        .id,
                              )
                              as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$PersonDistinctTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $PersonDistinctTable,
      PersonDistinctRow,
      $$PersonDistinctTableFilterComposer,
      $$PersonDistinctTableOrderingComposer,
      $$PersonDistinctTableAnnotationComposer,
      $$PersonDistinctTableCreateCompanionBuilder,
      $$PersonDistinctTableUpdateCompanionBuilder,
      (PersonDistinctRow, $$PersonDistinctTableReferences),
      PersonDistinctRow,
      PrefetchHooks Function({bool personA, bool personB})
    >;
typedef $$ServersTableCreateCompanionBuilder =
    ServersCompanion Function({
      required String id,
      required String name,
      required String host,
      required int port,
      required String fingerprint,
      required int pairedAt,
      Value<int?> lastSeenAt,
      Value<int> rowid,
    });
typedef $$ServersTableUpdateCompanionBuilder =
    ServersCompanion Function({
      Value<String> id,
      Value<String> name,
      Value<String> host,
      Value<int> port,
      Value<String> fingerprint,
      Value<int> pairedAt,
      Value<int?> lastSeenAt,
      Value<int> rowid,
    });

class $$ServersTableFilterComposer
    extends Composer<_$AppDatabase, $ServersTable> {
  $$ServersTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get host => $composableBuilder(
    column: $table.host,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get port => $composableBuilder(
    column: $table.port,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get fingerprint => $composableBuilder(
    column: $table.fingerprint,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get pairedAt => $composableBuilder(
    column: $table.pairedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get lastSeenAt => $composableBuilder(
    column: $table.lastSeenAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$ServersTableOrderingComposer
    extends Composer<_$AppDatabase, $ServersTable> {
  $$ServersTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get host => $composableBuilder(
    column: $table.host,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get port => $composableBuilder(
    column: $table.port,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get fingerprint => $composableBuilder(
    column: $table.fingerprint,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get pairedAt => $composableBuilder(
    column: $table.pairedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get lastSeenAt => $composableBuilder(
    column: $table.lastSeenAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$ServersTableAnnotationComposer
    extends Composer<_$AppDatabase, $ServersTable> {
  $$ServersTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get host =>
      $composableBuilder(column: $table.host, builder: (column) => column);

  GeneratedColumn<int> get port =>
      $composableBuilder(column: $table.port, builder: (column) => column);

  GeneratedColumn<String> get fingerprint => $composableBuilder(
    column: $table.fingerprint,
    builder: (column) => column,
  );

  GeneratedColumn<int> get pairedAt =>
      $composableBuilder(column: $table.pairedAt, builder: (column) => column);

  GeneratedColumn<int> get lastSeenAt => $composableBuilder(
    column: $table.lastSeenAt,
    builder: (column) => column,
  );
}

class $$ServersTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $ServersTable,
          ServerRow,
          $$ServersTableFilterComposer,
          $$ServersTableOrderingComposer,
          $$ServersTableAnnotationComposer,
          $$ServersTableCreateCompanionBuilder,
          $$ServersTableUpdateCompanionBuilder,
          (ServerRow, BaseReferences<_$AppDatabase, $ServersTable, ServerRow>),
          ServerRow,
          PrefetchHooks Function()
        > {
  $$ServersTableTableManager(_$AppDatabase db, $ServersTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ServersTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ServersTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ServersTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String> host = const Value.absent(),
                Value<int> port = const Value.absent(),
                Value<String> fingerprint = const Value.absent(),
                Value<int> pairedAt = const Value.absent(),
                Value<int?> lastSeenAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ServersCompanion(
                id: id,
                name: name,
                host: host,
                port: port,
                fingerprint: fingerprint,
                pairedAt: pairedAt,
                lastSeenAt: lastSeenAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String name,
                required String host,
                required int port,
                required String fingerprint,
                required int pairedAt,
                Value<int?> lastSeenAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ServersCompanion.insert(
                id: id,
                name: name,
                host: host,
                port: port,
                fingerprint: fingerprint,
                pairedAt: pairedAt,
                lastSeenAt: lastSeenAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$ServersTable, ServerRow>(table),
                  BaseReferences<_$AppDatabase, $ServersTable, ServerRow>(
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

typedef $$ServersTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $ServersTable,
      ServerRow,
      $$ServersTableFilterComposer,
      $$ServersTableOrderingComposer,
      $$ServersTableAnnotationComposer,
      $$ServersTableCreateCompanionBuilder,
      $$ServersTableUpdateCompanionBuilder,
      (ServerRow, BaseReferences<_$AppDatabase, $ServersTable, ServerRow>),
      ServerRow,
      PrefetchHooks Function()
    >;
typedef $$SettingsTableCreateCompanionBuilder =
    SettingsCompanion Function({
      required String key,
      required String value,
      Value<int> rowid,
    });
typedef $$SettingsTableUpdateCompanionBuilder =
    SettingsCompanion Function({
      Value<String> key,
      Value<String> value,
      Value<int> rowid,
    });

class $$SettingsTableFilterComposer
    extends Composer<_$AppDatabase, $SettingsTable> {
  $$SettingsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get key => $composableBuilder(
    column: $table.key,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get value => $composableBuilder(
    column: $table.value,
    builder: (column) => ColumnFilters(column),
  );
}

class $$SettingsTableOrderingComposer
    extends Composer<_$AppDatabase, $SettingsTable> {
  $$SettingsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get key => $composableBuilder(
    column: $table.key,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get value => $composableBuilder(
    column: $table.value,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$SettingsTableAnnotationComposer
    extends Composer<_$AppDatabase, $SettingsTable> {
  $$SettingsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get key =>
      $composableBuilder(column: $table.key, builder: (column) => column);

  GeneratedColumn<String> get value =>
      $composableBuilder(column: $table.value, builder: (column) => column);
}

class $$SettingsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $SettingsTable,
          SettingRow,
          $$SettingsTableFilterComposer,
          $$SettingsTableOrderingComposer,
          $$SettingsTableAnnotationComposer,
          $$SettingsTableCreateCompanionBuilder,
          $$SettingsTableUpdateCompanionBuilder,
          (
            SettingRow,
            BaseReferences<_$AppDatabase, $SettingsTable, SettingRow>,
          ),
          SettingRow,
          PrefetchHooks Function()
        > {
  $$SettingsTableTableManager(_$AppDatabase db, $SettingsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SettingsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SettingsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SettingsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> key = const Value.absent(),
                Value<String> value = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SettingsCompanion(key: key, value: value, rowid: rowid),
          createCompanionCallback:
              ({
                required String key,
                required String value,
                Value<int> rowid = const Value.absent(),
              }) => SettingsCompanion.insert(
                key: key,
                value: value,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$SettingsTable, SettingRow>(table),
                  BaseReferences<_$AppDatabase, $SettingsTable, SettingRow>(
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

typedef $$SettingsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $SettingsTable,
      SettingRow,
      $$SettingsTableFilterComposer,
      $$SettingsTableOrderingComposer,
      $$SettingsTableAnnotationComposer,
      $$SettingsTableCreateCompanionBuilder,
      $$SettingsTableUpdateCompanionBuilder,
      (SettingRow, BaseReferences<_$AppDatabase, $SettingsTable, SettingRow>),
      SettingRow,
      PrefetchHooks Function()
    >;
typedef $$UploadQueueTableCreateCompanionBuilder =
    UploadQueueCompanion Function({
      Value<int> id,
      required String sha256,
      required String localPath,
      required int sizeBytes,
      Value<int> uploadedBytes,
      Value<String> state,
      Value<int> attempts,
      Value<String?> lastError,
      required int createdAt,
    });
typedef $$UploadQueueTableUpdateCompanionBuilder =
    UploadQueueCompanion Function({
      Value<int> id,
      Value<String> sha256,
      Value<String> localPath,
      Value<int> sizeBytes,
      Value<int> uploadedBytes,
      Value<String> state,
      Value<int> attempts,
      Value<String?> lastError,
      Value<int> createdAt,
    });

class $$UploadQueueTableFilterComposer
    extends Composer<_$AppDatabase, $UploadQueueTable> {
  $$UploadQueueTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get sha256 => $composableBuilder(
    column: $table.sha256,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get localPath => $composableBuilder(
    column: $table.localPath,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get sizeBytes => $composableBuilder(
    column: $table.sizeBytes,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get uploadedBytes => $composableBuilder(
    column: $table.uploadedBytes,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get state => $composableBuilder(
    column: $table.state,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get attempts => $composableBuilder(
    column: $table.attempts,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get lastError => $composableBuilder(
    column: $table.lastError,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$UploadQueueTableOrderingComposer
    extends Composer<_$AppDatabase, $UploadQueueTable> {
  $$UploadQueueTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get sha256 => $composableBuilder(
    column: $table.sha256,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get localPath => $composableBuilder(
    column: $table.localPath,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get sizeBytes => $composableBuilder(
    column: $table.sizeBytes,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get uploadedBytes => $composableBuilder(
    column: $table.uploadedBytes,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get state => $composableBuilder(
    column: $table.state,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get attempts => $composableBuilder(
    column: $table.attempts,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get lastError => $composableBuilder(
    column: $table.lastError,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$UploadQueueTableAnnotationComposer
    extends Composer<_$AppDatabase, $UploadQueueTable> {
  $$UploadQueueTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get sha256 =>
      $composableBuilder(column: $table.sha256, builder: (column) => column);

  GeneratedColumn<String> get localPath =>
      $composableBuilder(column: $table.localPath, builder: (column) => column);

  GeneratedColumn<int> get sizeBytes =>
      $composableBuilder(column: $table.sizeBytes, builder: (column) => column);

  GeneratedColumn<int> get uploadedBytes => $composableBuilder(
    column: $table.uploadedBytes,
    builder: (column) => column,
  );

  GeneratedColumn<String> get state =>
      $composableBuilder(column: $table.state, builder: (column) => column);

  GeneratedColumn<int> get attempts =>
      $composableBuilder(column: $table.attempts, builder: (column) => column);

  GeneratedColumn<String> get lastError =>
      $composableBuilder(column: $table.lastError, builder: (column) => column);

  GeneratedColumn<int> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);
}

class $$UploadQueueTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $UploadQueueTable,
          UploadQueueRow,
          $$UploadQueueTableFilterComposer,
          $$UploadQueueTableOrderingComposer,
          $$UploadQueueTableAnnotationComposer,
          $$UploadQueueTableCreateCompanionBuilder,
          $$UploadQueueTableUpdateCompanionBuilder,
          (
            UploadQueueRow,
            BaseReferences<_$AppDatabase, $UploadQueueTable, UploadQueueRow>,
          ),
          UploadQueueRow,
          PrefetchHooks Function()
        > {
  $$UploadQueueTableTableManager(_$AppDatabase db, $UploadQueueTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$UploadQueueTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$UploadQueueTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$UploadQueueTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> sha256 = const Value.absent(),
                Value<String> localPath = const Value.absent(),
                Value<int> sizeBytes = const Value.absent(),
                Value<int> uploadedBytes = const Value.absent(),
                Value<String> state = const Value.absent(),
                Value<int> attempts = const Value.absent(),
                Value<String?> lastError = const Value.absent(),
                Value<int> createdAt = const Value.absent(),
              }) => UploadQueueCompanion(
                id: id,
                sha256: sha256,
                localPath: localPath,
                sizeBytes: sizeBytes,
                uploadedBytes: uploadedBytes,
                state: state,
                attempts: attempts,
                lastError: lastError,
                createdAt: createdAt,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String sha256,
                required String localPath,
                required int sizeBytes,
                Value<int> uploadedBytes = const Value.absent(),
                Value<String> state = const Value.absent(),
                Value<int> attempts = const Value.absent(),
                Value<String?> lastError = const Value.absent(),
                required int createdAt,
              }) => UploadQueueCompanion.insert(
                id: id,
                sha256: sha256,
                localPath: localPath,
                sizeBytes: sizeBytes,
                uploadedBytes: uploadedBytes,
                state: state,
                attempts: attempts,
                lastError: lastError,
                createdAt: createdAt,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$UploadQueueTable, UploadQueueRow>(table),
                  BaseReferences<
                    _$AppDatabase,
                    $UploadQueueTable,
                    UploadQueueRow
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$UploadQueueTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $UploadQueueTable,
      UploadQueueRow,
      $$UploadQueueTableFilterComposer,
      $$UploadQueueTableOrderingComposer,
      $$UploadQueueTableAnnotationComposer,
      $$UploadQueueTableCreateCompanionBuilder,
      $$UploadQueueTableUpdateCompanionBuilder,
      (
        UploadQueueRow,
        BaseReferences<_$AppDatabase, $UploadQueueTable, UploadQueueRow>,
      ),
      UploadQueueRow,
      PrefetchHooks Function()
    >;
typedef $$BlobHintsTableCreateCompanionBuilder =
    BlobHintsCompanion Function({
      required String sha256,
      required String serverId,
      required int sizeBytes,
      required int lastSeenAt,
      Value<int> rowid,
    });
typedef $$BlobHintsTableUpdateCompanionBuilder =
    BlobHintsCompanion Function({
      Value<String> sha256,
      Value<String> serverId,
      Value<int> sizeBytes,
      Value<int> lastSeenAt,
      Value<int> rowid,
    });

class $$BlobHintsTableFilterComposer
    extends Composer<_$AppDatabase, $BlobHintsTable> {
  $$BlobHintsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get sha256 => $composableBuilder(
    column: $table.sha256,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get serverId => $composableBuilder(
    column: $table.serverId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get sizeBytes => $composableBuilder(
    column: $table.sizeBytes,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get lastSeenAt => $composableBuilder(
    column: $table.lastSeenAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$BlobHintsTableOrderingComposer
    extends Composer<_$AppDatabase, $BlobHintsTable> {
  $$BlobHintsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get sha256 => $composableBuilder(
    column: $table.sha256,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get serverId => $composableBuilder(
    column: $table.serverId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get sizeBytes => $composableBuilder(
    column: $table.sizeBytes,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get lastSeenAt => $composableBuilder(
    column: $table.lastSeenAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$BlobHintsTableAnnotationComposer
    extends Composer<_$AppDatabase, $BlobHintsTable> {
  $$BlobHintsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get sha256 =>
      $composableBuilder(column: $table.sha256, builder: (column) => column);

  GeneratedColumn<String> get serverId =>
      $composableBuilder(column: $table.serverId, builder: (column) => column);

  GeneratedColumn<int> get sizeBytes =>
      $composableBuilder(column: $table.sizeBytes, builder: (column) => column);

  GeneratedColumn<int> get lastSeenAt => $composableBuilder(
    column: $table.lastSeenAt,
    builder: (column) => column,
  );
}

class $$BlobHintsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $BlobHintsTable,
          BlobHintRow,
          $$BlobHintsTableFilterComposer,
          $$BlobHintsTableOrderingComposer,
          $$BlobHintsTableAnnotationComposer,
          $$BlobHintsTableCreateCompanionBuilder,
          $$BlobHintsTableUpdateCompanionBuilder,
          (
            BlobHintRow,
            BaseReferences<_$AppDatabase, $BlobHintsTable, BlobHintRow>,
          ),
          BlobHintRow,
          PrefetchHooks Function()
        > {
  $$BlobHintsTableTableManager(_$AppDatabase db, $BlobHintsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$BlobHintsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$BlobHintsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$BlobHintsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> sha256 = const Value.absent(),
                Value<String> serverId = const Value.absent(),
                Value<int> sizeBytes = const Value.absent(),
                Value<int> lastSeenAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => BlobHintsCompanion(
                sha256: sha256,
                serverId: serverId,
                sizeBytes: sizeBytes,
                lastSeenAt: lastSeenAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String sha256,
                required String serverId,
                required int sizeBytes,
                required int lastSeenAt,
                Value<int> rowid = const Value.absent(),
              }) => BlobHintsCompanion.insert(
                sha256: sha256,
                serverId: serverId,
                sizeBytes: sizeBytes,
                lastSeenAt: lastSeenAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$BlobHintsTable, BlobHintRow>(table),
                  BaseReferences<_$AppDatabase, $BlobHintsTable, BlobHintRow>(
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

typedef $$BlobHintsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $BlobHintsTable,
      BlobHintRow,
      $$BlobHintsTableFilterComposer,
      $$BlobHintsTableOrderingComposer,
      $$BlobHintsTableAnnotationComposer,
      $$BlobHintsTableCreateCompanionBuilder,
      $$BlobHintsTableUpdateCompanionBuilder,
      (
        BlobHintRow,
        BaseReferences<_$AppDatabase, $BlobHintsTable, BlobHintRow>,
      ),
      BlobHintRow,
      PrefetchHooks Function()
    >;
typedef $$MediaDetectionsTableCreateCompanionBuilder =
    MediaDetectionsCompanion Function({
      Value<int> id,
      required int mediaId,
      required String kind,
      required int refId,
      required double x,
      required double y,
      required double w,
      required double h,
      Value<int?> frameNumber,
      Value<int?> timestampMs,
    });
typedef $$MediaDetectionsTableUpdateCompanionBuilder =
    MediaDetectionsCompanion Function({
      Value<int> id,
      Value<int> mediaId,
      Value<String> kind,
      Value<int> refId,
      Value<double> x,
      Value<double> y,
      Value<double> w,
      Value<double> h,
      Value<int?> frameNumber,
      Value<int?> timestampMs,
    });

final class $$MediaDetectionsTableReferences
    extends BaseReferences<_$AppDatabase, $MediaDetectionsTable, DetectionRow> {
  $$MediaDetectionsTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $MediaTable _mediaIdTable(_$AppDatabase db) =>
      db.media.createAlias('media_detections__media_id__media__id');

  $$MediaTableProcessedTableManager get mediaId {
    final $_column = $_itemColumn<int>('media_id')!;

    final manager = $$MediaTableTableManager(
      $_db,
      $_db.media,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_mediaIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$MediaDetectionsTableFilterComposer
    extends Composer<_$AppDatabase, $MediaDetectionsTable> {
  $$MediaDetectionsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get refId => $composableBuilder(
    column: $table.refId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get x => $composableBuilder(
    column: $table.x,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get y => $composableBuilder(
    column: $table.y,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get w => $composableBuilder(
    column: $table.w,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get h => $composableBuilder(
    column: $table.h,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get frameNumber => $composableBuilder(
    column: $table.frameNumber,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get timestampMs => $composableBuilder(
    column: $table.timestampMs,
    builder: (column) => ColumnFilters(column),
  );

  $$MediaTableFilterComposer get mediaId {
    final $$MediaTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.mediaId,
      referencedTable: $db.media,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$MediaTableFilterComposer(
            $db: $db,
            $table: $db.media,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$MediaDetectionsTableOrderingComposer
    extends Composer<_$AppDatabase, $MediaDetectionsTable> {
  $$MediaDetectionsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get refId => $composableBuilder(
    column: $table.refId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get x => $composableBuilder(
    column: $table.x,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get y => $composableBuilder(
    column: $table.y,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get w => $composableBuilder(
    column: $table.w,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get h => $composableBuilder(
    column: $table.h,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get frameNumber => $composableBuilder(
    column: $table.frameNumber,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get timestampMs => $composableBuilder(
    column: $table.timestampMs,
    builder: (column) => ColumnOrderings(column),
  );

  $$MediaTableOrderingComposer get mediaId {
    final $$MediaTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.mediaId,
      referencedTable: $db.media,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$MediaTableOrderingComposer(
            $db: $db,
            $table: $db.media,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$MediaDetectionsTableAnnotationComposer
    extends Composer<_$AppDatabase, $MediaDetectionsTable> {
  $$MediaDetectionsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get kind =>
      $composableBuilder(column: $table.kind, builder: (column) => column);

  GeneratedColumn<int> get refId =>
      $composableBuilder(column: $table.refId, builder: (column) => column);

  GeneratedColumn<double> get x =>
      $composableBuilder(column: $table.x, builder: (column) => column);

  GeneratedColumn<double> get y =>
      $composableBuilder(column: $table.y, builder: (column) => column);

  GeneratedColumn<double> get w =>
      $composableBuilder(column: $table.w, builder: (column) => column);

  GeneratedColumn<double> get h =>
      $composableBuilder(column: $table.h, builder: (column) => column);

  GeneratedColumn<int> get frameNumber => $composableBuilder(
    column: $table.frameNumber,
    builder: (column) => column,
  );

  GeneratedColumn<int> get timestampMs => $composableBuilder(
    column: $table.timestampMs,
    builder: (column) => column,
  );

  $$MediaTableAnnotationComposer get mediaId {
    final $$MediaTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.mediaId,
      referencedTable: $db.media,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$MediaTableAnnotationComposer(
            $db: $db,
            $table: $db.media,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$MediaDetectionsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $MediaDetectionsTable,
          DetectionRow,
          $$MediaDetectionsTableFilterComposer,
          $$MediaDetectionsTableOrderingComposer,
          $$MediaDetectionsTableAnnotationComposer,
          $$MediaDetectionsTableCreateCompanionBuilder,
          $$MediaDetectionsTableUpdateCompanionBuilder,
          (DetectionRow, $$MediaDetectionsTableReferences),
          DetectionRow,
          PrefetchHooks Function({bool mediaId})
        > {
  $$MediaDetectionsTableTableManager(
    _$AppDatabase db,
    $MediaDetectionsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$MediaDetectionsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$MediaDetectionsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$MediaDetectionsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<int> mediaId = const Value.absent(),
                Value<String> kind = const Value.absent(),
                Value<int> refId = const Value.absent(),
                Value<double> x = const Value.absent(),
                Value<double> y = const Value.absent(),
                Value<double> w = const Value.absent(),
                Value<double> h = const Value.absent(),
                Value<int?> frameNumber = const Value.absent(),
                Value<int?> timestampMs = const Value.absent(),
              }) => MediaDetectionsCompanion(
                id: id,
                mediaId: mediaId,
                kind: kind,
                refId: refId,
                x: x,
                y: y,
                w: w,
                h: h,
                frameNumber: frameNumber,
                timestampMs: timestampMs,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required int mediaId,
                required String kind,
                required int refId,
                required double x,
                required double y,
                required double w,
                required double h,
                Value<int?> frameNumber = const Value.absent(),
                Value<int?> timestampMs = const Value.absent(),
              }) => MediaDetectionsCompanion.insert(
                id: id,
                mediaId: mediaId,
                kind: kind,
                refId: refId,
                x: x,
                y: y,
                w: w,
                h: h,
                frameNumber: frameNumber,
                timestampMs: timestampMs,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$MediaDetectionsTable, DetectionRow>(table),
                  $$MediaDetectionsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({mediaId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (mediaId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.mediaId,
                                referencedTable:
                                    $$MediaDetectionsTableReferences
                                        ._mediaIdTable(db),
                                referencedColumn:
                                    $$MediaDetectionsTableReferences
                                        ._mediaIdTable(db)
                                        .id,
                              )
                              as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$MediaDetectionsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $MediaDetectionsTable,
      DetectionRow,
      $$MediaDetectionsTableFilterComposer,
      $$MediaDetectionsTableOrderingComposer,
      $$MediaDetectionsTableAnnotationComposer,
      $$MediaDetectionsTableCreateCompanionBuilder,
      $$MediaDetectionsTableUpdateCompanionBuilder,
      (DetectionRow, $$MediaDetectionsTableReferences),
      DetectionRow,
      PrefetchHooks Function({bool mediaId})
    >;
typedef $$ReviewMatchesTableCreateCompanionBuilder =
    ReviewMatchesCompanion Function({
      Value<int> faceId,
      required int personId,
      required double score,
      required double margin,
      required String decision,
    });
typedef $$ReviewMatchesTableUpdateCompanionBuilder =
    ReviewMatchesCompanion Function({
      Value<int> faceId,
      Value<int> personId,
      Value<double> score,
      Value<double> margin,
      Value<String> decision,
    });

final class $$ReviewMatchesTableReferences
    extends BaseReferences<_$AppDatabase, $ReviewMatchesTable, ReviewMatchRow> {
  $$ReviewMatchesTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $FacesTable _faceIdTable(_$AppDatabase db) =>
      db.faces.createAlias('review_matches__face_id__faces__id');

  $$FacesTableProcessedTableManager get faceId {
    final $_column = $_itemColumn<int>('face_id')!;

    final manager = $$FacesTableTableManager(
      $_db,
      $_db.faces,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_faceIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static $PersonsTable _personIdTable(_$AppDatabase db) =>
      db.persons.createAlias('review_matches__person_id__persons__id');

  $$PersonsTableProcessedTableManager get personId {
    final $_column = $_itemColumn<int>('person_id')!;

    final manager = $$PersonsTableTableManager(
      $_db,
      $_db.persons,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_personIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$ReviewMatchesTableFilterComposer
    extends Composer<_$AppDatabase, $ReviewMatchesTable> {
  $$ReviewMatchesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<double> get score => $composableBuilder(
    column: $table.score,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get margin => $composableBuilder(
    column: $table.margin,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get decision => $composableBuilder(
    column: $table.decision,
    builder: (column) => ColumnFilters(column),
  );

  $$FacesTableFilterComposer get faceId {
    final $$FacesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.faceId,
      referencedTable: $db.faces,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$FacesTableFilterComposer(
            $db: $db,
            $table: $db.faces,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$PersonsTableFilterComposer get personId {
    final $$PersonsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.personId,
      referencedTable: $db.persons,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$PersonsTableFilterComposer(
            $db: $db,
            $table: $db.persons,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$ReviewMatchesTableOrderingComposer
    extends Composer<_$AppDatabase, $ReviewMatchesTable> {
  $$ReviewMatchesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<double> get score => $composableBuilder(
    column: $table.score,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get margin => $composableBuilder(
    column: $table.margin,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get decision => $composableBuilder(
    column: $table.decision,
    builder: (column) => ColumnOrderings(column),
  );

  $$FacesTableOrderingComposer get faceId {
    final $$FacesTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.faceId,
      referencedTable: $db.faces,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$FacesTableOrderingComposer(
            $db: $db,
            $table: $db.faces,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$PersonsTableOrderingComposer get personId {
    final $$PersonsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.personId,
      referencedTable: $db.persons,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$PersonsTableOrderingComposer(
            $db: $db,
            $table: $db.persons,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$ReviewMatchesTableAnnotationComposer
    extends Composer<_$AppDatabase, $ReviewMatchesTable> {
  $$ReviewMatchesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<double> get score =>
      $composableBuilder(column: $table.score, builder: (column) => column);

  GeneratedColumn<double> get margin =>
      $composableBuilder(column: $table.margin, builder: (column) => column);

  GeneratedColumn<String> get decision =>
      $composableBuilder(column: $table.decision, builder: (column) => column);

  $$FacesTableAnnotationComposer get faceId {
    final $$FacesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.faceId,
      referencedTable: $db.faces,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$FacesTableAnnotationComposer(
            $db: $db,
            $table: $db.faces,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$PersonsTableAnnotationComposer get personId {
    final $$PersonsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.personId,
      referencedTable: $db.persons,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$PersonsTableAnnotationComposer(
            $db: $db,
            $table: $db.persons,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$ReviewMatchesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $ReviewMatchesTable,
          ReviewMatchRow,
          $$ReviewMatchesTableFilterComposer,
          $$ReviewMatchesTableOrderingComposer,
          $$ReviewMatchesTableAnnotationComposer,
          $$ReviewMatchesTableCreateCompanionBuilder,
          $$ReviewMatchesTableUpdateCompanionBuilder,
          (ReviewMatchRow, $$ReviewMatchesTableReferences),
          ReviewMatchRow,
          PrefetchHooks Function({bool faceId, bool personId})
        > {
  $$ReviewMatchesTableTableManager(_$AppDatabase db, $ReviewMatchesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ReviewMatchesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ReviewMatchesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ReviewMatchesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> faceId = const Value.absent(),
                Value<int> personId = const Value.absent(),
                Value<double> score = const Value.absent(),
                Value<double> margin = const Value.absent(),
                Value<String> decision = const Value.absent(),
              }) => ReviewMatchesCompanion(
                faceId: faceId,
                personId: personId,
                score: score,
                margin: margin,
                decision: decision,
              ),
          createCompanionCallback:
              ({
                Value<int> faceId = const Value.absent(),
                required int personId,
                required double score,
                required double margin,
                required String decision,
              }) => ReviewMatchesCompanion.insert(
                faceId: faceId,
                personId: personId,
                score: score,
                margin: margin,
                decision: decision,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$ReviewMatchesTable, ReviewMatchRow>(table),
                  $$ReviewMatchesTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({faceId = false, personId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (faceId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.faceId,
                                referencedTable: $$ReviewMatchesTableReferences
                                    ._faceIdTable(db),
                                referencedColumn: $$ReviewMatchesTableReferences
                                    ._faceIdTable(db)
                                    .id,
                              )
                              as T;
                    }
                    if (personId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.personId,
                                referencedTable: $$ReviewMatchesTableReferences
                                    ._personIdTable(db),
                                referencedColumn: $$ReviewMatchesTableReferences
                                    ._personIdTable(db)
                                    .id,
                              )
                              as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$ReviewMatchesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $ReviewMatchesTable,
      ReviewMatchRow,
      $$ReviewMatchesTableFilterComposer,
      $$ReviewMatchesTableOrderingComposer,
      $$ReviewMatchesTableAnnotationComposer,
      $$ReviewMatchesTableCreateCompanionBuilder,
      $$ReviewMatchesTableUpdateCompanionBuilder,
      (ReviewMatchRow, $$ReviewMatchesTableReferences),
      ReviewMatchRow,
      PrefetchHooks Function({bool faceId, bool personId})
    >;
typedef $$ReviewGroupsTableCreateCompanionBuilder =
    ReviewGroupsCompanion Function({
      Value<int> id,
      required String faceIds,
      required double cohesion,
      required double quality,
      Value<bool> autoCreate,
    });
typedef $$ReviewGroupsTableUpdateCompanionBuilder =
    ReviewGroupsCompanion Function({
      Value<int> id,
      Value<String> faceIds,
      Value<double> cohesion,
      Value<double> quality,
      Value<bool> autoCreate,
    });

class $$ReviewGroupsTableFilterComposer
    extends Composer<_$AppDatabase, $ReviewGroupsTable> {
  $$ReviewGroupsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get faceIds => $composableBuilder(
    column: $table.faceIds,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get cohesion => $composableBuilder(
    column: $table.cohesion,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get quality => $composableBuilder(
    column: $table.quality,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get autoCreate => $composableBuilder(
    column: $table.autoCreate,
    builder: (column) => ColumnFilters(column),
  );
}

class $$ReviewGroupsTableOrderingComposer
    extends Composer<_$AppDatabase, $ReviewGroupsTable> {
  $$ReviewGroupsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get faceIds => $composableBuilder(
    column: $table.faceIds,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get cohesion => $composableBuilder(
    column: $table.cohesion,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get quality => $composableBuilder(
    column: $table.quality,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get autoCreate => $composableBuilder(
    column: $table.autoCreate,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$ReviewGroupsTableAnnotationComposer
    extends Composer<_$AppDatabase, $ReviewGroupsTable> {
  $$ReviewGroupsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get faceIds =>
      $composableBuilder(column: $table.faceIds, builder: (column) => column);

  GeneratedColumn<double> get cohesion =>
      $composableBuilder(column: $table.cohesion, builder: (column) => column);

  GeneratedColumn<double> get quality =>
      $composableBuilder(column: $table.quality, builder: (column) => column);

  GeneratedColumn<bool> get autoCreate => $composableBuilder(
    column: $table.autoCreate,
    builder: (column) => column,
  );
}

class $$ReviewGroupsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $ReviewGroupsTable,
          ReviewGroupRow,
          $$ReviewGroupsTableFilterComposer,
          $$ReviewGroupsTableOrderingComposer,
          $$ReviewGroupsTableAnnotationComposer,
          $$ReviewGroupsTableCreateCompanionBuilder,
          $$ReviewGroupsTableUpdateCompanionBuilder,
          (
            ReviewGroupRow,
            BaseReferences<_$AppDatabase, $ReviewGroupsTable, ReviewGroupRow>,
          ),
          ReviewGroupRow,
          PrefetchHooks Function()
        > {
  $$ReviewGroupsTableTableManager(_$AppDatabase db, $ReviewGroupsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ReviewGroupsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ReviewGroupsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ReviewGroupsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> faceIds = const Value.absent(),
                Value<double> cohesion = const Value.absent(),
                Value<double> quality = const Value.absent(),
                Value<bool> autoCreate = const Value.absent(),
              }) => ReviewGroupsCompanion(
                id: id,
                faceIds: faceIds,
                cohesion: cohesion,
                quality: quality,
                autoCreate: autoCreate,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String faceIds,
                required double cohesion,
                required double quality,
                Value<bool> autoCreate = const Value.absent(),
              }) => ReviewGroupsCompanion.insert(
                id: id,
                faceIds: faceIds,
                cohesion: cohesion,
                quality: quality,
                autoCreate: autoCreate,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$ReviewGroupsTable, ReviewGroupRow>(table),
                  BaseReferences<
                    _$AppDatabase,
                    $ReviewGroupsTable,
                    ReviewGroupRow
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$ReviewGroupsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $ReviewGroupsTable,
      ReviewGroupRow,
      $$ReviewGroupsTableFilterComposer,
      $$ReviewGroupsTableOrderingComposer,
      $$ReviewGroupsTableAnnotationComposer,
      $$ReviewGroupsTableCreateCompanionBuilder,
      $$ReviewGroupsTableUpdateCompanionBuilder,
      (
        ReviewGroupRow,
        BaseReferences<_$AppDatabase, $ReviewGroupsTable, ReviewGroupRow>,
      ),
      ReviewGroupRow,
      PrefetchHooks Function()
    >;
typedef $$ReviewDuplicatesTableCreateCompanionBuilder =
    ReviewDuplicatesCompanion Function({
      required int personA,
      required int personB,
      required double score,
      Value<int> rowid,
    });
typedef $$ReviewDuplicatesTableUpdateCompanionBuilder =
    ReviewDuplicatesCompanion Function({
      Value<int> personA,
      Value<int> personB,
      Value<double> score,
      Value<int> rowid,
    });

final class $$ReviewDuplicatesTableReferences
    extends
        BaseReferences<
          _$AppDatabase,
          $ReviewDuplicatesTable,
          ReviewDuplicateRow
        > {
  $$ReviewDuplicatesTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $PersonsTable _personATable(_$AppDatabase db) =>
      db.persons.createAlias('review_duplicates__person_a__persons__id');

  $$PersonsTableProcessedTableManager get personA {
    final $_column = $_itemColumn<int>('person_a')!;

    final manager = $$PersonsTableTableManager(
      $_db,
      $_db.persons,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_personATable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static $PersonsTable _personBTable(_$AppDatabase db) =>
      db.persons.createAlias('review_duplicates__person_b__persons__id');

  $$PersonsTableProcessedTableManager get personB {
    final $_column = $_itemColumn<int>('person_b')!;

    final manager = $$PersonsTableTableManager(
      $_db,
      $_db.persons,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_personBTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$ReviewDuplicatesTableFilterComposer
    extends Composer<_$AppDatabase, $ReviewDuplicatesTable> {
  $$ReviewDuplicatesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<double> get score => $composableBuilder(
    column: $table.score,
    builder: (column) => ColumnFilters(column),
  );

  $$PersonsTableFilterComposer get personA {
    final $$PersonsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.personA,
      referencedTable: $db.persons,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$PersonsTableFilterComposer(
            $db: $db,
            $table: $db.persons,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$PersonsTableFilterComposer get personB {
    final $$PersonsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.personB,
      referencedTable: $db.persons,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$PersonsTableFilterComposer(
            $db: $db,
            $table: $db.persons,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$ReviewDuplicatesTableOrderingComposer
    extends Composer<_$AppDatabase, $ReviewDuplicatesTable> {
  $$ReviewDuplicatesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<double> get score => $composableBuilder(
    column: $table.score,
    builder: (column) => ColumnOrderings(column),
  );

  $$PersonsTableOrderingComposer get personA {
    final $$PersonsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.personA,
      referencedTable: $db.persons,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$PersonsTableOrderingComposer(
            $db: $db,
            $table: $db.persons,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$PersonsTableOrderingComposer get personB {
    final $$PersonsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.personB,
      referencedTable: $db.persons,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$PersonsTableOrderingComposer(
            $db: $db,
            $table: $db.persons,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$ReviewDuplicatesTableAnnotationComposer
    extends Composer<_$AppDatabase, $ReviewDuplicatesTable> {
  $$ReviewDuplicatesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<double> get score =>
      $composableBuilder(column: $table.score, builder: (column) => column);

  $$PersonsTableAnnotationComposer get personA {
    final $$PersonsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.personA,
      referencedTable: $db.persons,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$PersonsTableAnnotationComposer(
            $db: $db,
            $table: $db.persons,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$PersonsTableAnnotationComposer get personB {
    final $$PersonsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.personB,
      referencedTable: $db.persons,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$PersonsTableAnnotationComposer(
            $db: $db,
            $table: $db.persons,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$ReviewDuplicatesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $ReviewDuplicatesTable,
          ReviewDuplicateRow,
          $$ReviewDuplicatesTableFilterComposer,
          $$ReviewDuplicatesTableOrderingComposer,
          $$ReviewDuplicatesTableAnnotationComposer,
          $$ReviewDuplicatesTableCreateCompanionBuilder,
          $$ReviewDuplicatesTableUpdateCompanionBuilder,
          (ReviewDuplicateRow, $$ReviewDuplicatesTableReferences),
          ReviewDuplicateRow,
          PrefetchHooks Function({bool personA, bool personB})
        > {
  $$ReviewDuplicatesTableTableManager(
    _$AppDatabase db,
    $ReviewDuplicatesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ReviewDuplicatesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ReviewDuplicatesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ReviewDuplicatesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> personA = const Value.absent(),
                Value<int> personB = const Value.absent(),
                Value<double> score = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ReviewDuplicatesCompanion(
                personA: personA,
                personB: personB,
                score: score,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required int personA,
                required int personB,
                required double score,
                Value<int> rowid = const Value.absent(),
              }) => ReviewDuplicatesCompanion.insert(
                personA: personA,
                personB: personB,
                score: score,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$ReviewDuplicatesTable, ReviewDuplicateRow>(
                    table,
                  ),
                  $$ReviewDuplicatesTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({personA = false, personB = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (personA) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.personA,
                                referencedTable:
                                    $$ReviewDuplicatesTableReferences
                                        ._personATable(db),
                                referencedColumn:
                                    $$ReviewDuplicatesTableReferences
                                        ._personATable(db)
                                        .id,
                              )
                              as T;
                    }
                    if (personB) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.personB,
                                referencedTable:
                                    $$ReviewDuplicatesTableReferences
                                        ._personBTable(db),
                                referencedColumn:
                                    $$ReviewDuplicatesTableReferences
                                        ._personBTable(db)
                                        .id,
                              )
                              as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$ReviewDuplicatesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $ReviewDuplicatesTable,
      ReviewDuplicateRow,
      $$ReviewDuplicatesTableFilterComposer,
      $$ReviewDuplicatesTableOrderingComposer,
      $$ReviewDuplicatesTableAnnotationComposer,
      $$ReviewDuplicatesTableCreateCompanionBuilder,
      $$ReviewDuplicatesTableUpdateCompanionBuilder,
      (ReviewDuplicateRow, $$ReviewDuplicatesTableReferences),
      ReviewDuplicateRow,
      PrefetchHooks Function({bool personA, bool personB})
    >;
typedef $$ReviewBodyLinksTableCreateCompanionBuilder =
    ReviewBodyLinksCompanion Function({
      Value<int> bodyId,
      required int personId,
      required String method,
      required double confidence,
    });
typedef $$ReviewBodyLinksTableUpdateCompanionBuilder =
    ReviewBodyLinksCompanion Function({
      Value<int> bodyId,
      Value<int> personId,
      Value<String> method,
      Value<double> confidence,
    });

final class $$ReviewBodyLinksTableReferences
    extends
        BaseReferences<
          _$AppDatabase,
          $ReviewBodyLinksTable,
          ReviewBodyLinkRow
        > {
  $$ReviewBodyLinksTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $BodiesTable _bodyIdTable(_$AppDatabase db) =>
      db.bodies.createAlias('review_body_links__body_id__bodies__id');

  $$BodiesTableProcessedTableManager get bodyId {
    final $_column = $_itemColumn<int>('body_id')!;

    final manager = $$BodiesTableTableManager(
      $_db,
      $_db.bodies,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_bodyIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static $PersonsTable _personIdTable(_$AppDatabase db) =>
      db.persons.createAlias('review_body_links__person_id__persons__id');

  $$PersonsTableProcessedTableManager get personId {
    final $_column = $_itemColumn<int>('person_id')!;

    final manager = $$PersonsTableTableManager(
      $_db,
      $_db.persons,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_personIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$ReviewBodyLinksTableFilterComposer
    extends Composer<_$AppDatabase, $ReviewBodyLinksTable> {
  $$ReviewBodyLinksTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get method => $composableBuilder(
    column: $table.method,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get confidence => $composableBuilder(
    column: $table.confidence,
    builder: (column) => ColumnFilters(column),
  );

  $$BodiesTableFilterComposer get bodyId {
    final $$BodiesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.bodyId,
      referencedTable: $db.bodies,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$BodiesTableFilterComposer(
            $db: $db,
            $table: $db.bodies,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$PersonsTableFilterComposer get personId {
    final $$PersonsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.personId,
      referencedTable: $db.persons,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$PersonsTableFilterComposer(
            $db: $db,
            $table: $db.persons,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$ReviewBodyLinksTableOrderingComposer
    extends Composer<_$AppDatabase, $ReviewBodyLinksTable> {
  $$ReviewBodyLinksTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get method => $composableBuilder(
    column: $table.method,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get confidence => $composableBuilder(
    column: $table.confidence,
    builder: (column) => ColumnOrderings(column),
  );

  $$BodiesTableOrderingComposer get bodyId {
    final $$BodiesTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.bodyId,
      referencedTable: $db.bodies,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$BodiesTableOrderingComposer(
            $db: $db,
            $table: $db.bodies,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$PersonsTableOrderingComposer get personId {
    final $$PersonsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.personId,
      referencedTable: $db.persons,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$PersonsTableOrderingComposer(
            $db: $db,
            $table: $db.persons,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$ReviewBodyLinksTableAnnotationComposer
    extends Composer<_$AppDatabase, $ReviewBodyLinksTable> {
  $$ReviewBodyLinksTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get method =>
      $composableBuilder(column: $table.method, builder: (column) => column);

  GeneratedColumn<double> get confidence => $composableBuilder(
    column: $table.confidence,
    builder: (column) => column,
  );

  $$BodiesTableAnnotationComposer get bodyId {
    final $$BodiesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.bodyId,
      referencedTable: $db.bodies,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$BodiesTableAnnotationComposer(
            $db: $db,
            $table: $db.bodies,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$PersonsTableAnnotationComposer get personId {
    final $$PersonsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.personId,
      referencedTable: $db.persons,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$PersonsTableAnnotationComposer(
            $db: $db,
            $table: $db.persons,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$ReviewBodyLinksTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $ReviewBodyLinksTable,
          ReviewBodyLinkRow,
          $$ReviewBodyLinksTableFilterComposer,
          $$ReviewBodyLinksTableOrderingComposer,
          $$ReviewBodyLinksTableAnnotationComposer,
          $$ReviewBodyLinksTableCreateCompanionBuilder,
          $$ReviewBodyLinksTableUpdateCompanionBuilder,
          (ReviewBodyLinkRow, $$ReviewBodyLinksTableReferences),
          ReviewBodyLinkRow,
          PrefetchHooks Function({bool bodyId, bool personId})
        > {
  $$ReviewBodyLinksTableTableManager(
    _$AppDatabase db,
    $ReviewBodyLinksTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ReviewBodyLinksTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ReviewBodyLinksTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ReviewBodyLinksTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> bodyId = const Value.absent(),
                Value<int> personId = const Value.absent(),
                Value<String> method = const Value.absent(),
                Value<double> confidence = const Value.absent(),
              }) => ReviewBodyLinksCompanion(
                bodyId: bodyId,
                personId: personId,
                method: method,
                confidence: confidence,
              ),
          createCompanionCallback:
              ({
                Value<int> bodyId = const Value.absent(),
                required int personId,
                required String method,
                required double confidence,
              }) => ReviewBodyLinksCompanion.insert(
                bodyId: bodyId,
                personId: personId,
                method: method,
                confidence: confidence,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$ReviewBodyLinksTable, ReviewBodyLinkRow>(table),
                  $$ReviewBodyLinksTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({bodyId = false, personId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (bodyId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.bodyId,
                                referencedTable:
                                    $$ReviewBodyLinksTableReferences
                                        ._bodyIdTable(db),
                                referencedColumn:
                                    $$ReviewBodyLinksTableReferences
                                        ._bodyIdTable(db)
                                        .id,
                              )
                              as T;
                    }
                    if (personId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.personId,
                                referencedTable:
                                    $$ReviewBodyLinksTableReferences
                                        ._personIdTable(db),
                                referencedColumn:
                                    $$ReviewBodyLinksTableReferences
                                        ._personIdTable(db)
                                        .id,
                              )
                              as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$ReviewBodyLinksTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $ReviewBodyLinksTable,
      ReviewBodyLinkRow,
      $$ReviewBodyLinksTableFilterComposer,
      $$ReviewBodyLinksTableOrderingComposer,
      $$ReviewBodyLinksTableAnnotationComposer,
      $$ReviewBodyLinksTableCreateCompanionBuilder,
      $$ReviewBodyLinksTableUpdateCompanionBuilder,
      (ReviewBodyLinkRow, $$ReviewBodyLinksTableReferences),
      ReviewBodyLinkRow,
      PrefetchHooks Function({bool bodyId, bool personId})
    >;
typedef $$ReviewSnoozesTableCreateCompanionBuilder =
    ReviewSnoozesCompanion Function({
      required String questionKey,
      required double score,
      required int evidence,
      required int snoozedAt,
      Value<int> rowid,
    });
typedef $$ReviewSnoozesTableUpdateCompanionBuilder =
    ReviewSnoozesCompanion Function({
      Value<String> questionKey,
      Value<double> score,
      Value<int> evidence,
      Value<int> snoozedAt,
      Value<int> rowid,
    });

class $$ReviewSnoozesTableFilterComposer
    extends Composer<_$AppDatabase, $ReviewSnoozesTable> {
  $$ReviewSnoozesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get questionKey => $composableBuilder(
    column: $table.questionKey,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get score => $composableBuilder(
    column: $table.score,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get evidence => $composableBuilder(
    column: $table.evidence,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get snoozedAt => $composableBuilder(
    column: $table.snoozedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$ReviewSnoozesTableOrderingComposer
    extends Composer<_$AppDatabase, $ReviewSnoozesTable> {
  $$ReviewSnoozesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get questionKey => $composableBuilder(
    column: $table.questionKey,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get score => $composableBuilder(
    column: $table.score,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get evidence => $composableBuilder(
    column: $table.evidence,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get snoozedAt => $composableBuilder(
    column: $table.snoozedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$ReviewSnoozesTableAnnotationComposer
    extends Composer<_$AppDatabase, $ReviewSnoozesTable> {
  $$ReviewSnoozesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get questionKey => $composableBuilder(
    column: $table.questionKey,
    builder: (column) => column,
  );

  GeneratedColumn<double> get score =>
      $composableBuilder(column: $table.score, builder: (column) => column);

  GeneratedColumn<int> get evidence =>
      $composableBuilder(column: $table.evidence, builder: (column) => column);

  GeneratedColumn<int> get snoozedAt =>
      $composableBuilder(column: $table.snoozedAt, builder: (column) => column);
}

class $$ReviewSnoozesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $ReviewSnoozesTable,
          ReviewSnoozeRow,
          $$ReviewSnoozesTableFilterComposer,
          $$ReviewSnoozesTableOrderingComposer,
          $$ReviewSnoozesTableAnnotationComposer,
          $$ReviewSnoozesTableCreateCompanionBuilder,
          $$ReviewSnoozesTableUpdateCompanionBuilder,
          (
            ReviewSnoozeRow,
            BaseReferences<_$AppDatabase, $ReviewSnoozesTable, ReviewSnoozeRow>,
          ),
          ReviewSnoozeRow,
          PrefetchHooks Function()
        > {
  $$ReviewSnoozesTableTableManager(_$AppDatabase db, $ReviewSnoozesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ReviewSnoozesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ReviewSnoozesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ReviewSnoozesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> questionKey = const Value.absent(),
                Value<double> score = const Value.absent(),
                Value<int> evidence = const Value.absent(),
                Value<int> snoozedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ReviewSnoozesCompanion(
                questionKey: questionKey,
                score: score,
                evidence: evidence,
                snoozedAt: snoozedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String questionKey,
                required double score,
                required int evidence,
                required int snoozedAt,
                Value<int> rowid = const Value.absent(),
              }) => ReviewSnoozesCompanion.insert(
                questionKey: questionKey,
                score: score,
                evidence: evidence,
                snoozedAt: snoozedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$ReviewSnoozesTable, ReviewSnoozeRow>(table),
                  BaseReferences<
                    _$AppDatabase,
                    $ReviewSnoozesTable,
                    ReviewSnoozeRow
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$ReviewSnoozesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $ReviewSnoozesTable,
      ReviewSnoozeRow,
      $$ReviewSnoozesTableFilterComposer,
      $$ReviewSnoozesTableOrderingComposer,
      $$ReviewSnoozesTableAnnotationComposer,
      $$ReviewSnoozesTableCreateCompanionBuilder,
      $$ReviewSnoozesTableUpdateCompanionBuilder,
      (
        ReviewSnoozeRow,
        BaseReferences<_$AppDatabase, $ReviewSnoozesTable, ReviewSnoozeRow>,
      ),
      ReviewSnoozeRow,
      PrefetchHooks Function()
    >;
typedef $$JobsTableCreateCompanionBuilder =
    JobsCompanion Function({
      required String id,
      required String serverId,
      Value<String?> remoteId,
      required String type,
      required String requestJson,
      Value<String> inputFiles,
      Value<String> detailsJson,
      required String targetPath,
      required String targetSha,
      required int targetSize,
      Value<int?> personId,
      required String status,
      Value<double> progress,
      Value<String?> message,
      Value<String?> error,
      Value<bool> acknowledged,
      required int createdAt,
      required int updatedAt,
      Value<int> rowid,
    });
typedef $$JobsTableUpdateCompanionBuilder =
    JobsCompanion Function({
      Value<String> id,
      Value<String> serverId,
      Value<String?> remoteId,
      Value<String> type,
      Value<String> requestJson,
      Value<String> inputFiles,
      Value<String> detailsJson,
      Value<String> targetPath,
      Value<String> targetSha,
      Value<int> targetSize,
      Value<int?> personId,
      Value<String> status,
      Value<double> progress,
      Value<String?> message,
      Value<String?> error,
      Value<bool> acknowledged,
      Value<int> createdAt,
      Value<int> updatedAt,
      Value<int> rowid,
    });

final class $$JobsTableReferences
    extends BaseReferences<_$AppDatabase, $JobsTable, JobRow> {
  $$JobsTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $PersonsTable _personIdTable(_$AppDatabase db) =>
      db.persons.createAlias('jobs__person_id__persons__id');

  $$PersonsTableProcessedTableManager? get personId {
    final $_column = $_itemColumn<int>('person_id');
    if ($_column == null) return null;
    final manager = $$PersonsTableTableManager(
      $_db,
      $_db.persons,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_personIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static MultiTypedResultKey<$JobEventsTable, List<JobEventRow>>
  _jobEventsRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.jobEvents,
    aliasName: 'jobs__id__job_events__job_id',
  );

  $$JobEventsTableProcessedTableManager get jobEventsRefs {
    final manager = $$JobEventsTableTableManager(
      $_db,
      $_db.jobEvents,
    ).filter((f) => f.jobId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_jobEventsRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$JobsTableFilterComposer extends Composer<_$AppDatabase, $JobsTable> {
  $$JobsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get serverId => $composableBuilder(
    column: $table.serverId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get remoteId => $composableBuilder(
    column: $table.remoteId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get type => $composableBuilder(
    column: $table.type,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get requestJson => $composableBuilder(
    column: $table.requestJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get inputFiles => $composableBuilder(
    column: $table.inputFiles,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get detailsJson => $composableBuilder(
    column: $table.detailsJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get targetPath => $composableBuilder(
    column: $table.targetPath,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get targetSha => $composableBuilder(
    column: $table.targetSha,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get targetSize => $composableBuilder(
    column: $table.targetSize,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get progress => $composableBuilder(
    column: $table.progress,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get message => $composableBuilder(
    column: $table.message,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get error => $composableBuilder(
    column: $table.error,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get acknowledged => $composableBuilder(
    column: $table.acknowledged,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  $$PersonsTableFilterComposer get personId {
    final $$PersonsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.personId,
      referencedTable: $db.persons,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$PersonsTableFilterComposer(
            $db: $db,
            $table: $db.persons,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  Expression<bool> jobEventsRefs(
    Expression<bool> Function($$JobEventsTableFilterComposer f) f,
  ) {
    final $$JobEventsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.jobEvents,
      getReferencedColumn: (t) => t.jobId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$JobEventsTableFilterComposer(
            $db: $db,
            $table: $db.jobEvents,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$JobsTableOrderingComposer extends Composer<_$AppDatabase, $JobsTable> {
  $$JobsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get serverId => $composableBuilder(
    column: $table.serverId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get remoteId => $composableBuilder(
    column: $table.remoteId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get type => $composableBuilder(
    column: $table.type,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get requestJson => $composableBuilder(
    column: $table.requestJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get inputFiles => $composableBuilder(
    column: $table.inputFiles,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get detailsJson => $composableBuilder(
    column: $table.detailsJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get targetPath => $composableBuilder(
    column: $table.targetPath,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get targetSha => $composableBuilder(
    column: $table.targetSha,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get targetSize => $composableBuilder(
    column: $table.targetSize,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get progress => $composableBuilder(
    column: $table.progress,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get message => $composableBuilder(
    column: $table.message,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get error => $composableBuilder(
    column: $table.error,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get acknowledged => $composableBuilder(
    column: $table.acknowledged,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  $$PersonsTableOrderingComposer get personId {
    final $$PersonsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.personId,
      referencedTable: $db.persons,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$PersonsTableOrderingComposer(
            $db: $db,
            $table: $db.persons,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$JobsTableAnnotationComposer
    extends Composer<_$AppDatabase, $JobsTable> {
  $$JobsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get serverId =>
      $composableBuilder(column: $table.serverId, builder: (column) => column);

  GeneratedColumn<String> get remoteId =>
      $composableBuilder(column: $table.remoteId, builder: (column) => column);

  GeneratedColumn<String> get type =>
      $composableBuilder(column: $table.type, builder: (column) => column);

  GeneratedColumn<String> get requestJson => $composableBuilder(
    column: $table.requestJson,
    builder: (column) => column,
  );

  GeneratedColumn<String> get inputFiles => $composableBuilder(
    column: $table.inputFiles,
    builder: (column) => column,
  );

  GeneratedColumn<String> get detailsJson => $composableBuilder(
    column: $table.detailsJson,
    builder: (column) => column,
  );

  GeneratedColumn<String> get targetPath => $composableBuilder(
    column: $table.targetPath,
    builder: (column) => column,
  );

  GeneratedColumn<String> get targetSha =>
      $composableBuilder(column: $table.targetSha, builder: (column) => column);

  GeneratedColumn<int> get targetSize => $composableBuilder(
    column: $table.targetSize,
    builder: (column) => column,
  );

  GeneratedColumn<String> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);

  GeneratedColumn<double> get progress =>
      $composableBuilder(column: $table.progress, builder: (column) => column);

  GeneratedColumn<String> get message =>
      $composableBuilder(column: $table.message, builder: (column) => column);

  GeneratedColumn<String> get error =>
      $composableBuilder(column: $table.error, builder: (column) => column);

  GeneratedColumn<bool> get acknowledged => $composableBuilder(
    column: $table.acknowledged,
    builder: (column) => column,
  );

  GeneratedColumn<int> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<int> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  $$PersonsTableAnnotationComposer get personId {
    final $$PersonsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.personId,
      referencedTable: $db.persons,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$PersonsTableAnnotationComposer(
            $db: $db,
            $table: $db.persons,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  Expression<T> jobEventsRefs<T extends Object>(
    Expression<T> Function($$JobEventsTableAnnotationComposer a) f,
  ) {
    final $$JobEventsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.jobEvents,
      getReferencedColumn: (t) => t.jobId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$JobEventsTableAnnotationComposer(
            $db: $db,
            $table: $db.jobEvents,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$JobsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $JobsTable,
          JobRow,
          $$JobsTableFilterComposer,
          $$JobsTableOrderingComposer,
          $$JobsTableAnnotationComposer,
          $$JobsTableCreateCompanionBuilder,
          $$JobsTableUpdateCompanionBuilder,
          (JobRow, $$JobsTableReferences),
          JobRow,
          PrefetchHooks Function({bool personId, bool jobEventsRefs})
        > {
  $$JobsTableTableManager(_$AppDatabase db, $JobsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$JobsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$JobsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$JobsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> serverId = const Value.absent(),
                Value<String?> remoteId = const Value.absent(),
                Value<String> type = const Value.absent(),
                Value<String> requestJson = const Value.absent(),
                Value<String> inputFiles = const Value.absent(),
                Value<String> detailsJson = const Value.absent(),
                Value<String> targetPath = const Value.absent(),
                Value<String> targetSha = const Value.absent(),
                Value<int> targetSize = const Value.absent(),
                Value<int?> personId = const Value.absent(),
                Value<String> status = const Value.absent(),
                Value<double> progress = const Value.absent(),
                Value<String?> message = const Value.absent(),
                Value<String?> error = const Value.absent(),
                Value<bool> acknowledged = const Value.absent(),
                Value<int> createdAt = const Value.absent(),
                Value<int> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => JobsCompanion(
                id: id,
                serverId: serverId,
                remoteId: remoteId,
                type: type,
                requestJson: requestJson,
                inputFiles: inputFiles,
                detailsJson: detailsJson,
                targetPath: targetPath,
                targetSha: targetSha,
                targetSize: targetSize,
                personId: personId,
                status: status,
                progress: progress,
                message: message,
                error: error,
                acknowledged: acknowledged,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String serverId,
                Value<String?> remoteId = const Value.absent(),
                required String type,
                required String requestJson,
                Value<String> inputFiles = const Value.absent(),
                Value<String> detailsJson = const Value.absent(),
                required String targetPath,
                required String targetSha,
                required int targetSize,
                Value<int?> personId = const Value.absent(),
                required String status,
                Value<double> progress = const Value.absent(),
                Value<String?> message = const Value.absent(),
                Value<String?> error = const Value.absent(),
                Value<bool> acknowledged = const Value.absent(),
                required int createdAt,
                required int updatedAt,
                Value<int> rowid = const Value.absent(),
              }) => JobsCompanion.insert(
                id: id,
                serverId: serverId,
                remoteId: remoteId,
                type: type,
                requestJson: requestJson,
                inputFiles: inputFiles,
                detailsJson: detailsJson,
                targetPath: targetPath,
                targetSha: targetSha,
                targetSize: targetSize,
                personId: personId,
                status: status,
                progress: progress,
                message: message,
                error: error,
                acknowledged: acknowledged,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$JobsTable, JobRow>(table),
                  $$JobsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({personId = false, jobEventsRefs = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [if (jobEventsRefs) db.jobEvents],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (personId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.personId,
                                referencedTable: $$JobsTableReferences
                                    ._personIdTable(db),
                                referencedColumn: $$JobsTableReferences
                                    ._personIdTable(db)
                                    .id,
                              )
                              as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [
                  if (jobEventsRefs)
                    await $_getPrefetchedData<JobRow, $JobsTable, JobEventRow>(
                      currentTable: table,
                      referencedTable: $$JobsTableReferences
                          ._jobEventsRefsTable(db),
                      managerFromTypedResult: (p0) =>
                          $$JobsTableReferences(db, table, p0).jobEventsRefs,
                      referencedItemsForCurrentItem: (item, referencedItems) =>
                          referencedItems.where((e) => e.jobId == item.id),
                      typedResults: items,
                    ),
                ];
              },
            );
          },
        ),
      );
}

typedef $$JobsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $JobsTable,
      JobRow,
      $$JobsTableFilterComposer,
      $$JobsTableOrderingComposer,
      $$JobsTableAnnotationComposer,
      $$JobsTableCreateCompanionBuilder,
      $$JobsTableUpdateCompanionBuilder,
      (JobRow, $$JobsTableReferences),
      JobRow,
      PrefetchHooks Function({bool personId, bool jobEventsRefs})
    >;
typedef $$ResultsTableCreateCompanionBuilder =
    ResultsCompanion Function({
      required String id,
      required String type,
      required String path,
      required String originalPath,
      required String mime,
      required int sizeBytes,
      required String sha256,
      Value<int?> personId,
      Value<bool> favourite,
      required int createdAt,
      Value<int> rowid,
    });
typedef $$ResultsTableUpdateCompanionBuilder =
    ResultsCompanion Function({
      Value<String> id,
      Value<String> type,
      Value<String> path,
      Value<String> originalPath,
      Value<String> mime,
      Value<int> sizeBytes,
      Value<String> sha256,
      Value<int?> personId,
      Value<bool> favourite,
      Value<int> createdAt,
      Value<int> rowid,
    });

final class $$ResultsTableReferences
    extends BaseReferences<_$AppDatabase, $ResultsTable, ResultRow> {
  $$ResultsTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $PersonsTable _personIdTable(_$AppDatabase db) =>
      db.persons.createAlias('results__person_id__persons__id');

  $$PersonsTableProcessedTableManager? get personId {
    final $_column = $_itemColumn<int>('person_id');
    if ($_column == null) return null;
    final manager = $$PersonsTableTableManager(
      $_db,
      $_db.persons,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_personIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$ResultsTableFilterComposer
    extends Composer<_$AppDatabase, $ResultsTable> {
  $$ResultsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get type => $composableBuilder(
    column: $table.type,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get path => $composableBuilder(
    column: $table.path,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get originalPath => $composableBuilder(
    column: $table.originalPath,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get mime => $composableBuilder(
    column: $table.mime,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get sizeBytes => $composableBuilder(
    column: $table.sizeBytes,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get sha256 => $composableBuilder(
    column: $table.sha256,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get favourite => $composableBuilder(
    column: $table.favourite,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  $$PersonsTableFilterComposer get personId {
    final $$PersonsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.personId,
      referencedTable: $db.persons,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$PersonsTableFilterComposer(
            $db: $db,
            $table: $db.persons,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$ResultsTableOrderingComposer
    extends Composer<_$AppDatabase, $ResultsTable> {
  $$ResultsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get type => $composableBuilder(
    column: $table.type,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get path => $composableBuilder(
    column: $table.path,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get originalPath => $composableBuilder(
    column: $table.originalPath,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get mime => $composableBuilder(
    column: $table.mime,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get sizeBytes => $composableBuilder(
    column: $table.sizeBytes,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get sha256 => $composableBuilder(
    column: $table.sha256,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get favourite => $composableBuilder(
    column: $table.favourite,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  $$PersonsTableOrderingComposer get personId {
    final $$PersonsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.personId,
      referencedTable: $db.persons,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$PersonsTableOrderingComposer(
            $db: $db,
            $table: $db.persons,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$ResultsTableAnnotationComposer
    extends Composer<_$AppDatabase, $ResultsTable> {
  $$ResultsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get type =>
      $composableBuilder(column: $table.type, builder: (column) => column);

  GeneratedColumn<String> get path =>
      $composableBuilder(column: $table.path, builder: (column) => column);

  GeneratedColumn<String> get originalPath => $composableBuilder(
    column: $table.originalPath,
    builder: (column) => column,
  );

  GeneratedColumn<String> get mime =>
      $composableBuilder(column: $table.mime, builder: (column) => column);

  GeneratedColumn<int> get sizeBytes =>
      $composableBuilder(column: $table.sizeBytes, builder: (column) => column);

  GeneratedColumn<String> get sha256 =>
      $composableBuilder(column: $table.sha256, builder: (column) => column);

  GeneratedColumn<bool> get favourite =>
      $composableBuilder(column: $table.favourite, builder: (column) => column);

  GeneratedColumn<int> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  $$PersonsTableAnnotationComposer get personId {
    final $$PersonsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.personId,
      referencedTable: $db.persons,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$PersonsTableAnnotationComposer(
            $db: $db,
            $table: $db.persons,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$ResultsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $ResultsTable,
          ResultRow,
          $$ResultsTableFilterComposer,
          $$ResultsTableOrderingComposer,
          $$ResultsTableAnnotationComposer,
          $$ResultsTableCreateCompanionBuilder,
          $$ResultsTableUpdateCompanionBuilder,
          (ResultRow, $$ResultsTableReferences),
          ResultRow,
          PrefetchHooks Function({bool personId})
        > {
  $$ResultsTableTableManager(_$AppDatabase db, $ResultsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ResultsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ResultsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ResultsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> type = const Value.absent(),
                Value<String> path = const Value.absent(),
                Value<String> originalPath = const Value.absent(),
                Value<String> mime = const Value.absent(),
                Value<int> sizeBytes = const Value.absent(),
                Value<String> sha256 = const Value.absent(),
                Value<int?> personId = const Value.absent(),
                Value<bool> favourite = const Value.absent(),
                Value<int> createdAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ResultsCompanion(
                id: id,
                type: type,
                path: path,
                originalPath: originalPath,
                mime: mime,
                sizeBytes: sizeBytes,
                sha256: sha256,
                personId: personId,
                favourite: favourite,
                createdAt: createdAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String type,
                required String path,
                required String originalPath,
                required String mime,
                required int sizeBytes,
                required String sha256,
                Value<int?> personId = const Value.absent(),
                Value<bool> favourite = const Value.absent(),
                required int createdAt,
                Value<int> rowid = const Value.absent(),
              }) => ResultsCompanion.insert(
                id: id,
                type: type,
                path: path,
                originalPath: originalPath,
                mime: mime,
                sizeBytes: sizeBytes,
                sha256: sha256,
                personId: personId,
                favourite: favourite,
                createdAt: createdAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$ResultsTable, ResultRow>(table),
                  $$ResultsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({personId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (personId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.personId,
                                referencedTable: $$ResultsTableReferences
                                    ._personIdTable(db),
                                referencedColumn: $$ResultsTableReferences
                                    ._personIdTable(db)
                                    .id,
                              )
                              as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$ResultsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $ResultsTable,
      ResultRow,
      $$ResultsTableFilterComposer,
      $$ResultsTableOrderingComposer,
      $$ResultsTableAnnotationComposer,
      $$ResultsTableCreateCompanionBuilder,
      $$ResultsTableUpdateCompanionBuilder,
      (ResultRow, $$ResultsTableReferences),
      ResultRow,
      PrefetchHooks Function({bool personId})
    >;
typedef $$DatasetsTableCreateCompanionBuilder =
    DatasetsCompanion Function({
      required String id,
      Value<int?> personId,
      required String triggerWord,
      Value<int> repeats,
      required int createdAt,
      Value<int> rowid,
    });
typedef $$DatasetsTableUpdateCompanionBuilder =
    DatasetsCompanion Function({
      Value<String> id,
      Value<int?> personId,
      Value<String> triggerWord,
      Value<int> repeats,
      Value<int> createdAt,
      Value<int> rowid,
    });

final class $$DatasetsTableReferences
    extends BaseReferences<_$AppDatabase, $DatasetsTable, DatasetRow> {
  $$DatasetsTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $PersonsTable _personIdTable(_$AppDatabase db) =>
      db.persons.createAlias('datasets__person_id__persons__id');

  $$PersonsTableProcessedTableManager? get personId {
    final $_column = $_itemColumn<int>('person_id');
    if ($_column == null) return null;
    final manager = $$PersonsTableTableManager(
      $_db,
      $_db.persons,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_personIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static MultiTypedResultKey<$DatasetItemsTable, List<DatasetItemRow>>
  _datasetItemsRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.datasetItems,
    aliasName: 'datasets__id__dataset_items__dataset_id',
  );

  $$DatasetItemsTableProcessedTableManager get datasetItemsRefs {
    final manager = $$DatasetItemsTableTableManager(
      $_db,
      $_db.datasetItems,
    ).filter((f) => f.datasetId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_datasetItemsRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$DatasetsTableFilterComposer
    extends Composer<_$AppDatabase, $DatasetsTable> {
  $$DatasetsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get triggerWord => $composableBuilder(
    column: $table.triggerWord,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get repeats => $composableBuilder(
    column: $table.repeats,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  $$PersonsTableFilterComposer get personId {
    final $$PersonsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.personId,
      referencedTable: $db.persons,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$PersonsTableFilterComposer(
            $db: $db,
            $table: $db.persons,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  Expression<bool> datasetItemsRefs(
    Expression<bool> Function($$DatasetItemsTableFilterComposer f) f,
  ) {
    final $$DatasetItemsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.datasetItems,
      getReferencedColumn: (t) => t.datasetId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$DatasetItemsTableFilterComposer(
            $db: $db,
            $table: $db.datasetItems,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$DatasetsTableOrderingComposer
    extends Composer<_$AppDatabase, $DatasetsTable> {
  $$DatasetsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get triggerWord => $composableBuilder(
    column: $table.triggerWord,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get repeats => $composableBuilder(
    column: $table.repeats,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  $$PersonsTableOrderingComposer get personId {
    final $$PersonsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.personId,
      referencedTable: $db.persons,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$PersonsTableOrderingComposer(
            $db: $db,
            $table: $db.persons,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$DatasetsTableAnnotationComposer
    extends Composer<_$AppDatabase, $DatasetsTable> {
  $$DatasetsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get triggerWord => $composableBuilder(
    column: $table.triggerWord,
    builder: (column) => column,
  );

  GeneratedColumn<int> get repeats =>
      $composableBuilder(column: $table.repeats, builder: (column) => column);

  GeneratedColumn<int> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  $$PersonsTableAnnotationComposer get personId {
    final $$PersonsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.personId,
      referencedTable: $db.persons,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$PersonsTableAnnotationComposer(
            $db: $db,
            $table: $db.persons,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  Expression<T> datasetItemsRefs<T extends Object>(
    Expression<T> Function($$DatasetItemsTableAnnotationComposer a) f,
  ) {
    final $$DatasetItemsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.datasetItems,
      getReferencedColumn: (t) => t.datasetId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$DatasetItemsTableAnnotationComposer(
            $db: $db,
            $table: $db.datasetItems,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$DatasetsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $DatasetsTable,
          DatasetRow,
          $$DatasetsTableFilterComposer,
          $$DatasetsTableOrderingComposer,
          $$DatasetsTableAnnotationComposer,
          $$DatasetsTableCreateCompanionBuilder,
          $$DatasetsTableUpdateCompanionBuilder,
          (DatasetRow, $$DatasetsTableReferences),
          DatasetRow,
          PrefetchHooks Function({bool personId, bool datasetItemsRefs})
        > {
  $$DatasetsTableTableManager(_$AppDatabase db, $DatasetsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$DatasetsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$DatasetsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$DatasetsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<int?> personId = const Value.absent(),
                Value<String> triggerWord = const Value.absent(),
                Value<int> repeats = const Value.absent(),
                Value<int> createdAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => DatasetsCompanion(
                id: id,
                personId: personId,
                triggerWord: triggerWord,
                repeats: repeats,
                createdAt: createdAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                Value<int?> personId = const Value.absent(),
                required String triggerWord,
                Value<int> repeats = const Value.absent(),
                required int createdAt,
                Value<int> rowid = const Value.absent(),
              }) => DatasetsCompanion.insert(
                id: id,
                personId: personId,
                triggerWord: triggerWord,
                repeats: repeats,
                createdAt: createdAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$DatasetsTable, DatasetRow>(table),
                  $$DatasetsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback:
              ({personId = false, datasetItemsRefs = false}) {
                return PrefetchHooks(
                  db: db,
                  explicitlyWatchedTables: [
                    if (datasetItemsRefs) db.datasetItems,
                  ],
                  addJoins:
                      <
                        T extends TableManagerState<
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic
                        >
                      >(state) {
                        if (personId) {
                          state =
                              state.withJoin(
                                    currentTable: table,
                                    currentColumn: table.personId,
                                    referencedTable: $$DatasetsTableReferences
                                        ._personIdTable(db),
                                    referencedColumn: $$DatasetsTableReferences
                                        ._personIdTable(db)
                                        .id,
                                  )
                                  as T;
                        }

                        return state;
                      },
                  getPrefetchedDataCallback: (items) async {
                    return [
                      if (datasetItemsRefs)
                        await $_getPrefetchedData<
                          DatasetRow,
                          $DatasetsTable,
                          DatasetItemRow
                        >(
                          currentTable: table,
                          referencedTable: $$DatasetsTableReferences
                              ._datasetItemsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$DatasetsTableReferences(
                                db,
                                table,
                                p0,
                              ).datasetItemsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.datasetId == item.id,
                              ),
                          typedResults: items,
                        ),
                    ];
                  },
                );
              },
        ),
      );
}

typedef $$DatasetsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $DatasetsTable,
      DatasetRow,
      $$DatasetsTableFilterComposer,
      $$DatasetsTableOrderingComposer,
      $$DatasetsTableAnnotationComposer,
      $$DatasetsTableCreateCompanionBuilder,
      $$DatasetsTableUpdateCompanionBuilder,
      (DatasetRow, $$DatasetsTableReferences),
      DatasetRow,
      PrefetchHooks Function({bool personId, bool datasetItemsRefs})
    >;
typedef $$DatasetItemsTableCreateCompanionBuilder =
    DatasetItemsCompanion Function({
      Value<int> id,
      required String datasetId,
      required String path,
      required String caption,
      Value<bool> included,
    });
typedef $$DatasetItemsTableUpdateCompanionBuilder =
    DatasetItemsCompanion Function({
      Value<int> id,
      Value<String> datasetId,
      Value<String> path,
      Value<String> caption,
      Value<bool> included,
    });

final class $$DatasetItemsTableReferences
    extends BaseReferences<_$AppDatabase, $DatasetItemsTable, DatasetItemRow> {
  $$DatasetItemsTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $DatasetsTable _datasetIdTable(_$AppDatabase db) =>
      db.datasets.createAlias('dataset_items__dataset_id__datasets__id');

  $$DatasetsTableProcessedTableManager get datasetId {
    final $_column = $_itemColumn<String>('dataset_id')!;

    final manager = $$DatasetsTableTableManager(
      $_db,
      $_db.datasets,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_datasetIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$DatasetItemsTableFilterComposer
    extends Composer<_$AppDatabase, $DatasetItemsTable> {
  $$DatasetItemsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get path => $composableBuilder(
    column: $table.path,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get caption => $composableBuilder(
    column: $table.caption,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get included => $composableBuilder(
    column: $table.included,
    builder: (column) => ColumnFilters(column),
  );

  $$DatasetsTableFilterComposer get datasetId {
    final $$DatasetsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.datasetId,
      referencedTable: $db.datasets,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$DatasetsTableFilterComposer(
            $db: $db,
            $table: $db.datasets,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$DatasetItemsTableOrderingComposer
    extends Composer<_$AppDatabase, $DatasetItemsTable> {
  $$DatasetItemsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get path => $composableBuilder(
    column: $table.path,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get caption => $composableBuilder(
    column: $table.caption,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get included => $composableBuilder(
    column: $table.included,
    builder: (column) => ColumnOrderings(column),
  );

  $$DatasetsTableOrderingComposer get datasetId {
    final $$DatasetsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.datasetId,
      referencedTable: $db.datasets,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$DatasetsTableOrderingComposer(
            $db: $db,
            $table: $db.datasets,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$DatasetItemsTableAnnotationComposer
    extends Composer<_$AppDatabase, $DatasetItemsTable> {
  $$DatasetItemsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get path =>
      $composableBuilder(column: $table.path, builder: (column) => column);

  GeneratedColumn<String> get caption =>
      $composableBuilder(column: $table.caption, builder: (column) => column);

  GeneratedColumn<bool> get included =>
      $composableBuilder(column: $table.included, builder: (column) => column);

  $$DatasetsTableAnnotationComposer get datasetId {
    final $$DatasetsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.datasetId,
      referencedTable: $db.datasets,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$DatasetsTableAnnotationComposer(
            $db: $db,
            $table: $db.datasets,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$DatasetItemsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $DatasetItemsTable,
          DatasetItemRow,
          $$DatasetItemsTableFilterComposer,
          $$DatasetItemsTableOrderingComposer,
          $$DatasetItemsTableAnnotationComposer,
          $$DatasetItemsTableCreateCompanionBuilder,
          $$DatasetItemsTableUpdateCompanionBuilder,
          (DatasetItemRow, $$DatasetItemsTableReferences),
          DatasetItemRow,
          PrefetchHooks Function({bool datasetId})
        > {
  $$DatasetItemsTableTableManager(_$AppDatabase db, $DatasetItemsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$DatasetItemsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$DatasetItemsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$DatasetItemsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> datasetId = const Value.absent(),
                Value<String> path = const Value.absent(),
                Value<String> caption = const Value.absent(),
                Value<bool> included = const Value.absent(),
              }) => DatasetItemsCompanion(
                id: id,
                datasetId: datasetId,
                path: path,
                caption: caption,
                included: included,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String datasetId,
                required String path,
                required String caption,
                Value<bool> included = const Value.absent(),
              }) => DatasetItemsCompanion.insert(
                id: id,
                datasetId: datasetId,
                path: path,
                caption: caption,
                included: included,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$DatasetItemsTable, DatasetItemRow>(table),
                  $$DatasetItemsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({datasetId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (datasetId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.datasetId,
                                referencedTable: $$DatasetItemsTableReferences
                                    ._datasetIdTable(db),
                                referencedColumn: $$DatasetItemsTableReferences
                                    ._datasetIdTable(db)
                                    .id,
                              )
                              as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$DatasetItemsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $DatasetItemsTable,
      DatasetItemRow,
      $$DatasetItemsTableFilterComposer,
      $$DatasetItemsTableOrderingComposer,
      $$DatasetItemsTableAnnotationComposer,
      $$DatasetItemsTableCreateCompanionBuilder,
      $$DatasetItemsTableUpdateCompanionBuilder,
      (DatasetItemRow, $$DatasetItemsTableReferences),
      DatasetItemRow,
      PrefetchHooks Function({bool datasetId})
    >;
typedef $$LorasTableCreateCompanionBuilder =
    LorasCompanion Function({
      required String id,
      Value<int?> personId,
      required String path,
      required String triggerWord,
      Value<String?> identityJson,
      required int createdAt,
      Value<int> rowid,
    });
typedef $$LorasTableUpdateCompanionBuilder =
    LorasCompanion Function({
      Value<String> id,
      Value<int?> personId,
      Value<String> path,
      Value<String> triggerWord,
      Value<String?> identityJson,
      Value<int> createdAt,
      Value<int> rowid,
    });

final class $$LorasTableReferences
    extends BaseReferences<_$AppDatabase, $LorasTable, LoraRow> {
  $$LorasTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $PersonsTable _personIdTable(_$AppDatabase db) =>
      db.persons.createAlias('loras__person_id__persons__id');

  $$PersonsTableProcessedTableManager? get personId {
    final $_column = $_itemColumn<int>('person_id');
    if ($_column == null) return null;
    final manager = $$PersonsTableTableManager(
      $_db,
      $_db.persons,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_personIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$LorasTableFilterComposer extends Composer<_$AppDatabase, $LorasTable> {
  $$LorasTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get path => $composableBuilder(
    column: $table.path,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get triggerWord => $composableBuilder(
    column: $table.triggerWord,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get identityJson => $composableBuilder(
    column: $table.identityJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  $$PersonsTableFilterComposer get personId {
    final $$PersonsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.personId,
      referencedTable: $db.persons,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$PersonsTableFilterComposer(
            $db: $db,
            $table: $db.persons,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$LorasTableOrderingComposer
    extends Composer<_$AppDatabase, $LorasTable> {
  $$LorasTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get path => $composableBuilder(
    column: $table.path,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get triggerWord => $composableBuilder(
    column: $table.triggerWord,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get identityJson => $composableBuilder(
    column: $table.identityJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  $$PersonsTableOrderingComposer get personId {
    final $$PersonsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.personId,
      referencedTable: $db.persons,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$PersonsTableOrderingComposer(
            $db: $db,
            $table: $db.persons,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$LorasTableAnnotationComposer
    extends Composer<_$AppDatabase, $LorasTable> {
  $$LorasTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get path =>
      $composableBuilder(column: $table.path, builder: (column) => column);

  GeneratedColumn<String> get triggerWord => $composableBuilder(
    column: $table.triggerWord,
    builder: (column) => column,
  );

  GeneratedColumn<String> get identityJson => $composableBuilder(
    column: $table.identityJson,
    builder: (column) => column,
  );

  GeneratedColumn<int> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  $$PersonsTableAnnotationComposer get personId {
    final $$PersonsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.personId,
      referencedTable: $db.persons,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$PersonsTableAnnotationComposer(
            $db: $db,
            $table: $db.persons,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$LorasTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $LorasTable,
          LoraRow,
          $$LorasTableFilterComposer,
          $$LorasTableOrderingComposer,
          $$LorasTableAnnotationComposer,
          $$LorasTableCreateCompanionBuilder,
          $$LorasTableUpdateCompanionBuilder,
          (LoraRow, $$LorasTableReferences),
          LoraRow,
          PrefetchHooks Function({bool personId})
        > {
  $$LorasTableTableManager(_$AppDatabase db, $LorasTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$LorasTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$LorasTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$LorasTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<int?> personId = const Value.absent(),
                Value<String> path = const Value.absent(),
                Value<String> triggerWord = const Value.absent(),
                Value<String?> identityJson = const Value.absent(),
                Value<int> createdAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => LorasCompanion(
                id: id,
                personId: personId,
                path: path,
                triggerWord: triggerWord,
                identityJson: identityJson,
                createdAt: createdAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                Value<int?> personId = const Value.absent(),
                required String path,
                required String triggerWord,
                Value<String?> identityJson = const Value.absent(),
                required int createdAt,
                Value<int> rowid = const Value.absent(),
              }) => LorasCompanion.insert(
                id: id,
                personId: personId,
                path: path,
                triggerWord: triggerWord,
                identityJson: identityJson,
                createdAt: createdAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$LorasTable, LoraRow>(table),
                  $$LorasTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({personId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (personId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.personId,
                                referencedTable: $$LorasTableReferences
                                    ._personIdTable(db),
                                referencedColumn: $$LorasTableReferences
                                    ._personIdTable(db)
                                    .id,
                              )
                              as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$LorasTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $LorasTable,
      LoraRow,
      $$LorasTableFilterComposer,
      $$LorasTableOrderingComposer,
      $$LorasTableAnnotationComposer,
      $$LorasTableCreateCompanionBuilder,
      $$LorasTableUpdateCompanionBuilder,
      (LoraRow, $$LorasTableReferences),
      LoraRow,
      PrefetchHooks Function({bool personId})
    >;
typedef $$IdentitySetsTableCreateCompanionBuilder =
    IdentitySetsCompanion Function({
      Value<int> id,
      required int personId,
      required String name,
      required String modelId,
      required int createdAt,
    });
typedef $$IdentitySetsTableUpdateCompanionBuilder =
    IdentitySetsCompanion Function({
      Value<int> id,
      Value<int> personId,
      Value<String> name,
      Value<String> modelId,
      Value<int> createdAt,
    });

final class $$IdentitySetsTableReferences
    extends BaseReferences<_$AppDatabase, $IdentitySetsTable, IdentitySetRow> {
  $$IdentitySetsTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $PersonsTable _personIdTable(_$AppDatabase db) =>
      db.persons.createAlias('identity_sets__person_id__persons__id');

  $$PersonsTableProcessedTableManager get personId {
    final $_column = $_itemColumn<int>('person_id')!;

    final manager = $$PersonsTableTableManager(
      $_db,
      $_db.persons,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_personIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static MultiTypedResultKey<$IdentitySetFacesTable, List<IdentitySetFaceRow>>
  _identitySetFacesRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.identitySetFaces,
    aliasName: 'identity_sets__id__identity_set_faces__set_id',
  );

  $$IdentitySetFacesTableProcessedTableManager get identitySetFacesRefs {
    final manager = $$IdentitySetFacesTableTableManager(
      $_db,
      $_db.identitySetFaces,
    ).filter((f) => f.setId.id.sqlEquals($_itemColumn<int>('id')!));

    final cache = $_typedResult.readTableOrNull(
      _identitySetFacesRefsTable($_db),
    );
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$IdentitySetsTableFilterComposer
    extends Composer<_$AppDatabase, $IdentitySetsTable> {
  $$IdentitySetsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get modelId => $composableBuilder(
    column: $table.modelId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  $$PersonsTableFilterComposer get personId {
    final $$PersonsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.personId,
      referencedTable: $db.persons,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$PersonsTableFilterComposer(
            $db: $db,
            $table: $db.persons,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  Expression<bool> identitySetFacesRefs(
    Expression<bool> Function($$IdentitySetFacesTableFilterComposer f) f,
  ) {
    final $$IdentitySetFacesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.identitySetFaces,
      getReferencedColumn: (t) => t.setId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$IdentitySetFacesTableFilterComposer(
            $db: $db,
            $table: $db.identitySetFaces,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$IdentitySetsTableOrderingComposer
    extends Composer<_$AppDatabase, $IdentitySetsTable> {
  $$IdentitySetsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get modelId => $composableBuilder(
    column: $table.modelId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  $$PersonsTableOrderingComposer get personId {
    final $$PersonsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.personId,
      referencedTable: $db.persons,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$PersonsTableOrderingComposer(
            $db: $db,
            $table: $db.persons,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$IdentitySetsTableAnnotationComposer
    extends Composer<_$AppDatabase, $IdentitySetsTable> {
  $$IdentitySetsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get modelId =>
      $composableBuilder(column: $table.modelId, builder: (column) => column);

  GeneratedColumn<int> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  $$PersonsTableAnnotationComposer get personId {
    final $$PersonsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.personId,
      referencedTable: $db.persons,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$PersonsTableAnnotationComposer(
            $db: $db,
            $table: $db.persons,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  Expression<T> identitySetFacesRefs<T extends Object>(
    Expression<T> Function($$IdentitySetFacesTableAnnotationComposer a) f,
  ) {
    final $$IdentitySetFacesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.identitySetFaces,
      getReferencedColumn: (t) => t.setId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$IdentitySetFacesTableAnnotationComposer(
            $db: $db,
            $table: $db.identitySetFaces,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$IdentitySetsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $IdentitySetsTable,
          IdentitySetRow,
          $$IdentitySetsTableFilterComposer,
          $$IdentitySetsTableOrderingComposer,
          $$IdentitySetsTableAnnotationComposer,
          $$IdentitySetsTableCreateCompanionBuilder,
          $$IdentitySetsTableUpdateCompanionBuilder,
          (IdentitySetRow, $$IdentitySetsTableReferences),
          IdentitySetRow,
          PrefetchHooks Function({bool personId, bool identitySetFacesRefs})
        > {
  $$IdentitySetsTableTableManager(_$AppDatabase db, $IdentitySetsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$IdentitySetsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$IdentitySetsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$IdentitySetsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<int> personId = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String> modelId = const Value.absent(),
                Value<int> createdAt = const Value.absent(),
              }) => IdentitySetsCompanion(
                id: id,
                personId: personId,
                name: name,
                modelId: modelId,
                createdAt: createdAt,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required int personId,
                required String name,
                required String modelId,
                required int createdAt,
              }) => IdentitySetsCompanion.insert(
                id: id,
                personId: personId,
                name: name,
                modelId: modelId,
                createdAt: createdAt,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$IdentitySetsTable, IdentitySetRow>(table),
                  $$IdentitySetsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback:
              ({personId = false, identitySetFacesRefs = false}) {
                return PrefetchHooks(
                  db: db,
                  explicitlyWatchedTables: [
                    if (identitySetFacesRefs) db.identitySetFaces,
                  ],
                  addJoins:
                      <
                        T extends TableManagerState<
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic
                        >
                      >(state) {
                        if (personId) {
                          state =
                              state.withJoin(
                                    currentTable: table,
                                    currentColumn: table.personId,
                                    referencedTable:
                                        $$IdentitySetsTableReferences
                                            ._personIdTable(db),
                                    referencedColumn:
                                        $$IdentitySetsTableReferences
                                            ._personIdTable(db)
                                            .id,
                                  )
                                  as T;
                        }

                        return state;
                      },
                  getPrefetchedDataCallback: (items) async {
                    return [
                      if (identitySetFacesRefs)
                        await $_getPrefetchedData<
                          IdentitySetRow,
                          $IdentitySetsTable,
                          IdentitySetFaceRow
                        >(
                          currentTable: table,
                          referencedTable: $$IdentitySetsTableReferences
                              ._identitySetFacesRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$IdentitySetsTableReferences(
                                db,
                                table,
                                p0,
                              ).identitySetFacesRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.setId == item.id,
                              ),
                          typedResults: items,
                        ),
                    ];
                  },
                );
              },
        ),
      );
}

typedef $$IdentitySetsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $IdentitySetsTable,
      IdentitySetRow,
      $$IdentitySetsTableFilterComposer,
      $$IdentitySetsTableOrderingComposer,
      $$IdentitySetsTableAnnotationComposer,
      $$IdentitySetsTableCreateCompanionBuilder,
      $$IdentitySetsTableUpdateCompanionBuilder,
      (IdentitySetRow, $$IdentitySetsTableReferences),
      IdentitySetRow,
      PrefetchHooks Function({bool personId, bool identitySetFacesRefs})
    >;
typedef $$IdentitySetFacesTableCreateCompanionBuilder =
    IdentitySetFacesCompanion Function({
      required int setId,
      required int faceId,
      Value<int> rowid,
    });
typedef $$IdentitySetFacesTableUpdateCompanionBuilder =
    IdentitySetFacesCompanion Function({
      Value<int> setId,
      Value<int> faceId,
      Value<int> rowid,
    });

final class $$IdentitySetFacesTableReferences
    extends
        BaseReferences<
          _$AppDatabase,
          $IdentitySetFacesTable,
          IdentitySetFaceRow
        > {
  $$IdentitySetFacesTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $IdentitySetsTable _setIdTable(_$AppDatabase db) => db.identitySets
      .createAlias('identity_set_faces__set_id__identity_sets__id');

  $$IdentitySetsTableProcessedTableManager get setId {
    final $_column = $_itemColumn<int>('set_id')!;

    final manager = $$IdentitySetsTableTableManager(
      $_db,
      $_db.identitySets,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_setIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static $FacesTable _faceIdTable(_$AppDatabase db) =>
      db.faces.createAlias('identity_set_faces__face_id__faces__id');

  $$FacesTableProcessedTableManager get faceId {
    final $_column = $_itemColumn<int>('face_id')!;

    final manager = $$FacesTableTableManager(
      $_db,
      $_db.faces,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_faceIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$IdentitySetFacesTableFilterComposer
    extends Composer<_$AppDatabase, $IdentitySetFacesTable> {
  $$IdentitySetFacesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  $$IdentitySetsTableFilterComposer get setId {
    final $$IdentitySetsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.setId,
      referencedTable: $db.identitySets,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$IdentitySetsTableFilterComposer(
            $db: $db,
            $table: $db.identitySets,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$FacesTableFilterComposer get faceId {
    final $$FacesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.faceId,
      referencedTable: $db.faces,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$FacesTableFilterComposer(
            $db: $db,
            $table: $db.faces,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$IdentitySetFacesTableOrderingComposer
    extends Composer<_$AppDatabase, $IdentitySetFacesTable> {
  $$IdentitySetFacesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  $$IdentitySetsTableOrderingComposer get setId {
    final $$IdentitySetsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.setId,
      referencedTable: $db.identitySets,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$IdentitySetsTableOrderingComposer(
            $db: $db,
            $table: $db.identitySets,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$FacesTableOrderingComposer get faceId {
    final $$FacesTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.faceId,
      referencedTable: $db.faces,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$FacesTableOrderingComposer(
            $db: $db,
            $table: $db.faces,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$IdentitySetFacesTableAnnotationComposer
    extends Composer<_$AppDatabase, $IdentitySetFacesTable> {
  $$IdentitySetFacesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  $$IdentitySetsTableAnnotationComposer get setId {
    final $$IdentitySetsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.setId,
      referencedTable: $db.identitySets,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$IdentitySetsTableAnnotationComposer(
            $db: $db,
            $table: $db.identitySets,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$FacesTableAnnotationComposer get faceId {
    final $$FacesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.faceId,
      referencedTable: $db.faces,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$FacesTableAnnotationComposer(
            $db: $db,
            $table: $db.faces,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$IdentitySetFacesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $IdentitySetFacesTable,
          IdentitySetFaceRow,
          $$IdentitySetFacesTableFilterComposer,
          $$IdentitySetFacesTableOrderingComposer,
          $$IdentitySetFacesTableAnnotationComposer,
          $$IdentitySetFacesTableCreateCompanionBuilder,
          $$IdentitySetFacesTableUpdateCompanionBuilder,
          (IdentitySetFaceRow, $$IdentitySetFacesTableReferences),
          IdentitySetFaceRow,
          PrefetchHooks Function({bool setId, bool faceId})
        > {
  $$IdentitySetFacesTableTableManager(
    _$AppDatabase db,
    $IdentitySetFacesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$IdentitySetFacesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$IdentitySetFacesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$IdentitySetFacesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> setId = const Value.absent(),
                Value<int> faceId = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => IdentitySetFacesCompanion(
                setId: setId,
                faceId: faceId,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required int setId,
                required int faceId,
                Value<int> rowid = const Value.absent(),
              }) => IdentitySetFacesCompanion.insert(
                setId: setId,
                faceId: faceId,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$IdentitySetFacesTable, IdentitySetFaceRow>(
                    table,
                  ),
                  $$IdentitySetFacesTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({setId = false, faceId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (setId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.setId,
                                referencedTable:
                                    $$IdentitySetFacesTableReferences
                                        ._setIdTable(db),
                                referencedColumn:
                                    $$IdentitySetFacesTableReferences
                                        ._setIdTable(db)
                                        .id,
                              )
                              as T;
                    }
                    if (faceId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.faceId,
                                referencedTable:
                                    $$IdentitySetFacesTableReferences
                                        ._faceIdTable(db),
                                referencedColumn:
                                    $$IdentitySetFacesTableReferences
                                        ._faceIdTable(db)
                                        .id,
                              )
                              as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$IdentitySetFacesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $IdentitySetFacesTable,
      IdentitySetFaceRow,
      $$IdentitySetFacesTableFilterComposer,
      $$IdentitySetFacesTableOrderingComposer,
      $$IdentitySetFacesTableAnnotationComposer,
      $$IdentitySetFacesTableCreateCompanionBuilder,
      $$IdentitySetFacesTableUpdateCompanionBuilder,
      (IdentitySetFaceRow, $$IdentitySetFacesTableReferences),
      IdentitySetFaceRow,
      PrefetchHooks Function({bool setId, bool faceId})
    >;
typedef $$JobEventsTableCreateCompanionBuilder =
    JobEventsCompanion Function({
      Value<int> id,
      required String jobId,
      required String status,
      Value<String?> message,
      required int createdAt,
    });
typedef $$JobEventsTableUpdateCompanionBuilder =
    JobEventsCompanion Function({
      Value<int> id,
      Value<String> jobId,
      Value<String> status,
      Value<String?> message,
      Value<int> createdAt,
    });

final class $$JobEventsTableReferences
    extends BaseReferences<_$AppDatabase, $JobEventsTable, JobEventRow> {
  $$JobEventsTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $JobsTable _jobIdTable(_$AppDatabase db) =>
      db.jobs.createAlias('job_events__job_id__jobs__id');

  $$JobsTableProcessedTableManager get jobId {
    final $_column = $_itemColumn<String>('job_id')!;

    final manager = $$JobsTableTableManager(
      $_db,
      $_db.jobs,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_jobIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$JobEventsTableFilterComposer
    extends Composer<_$AppDatabase, $JobEventsTable> {
  $$JobEventsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get message => $composableBuilder(
    column: $table.message,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  $$JobsTableFilterComposer get jobId {
    final $$JobsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.jobId,
      referencedTable: $db.jobs,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$JobsTableFilterComposer(
            $db: $db,
            $table: $db.jobs,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$JobEventsTableOrderingComposer
    extends Composer<_$AppDatabase, $JobEventsTable> {
  $$JobEventsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get message => $composableBuilder(
    column: $table.message,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  $$JobsTableOrderingComposer get jobId {
    final $$JobsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.jobId,
      referencedTable: $db.jobs,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$JobsTableOrderingComposer(
            $db: $db,
            $table: $db.jobs,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$JobEventsTableAnnotationComposer
    extends Composer<_$AppDatabase, $JobEventsTable> {
  $$JobEventsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);

  GeneratedColumn<String> get message =>
      $composableBuilder(column: $table.message, builder: (column) => column);

  GeneratedColumn<int> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  $$JobsTableAnnotationComposer get jobId {
    final $$JobsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.jobId,
      referencedTable: $db.jobs,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$JobsTableAnnotationComposer(
            $db: $db,
            $table: $db.jobs,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$JobEventsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $JobEventsTable,
          JobEventRow,
          $$JobEventsTableFilterComposer,
          $$JobEventsTableOrderingComposer,
          $$JobEventsTableAnnotationComposer,
          $$JobEventsTableCreateCompanionBuilder,
          $$JobEventsTableUpdateCompanionBuilder,
          (JobEventRow, $$JobEventsTableReferences),
          JobEventRow,
          PrefetchHooks Function({bool jobId})
        > {
  $$JobEventsTableTableManager(_$AppDatabase db, $JobEventsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$JobEventsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$JobEventsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$JobEventsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> jobId = const Value.absent(),
                Value<String> status = const Value.absent(),
                Value<String?> message = const Value.absent(),
                Value<int> createdAt = const Value.absent(),
              }) => JobEventsCompanion(
                id: id,
                jobId: jobId,
                status: status,
                message: message,
                createdAt: createdAt,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String jobId,
                required String status,
                Value<String?> message = const Value.absent(),
                required int createdAt,
              }) => JobEventsCompanion.insert(
                id: id,
                jobId: jobId,
                status: status,
                message: message,
                createdAt: createdAt,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$JobEventsTable, JobEventRow>(table),
                  $$JobEventsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({jobId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (jobId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.jobId,
                                referencedTable: $$JobEventsTableReferences
                                    ._jobIdTable(db),
                                referencedColumn: $$JobEventsTableReferences
                                    ._jobIdTable(db)
                                    .id,
                              )
                              as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$JobEventsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $JobEventsTable,
      JobEventRow,
      $$JobEventsTableFilterComposer,
      $$JobEventsTableOrderingComposer,
      $$JobEventsTableAnnotationComposer,
      $$JobEventsTableCreateCompanionBuilder,
      $$JobEventsTableUpdateCompanionBuilder,
      (JobEventRow, $$JobEventsTableReferences),
      JobEventRow,
      PrefetchHooks Function({bool jobId})
    >;
typedef $$CharacterIdentitiesTableCreateCompanionBuilder =
    CharacterIdentitiesCompanion Function({
      Value<int> id,
      Value<String?> name,
      required int createdAt,
    });
typedef $$CharacterIdentitiesTableUpdateCompanionBuilder =
    CharacterIdentitiesCompanion Function({
      Value<int> id,
      Value<String?> name,
      Value<int> createdAt,
    });

final class $$CharacterIdentitiesTableReferences
    extends
        BaseReferences<
          _$AppDatabase,
          $CharacterIdentitiesTable,
          CharacterIdentityRow
        > {
  $$CharacterIdentitiesTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static MultiTypedResultKey<$CharacterSamplesTable, List<CharacterSampleRow>>
  _characterSamplesRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.characterSamples,
    aliasName: 'character_identities__id__character_samples__identity_id',
  );

  $$CharacterSamplesTableProcessedTableManager get characterSamplesRefs {
    final manager = $$CharacterSamplesTableTableManager(
      $_db,
      $_db.characterSamples,
    ).filter((f) => f.identityId.id.sqlEquals($_itemColumn<int>('id')!));

    final cache = $_typedResult.readTableOrNull(
      _characterSamplesRefsTable($_db),
    );
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$CharacterIdentitiesTableFilterComposer
    extends Composer<_$AppDatabase, $CharacterIdentitiesTable> {
  $$CharacterIdentitiesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  Expression<bool> characterSamplesRefs(
    Expression<bool> Function($$CharacterSamplesTableFilterComposer f) f,
  ) {
    final $$CharacterSamplesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.characterSamples,
      getReferencedColumn: (t) => t.identityId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$CharacterSamplesTableFilterComposer(
            $db: $db,
            $table: $db.characterSamples,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$CharacterIdentitiesTableOrderingComposer
    extends Composer<_$AppDatabase, $CharacterIdentitiesTable> {
  $$CharacterIdentitiesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$CharacterIdentitiesTableAnnotationComposer
    extends Composer<_$AppDatabase, $CharacterIdentitiesTable> {
  $$CharacterIdentitiesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<int> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  Expression<T> characterSamplesRefs<T extends Object>(
    Expression<T> Function($$CharacterSamplesTableAnnotationComposer a) f,
  ) {
    final $$CharacterSamplesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.characterSamples,
      getReferencedColumn: (t) => t.identityId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$CharacterSamplesTableAnnotationComposer(
            $db: $db,
            $table: $db.characterSamples,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$CharacterIdentitiesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $CharacterIdentitiesTable,
          CharacterIdentityRow,
          $$CharacterIdentitiesTableFilterComposer,
          $$CharacterIdentitiesTableOrderingComposer,
          $$CharacterIdentitiesTableAnnotationComposer,
          $$CharacterIdentitiesTableCreateCompanionBuilder,
          $$CharacterIdentitiesTableUpdateCompanionBuilder,
          (CharacterIdentityRow, $$CharacterIdentitiesTableReferences),
          CharacterIdentityRow,
          PrefetchHooks Function({bool characterSamplesRefs})
        > {
  $$CharacterIdentitiesTableTableManager(
    _$AppDatabase db,
    $CharacterIdentitiesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$CharacterIdentitiesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$CharacterIdentitiesTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$CharacterIdentitiesTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String?> name = const Value.absent(),
                Value<int> createdAt = const Value.absent(),
              }) => CharacterIdentitiesCompanion(
                id: id,
                name: name,
                createdAt: createdAt,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String?> name = const Value.absent(),
                required int createdAt,
              }) => CharacterIdentitiesCompanion.insert(
                id: id,
                name: name,
                createdAt: createdAt,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$CharacterIdentitiesTable, CharacterIdentityRow>(
                    table,
                  ),
                  $$CharacterIdentitiesTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({characterSamplesRefs = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [
                if (characterSamplesRefs) db.characterSamples,
              ],
              addJoins: null,
              getPrefetchedDataCallback: (items) async {
                return [
                  if (characterSamplesRefs)
                    await $_getPrefetchedData<
                      CharacterIdentityRow,
                      $CharacterIdentitiesTable,
                      CharacterSampleRow
                    >(
                      currentTable: table,
                      referencedTable: $$CharacterIdentitiesTableReferences
                          ._characterSamplesRefsTable(db),
                      managerFromTypedResult: (p0) =>
                          $$CharacterIdentitiesTableReferences(
                            db,
                            table,
                            p0,
                          ).characterSamplesRefs,
                      referencedItemsForCurrentItem: (item, referencedItems) =>
                          referencedItems.where((e) => e.identityId == item.id),
                      typedResults: items,
                    ),
                ];
              },
            );
          },
        ),
      );
}

typedef $$CharacterIdentitiesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $CharacterIdentitiesTable,
      CharacterIdentityRow,
      $$CharacterIdentitiesTableFilterComposer,
      $$CharacterIdentitiesTableOrderingComposer,
      $$CharacterIdentitiesTableAnnotationComposer,
      $$CharacterIdentitiesTableCreateCompanionBuilder,
      $$CharacterIdentitiesTableUpdateCompanionBuilder,
      (CharacterIdentityRow, $$CharacterIdentitiesTableReferences),
      CharacterIdentityRow,
      PrefetchHooks Function({bool characterSamplesRefs})
    >;
typedef $$CharacterSamplesTableCreateCompanionBuilder =
    CharacterSamplesCompanion Function({
      Value<int> id,
      required int identityId,
      required int mediaId,
      required String modelId,
      required Uint8List descriptor,
      required double bboxX,
      required double bboxY,
      required double bboxW,
      required double bboxH,
      required double score,
      Value<int?> frameNumber,
      Value<int?> timestampMs,
      Value<String?> cropPath,
      required int createdAt,
    });
typedef $$CharacterSamplesTableUpdateCompanionBuilder =
    CharacterSamplesCompanion Function({
      Value<int> id,
      Value<int> identityId,
      Value<int> mediaId,
      Value<String> modelId,
      Value<Uint8List> descriptor,
      Value<double> bboxX,
      Value<double> bboxY,
      Value<double> bboxW,
      Value<double> bboxH,
      Value<double> score,
      Value<int?> frameNumber,
      Value<int?> timestampMs,
      Value<String?> cropPath,
      Value<int> createdAt,
    });

final class $$CharacterSamplesTableReferences
    extends
        BaseReferences<
          _$AppDatabase,
          $CharacterSamplesTable,
          CharacterSampleRow
        > {
  $$CharacterSamplesTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $CharacterIdentitiesTable _identityIdTable(_$AppDatabase db) => db
      .characterIdentities
      .createAlias('character_samples__identity_id__character_identities__id');

  $$CharacterIdentitiesTableProcessedTableManager get identityId {
    final $_column = $_itemColumn<int>('identity_id')!;

    final manager = $$CharacterIdentitiesTableTableManager(
      $_db,
      $_db.characterIdentities,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_identityIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static $MediaTable _mediaIdTable(_$AppDatabase db) =>
      db.media.createAlias('character_samples__media_id__media__id');

  $$MediaTableProcessedTableManager get mediaId {
    final $_column = $_itemColumn<int>('media_id')!;

    final manager = $$MediaTableTableManager(
      $_db,
      $_db.media,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_mediaIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$CharacterSamplesTableFilterComposer
    extends Composer<_$AppDatabase, $CharacterSamplesTable> {
  $$CharacterSamplesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get modelId => $composableBuilder(
    column: $table.modelId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<Uint8List> get descriptor => $composableBuilder(
    column: $table.descriptor,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get bboxX => $composableBuilder(
    column: $table.bboxX,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get bboxY => $composableBuilder(
    column: $table.bboxY,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get bboxW => $composableBuilder(
    column: $table.bboxW,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get bboxH => $composableBuilder(
    column: $table.bboxH,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get score => $composableBuilder(
    column: $table.score,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get frameNumber => $composableBuilder(
    column: $table.frameNumber,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get timestampMs => $composableBuilder(
    column: $table.timestampMs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get cropPath => $composableBuilder(
    column: $table.cropPath,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  $$CharacterIdentitiesTableFilterComposer get identityId {
    final $$CharacterIdentitiesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.identityId,
      referencedTable: $db.characterIdentities,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$CharacterIdentitiesTableFilterComposer(
            $db: $db,
            $table: $db.characterIdentities,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$MediaTableFilterComposer get mediaId {
    final $$MediaTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.mediaId,
      referencedTable: $db.media,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$MediaTableFilterComposer(
            $db: $db,
            $table: $db.media,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$CharacterSamplesTableOrderingComposer
    extends Composer<_$AppDatabase, $CharacterSamplesTable> {
  $$CharacterSamplesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get modelId => $composableBuilder(
    column: $table.modelId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<Uint8List> get descriptor => $composableBuilder(
    column: $table.descriptor,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get bboxX => $composableBuilder(
    column: $table.bboxX,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get bboxY => $composableBuilder(
    column: $table.bboxY,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get bboxW => $composableBuilder(
    column: $table.bboxW,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get bboxH => $composableBuilder(
    column: $table.bboxH,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get score => $composableBuilder(
    column: $table.score,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get frameNumber => $composableBuilder(
    column: $table.frameNumber,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get timestampMs => $composableBuilder(
    column: $table.timestampMs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get cropPath => $composableBuilder(
    column: $table.cropPath,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  $$CharacterIdentitiesTableOrderingComposer get identityId {
    final $$CharacterIdentitiesTableOrderingComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.identityId,
          referencedTable: $db.characterIdentities,
          getReferencedColumn: (t) => t.id,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$CharacterIdentitiesTableOrderingComposer(
                $db: $db,
                $table: $db.characterIdentities,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return composer;
  }

  $$MediaTableOrderingComposer get mediaId {
    final $$MediaTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.mediaId,
      referencedTable: $db.media,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$MediaTableOrderingComposer(
            $db: $db,
            $table: $db.media,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$CharacterSamplesTableAnnotationComposer
    extends Composer<_$AppDatabase, $CharacterSamplesTable> {
  $$CharacterSamplesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get modelId =>
      $composableBuilder(column: $table.modelId, builder: (column) => column);

  GeneratedColumn<Uint8List> get descriptor => $composableBuilder(
    column: $table.descriptor,
    builder: (column) => column,
  );

  GeneratedColumn<double> get bboxX =>
      $composableBuilder(column: $table.bboxX, builder: (column) => column);

  GeneratedColumn<double> get bboxY =>
      $composableBuilder(column: $table.bboxY, builder: (column) => column);

  GeneratedColumn<double> get bboxW =>
      $composableBuilder(column: $table.bboxW, builder: (column) => column);

  GeneratedColumn<double> get bboxH =>
      $composableBuilder(column: $table.bboxH, builder: (column) => column);

  GeneratedColumn<double> get score =>
      $composableBuilder(column: $table.score, builder: (column) => column);

  GeneratedColumn<int> get frameNumber => $composableBuilder(
    column: $table.frameNumber,
    builder: (column) => column,
  );

  GeneratedColumn<int> get timestampMs => $composableBuilder(
    column: $table.timestampMs,
    builder: (column) => column,
  );

  GeneratedColumn<String> get cropPath =>
      $composableBuilder(column: $table.cropPath, builder: (column) => column);

  GeneratedColumn<int> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  $$CharacterIdentitiesTableAnnotationComposer get identityId {
    final $$CharacterIdentitiesTableAnnotationComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.identityId,
          referencedTable: $db.characterIdentities,
          getReferencedColumn: (t) => t.id,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$CharacterIdentitiesTableAnnotationComposer(
                $db: $db,
                $table: $db.characterIdentities,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return composer;
  }

  $$MediaTableAnnotationComposer get mediaId {
    final $$MediaTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.mediaId,
      referencedTable: $db.media,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$MediaTableAnnotationComposer(
            $db: $db,
            $table: $db.media,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$CharacterSamplesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $CharacterSamplesTable,
          CharacterSampleRow,
          $$CharacterSamplesTableFilterComposer,
          $$CharacterSamplesTableOrderingComposer,
          $$CharacterSamplesTableAnnotationComposer,
          $$CharacterSamplesTableCreateCompanionBuilder,
          $$CharacterSamplesTableUpdateCompanionBuilder,
          (CharacterSampleRow, $$CharacterSamplesTableReferences),
          CharacterSampleRow,
          PrefetchHooks Function({bool identityId, bool mediaId})
        > {
  $$CharacterSamplesTableTableManager(
    _$AppDatabase db,
    $CharacterSamplesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$CharacterSamplesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$CharacterSamplesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$CharacterSamplesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<int> identityId = const Value.absent(),
                Value<int> mediaId = const Value.absent(),
                Value<String> modelId = const Value.absent(),
                Value<Uint8List> descriptor = const Value.absent(),
                Value<double> bboxX = const Value.absent(),
                Value<double> bboxY = const Value.absent(),
                Value<double> bboxW = const Value.absent(),
                Value<double> bboxH = const Value.absent(),
                Value<double> score = const Value.absent(),
                Value<int?> frameNumber = const Value.absent(),
                Value<int?> timestampMs = const Value.absent(),
                Value<String?> cropPath = const Value.absent(),
                Value<int> createdAt = const Value.absent(),
              }) => CharacterSamplesCompanion(
                id: id,
                identityId: identityId,
                mediaId: mediaId,
                modelId: modelId,
                descriptor: descriptor,
                bboxX: bboxX,
                bboxY: bboxY,
                bboxW: bboxW,
                bboxH: bboxH,
                score: score,
                frameNumber: frameNumber,
                timestampMs: timestampMs,
                cropPath: cropPath,
                createdAt: createdAt,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required int identityId,
                required int mediaId,
                required String modelId,
                required Uint8List descriptor,
                required double bboxX,
                required double bboxY,
                required double bboxW,
                required double bboxH,
                required double score,
                Value<int?> frameNumber = const Value.absent(),
                Value<int?> timestampMs = const Value.absent(),
                Value<String?> cropPath = const Value.absent(),
                required int createdAt,
              }) => CharacterSamplesCompanion.insert(
                id: id,
                identityId: identityId,
                mediaId: mediaId,
                modelId: modelId,
                descriptor: descriptor,
                bboxX: bboxX,
                bboxY: bboxY,
                bboxW: bboxW,
                bboxH: bboxH,
                score: score,
                frameNumber: frameNumber,
                timestampMs: timestampMs,
                cropPath: cropPath,
                createdAt: createdAt,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$CharacterSamplesTable, CharacterSampleRow>(
                    table,
                  ),
                  $$CharacterSamplesTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({identityId = false, mediaId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (identityId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.identityId,
                                referencedTable:
                                    $$CharacterSamplesTableReferences
                                        ._identityIdTable(db),
                                referencedColumn:
                                    $$CharacterSamplesTableReferences
                                        ._identityIdTable(db)
                                        .id,
                              )
                              as T;
                    }
                    if (mediaId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.mediaId,
                                referencedTable:
                                    $$CharacterSamplesTableReferences
                                        ._mediaIdTable(db),
                                referencedColumn:
                                    $$CharacterSamplesTableReferences
                                        ._mediaIdTable(db)
                                        .id,
                              )
                              as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$CharacterSamplesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $CharacterSamplesTable,
      CharacterSampleRow,
      $$CharacterSamplesTableFilterComposer,
      $$CharacterSamplesTableOrderingComposer,
      $$CharacterSamplesTableAnnotationComposer,
      $$CharacterSamplesTableCreateCompanionBuilder,
      $$CharacterSamplesTableUpdateCompanionBuilder,
      (CharacterSampleRow, $$CharacterSamplesTableReferences),
      CharacterSampleRow,
      PrefetchHooks Function({bool identityId, bool mediaId})
    >;

class $AppDatabaseManager {
  final _$AppDatabase _db;
  $AppDatabaseManager(this._db);
  $$PersonsTableTableManager get persons =>
      $$PersonsTableTableManager(_db, _db.persons);
  $$MediaTableTableManager get media =>
      $$MediaTableTableManager(_db, _db.media);
  $$FacesTableTableManager get faces =>
      $$FacesTableTableManager(_db, _db.faces);
  $$FaceSuppressionsTableTableManager get faceSuppressions =>
      $$FaceSuppressionsTableTableManager(_db, _db.faceSuppressions);
  $$BodiesTableTableManager get bodies =>
      $$BodiesTableTableManager(_db, _db.bodies);
  $$FaceRejectionsTableTableManager get faceRejections =>
      $$FaceRejectionsTableTableManager(_db, _db.faceRejections);
  $$BodyRejectionsTableTableManager get bodyRejections =>
      $$BodyRejectionsTableTableManager(_db, _db.bodyRejections);
  $$PersonDistinctTableTableManager get personDistinct =>
      $$PersonDistinctTableTableManager(_db, _db.personDistinct);
  $$ServersTableTableManager get servers =>
      $$ServersTableTableManager(_db, _db.servers);
  $$SettingsTableTableManager get settings =>
      $$SettingsTableTableManager(_db, _db.settings);
  $$UploadQueueTableTableManager get uploadQueue =>
      $$UploadQueueTableTableManager(_db, _db.uploadQueue);
  $$BlobHintsTableTableManager get blobHints =>
      $$BlobHintsTableTableManager(_db, _db.blobHints);
  $$MediaDetectionsTableTableManager get mediaDetections =>
      $$MediaDetectionsTableTableManager(_db, _db.mediaDetections);
  $$ReviewMatchesTableTableManager get reviewMatches =>
      $$ReviewMatchesTableTableManager(_db, _db.reviewMatches);
  $$ReviewGroupsTableTableManager get reviewGroups =>
      $$ReviewGroupsTableTableManager(_db, _db.reviewGroups);
  $$ReviewDuplicatesTableTableManager get reviewDuplicates =>
      $$ReviewDuplicatesTableTableManager(_db, _db.reviewDuplicates);
  $$ReviewBodyLinksTableTableManager get reviewBodyLinks =>
      $$ReviewBodyLinksTableTableManager(_db, _db.reviewBodyLinks);
  $$ReviewSnoozesTableTableManager get reviewSnoozes =>
      $$ReviewSnoozesTableTableManager(_db, _db.reviewSnoozes);
  $$JobsTableTableManager get jobs => $$JobsTableTableManager(_db, _db.jobs);
  $$ResultsTableTableManager get results =>
      $$ResultsTableTableManager(_db, _db.results);
  $$DatasetsTableTableManager get datasets =>
      $$DatasetsTableTableManager(_db, _db.datasets);
  $$DatasetItemsTableTableManager get datasetItems =>
      $$DatasetItemsTableTableManager(_db, _db.datasetItems);
  $$LorasTableTableManager get loras =>
      $$LorasTableTableManager(_db, _db.loras);
  $$IdentitySetsTableTableManager get identitySets =>
      $$IdentitySetsTableTableManager(_db, _db.identitySets);
  $$IdentitySetFacesTableTableManager get identitySetFaces =>
      $$IdentitySetFacesTableTableManager(_db, _db.identitySetFaces);
  $$JobEventsTableTableManager get jobEvents =>
      $$JobEventsTableTableManager(_db, _db.jobEvents);
  $$CharacterIdentitiesTableTableManager get characterIdentities =>
      $$CharacterIdentitiesTableTableManager(_db, _db.characterIdentities);
  $$CharacterSamplesTableTableManager get characterSamples =>
      $$CharacterSamplesTableTableManager(_db, _db.characterSamples);
}
