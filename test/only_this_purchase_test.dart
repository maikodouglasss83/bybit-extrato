import 'package:bybit_extrato/app_state.dart';
import 'package:bybit_extrato/models.dart';
import 'package:bybit_extrato/util/categorizer.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Canal do cofre onde o app guarda os ajustes.
const _cofre = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_cofre, (_) async => null);
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_cofre, null);
  });

  /// Duas cobranças da mesma operadora: a internet de casa e o celular.
  LedgerEntry cobranca(String id, double valor) =>
      LedgerEntry.fromCardTransaction({
        'transactionId': id,
        'side': '1',
        'transactionDate': '${DateTime(2026, 9, 10).millisecondsSinceEpoch}',
        'transactionAmount': '$valor',
        'basicCurrency': 'BRL',
        'merchName': 'NET PGT*FATURA CLARO',
      });

  late LedgerEntry internet;
  late LedgerEntry celular;
  late AppState state;

  setUp(() {
    internet = cobranca('net', 124.81);
    celular = cobranca('cel', 70);
    state = AppState()..seedEntries([internet, celular]);
  });

  group('Só esta compra', () {
    test('a categoria muda só na compra editada', () async {
      final antes = state.categoryOf(celular);

      await state.setEntryOverrides(
        internet,
        category: SpendCategories.casa,
        onlyThis: true,
      );

      expect(state.categoryOf(internet), SpendCategories.casa);
      expect(state.categoryOf(celular), antes);
    });

    test('fixo ou variável muda só na compra editada', () async {
      final antes = state.isFixed(celular);

      await state.setFixed(internet, !antes, onlyThis: true);

      expect(state.isFixed(internet), !antes);
      expect(state.isFixed(celular), antes);
    });

    test('o nome também fica só nela', () async {
      await state.setEntryOverrides(
        internet,
        name: 'Internet Residencial',
        onlyThis: true,
      );

      expect(state.displayNameOf(internet), 'Internet Residencial');
      expect(state.displayNameOf(celular), isNot('Internet Residencial'));
    });

    test('escolher o que o lugar já tem não vira ajuste', () async {
      await state.setEntryOverrides(
        internet,
        category: state.categoryOf(celular),
        onlyThis: true,
      );

      expect(state.hasEntryAdjustments(internet), isFalse);
    });
  });

  group('O lugar todo', () {
    test('muda todas, inclusive a que tinha categoria própria', () async {
      await state.setEntryOverrides(
        internet,
        category: SpendCategories.casa,
        onlyThis: true,
      );

      // Agora para o lugar todo, a partir da outra compra.
      await state.setEntryOverrides(celular, category: SpendCategories.telefonia);

      expect(state.categoryOf(internet), SpendCategories.telefonia);
      expect(state.categoryOf(celular), SpendCategories.telefonia);
      expect(state.hasEntryAdjustments(internet), isFalse);
    });

    test('fixo para o lugar todo desfaz a escolha própria', () async {
      await state.setFixed(internet, true, onlyThis: true);
      await state.setFixed(celular, false);

      expect(state.isFixed(internet), isFalse);
      expect(state.isFixed(celular), isFalse);
    });
  });
}
