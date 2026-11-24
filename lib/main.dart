import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'finance.dart';

void main() => runApp(const FinanceApp());

class FinanceApp extends StatelessWidget {
  const FinanceApp({super.key, this.store});
  final FinanceStore? store;

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Mis finanzas',
    debugShowCheckedModeBanner: false,
    locale: const Locale('es'),
    supportedLocales: const [Locale('es')],
    localizationsDelegates: GlobalMaterialLocalizations.delegates,
    theme: ThemeData(
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xff176c58),
        surface: const Color(0xfff8faf8),
      ),
      useMaterial3: true,
      scaffoldBackgroundColor: const Color(0xfff4f7f5),
      inputDecorationTheme: const InputDecorationTheme(
        border: OutlineInputBorder(),
      ),
    ),
    home: FinanceHome(store: store ?? FinanceStore()),
  );
}

class FinanceHome extends StatefulWidget {
  const FinanceHome({super.key, required this.store});
  final FinanceStore store;

  @override
  State<FinanceHome> createState() => _FinanceHomeState();
}

class _FinanceHomeState extends State<FinanceHome> {
  FinanceData? data;
  Object? loadError;
  bool busy = false;
  DateTime month = DateTime(DateTime.now().year, DateTime.now().month);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => loadError = null);
    try {
      final result = await widget.store.load();
      if (mounted) setState(() => data = result);
    } catch (error) {
      if (mounted) setState(() => loadError = error);
    }
  }

  Future<bool> _save(FinanceData next) async {
    if (busy) return false;
    setState(() => busy = true);
    try {
      await widget.store.save(next);
      if (mounted) setState(() => data = next);
      return true;
    } catch (error) {
      if (mounted) _message('No se pudieron guardar los cambios: $error');
      return false;
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  void _message(String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  DateTime _defaultDate() {
    final now = DateTime.now();
    return monthKey(now) == monthKey(month)
        ? DateTime(now.year, now.month, now.day)
        : month;
  }

  Future<void> _movement({required bool income, Movement? existing}) async {
    final result = await showDialog<_MovementResult>(
      context: context,
      builder: (_) => _MovementDialog(
        income: income,
        month: month,
        initialDate: existing?.date ?? _defaultDate(),
        existing: existing,
      ),
    );
    if (result == null || !mounted) return;
    final current = data!;
    final recurrenceId =
        existing?.recurrenceId ?? (result.recurring ? newId() : null);
    final movement = Movement(
      id: existing?.id ?? newId(),
      concept: result.concept,
      cents: result.cents,
      date: result.date,
      isIncome: income,
      recurrenceId: recurrenceId,
    );
    final movements = [...current.movements];
    if (existing != null) movements.removeWhere((m) => m.id == existing.id);
    movements.add(movement);
    final recurring = [...current.recurring];
    if (existing == null && recurrenceId != null) {
      recurring.add(
        RecurringExpense(
          id: recurrenceId,
          concept: result.concept,
          cents: result.cents,
          startMonth: monthKey(result.date),
        ),
      );
    }
    await _save(current.copyWith(movements: movements, recurring: recurring));
  }

  Future<void> _confirmRecurring(RecurringExpense expense) async {
    final current = data!;
    if (!current.pending(month).any((r) => r.id == expense.id)) return;
    final movement = Movement(
      id: newId(),
      concept: expense.concept,
      cents: expense.cents,
      date: _defaultDate(),
      isIncome: false,
      recurrenceId: expense.id,
    );
    await _save(current.copyWith(movements: [...current.movements, movement]));
  }

  Future<void> _deleteMovement(Movement movement) async {
    final confirmed = await _confirm(
      'Eliminar movimiento',
      movement.recurrenceId == null ? '¿Quieres eliminar este movimiento?' : '¿Quieres eliminar este movimiento? El gasto recurrente volverá a aparecer como pendiente este mes.',
      'Eliminar',
    );
    if (!confirmed || !mounted) return;
    await _save(
      data!.copyWith(
        movements: data!.movements.where((m) => m.id != movement.id).toList(),
      ),
    );
  }

  Future<bool> _confirm(String title, String text, String action) async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(title),
          content: Text(text),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(action),
            ),
          ],
        ),
      ) ??
      false;

  Future<void> _editSavings() async {
    final controller = TextEditingController(text: amountInput(data!.savings));
    final formKey = GlobalKey<FormState>();
    final route = DialogRoute<int>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Mis ahorros'),
        content: Form(
          key: formKey,
          child: TextFormField(
            controller: controller,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'Cantidad ahorrada',
              suffixText: '€',
            ),
            validator: (value) =>
                parseAmount(value ?? '', allowZero: true) == null
                ? 'Introduce un importe válido.'
                : null,
            onFieldSubmitted: (_) {
              if (formKey.currentState!.validate()) {
                Navigator.pop(
                  context,
                  parseAmount(controller.text, allowZero: true),
                );
              }
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () {
              if (formKey.currentState!.validate()) {
                Navigator.pop(
                  context,
                  parseAmount(controller.text, allowZero: true),
                );
              }
            },
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
    Navigator.of(context).push(route);
    final value = await route.completed;
    controller.dispose();
    if (value != null && mounted) await _save(data!.copyWith(savings: value));
  }

  Future<void> _recurringSettings() async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, refresh) => AlertDialog(
          title: const Text('Gastos recurrentes'),
          content: SizedBox(
            width: 400,
            child: data!.recurring.isEmpty
                ? const Text('Aún no tienes gastos recurrentes.')
                : SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: data!.recurring
                          .map(
                            (expense) => ListTile(
                              contentPadding: EdgeInsets.zero,
                              title: Text(expense.concept),
                              subtitle: Text(
                                '${formatAmount(expense.cents)} al mes',
                              ),
                              trailing: IconButton(
                                tooltip: 'Dejar de repetir',
                                icon: const Icon(Icons.delete_outline),
                                onPressed: busy
                                    ? null
                                    : () async {
                                        final confirmed = await _confirm(
                                          'Dejar de repetir',
                                          'Se quitará "${expense.concept}" de los pendientes. Los movimientos ya registrados se conservarán.',
                                          'Dejar de repetir',
                                        );
                                        if (!confirmed || !mounted) return;
                                        final saved = await _save(
                                          data!.copyWith(
                                            recurring: data!.recurring
                                                .where(
                                                  (r) => r.id != expense.id,
                                                )
                                                .toList(),
                                          ),
                                        );
                                        if (saved && dialogContext.mounted) {
                                          refresh(() {});
                                        }
                                      },
                              ),
                            ),
                          )
                          .toList(),
                    ),
                  ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cerrar'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _backup() async {
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Copia de seguridad'),
        content: const Text(
          'Copia tus datos como texto y guárdalos en un lugar privado. '
          'Puedes pegarlos después para restaurarlos en este u otro dispositivo. '
          'El texto contiene toda tu información financiera.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cerrar'),
          ),
          TextButton(
            onPressed: () async {
              try {
                await Clipboard.setData(ClipboardData(text: data!.export()));
                if (!context.mounted) return;
                Navigator.pop(context);
                _message('Copia creada. Pega el texto en un lugar seguro.');
              } catch (error) {
                if (context.mounted) _message('No se pudo copiar: $error');
              }
            },
            child: const Text('Copiar datos'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(context);
              _importBackup();
            },
            child: const Text('Restaurar'),
          ),
        ],
      ),
    );
  }

  Future<void> _importBackup() async {
    final controller = TextEditingController();
    final route = DialogRoute<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Restaurar copia'),
        content: SizedBox(
          width: 450,
          child: TextField(
            controller: controller,
            minLines: 5,
            maxLines: 10,
            decoration: const InputDecoration(
              hintText: 'Pega aquí el texto de tu copia de seguridad',
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('Continuar'),
          ),
        ],
      ),
    );
    Navigator.of(context).push(route);
    final text = await route.completed;
    controller.dispose();
    if (text == null || !mounted) return;
    late final FinanceData imported;
    try {
      imported = FinanceData.import(text);
    } on FormatException catch (error) {
      _message('La copia no es válida: ${error.message}');
      return;
    }
    final confirmed = await _confirm(
      'Reemplazar datos',
      'La copia reemplazará todos los datos actuales de este dispositivo. Esta acción no se puede deshacer.',
      'Restaurar',
    );
    if (confirmed && mounted && await _save(imported) && mounted) {
      _message('Copia restaurada.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final current = data;
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Mis finanzas',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        actions: [
          if (current != null)
            PopupMenuButton<String>(
              tooltip: 'Opciones',
              onSelected: (value) {
                if (value == 'recurring') _recurringSettings();
                if (value == 'backup') _backup();
              },
              itemBuilder: (_) => const [
                PopupMenuItem(
                  value: 'recurring',
                  child: Text('Gastos recurrentes'),
                ),
                PopupMenuItem(
                  value: 'backup',
                  child: Text('Copia de seguridad'),
                ),
              ],
            ),
        ],
      ),
      body: current == null
          ? Center(
              child: loadError == null
                  ? const CircularProgressIndicator()
                  : Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'No se pudieron cargar tus datos: $loadError',
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 12),
                          FilledButton(
                            onPressed: _load,
                            child: const Text('Reintentar'),
                          ),
                          TextButton(
                            onPressed: _importBackup,
                            child: const Text('Restaurar una copia'),
                          ),
                        ],
                      ),
                    ),
            )
          : _body(current),
    );
  }

  Widget _body(FinanceData current) {
    final movements = current.forMonth(month);
    final income = movements
        .where((m) => m.isIncome)
        .fold<int>(0, (sum, m) => sum + m.cents);
    final expenses = movements
        .where((m) => !m.isIncome)
        .fold<int>(0, (sum, m) => sum + m.cents);
    final previous = current.forMonth(DateTime(month.year, month.month - 1));
    final previousBalance = previous.fold<int>(
      0,
      (sum, m) => sum + (m.isIncome ? m.cents : -m.cents),
    );
    final difference = income - expenses - previousBalance;
    final pending = current.pending(month);
    return AbsorbPointer(
      absorbing: busy,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 40),
        children: [
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 700),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      IconButton(
                        tooltip: 'Mes anterior',
                        onPressed: month.year == 1900 && month.month == 1
                            ? null
                            : () => setState(
                                () => month = DateTime(
                                  month.year,
                                  month.month - 1,
                                ),
                              ),
                        icon: const Icon(Icons.chevron_left),
                      ),
                      Expanded(
                        child: Text(
                          _monthName(month),
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.titleLarge
                              ?.copyWith(fontWeight: FontWeight.bold),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Mes siguiente',
                        onPressed: month.year == 9999 && month.month == 12
                            ? null
                            : () => setState(
                                () => month = DateTime(
                                  month.year,
                                  month.month + 1,
                                ),
                              ),
                        icon: const Icon(Icons.chevron_right),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(22),
                    decoration: BoxDecoration(
                      color: const Color(0xff145f4d),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Balance del mes',
                          style: TextStyle(color: Colors.white70),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          formatAmount(income - expenses),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 32,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        if (previous.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            '${difference > 0 ? '+' : ''}${formatAmount(difference)} frente al mes anterior',
                            style: const TextStyle(color: Colors.white70),
                          ),
                        ],
                        const SizedBox(height: 20),
                        Row(
                          children: [
                            Expanded(child: _summary('Ingresos', income)),
                            Expanded(child: _summary('Gastos', expenses)),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  Card(
                    child: ListTile(
                      leading: const CircleAvatar(
                        child: Icon(Icons.savings_outlined),
                      ),
                      title: const Text('Mis ahorros'),
                      subtitle: const Text(
                        'Cantidad total, independiente del balance',
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            formatAmount(current.savings),
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(width: 4),
                          const Icon(Icons.edit_outlined, size: 19),
                        ],
                      ),
                      onTap: _editSavings,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: () => _movement(income: true),
                          icon: const Icon(Icons.add),
                          label: const Text('Ingreso'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: FilledButton.tonalIcon(
                          onPressed: () => _movement(income: false),
                          icon: const Icon(Icons.remove),
                          label: const Text('Gasto'),
                        ),
                      ),
                    ],
                  ),
                  if (pending.isNotEmpty) ...[
                    const SizedBox(height: 28),
                    _sectionTitle('Pendientes', '${pending.length}'),
                    const SizedBox(height: 4),
                    const Text(
                      'Confirma los gastos recurrentes cuando los pagues.',
                      style: TextStyle(color: Colors.black54),
                    ),
                    const SizedBox(height: 8),
                    ...pending.map(
                      (expense) => Card(
                        child: ListTile(
                          title: Text(expense.concept),
                          subtitle: Text(formatAmount(expense.cents)),
                          trailing: TextButton(
                            onPressed: () => _confirmRecurring(expense),
                            child: const Text('Confirmar'),
                          ),
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 28),
                  _sectionTitle('Movimientos', '${movements.length}'),
                  const SizedBox(height: 8),
                  if (movements.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 24),
                      child: Text(
                        'Aún no hay movimientos este mes.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.black54),
                      ),
                    )
                  else
                    ...movements.map(
                      (movement) => Card(
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor: movement.isIncome
                                ? const Color(0xffe1f3eb)
                                : const Color(0xffffece7),
                            child: Icon(
                              movement.isIncome
                                  ? Icons.south_west
                                  : Icons.north_east,
                              color: movement.isIncome
                                  ? const Color(0xff176c58)
                                  : const Color(0xffad4d3e),
                            ),
                          ),
                          title: Text(movement.concept),
                          subtitle: Text(
                            '${movement.date.day} ${_shortMonth(movement.date)}${movement.recurrenceId != null ? ' · Recurrente' : ''}',
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                '${movement.isIncome ? '+' : '-'}${formatAmount(movement.cents)}',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: movement.isIncome
                                      ? const Color(0xff176c58)
                                      : const Color(0xffad4d3e),
                                ),
                              ),
                              PopupMenuButton<String>(
                                tooltip: 'Opciones del movimiento',
                                onSelected: (value) {
                                  if (value == 'edit') {
                                    _movement(
                                      income: movement.isIncome,
                                      existing: movement,
                                    );
                                  }
                                  if (value == 'delete') {
                                    _deleteMovement(movement);
                                  }
                                },
                                itemBuilder: (_) => const [
                                  PopupMenuItem(
                                    value: 'edit',
                                    child: Text('Editar'),
                                  ),
                                  PopupMenuItem(
                                    value: 'delete',
                                    child: Text('Eliminar'),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _summary(String title, int amount) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(title, style: const TextStyle(color: Colors.white70)),
      const SizedBox(height: 4),
      Text(
        formatAmount(amount),
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w600,
        ),
      ),
    ],
  );

  Widget _sectionTitle(String title, String count) => Row(
    children: [
      Text(
        title,
        style: Theme.of(context).textTheme.titleMedium
            ?.copyWith(fontWeight: FontWeight.bold),
      ),
      const SizedBox(width: 8),
      Text(count, style: const TextStyle(color: Colors.black54)),
    ],
  );
}

const _months = [
  'enero',
  'febrero',
  'marzo',
  'abril',
  'mayo',
  'junio',
  'julio',
  'agosto',
  'septiembre',
  'octubre',
  'noviembre',
  'diciembre',
];
String _monthName(DateTime date) {
  final name = _months[date.month - 1];
  return '${name[0].toUpperCase()}${name.substring(1)} ${date.year}';
}

String _shortMonth(DateTime date) => _months[date.month - 1].substring(0, 3);

class _MovementResult {
  const _MovementResult(this.concept, this.cents, this.date, this.recurring);
  final String concept;
  final int cents;
  final DateTime date;
  final bool recurring;
}

class _MovementDialog extends StatefulWidget {
  const _MovementDialog({
    required this.income,
    required this.month,
    required this.initialDate,
    this.existing,
  });
  final bool income;
  final DateTime month;
  final DateTime initialDate;
  final Movement? existing;

  @override
  State<_MovementDialog> createState() => _MovementDialogState();
}

class _MovementDialogState extends State<_MovementDialog> {
  final formKey = GlobalKey<FormState>();
  late final TextEditingController concept;
  late final TextEditingController amount;
  late DateTime date;
  bool recurring = false;

  @override
  void initState() {
    super.initState();
    concept = TextEditingController(text: widget.existing?.concept);
    amount = TextEditingController(
      text: widget.existing == null ? '' : amountInput(widget.existing!.cents),
    );
    date = widget.initialDate;
  }

  @override
  void dispose() {
    concept.dispose();
    amount.dispose();
    super.dispose();
  }

  void submit() {
    if (formKey.currentState!.validate()) {
      Navigator.pop(
        context,
        _MovementResult(
          concept.text.trim(),
          parseAmount(amount.text)!,
          date,
          recurring,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(
      '${widget.existing == null ? 'Nuevo' : 'Editar'} ${widget.income ? 'ingreso' : 'gasto'}',
    ),
    content: SizedBox(
      width: 400,
      child: Form(
        key: formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: concept,
                autofocus: true,
                maxLength: 200,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Concepto',
                  hintText: 'Ej. supermercado',
                  counterText: '',
                ),
                validator: (value) => value == null || value.trim().isEmpty
                    ? 'Escribe un concepto.'
                    : null,
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: amount,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'Monto',
                  hintText: '0,00',
                  suffixText: '€',
                ),
                validator: (value) => parseAmount(value ?? '') == null
                    ? 'Introduce un importe mayor que cero (máximo 2 decimales).'
                    : null,
                onFieldSubmitted: (_) => submit(),
              ),
              const SizedBox(height: 8),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.calendar_today_outlined),
                title: Text('Fecha: ${date.day} de ${_months[date.month - 1]}'),
                trailing: const Icon(Icons.edit_outlined, size: 18),
                onTap: () async {
                  final selected = await showDatePicker(
                    context: context,
                    initialDate: date,
                    firstDate: widget.month,
                    lastDate: DateTime(
                      widget.month.year,
                      widget.month.month + 1,
                      0,
                    ),
                  );
                  if (selected != null) setState(() => date = selected);
                },
              ),
              if (!widget.income && widget.existing == null)
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: recurring,
                  onChanged: (value) =>
                      setState(() => recurring = value ?? false),
                  title: const Text('Repetir cada mes'),
                  subtitle: const Text('Podrás confirmar cada pago.'),
                  controlAffinity: ListTileControlAffinity.leading,
                ),
              if (widget.existing?.recurrenceId != null)
                const Text(
                  'Los cambios solo afectan a este movimiento.',
                  style: TextStyle(color: Colors.black54),
                ),
            ],
          ),
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancelar'),
      ),
      FilledButton(onPressed: submit, child: const Text('Guardar')),
    ],
  );
}
