// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'app_database.dart';

// ignore_for_file: type=lint
class $PatientsTable extends Patients with TableInfo<$PatientsTable, Patient> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $PatientsTable(this.attachedDatabase, [this._alias]);
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
  static const VerificationMeta _phoneMeta = const VerificationMeta('phone');
  @override
  late final GeneratedColumn<String> phone = GeneratedColumn<String>(
    'phone',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _notesMeta = const VerificationMeta('notes');
  @override
  late final GeneratedColumn<String> notes = GeneratedColumn<String>(
    'notes',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _lastVisitMeta = const VerificationMeta(
    'lastVisit',
  );
  @override
  late final GeneratedColumn<String> lastVisit = GeneratedColumn<String>(
    'last_visit',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<String> createdAt = GeneratedColumn<String>(
    'created_at',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<String> updatedAt = GeneratedColumn<String>(
    'updated_at',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _modMeta = const VerificationMeta('mod');
  @override
  late final GeneratedColumn<int> mod = GeneratedColumn<int>(
    '_mod',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _deletedMeta = const VerificationMeta(
    'deleted',
  );
  @override
  late final GeneratedColumn<int> deleted = GeneratedColumn<int>(
    '_deleted',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _dataMeta = const VerificationMeta('data');
  @override
  late final GeneratedColumn<String> data = GeneratedColumn<String>(
    'data',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _clinicIdMeta = const VerificationMeta(
    'clinicId',
  );
  @override
  late final GeneratedColumn<String> clinicId = GeneratedColumn<String>(
    'clinic_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _hlcMeta = const VerificationMeta('hlc');
  @override
  late final GeneratedColumn<String> hlc = GeneratedColumn<String>(
    '_hlc',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _dirtyMeta = const VerificationMeta('dirty');
  @override
  late final GeneratedColumn<int> dirty = GeneratedColumn<int>(
    '_dirty',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _originMeta = const VerificationMeta('origin');
  @override
  late final GeneratedColumn<String> origin = GeneratedColumn<String>(
    '_origin',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _serverSeqMeta = const VerificationMeta(
    'serverSeq',
  );
  @override
  late final GeneratedColumn<int> serverSeq = GeneratedColumn<int>(
    'server_seq',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _ownerUidMeta = const VerificationMeta(
    'ownerUid',
  );
  @override
  late final GeneratedColumn<String> ownerUid = GeneratedColumn<String>(
    'owner_uid',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _patientIdMeta = const VerificationMeta(
    'patientId',
  );
  @override
  late final GeneratedColumn<String> patientId = GeneratedColumn<String>(
    'patient_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    name,
    phone,
    notes,
    lastVisit,
    createdAt,
    updatedAt,
    mod,
    deleted,
    data,
    clinicId,
    hlc,
    dirty,
    origin,
    serverSeq,
    ownerUid,
    patientId,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'patients';
  @override
  VerificationContext validateIntegrity(
    Insertable<Patient> instance, {
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
    if (data.containsKey('phone')) {
      context.handle(
        _phoneMeta,
        phone.isAcceptableOrUnknown(data['phone']!, _phoneMeta),
      );
    }
    if (data.containsKey('notes')) {
      context.handle(
        _notesMeta,
        notes.isAcceptableOrUnknown(data['notes']!, _notesMeta),
      );
    }
    if (data.containsKey('last_visit')) {
      context.handle(
        _lastVisitMeta,
        lastVisit.isAcceptableOrUnknown(data['last_visit']!, _lastVisitMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    }
    if (data.containsKey('_mod')) {
      context.handle(
        _modMeta,
        mod.isAcceptableOrUnknown(data['_mod']!, _modMeta),
      );
    }
    if (data.containsKey('_deleted')) {
      context.handle(
        _deletedMeta,
        deleted.isAcceptableOrUnknown(data['_deleted']!, _deletedMeta),
      );
    }
    if (data.containsKey('data')) {
      context.handle(
        _dataMeta,
        this.data.isAcceptableOrUnknown(data['data']!, _dataMeta),
      );
    }
    if (data.containsKey('clinic_id')) {
      context.handle(
        _clinicIdMeta,
        clinicId.isAcceptableOrUnknown(data['clinic_id']!, _clinicIdMeta),
      );
    }
    if (data.containsKey('_hlc')) {
      context.handle(
        _hlcMeta,
        hlc.isAcceptableOrUnknown(data['_hlc']!, _hlcMeta),
      );
    }
    if (data.containsKey('_dirty')) {
      context.handle(
        _dirtyMeta,
        dirty.isAcceptableOrUnknown(data['_dirty']!, _dirtyMeta),
      );
    }
    if (data.containsKey('_origin')) {
      context.handle(
        _originMeta,
        origin.isAcceptableOrUnknown(data['_origin']!, _originMeta),
      );
    }
    if (data.containsKey('server_seq')) {
      context.handle(
        _serverSeqMeta,
        serverSeq.isAcceptableOrUnknown(data['server_seq']!, _serverSeqMeta),
      );
    }
    if (data.containsKey('owner_uid')) {
      context.handle(
        _ownerUidMeta,
        ownerUid.isAcceptableOrUnknown(data['owner_uid']!, _ownerUidMeta),
      );
    }
    if (data.containsKey('patient_id')) {
      context.handle(
        _patientIdMeta,
        patientId.isAcceptableOrUnknown(data['patient_id']!, _patientIdMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Patient map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Patient(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      phone: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}phone'],
      ),
      notes: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}notes'],
      ),
      lastVisit: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}last_visit'],
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}created_at'],
      ),
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}updated_at'],
      ),
      mod: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}_mod'],
      ),
      deleted: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}_deleted'],
      ),
      data: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}data'],
      ),
      clinicId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}clinic_id'],
      ),
      hlc: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}_hlc'],
      ),
      dirty: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}_dirty'],
      ),
      origin: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}_origin'],
      ),
      serverSeq: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}server_seq'],
      ),
      ownerUid: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}owner_uid'],
      ),
      patientId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}patient_id'],
      ),
    );
  }

  @override
  $PatientsTable createAlias(String alias) {
    return $PatientsTable(attachedDatabase, alias);
  }
}

