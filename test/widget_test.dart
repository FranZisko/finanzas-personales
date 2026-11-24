import 'package:finanzas_personales/finance.dart';
import 'package:finanzas_personales/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('validates input and saves income on a narrow screen', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    await tester.binding.setSurfaceSize(const Size(360, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const FinanceApp());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Ingreso'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Guardar'));
    await tester.pumpAndSettle();
    expect(find.text('Escribe un concepto.'), findsOneWidget);
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Concepto'),
      'Trabajo',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Monto'),
      '100,25',
    );
    await tester.tap(find.text('Guardar'));
    await tester.pumpAndSettle();
    expect(find.text('+100,25 €'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a backup can restore data when stored data is corrupt', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({'finanzas_v1': 'corrupto'});
    await tester.pumpWidget(const FinanceApp());
    await tester.pumpAndSettle();
    expect(
      find.textContaining('No se pudieron cargar tus datos'),
      findsOneWidget,
    );
    await tester.tap(find.text('Restaurar una copia'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byType(TextField),
      const FinanceData(savings: 50000).export(),
    );
    await tester.tap(find.text('Continuar'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Restaurar'));
    await tester.pumpAndSettle();
    expect(find.text('500,00 €'), findsOneWidget);
    expect((await FinanceStore().load()).savings, 50000);
  });

  testWidgets(
    'registers a recurring expense and confirms it in the next month',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      await tester.binding.setSurfaceSize(const Size(900, 1100));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(const FinanceApp());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Gasto'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Concepto'),
        'Internet',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Monto'),
        '25,50',
      );
      await tester.tap(find.text('Repetir cada mes'));
      await tester.tap(find.text('Guardar'));
      await tester.pumpAndSettle();
      expect(find.text('Internet'), findsOneWidget);
      expect(find.text('-25,50 €'), findsNWidgets(2));

      await tester.tap(find.byTooltip('Mes siguiente'));
      await tester.pumpAndSettle();
      expect(find.text('Confirmar'), findsOneWidget);
      await tester.tap(find.text('Confirmar'));
      await tester.pumpAndSettle();
      expect(find.text('Confirmar'), findsNothing);
      expect(find.text('-25,50 €'), findsNWidgets(2));

      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(const FinanceApp());
      await tester.pumpAndSettle();
      expect(find.text('Internet'), findsOneWidget);
    },
  );
}
