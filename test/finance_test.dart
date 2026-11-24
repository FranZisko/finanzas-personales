import 'dart:convert';

import 'package:finanzas_personales/finance.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('money is parsed exactly, with at most two decimal places', () {
    expect(parseAmount('12,3'), 1230);
    expect(parseAmount('12.34'), 1234);
    expect(parseAmount('0'), isNull);
    expect(parseAmount('0', allowZero: true), 0);
    expect(parseAmount('1,234'), isNull);
    expect(parseAmount('-1'), isNull);
    expect(formatAmount(-123456), '-1.234,56 €');
  });

  test(
    'recurring expense is pending from its start until confirmed each month',
    () {
      const recurring = RecurringExpense(
        id: 'rent',
        concept: 'Alquiler',
        cents: 80000,
        startMonth: '2026-03',
      );
      final data = FinanceData(
        recurring: const [recurring],
        movements: [
          Movement(
            id: 'march',
            concept: 'Alquiler',
            cents: 80000,
            date: DateTime(2026, 3, 5),
            isIncome: false,
            recurrenceId: 'rent',
          ),
        ],
      );
      expect(data.pending(DateTime(2026, 2)), isEmpty);
      expect(data.pending(DateTime(2026, 3)), isEmpty);
      expect(data.pending(DateTime(2026, 4)), [recurring]);
      expect(data.copyWith(movements: []).pending(DateTime(2026, 3)), [
        recurring,
      ]);
    },
  );

  test(
    'backup round trip preserves data and rejects duplicate occurrences',
    () {
      final movement = Movement(
        id: 'one',
        concept: 'Luz',
        cents: 1200,
        date: DateTime(2026, 4, 3),
        isIncome: false,
        recurrenceId: 'electricity',
      );
      final original = FinanceData(savings: 50000, movements: [movement]);
      final restored = FinanceData.import(original.export());
      expect(restored.savings, 50000);
      expect(restored.movements.single.concept, 'Luz');
      final json = jsonDecode(original.export()) as Map<String, dynamic>;
      final duplicate = Map<String, dynamic>.from(movement.toJson())
        ..['id'] = 'two';
      (json['movements'] as List).add(duplicate);
      expect(() => FinanceData.import(jsonEncode(json)), throwsFormatException);
      expect(() => FinanceData.import('no es json'), throwsFormatException);
    },
  );

  test(
    'storage persists data and reports corrupt data instead of resetting it',
    () async {
      SharedPreferences.setMockInitialValues({});
      final store = FinanceStore();
      expect((await store.load()).savings, 0);
      await store.save(const FinanceData(savings: 12345));
      expect((await store.load()).savings, 12345);
      SharedPreferences.setMockInitialValues({'finanzas_v1': 'corrupto'});
      await expectLater(store.load(), throwsFormatException);
    },
  );
}
