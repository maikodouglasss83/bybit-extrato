import 'package:bybit_extrato/app_state.dart';
import 'package:bybit_extrato/budget.dart';
import 'package:bybit_extrato/models.dart';
import 'package:bybit_extrato/theme.dart';
import 'package:bybit_extrato/ui/widgets/entry_editor.dart';
import 'package:bybit_extrato/util/categorizer.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

/// Canal do cofre onde o app guarda os ajustes.
const _cofre = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => initializeDateFormatting('pt_BR', null));

  setUp(() {
    // O cursor piscando agenda quadros sem parar, e o pumpAndSettle nunca
    // terminaria de esperar a tela assentar.
    EditableText.debugDeterministicCursor = true;
    // Criar uma categoria e salvar a compra gravam no cofre. Sem resposta
    // simulada, essas gravações ficariam esperando uma resposta que o
    // ambiente de teste nunca entrega, e a tela não sairia do lugar.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_cofre, (_) async => null);
  });

  tearDown(() {
    EditableText.debugDeterministicCursor = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_cofre, null);
  });

  LedgerEntry compra() => LedgerEntry.fromCardTransaction({
        'transactionId': 'c1',
        'side': '1',
        'transactionDate': '${DateTime(2026, 9, 7, 14).millisecondsSinceEpoch}',
        'transactionAmount': '68.61',
        'basicCurrency': 'BRL',
        'merchName': 'ATACADO E AUTO SERVICO',
      });

  Future<void> abrirEditor(
    WidgetTester tester,
    AppState state,
    LedgerEntry entry,
  ) async {
    tester.view.physicalSize = const Size(600, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(Brightness.dark),
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: TextButton(
                onPressed: () =>
                    showEntryEditor(context, state: state, entry: entry),
                child: const Text('abrir'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();
  }

  Finder campoDoDialogo() => find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(TextField),
      );

  Future<void> tocar(WidgetTester tester, Finder alvo) async {
    await tester.ensureVisible(alvo);
    await tester.pumpAndSettle();
    await tester.tap(alvo);
    await tester.pumpAndSettle();
  }

  group('Editor de compra', () {
    testWidgets('Cancelar fecha sem salvar e volta para a tela anterior',
        (tester) async {
      final state = AppState();
      final entry = compra();
      await abrirEditor(tester, state, entry);

      expect(find.text('Restaurar nome e categoria originais'), findsNothing);
      await tocar(tester, find.text('Cancelar'));

      expect(find.text('Editar'), findsNothing);
      expect(find.text('abrir'), findsOneWidget);
      expect(state.hasCustomizations(entry), isFalse);
    });

    testWidgets('dá para criar uma categoria nova sem sair da compra',
        (tester) async {
      final state = AppState();
      final entry = compra();
      await abrirEditor(tester, state, entry);

      await tocar(tester, find.text('Nova categoria'));
      expect(find.widgetWithText(AlertDialog, 'Nova categoria'), findsOneWidget);

      await tester.enterText(campoDoDialogo(), 'Pets');
      await tocar(tester, find.text('Criar'));

      // O diálogo fecha sozinho depois de criar.
      expect(find.byType(AlertDialog), findsNothing);
      final pets = state.budgetNodes.where((n) => n.name == 'Pets');
      expect(pets, hasLength(1));
      expect(pets.single.isMain, isTrue);

      // Já vem escolhida: é só salvar.
      await tocar(tester, find.text('Salvar'));
      expect(state.categoryOf(entry), 'Pets');
    });

    testWidgets('a subcategoria nova entra na categoria aberta',
        (tester) async {
      final state = AppState();
      final entry = compra();
      await state.setEntryOverrides(entry, category: SpendCategories.mercado);
      await abrirEditor(tester, state, entry);

      await tocar(tester, find.text('Nova subcategoria'));
      expect(find.text('Dentro de Alimentação'), findsOneWidget);

      await tester.enterText(campoDoDialogo(), 'Hortifruti');
      await tocar(tester, find.text('Criar'));

      final nova = state.budgetNodes.singleWhere((n) => n.name == 'Hortifruti');
      expect(nova.parentId, 'alimentacao');

      await tocar(tester, find.text('Salvar'));
      expect(state.categoryOf(entry), 'Hortifruti');
    });

    testWidgets('as categorias trazem os mesmos ícones do planejamento',
        (tester) async {
      await abrirEditor(tester, AppState(), compra());

      expect(find.byIcon(Icons.folder_outlined), findsNothing);
      for (final icone in [
        Icons.home_outlined, // Casa
        Icons.school_outlined, // Educação
        Icons.favorite_border_rounded, // Saúde
        Icons.directions_car_filled_outlined, // Transporte
        Icons.person_outline_rounded, // Despesas pessoais
        Icons.more_horiz_rounded, // Outros
      ]) {
        expect(find.byIcon(icone), findsWidgets, reason: '$icone');
      }
    });

    testWidgets('subcategoria que ficou vazia aparece e recebe a compra',
        (tester) async {
      // Como na conta real: a Streaming passou a receber "Assinaturas", e a
      // subcategoria Assinaturas ficou sem nada.
      final state = AppState()
        ..budgetNodes = [
          for (final n in defaultBudgetTree())
            if (n.id == 'lazer_assinaturas')
              n.copyWith(sources: const [])
            else
              n,
          const BudgetNode(
            id: 'user_streaming',
            name: 'Streaming',
            parentId: 'lazer',
            sources: ['Streaming', SpendCategories.assinaturas],
          ),
        ];
      final entry = compra();
      await abrirEditor(tester, state, entry);

      await tocar(tester, find.text('Lazer'));
      expect(find.text('Assinaturas'), findsOneWidget);
      expect(find.text('Streaming'), findsOneWidget);

      await tocar(tester, find.text('Assinaturas'));
      await tocar(tester, find.text('Salvar'));

      expect(state.nodeForCategory(state.categoryOf(entry))?.id,
          'lazer_assinaturas');
      // A Streaming segue com o que tinha.
      expect(
        state.budgetNodeById('user_streaming')!.sources,
        ['Streaming', SpendCategories.assinaturas],
      );
    });

    testWidgets('só esta compra: marcar como fixo não mexe nas outras',
        (tester) async {
      final entry = compra();
      final outra = LedgerEntry.fromCardTransaction({
        'transactionId': 'c2',
        'side': '1',
        'transactionDate': '${DateTime(2026, 8, 7, 14).millisecondsSinceEpoch}',
        'transactionAmount': '68.61',
        'basicCurrency': 'BRL',
        'merchName': 'ATACADO E AUTO SERVICO',
      });
      final state = AppState()..seedEntries([entry, outra]);
      final antes = state.isFixed(outra);
      await abrirEditor(tester, state, entry);

      // Com duas compras no lugar, a escolha aparece e começa em "só esta".
      expect(find.text('Esta alteração vale para'), findsOneWidget);

      await tocar(tester, find.text(antes ? 'Variável' : 'Fixo'));
      await tocar(tester, find.text('Salvar'));

      expect(state.isFixed(entry), !antes);
      expect(state.isFixed(outra), antes);
    });

    testWidgets('nome repetido mostra o motivo no próprio diálogo',
        (tester) async {
      final state = AppState();
      await abrirEditor(tester, state, compra());

      await tocar(tester, find.text('Nova categoria'));
      await tester.enterText(campoDoDialogo(), 'Alimentação');
      await tocar(tester, find.text('Criar'));

      expect(find.textContaining('Já existe'), findsOneWidget);
      expect(find.byType(AlertDialog), findsOneWidget);
    });
  });
}
