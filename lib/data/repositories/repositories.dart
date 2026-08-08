/// ============================================================================
///  Repositories barrel + aggregate — mirror of repositories/index.js
/// ============================================================================
///
///  Phase 1 invariant preserved: UI/stores import data access ONLY from here.
///  The JS module singletons become one [Repositories] aggregate over a shared
///  [LocalDb] (DI/Riverpod-friendly, trivially testable).
library;

import '../db/local_db.dart';
import 'appointments_repository.dart';
import 'base_repository.dart';
import 'config_repository.dart';
import 'debts_repository.dart';
import 'patients_repository.dart';
import 'prosthetics_repository.dart';
import 'queue_repository.dart';
import 'records_repository.dart';
import 'employees_repository.dart';
import 'expenses_repository.dart';
import 'settings_repository.dart';
import 'xrays_repository.dart';

export 'appointments_repository.dart';
export 'base_repository.dart';
export 'config_repository.dart';
export 'debts_repository.dart';
export 'patients_repository.dart'
    show
        PatientsRepository,
        patientKeyFor,
        patientIdForName,
        resolvePid,
        clinicKeyFor,
        clinicScopedKey;
export 'prosthetics_repository.dart';
export 'queue_repository.dart';
export 'records_repository.dart';
export 'employees_repository.dart';
export 'expenses_repository.dart';
export 'settings_repository.dart';
export 'xrays_repository.dart';

class Repositories {
  Repositories(this.db)
      : patients = PatientsRepository(db),
        appointments = AppointmentsRepository(db),
        records = RecordsRepository(db),
        debts = DebtsRepository(db),
        prosthetics = ProstheticsRepository(db),
        xrays = XraysRepository(db),
        queue = QueueRepository(db),
        employees = EmployeesRepository(db),
        expenses = ExpensesRepository(db),
        settings = SettingsRepository(db),
        config = ConfigRepository(db);

  final LocalDb db;

  final PatientsRepository patients;
  final AppointmentsRepository appointments;
  final RecordsRepository records;
  final DebtsRepository debts;
  final ProstheticsRepository prosthetics;
  final XraysRepository xrays;
  final QueueRepository queue;
  final EmployeesRepository employees;
  final ExpensesRepository expenses;
  final SettingsRepository settings;
  final ConfigRepository config;

  /// Every BaseRepository-backed entity (sync engine iteration order).
  List<BaseRepository> get all => [
        patients, appointments, records, debts, prosthetics, xrays, queue,
        employees, expenses,
      ];
}
