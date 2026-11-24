import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:finanzas_personales/finance.dart';
import 'package:finanzas_personales/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FakeFilePicker extends FilePickerPlatform {
  Uint8List? exportedBytes;
  String? exportedName;
  Uint8List? selectedBytes;
  bool cancelPick = false;
  bool failSave = false;

  @override
  Future<Uri?> saveFile({
    required String fileName,
    required Uint8List bytes,
    required String mimeType,
    String? dialogTitle,
    String? initialDirectory,
    Function(FilePickerStatus)? onFileSaving,
    WindowsOptions windowsOptions = const WindowsOptions(),
    LinuxOptions linuxOptions = const LinuxOptions(),
    WebOptions webOptions = const WebOptions(),
  }) async {
    if (failSave) throw StateError('error al guardar');
    exportedName = fileName;
    exportedBytes = bytes;
    return Uri.file('/mis-finanzas.txt');
  }

  @override
  Future<PlatformFile?> pickFile({
    String? dialogTitle,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Function(FilePickerStatus)? onFileLoading,
    int compressionQuality = 0,
    AndroidOptions androidOptions = const AndroidOptions(),
    DarwinOptions darwinOptions = const DarwinOptions(),
    WindowsOptions windowsOptions = const WindowsOptions(),
    LinuxOptions linuxOptions = const LinuxOptions(),
    WebOptions webOptions = const WebOptions(),
  }) async => cancelPick ? null : FakeSelectedFile(selectedBytes!);
}

final class FakeSelectedFile extends PlatformFile {
  FakeSelectedFile(this.bytes);
  final Uint8List bytes;

  @override
  Future<Uint8List> readAsBytes() async => bytes;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  testWidgets('exports a file and restores it after confirmation', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final oldPicker = FilePickerPlatform.instance;
    final picker = FakeFilePicker();
    FilePickerPlatform.instance = picker;
    addTearDown(() => FilePickerPlatform.instance = oldPicker);
    await FinanceStore().save(const FinanceData(savings: 50000));
    await tester.pumpWidget(const FinanceApp());
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Opciones'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Copia de seguridad'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Guardar archivo'));
    await tester.pumpAndSettle();
    expect(picker.exportedName, 'mis-finanzas.txt');
    expect(
      FinanceData.import(utf8.decode(picker.exportedBytes!)).savings,
      50000,
    );

    picker.selectedBytes = picker.exportedBytes;
    await tester.tap(find.byTooltip('Opciones'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Copia de seguridad'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Restaurar'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Elegir archivo'));
    await tester.pumpAndSettle();
    expect(find.text('Reemplazar datos'), findsOneWidget);
    await tester.tap(find.text('Restaurar'));
    await tester.pumpAndSettle();
    expect((await FinanceStore().load()).savings, 50000);
  });

  testWidgets(
    'invalid or cancelled file selection does not replace existing data',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final oldPicker = FilePickerPlatform.instance;
      final picker = FakeFilePicker()
        ..selectedBytes = Uint8List.fromList(utf8.encode('incorrecto'));
      FilePickerPlatform.instance = picker;
      addTearDown(() => FilePickerPlatform.instance = oldPicker);
      await FinanceStore().save(const FinanceData(savings: 10000));
      await tester.pumpWidget(const FinanceApp());
      await tester.pumpAndSettle();
      Future<void> choose() async {
        await tester.tap(find.byTooltip('Opciones'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Copia de seguridad'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Restaurar'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Elegir archivo'));
        await tester.pumpAndSettle();
      }

      await choose();
      expect(find.textContaining('La copia no es válida'), findsOneWidget);
      expect((await FinanceStore().load()).savings, 10000);
      picker.cancelPick = true;
      await choose();
      expect(find.text('Reemplazar datos'), findsNothing);
      expect((await FinanceStore().load()).savings, 10000);
    },
  );

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
    await tester.tap(find.text('Pegar texto'));
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
