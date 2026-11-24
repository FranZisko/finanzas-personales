import 'dart:convert';
import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

const int maxAmount = 99999999999;

int? parseAmount(String input, {bool allowZero = false}) {
  final match = RegExp(r'^(\d{1,9})(?:[,.](\d{1,2}))?$')
      .firstMatch(input.trim());
  if (match == null) return null;
  final cents =
      int.parse(match.group(1)!) * 100 +
      int.parse((match.group(2) ?? '').padRight(2, '0'));
  if (cents > maxAmount || (!allowZero && cents == 0)) return null;
  return cents;
}

String formatAmount(int cents) {
  final negative = cents < 0;
  final value = cents.abs();
  final digits = (value ~/ 100).toString();
  final grouped = digits.replaceAllMapped(
    RegExp(r'\B(?=(\d{3})+(?!\d))'),
    (_) => '.',
  );
  return '${negative ? '-' : ''}$grouped,${(value % 100).toString().padLeft(2, '0')} €';
}

String amountInput(int cents) =>
    '${cents ~/ 100},${(cents % 100).toString().padLeft(2, '0')}';

String monthKey(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}';

String newId() {
  final random = Random.secure();
  return List.generate(
    16,
    (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
  ).join();
}

class Movement {
  const Movement({
    required this.id,
    required this.concept,
    required this.cents,
    required this.date,
    required this.isIncome,
    this.recurrenceId,
  });

  final String id;
  final String concept;
  final int cents;
  final DateTime date;
  final bool isIncome;
  final String? recurrenceId;

  Map<String, Object?> toJson() => {
    'id': id,
    'concept': concept,
    'cents': cents,
    'date': date.toIso8601String(),
    'isIncome': isIncome,
    'recurrenceId': recurrenceId,
  };

  factory Movement.fromJson(Object? value) {
    final map = _object(value);
    final dateText = _string(map['date']);
    final date = DateTime.tryParse(dateText);
    if (date == null || date.isUtc || date.year < 1900 || date.year > 9999) {
      throw const FormatException('Fecha de movimiento inválida.');
    }
    final income = map['isIncome'];
    if (income is! bool) {
      throw const FormatException('Tipo de movimiento inválido.');
    }
    final recurrenceId = map['recurrenceId'];
    if (recurrenceId != null &&
        (recurrenceId is! String || recurrenceId.isEmpty || income)) {
      throw const FormatException('Gasto recurrente inválido.');
    }
    return Movement(
      id: _string(map['id']),
      concept: _string(map['concept']),
      cents: _amount(map['cents']),
      date: date,
      isIncome: income,
      recurrenceId: recurrenceId as String?,
    );
  }
}

class RecurringExpense {
  const RecurringExpense({
    required this.id,
    required this.concept,
    required this.cents,
    required this.startMonth,
  });

  final String id;
  final String concept;
  final int cents;
  final String startMonth;

  Map<String, Object> toJson() => {
    'id': id,
    'concept': concept,
    'cents': cents,
    'startMonth': startMonth,
  };

  factory RecurringExpense.fromJson(Object? value) {
    final map = _object(value);
    final start = _string(map['startMonth']);
    if (!RegExp(r'^(19\d\d|[2-9]\d{3})-(0[1-9]|1[0-2])$').hasMatch(start)) {
      throw const FormatException('Mes de inicio inválido.');
    }
    return RecurringExpense(
      id: _string(map['id']),
      concept: _string(map['concept']),
      cents: _amount(map['cents']),
      startMonth: start,
    );
  }
}

class FinanceData {
  const FinanceData({
    this.savings = 0,
    this.movements = const [],
    this.recurring = const [],
  });

  final int savings;
  final List<Movement> movements;
  final List<RecurringExpense> recurring;

  FinanceData copyWith({
    int? savings,
    List<Movement>? movements,
    List<RecurringExpense>? recurring,
  }) => FinanceData(
    savings: savings ?? this.savings,
    movements: movements ?? this.movements,
    recurring: recurring ?? this.recurring,
  );

  List<Movement> forMonth(DateTime month) =>
      movements.where((m) => monthKey(m.date) == monthKey(month)).toList()
        ..sort((a, b) => b.date.compareTo(a.date));

  List<RecurringExpense> pending(DateTime month) {
    final key = monthKey(month);
    final confirmed = movements
        .where((m) => monthKey(m.date) == key && m.recurrenceId != null)
        .map((m) => m.recurrenceId)
        .toSet();
    return recurring
        .where(
          (r) => r.startMonth.compareTo(key) <= 0 && !confirmed.contains(r.id),
        )
        .toList();
  }

  String export() => const JsonEncoder.withIndent('  ').convert({
    'version': 1,
    'savings': savings,
    'movements': movements.map((m) => m.toJson()).toList(),
    'recurring': recurring.map((r) => r.toJson()).toList(),
  });

  factory FinanceData.import(String text) {
    final map = _object(jsonDecode(text));
    if (map['version'] != 1 ||
        map['movements'] is! List ||
        map['recurring'] is! List) {
      throw const FormatException('Formato de copia no compatible.');
    }
    final movements = (map['movements'] as List)
        .map(Movement.fromJson)
        .toList();
    final recurring = (map['recurring'] as List)
        .map(RecurringExpense.fromJson)
        .toList();
    if (movements.map((m) => m.id).toSet().length != movements.length ||
        recurring.map((r) => r.id).toSet().length != recurring.length) {
      throw const FormatException(
        'La copia contiene identificadores duplicados.',
      );
    }
    final occurrences = <String>{};
    for (final m in movements.where((m) => m.recurrenceId != null)) {
      if (!occurrences.add('${m.recurrenceId}:${monthKey(m.date)}')) {
        throw const FormatException(
          'La copia contiene gastos recurrentes duplicados.',
        );
      }
    }
    return FinanceData(
      savings: _amount(map['savings'], allowZero: true),
      movements: movements,
      recurring: recurring,
    );
  }
}

Map<String, dynamic> _object(Object? value) {
  if (value is! Map<String, dynamic>) {
    throw const FormatException('Datos inválidos.');
  }
  return value;
}

String _string(Object? value) {
  if (value is! String || value.trim().isEmpty || value.length > 200) {
    throw const FormatException('Texto inválido.');
  }
  return value;
}

int _amount(Object? value, {bool allowZero = false}) {
  if (value is! int || value < (allowZero ? 0 : 1) || value > maxAmount) {
    throw const FormatException('Importe inválido.');
  }
  return value;
}

class FinanceStore {
  static const _key = 'finanzas_v1';

  Future<FinanceData> load() async {
    final prefs = await SharedPreferences.getInstance();
    final text = prefs.getString(_key);
    return text == null ? const FinanceData() : FinanceData.import(text);
  }

  Future<void> save(FinanceData data) async {
    final prefs = await SharedPreferences.getInstance();
    if (!await prefs.setString(_key, data.export())) {
      throw StateError('No se pudieron guardar los datos.');
    }
  }
}