class Patient extends DataClass implements Insertable<Patient> {
  final String id;
  final String name;
  final String? phone;
  final String? notes;
  final String? lastVisit;
  final String? createdAt;
  final String? updatedAt;
  final int? mod;
  final int? deleted;
  final String? data;
  final String? clinicId;
  final String? hlc;
  final int? dirty;
  final String? origin;
  final int? serverSeq;
  final String? ownerUid;
  final String? patientId;
  const Patient({
    required this.id,
    required this.name,
    this.phone,
    this.notes,
    this.lastVisit,
    this.createdAt,
    this.updatedAt,
    this.mod,
    this.deleted,
    this.data,
    this.clinicId,
    this.hlc,
    this.dirty,
    this.origin,
    this.serverSeq,
    this.ownerUid,
    this.patientId,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['name'] = Variable<String>(name);
    if (!nullToAbsent || phone != null) {
      map['phone'] = Variable<String>(phone);
    }
    if (!nullToAbsent || notes != null) {
      map['notes'] = Variable<String>(notes);
    }
    if (!nullToAbsent || lastVisit != null) {
      map['last_visit'] = Variable<String>(lastVisit);
    }
    if (!nullToAbsent || createdAt != null) {
      map['created_at'] = Variable<String>(createdAt);
    }
    if (!nullToAbsent || updatedAt != null) {
      map['updated_at'] = Variable<String>(updatedAt);
    }
    if (!nullToAbsent || mod != null) {
      map['_mod'] = Variable<int>(mod);
    }
    if (!nullToAbsent || deleted != null) {
      map['_deleted'] = Variable<int>(deleted);
    }
    if (!nullToAbsent || data != null) {
      map['data'] = Variable<String>(data);
    }
    if (!nullToAbsent || clinicId != null) {
      map['clinic_id'] = Variable<String>(clinicId);
    }
    if (!nullToAbsent || hlc != null) {
      map['_hlc'] = Variable<String>(hlc);
    }
    if (!nullToAbsent || dirty != null) {
      map['_dirty'] = Variable<int>(dirty);
    }
    if (!nullToAbsent || origin != null) {
      map['_origin'] = Variable<String>(origin);
    }
    if (!nullToAbsent || serverSeq != null) {
      map['server_seq'] = Variable<int>(serverSeq);
    }
    if (!nullToAbsent || ownerUid != null) {
      map['owner_uid'] = Variable<String>(ownerUid);
    }
    if (!nullToAbsent || patientId != null) {
      map['patient_id'] = Variable<String>(patientId);
    }
    return map;
  }

  PatientsCompanion toCompanion(bool nullToAbsent) {
    return PatientsCompanion(
      id: Value(id),
      name: Value(name),
      phone: phone == null && nullToAbsent
          ? const Value.absent()
          : Value(phone),
      notes: notes == null && nullToAbsent
          ? const Value.absent()
          : Value(notes),
      lastVisit: lastVisit == null && nullToAbsent
          ? const Value.absent()
          : Value(lastVisit),
      createdAt: createdAt == null && nullToAbsent
          ? const Value.absent()
          : Value(createdAt),
      updatedAt: updatedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(updatedAt),
      mod: mod == null && nullToAbsent ? const Value.absent() : Value(mod),
      deleted: deleted == null && nullToAbsent
          ? const Value.absent()
          : Value(deleted),
      data: data == null && nullToAbsent ? const Value.absent() : Value(data),
      clinicId: clinicId == null && nullToAbsent
          ? const Value.absent()
          : Value(clinicId),
      hlc: hlc == null && nullToAbsent ? const Value.absent() : Value(hlc),
      dirty: dirty == null && nullToAbsent
          ? const Value.absent()
          : Value(dirty),
      origin: origin == null && nullToAbsent
          ? const Value.absent()
          : Value(origin),
      serverSeq: serverSeq == null && nullToAbsent
          ? const Value.absent()
          : Value(serverSeq),
      ownerUid: ownerUid == null && nullToAbsent
          ? const Value.absent()
          : Value(ownerUid),
      patientId: patientId == null && nullToAbsent
          ? const Value.absent()
          : Value(patientId),
    );
  }

  factory Patient.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Patient(
      id: serializer.fromJson<String>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      phone: serializer.fromJson<String?>(json['phone']),
      notes: serializer.fromJson<String?>(json['notes']),
      lastVisit: serializer.fromJson<String?>(json['lastVisit']),
      createdAt: serializer.fromJson<String?>(json['createdAt']),
      updatedAt: serializer.fromJson<String?>(json['updatedAt']),
      mod: serializer.fromJson<int?>(json['mod']),
      deleted: serializer.fromJson<int?>(json['deleted']),
      data: serializer.fromJson<String?>(json['data']),
      clinicId: serializer.fromJson<String?>(json['clinicId']),
      hlc: serializer.fromJson<String?>(json['hlc']),
      dirty: serializer.fromJson<int?>(json['dirty']),
      origin: serializer.fromJson<String?>(json['origin']),
      serverSeq: serializer.fromJson<int?>(json['serverSeq']),
      ownerUid: serializer.fromJson<String?>(json['ownerUid']),
      patientId: serializer.fromJson<String?>(json['patientId']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'name': serializer.toJson<String>(name),
      'phone': serializer.toJson<String?>(phone),
      'notes': serializer.toJson<String?>(notes),
      'lastVisit': serializer.toJson<String?>(lastVisit),
      'createdAt': serializer.toJson<String?>(createdAt),
      'updatedAt': serializer.toJson<String?>(updatedAt),
      'mod': serializer.toJson<int?>(mod),
      'deleted': serializer.toJson<int?>(deleted),
      'data': serializer.toJson<String?>(data),
      'clinicId': serializer.toJson<String?>(clinicId),
      'hlc': serializer.toJson<String?>(hlc),
      'dirty': serializer.toJson<int?>(dirty),
      'origin': serializer.toJson<String?>(origin),
      'serverSeq': serializer.toJson<int?>(serverSeq),
      'ownerUid': serializer.toJson<String?>(ownerUid),
      'patientId': serializer.toJson<String?>(patientId),
    };
  }

  Patient copyWith({
    String? id,
    String? name,
    Value<String?> phone = const Value.absent(),
    Value<String?> notes = const Value.absent(),
    Value<String?> lastVisit = const Value.absent(),
    Value<String?> createdAt = const Value.absent(),
    Value<String?> updatedAt = const Value.absent(),
    Value<int?> mod = const Value.absent(),
    Value<int?> deleted = const Value.absent(),
    Value<String?> data = const Value.absent(),
    Value<String?> clinicId = const Value.absent(),
    Value<String?> hlc = const Value.absent(),
    Value<int?> dirty = const Value.absent(),
    Value<String?> origin = const Value.absent(),
    Value<int?> serverSeq = const Value.absent(),
    Value<String?> ownerUid = const Value.absent(),
    Value<String?> patientId = const Value.absent(),
  }) => Patient(
    id: id ?? this.id,
    name: name ?? this.name,
    phone: phone.present ? phone.value : this.phone,
    notes: notes.present ? notes.value : this.notes,
    lastVisit: lastVisit.present ? lastVisit.value : this.lastVisit,
    createdAt: createdAt.present ? createdAt.value : this.createdAt,
    updatedAt: updatedAt.present ? updatedAt.value : this.updatedAt,
    mod: mod.present ? mod.value : this.mod,
    deleted: deleted.present ? deleted.value : this.deleted,
    data: data.present ? data.value : this.data,
    clinicId: clinicId.present ? clinicId.value : this.clinicId,
    hlc: hlc.present ? hlc.value : this.hlc,
    dirty: dirty.present ? dirty.value : this.dirty,
    origin: origin.present ? origin.value : this.origin,
    serverSeq: serverSeq.present ? serverSeq.value : this.serverSeq,
    ownerUid: ownerUid.present ? ownerUid.value : this.ownerUid,
    patientId: patientId.present ? patientId.value : this.patientId,
  );
  Patient copyWithCompanion(PatientsCompanion data) {
    return Patient(
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      phone: data.phone.present ? data.phone.value : this.phone,
      notes: data.notes.present ? data.notes.value : this.notes,
      lastVisit: data.lastVisit.present ? data.lastVisit.value : this.lastVisit,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      mod: data.mod.present ? data.mod.value : this.mod,
      deleted: data.deleted.present ? data.deleted.value : this.deleted,
      data: data.data.present ? data.data.value : this.data,
      clinicId: data.clinicId.present ? data.clinicId.value : this.clinicId,
      hlc: data.hlc.present ? data.hlc.value : this.hlc,
      dirty: data.dirty.present ? data.dirty.value : this.dirty,
      origin: data.origin.present ? data.origin.value : this.origin,
      serverSeq: data.serverSeq.present ? data.serverSeq.value : this.serverSeq,
      ownerUid: data.ownerUid.present ? data.ownerUid.value : this.ownerUid,
      patientId: data.patientId.present ? data.patientId.value : this.patientId,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Patient(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('phone: $phone, ')
          ..write('notes: $notes, ')
          ..write('lastVisit: $lastVisit, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('mod: $mod, ')
          ..write('deleted: $deleted, ')
          ..write('data: $data, ')
          ..write('clinicId: $clinicId, ')
          ..write('hlc: $hlc, ')
          ..write('dirty: $dirty, ')
          ..write('origin: $origin, ')
          ..write('serverSeq: $serverSeq, ')
          ..write('ownerUid: $ownerUid, ')
          ..write('patientId: $patientId')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    name,
    phone,
    notes,
    lastVisit,
    createdAt,
    updatedAt,
    mod,
    deleted,
    data,
    clinicId,
    hlc,
    dirty,
    origin,
    serverSeq,
    ownerUid,
    patientId,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Patient &&
          other.id == this.id &&
          other.name == this.name &&
          other.phone == this.phone &&
          other.notes == this.notes &&
          other.lastVisit == this.lastVisit &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt &&
          other.mod == this.mod &&
          other.deleted == this.deleted &&
          other.data == this.data &&
          other.clinicId == this.clinicId &&
          other.hlc == this.hlc &&
          other.dirty == this.dirty &&
          other.origin == this.origin &&
          other.serverSeq == this.serverSeq &&
          other.ownerUid == this.ownerUid &&
          other.patientId == this.patientId);
}

class PatientsCompanion extends UpdateCompanion<Patient> {
  final Value<String> id;
  final Value<String> name;
  final Value<String?> phone;
  final Value<String?> notes;
  final Value<String?> lastVisit;
  final Value<String?> createdAt;
  final Value<String?> updatedAt;
  final Value<int?> mod;
  final Value<int?> deleted;
  final Value<String?> data;
  final Value<String?> clinicId;
  final Value<String?> hlc;
  final Value<int?> dirty;
  final Value<String?> origin;
  final Value<int?> serverSeq;
  final Value<String?> ownerUid;
  final Value<String?> patientId;
  final Value<int> rowid;
  const PatientsCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.phone = const Value.absent(),
    this.notes = const Value.absent(),
    this.lastVisit = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.mod = const Value.absent(),
    this.deleted = const Value.absent(),
    this.data = const Value.absent(),
    this.clinicId = const Value.absent(),
    this.hlc = const Value.absent(),
    this.dirty = const Value.absent(),
    this.origin = const Value.absent(),
    this.serverSeq = const Value.absent(),
    this.ownerUid = const Value.absent(),
    this.patientId = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  PatientsCompanion.insert({
    required String id,
    required String name,
    this.phone = const Value.absent(),
    this.notes = const Value.absent(),
    this.lastVisit = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.mod = const Value.absent(),
    this.deleted = const Value.absent(),
    this.data = const Value.absent(),
    this.clinicId = const Value.absent(),
    this.hlc = const Value.absent(),
    this.dirty = const Value.absent(),
    this.origin = const Value.absent(),
    this.serverSeq = const Value.absent(),
    this.ownerUid = const Value.absent(),
    this.patientId = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       name = Value(name);
  static Insertable<Patient> custom({
    Expression<String>? id,
    Expression<String>? name,
    Expression<String>? phone,
    Expression<String>? notes,
    Expression<String>? lastVisit,
    Expression<String>? createdAt,
    Expression<String>? updatedAt,
    Expression<int>? mod,
    Expression<int>? deleted,
    Expression<String>? data,
    Expression<String>? clinicId,
    Expression<String>? hlc,
    Expression<int>? dirty,
    Expression<String>? origin,
    Expression<int>? serverSeq,
    Expression<String>? ownerUid,
    Expression<String>? patientId,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (phone != null) 'phone': phone,
      if (notes != null) 'notes': notes,
      if (lastVisit != null) 'last_visit': lastVisit,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (mod != null) '_mod': mod,
      if (deleted != null) '_deleted': deleted,
      if (data != null) 'data': data,
      if (clinicId != null) 'clinic_id': clinicId,
      if (hlc != null) '_hlc': hlc,
      if (dirty != null) '_dirty': dirty,
      if (origin != null) '_origin': origin,
      if (serverSeq != null) 'server_seq': serverSeq,
      if (ownerUid != null) 'owner_uid': ownerUid,
      if (patientId != null) 'patient_id': patientId,
      if (rowid != null) 'rowid': rowid,
    });
  }

  PatientsCompanion copyWith({
    Value<String>? id,
    Value<String>? name,
    Value<String?>? phone,
    Value<String?>? notes,
    Value<String?>? lastVisit,
    Value<String?>? createdAt,
    Value<String?>? updatedAt,
    Value<int?>? mod,
    Value<int?>? deleted,
    Value<String?>? data,
    Value<String?>? clinicId,
    Value<String?>? hlc,
    Value<int?>? dirty,
    Value<String?>? origin,
    Value<int?>? serverSeq,
    Value<String?>? ownerUid,
    Value<String?>? patientId,
    Value<int>? rowid,
  }) {
    return PatientsCompanion(
      id: id ?? this.id,
      name: name ?? this.name,
      phone: phone ?? this.phone,
      notes: notes ?? this.notes,
      lastVisit: lastVisit ?? this.lastVisit,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      mod: mod ?? this.mod,
      deleted: deleted ?? this.deleted,
      data: data ?? this.data,
      clinicId: clinicId ?? this.clinicId,
      hlc: hlc ?? this.hlc,
      dirty: dirty ?? this.dirty,
      origin: origin ?? this.origin,
      serverSeq: serverSeq ?? this.serverSeq,
      ownerUid: ownerUid ?? this.ownerUid,
      patientId: patientId ?? this.patientId,
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
    if (phone.present) {
      map['phone'] = Variable<String>(phone.value);
    }
    if (notes.present) {
      map['notes'] = Variable<String>(notes.value);
    }
    if (lastVisit.present) {
      map['last_visit'] = Variable<String>(lastVisit.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<String>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<String>(updatedAt.value);
    }
    if (mod.present) {
      map['_mod'] = Variable<int>(mod.value);
    }
    if (deleted.present) {
      map['_deleted'] = Variable<int>(deleted.value);
    }
    if (data.present) {
      map['data'] = Variable<String>(data.value);
    }
    if (clinicId.present) {
      map['clinic_id'] = Variable<String>(clinicId.value);
    }
    if (hlc.present) {
      map['_hlc'] = Variable<String>(hlc.value);
    }
    if (dirty.present) {
      map['_dirty'] = Variable<int>(dirty.value);
    }
    if (origin.present) {
      map['_origin'] = Variable<String>(origin.value);
    }
    if (serverSeq.present) {
      map['server_seq'] = Variable<int>(serverSeq.value);
    }
    if (ownerUid.present) {
      map['owner_uid'] = Variable<String>(ownerUid.value);
    }
    if (patientId.present) {
      map['patient_id'] = Variable<String>(patientId.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('PatientsCompanion(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('phone: $phone, ')
          ..write('notes: $notes, ')
          ..write('lastVisit: $lastVisit, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('mod: $mod, ')
          ..write('deleted: $deleted, ')
          ..write('data: $data, ')
          ..write('clinicId: $clinicId, ')
          ..write('hlc: $hlc, ')
          ..write('dirty: $dirty, ')
          ..write('origin: $origin, ')
          ..write('serverSeq: $serverSeq, ')
          ..write('ownerUid: $ownerUid, ')
          ..write('patientId: $patientId, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$AppDatabase extends GeneratedDatabase {
  _$AppDatabase(QueryExecutor e) : super(e);
  $AppDatabaseManager get managers => $AppDatabaseManager(this);
  late final $PatientsTable patients = $PatientsTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [patients];
}

typedef $$PatientsTableCreateCompanionBuilder =
    PatientsCompanion Function({
      required String id,
      required String name,
      Value<String?> phone,
      Value<String?> notes,
      Value<String?> lastVisit,
      Value<String?> createdAt,
      Value<String?> updatedAt,
      Value<int?> mod,
      Value<int?> deleted,
      Value<String?> data,
      Value<String?> clinicId,
      Value<String?> hlc,
      Value<int?> dirty,
      Value<String?> origin,
      Value<int?> serverSeq,
      Value<String?> ownerUid,
      Value<String?> patientId,
      Value<int> rowid,
    });
typedef $$PatientsTableUpdateCompanionBuilder =
    PatientsCompanion Function({
      Value<String> id,
      Value<String> name,
      Value<String?> phone,
      Value<String?> notes,
      Value<String?> lastVisit,
      Value<String?> createdAt,
      Value<String?> updatedAt,
      Value<int?> mod,
      Value<int?> deleted,
      Value<String?> data,
      Value<String?> clinicId,
      Value<String?> hlc,
      Value<int?> dirty,
      Value<String?> origin,
      Value<int?> serverSeq,
      Value<String?> ownerUid,
      Value<String?> patientId,
      Value<int> rowid,
    });

class $$PatientsTableFilterComposer
    extends Composer<_$AppDatabase, $PatientsTable> {
  $$PatientsTableFilterComposer({
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

  ColumnFilters<String> get phone => $composableBuilder(
    column: $table.phone,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get notes => $composableBuilder(
    column: $table.notes,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get lastVisit => $composableBuilder(
    column: $table.lastVisit,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get mod => $composableBuilder(
    column: $table.mod,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get deleted => $composableBuilder(
    column: $table.deleted,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get data => $composableBuilder(
    column: $table.data,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get clinicId => $composableBuilder(
    column: $table.clinicId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get hlc => $composableBuilder(
    column: $table.hlc,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get dirty => $composableBuilder(
    column: $table.dirty,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get origin => $composableBuilder(
    column: $table.origin,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get serverSeq => $composableBuilder(
    column: $table.serverSeq,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get ownerUid => $composableBuilder(
    column: $table.ownerUid,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get patientId => $composableBuilder(
    column: $table.patientId,
    builder: (column) => ColumnFilters(column),
  );
}

class $$PatientsTableOrderingComposer
    extends Composer<_$AppDatabase, $PatientsTable> {
  $$PatientsTableOrderingComposer({
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

  ColumnOrderings<String> get phone => $composableBuilder(
    column: $table.phone,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get notes => $composableBuilder(
    column: $table.notes,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get lastVisit => $composableBuilder(
    column: $table.lastVisit,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get mod => $composableBuilder(
    column: $table.mod,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get deleted => $composableBuilder(
    column: $table.deleted,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get data => $composableBuilder(
    column: $table.data,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get clinicId => $composableBuilder(
    column: $table.clinicId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get hlc => $composableBuilder(
    column: $table.hlc,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get dirty => $composableBuilder(
    column: $table.dirty,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get origin => $composableBuilder(
    column: $table.origin,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get serverSeq => $composableBuilder(
    column: $table.serverSeq,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get ownerUid => $composableBuilder(
    column: $table.ownerUid,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get patientId => $composableBuilder(
    column: $table.patientId,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$PatientsTableAnnotationComposer
    extends Composer<_$AppDatabase, $PatientsTable> {
  $$PatientsTableAnnotationComposer({
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

  GeneratedColumn<String> get phone =>
      $composableBuilder(column: $table.phone, builder: (column) => column);

  GeneratedColumn<String> get notes =>
      $composableBuilder(column: $table.notes, builder: (column) => column);

  GeneratedColumn<String> get lastVisit =>
      $composableBuilder(column: $table.lastVisit, builder: (column) => column);

  GeneratedColumn<String> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<String> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<int> get mod =>
      $composableBuilder(column: $table.mod, builder: (column) => column);

  GeneratedColumn<int> get deleted =>
      $composableBuilder(column: $table.deleted, builder: (column) => column);

  GeneratedColumn<String> get data =>
      $composableBuilder(column: $table.data, builder: (column) => column);

  GeneratedColumn<String> get clinicId =>
      $composableBuilder(column: $table.clinicId, builder: (column) => column);

  GeneratedColumn<String> get hlc =>
      $composableBuilder(column: $table.hlc, builder: (column) => column);

  GeneratedColumn<int> get dirty =>
      $composableBuilder(column: $table.dirty, builder: (column) => column);

  GeneratedColumn<String> get origin =>
      $composableBuilder(column: $table.origin, builder: (column) => column);

  GeneratedColumn<int> get serverSeq =>
      $composableBuilder(column: $table.serverSeq, builder: (column) => column);

  GeneratedColumn<String> get ownerUid =>
      $composableBuilder(column: $table.ownerUid, builder: (column) => column);

  GeneratedColumn<String> get patientId =>
      $composableBuilder(column: $table.patientId, builder: (column) => column);
}

class $$PatientsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $PatientsTable,
          Patient,
          $$PatientsTableFilterComposer,
          $$PatientsTableOrderingComposer,
          $$PatientsTableAnnotationComposer,
          $$PatientsTableCreateCompanionBuilder,
          $$PatientsTableUpdateCompanionBuilder,
          (Patient, BaseReferences<_$AppDatabase, $PatientsTable, Patient>),
          Patient,
          PrefetchHooks Function()
        > {
  $$PatientsTableTableManager(_$AppDatabase db, $PatientsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$PatientsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$PatientsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$PatientsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String?> phone = const Value.absent(),
                Value<String?> notes = const Value.absent(),
                Value<String?> lastVisit = const Value.absent(),
                Value<String?> createdAt = const Value.absent(),
                Value<String?> updatedAt = const Value.absent(),
                Value<int?> mod = const Value.absent(),
                Value<int?> deleted = const Value.absent(),
                Value<String?> data = const Value.absent(),
                Value<String?> clinicId = const Value.absent(),
                Value<String?> hlc = const Value.absent(),
                Value<int?> dirty = const Value.absent(),
                Value<String?> origin = const Value.absent(),
                Value<int?> serverSeq = const Value.absent(),
                Value<String?> ownerUid = const Value.absent(),
                Value<String?> patientId = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => PatientsCompanion(
                id: id,
                name: name,
                phone: phone,
                notes: notes,
                lastVisit: lastVisit,
                createdAt: createdAt,
                updatedAt: updatedAt,
                mod: mod,
                deleted: deleted,
                data: data,
                clinicId: clinicId,
                hlc: hlc,
                dirty: dirty,
                origin: origin,
                serverSeq: serverSeq,
                ownerUid: ownerUid,
                patientId: patientId,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String name,
                Value<String?> phone = const Value.absent(),
                Value<String?> notes = const Value.absent(),
                Value<String?> lastVisit = const Value.absent(),
                Value<String?> createdAt = const Value.absent(),
                Value<String?> updatedAt = const Value.absent(),
                Value<int?> mod = const Value.absent(),
                Value<int?> deleted = const Value.absent(),
                Value<String?> data = const Value.absent(),
                Value<String?> clinicId = const Value.absent(),
                Value<String?> hlc = const Value.absent(),
                Value<int?> dirty = const Value.absent(),
                Value<String?> origin = const Value.absent(),
                Value<int?> serverSeq = const Value.absent(),
                Value<String?> ownerUid = const Value.absent(),
                Value<String?> patientId = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => PatientsCompanion.insert(
                id: id,
                name: name,
                phone: phone,
                notes: notes,
                lastVisit: lastVisit,
                createdAt: createdAt,
                updatedAt: updatedAt,
                mod: mod,
                deleted: deleted,
                data: data,
                clinicId: clinicId,
                hlc: hlc,
                dirty: dirty,
                origin: origin,
                serverSeq: serverSeq,
                ownerUid: ownerUid,
                patientId: patientId,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$PatientsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $PatientsTable,
      Patient,
      $$PatientsTableFilterComposer,
      $$PatientsTableOrderingComposer,
      $$PatientsTableAnnotationComposer,
      $$PatientsTableCreateCompanionBuilder,
      $$PatientsTableUpdateCompanionBuilder,
      (Patient, BaseReferences<_$AppDatabase, $PatientsTable, Patient>),
      Patient,
      PrefetchHooks Function()
    >;

class $AppDatabaseManager {
  final _$AppDatabase _db;
  $AppDatabaseManager(this._db);
  $$PatientsTableTableManager get patients =>
      $$PatientsTableTableManager(_db, _db.patients);
}
