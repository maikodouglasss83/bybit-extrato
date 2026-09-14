import 'package:flutter/material.dart';

import '../app_state.dart';
import '../subscriptions.dart';
import '../theme.dart';
import '../util/format.dart';
import 'widgets/common.dart';
import 'widgets/entry_editor.dart';
import 'widgets/merchant_avatar.dart';

/// Tudo o que se repete todo mês num lugar só.
///
/// A lista junta duas origens: os estabelecimentos que o app já reconhece
/// como gasto fixo e as assinaturas cadastradas à mão, para o que é cobrado
/// fora do cartão da Bybit.
class SubscriptionsPage extends StatelessWidget {
  const SubscriptionsPage({super.key, required this.state});

  final AppState state;

  /// Abaixo desta largura a tabela vira lista: as colunas não cabem.
  static const _larguraDaTabela = 720.0;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: state,
      builder: (context, _) {
        final assinaturas = state.subscriptions();

        return LayoutBuilder(
          builder: (context, constraints) {
            final tabela = constraints.maxWidth >= _larguraDaTabela;

            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
              children: [
                Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton.icon(
                    onPressed: () => _novaAssinatura(context, state),
                    icon: const Icon(Icons.add_rounded, size: 20),
                    label: const Text('Nova assinatura'),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(0, 44),
                      padding: const EdgeInsets.symmetric(horizontal: 18),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                _Resumo(state: state, assinaturas: assinaturas),
                const SizedBox(height: 16),
                if (assinaturas.isEmpty)
                  _Vazio(state: state)
                else
                  _Tabela(
                    state: state,
                    assinaturas: assinaturas,
                    emColunas: tabela,
                  ),
              ],
            );
          },
        );
      },
    );
  }
}

/// Faixa de destaque com o custo mensal somado.
class _Resumo extends StatelessWidget {
  const _Resumo({required this.state, required this.assinaturas});

  final AppState state;
  final List<Subscription> assinaturas;

  /// O azul não é o acento do app de propósito: esta faixa é o número que
  /// resume a página, e destacá-la do resto é o ponto.
  static const _de = Color(0xFF2E6BE6);
  static const _para = Color(0xFF1B3F9E);

  @override
  Widget build(BuildContext context) {
    final ativas = assinaturas.where((s) => s.active).length;
    final mensal = state.brlToDisplay(state.subscriptionsMonthlyBrl);
    final anual = mensal * 12;

    final esconder = state.hideBalances;
    final porMes = esconder ? '••••' : _redondo(mensal, state.showInBrl);
    final porAno = esconder ? '••••' : _redondo(anual, state.showInBrl);

    return Container(
      padding: const EdgeInsets.fromLTRB(22, 20, 22, 22),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: const LinearGradient(
          colors: [_de, _para],
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'SUAS ASSINATURAS CUSTAM',
            style: context.texts.labelSmall?.copyWith(
              color: Colors.white.withValues(alpha: 0.82),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    porMes,
                    style: const TextStyle(
                      fontSize: 38,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                      letterSpacing: -1,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Text(
                '/mês',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                  color: Colors.white.withValues(alpha: 0.75),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text.rich(
            TextSpan(
              style: TextStyle(
                fontSize: 13,
                color: Colors.white.withValues(alpha: 0.85),
              ),
              children: [
                const TextSpan(text: 'isso dá '),
                TextSpan(
                  text: '$porAno/ano',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                TextSpan(text: ' · $ativas ${ativas == 1 ? 'ativa' : 'ativas'}'),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Valor arredondado ao real, do jeito que se fala: "R$ 368".
String _redondo(double valor, bool brl) {
  final texto = fmtFiat(valor.roundToDouble(), brl: brl);
  final corte = texto.lastIndexOf(',');
  return corte == -1 ? texto : texto.substring(0, corte);
}

class _Tabela extends StatelessWidget {
  const _Tabela({
    required this.state,
    required this.assinaturas,
    required this.emColunas,
  });

  final AppState state;
  final List<Subscription> assinaturas;
  final bool emColunas;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          if (emColunas) const _Cabecalho(),
          for (var i = 0; i < assinaturas.length; i++) ...[
            if (i > 0 || emColunas) const Divider(height: 1),
            _Linha(
              state: state,
              assinatura: assinaturas[i],
              emColunas: emColunas,
            ),
          ],
        ],
      ),
    );
  }
}

class _Cabecalho extends StatelessWidget {
  const _Cabecalho();

  @override
  Widget build(BuildContext context) {
    Widget rotulo(String texto, {TextAlign align = TextAlign.left}) => Text(
          texto,
          style: context.texts.labelSmall,
          textAlign: align,
        );

    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 12),
      child: Row(
        children: [
          Expanded(flex: 5, child: rotulo('ASSINATURA')),
          Expanded(flex: 3, child: rotulo('CATEGORIA')),
          Expanded(flex: 3, child: rotulo('VENCE ↓')),
          SizedBox(
            width: 110,
            child: rotulo('POR MÊS', align: TextAlign.right),
          ),
        ],
      ),
    );
  }
}

class _Linha extends StatelessWidget {
  const _Linha({
    required this.state,
    required this.assinatura,
    required this.emColunas,
  });

  final AppState state;
  final Subscription assinatura;
  final bool emColunas;

  @override
  Widget build(BuildContext context) {
    final tones = context.tones;
    final cancelada = assinatura.cancelled;

    final nome = Text(
      assinatura.name,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: context.texts.titleSmall?.copyWith(
        color: cancelada ? tones.muted : null,
        decoration: cancelada ? TextDecoration.lineThrough : null,
        decorationColor: tones.muted,
      ),
    );

    final categoria = assinatura.category.isEmpty ? '—' : assinatura.category;
    // O que importa numa assinatura é quando ela cai de novo, não quando caiu.
    // As canceladas também mostram a data: é por ela que a lista está em
    // ordem, e sem ela a riscada pareceria fora do lugar.
    final vence =
        assinatura.proximoVencimento(DateTime.now(), mesmoCancelada: true);
    final quando =
        vence == null ? '—' : fmtVencimento(vence, comPrefixo: false);

    final valor = _Valor(
      texto: state.hideBalances
          ? '••••'
          : fmtFiat(state.brlToDisplay(assinatura.monthlyBrl),
              brl: state.showInBrl),
      esmaecido: cancelada,
    );

    return InkWell(
      onTap: () => _abrirAssinatura(context, state, assinatura),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        child: Row(
          children: [
            Opacity(
              opacity: cancelada ? 0.45 : 1,
              child: _Selo(state: state, assinatura: assinatura),
            ),
            const SizedBox(width: 14),
            if (emColunas) ...[
              Expanded(flex: 5, child: nome),
              Expanded(
                flex: 3,
                child: Text(
                  categoria,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.texts.bodyMedium?.copyWith(color: tones.muted),
                ),
              ),
              Expanded(
                flex: 3,
                child: Text(
                  quando,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.texts.bodyMedium?.copyWith(color: tones.muted),
                ),
              ),
              SizedBox(width: 110, child: valor),
            ] else ...[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    nome,
                    const SizedBox(height: 3),
                    Text(
                      [
                        if (assinatura.category.isNotEmpty) assinatura.category,
                        if (vence != null)
                          fmtVencimento(vence)
                        else if (!cancelada)
                          // Lembra que dá para informar o dia ao editar.
                          'sem dia de vencimento',
                      ].join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.texts.bodySmall,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              valor,
            ],
          ],
        ),
      ),
    );
  }
}

/// Ícone da categoria da assinatura, como nas outras listas.
class _Selo extends StatelessWidget {
  const _Selo({required this.state, required this.assinatura});

  final AppState state;
  final Subscription assinatura;

  @override
  Widget build(BuildContext context) {
    return BrandAvatar(
      name: assinatura.name,
      state: state,
      category: assinatura.category,
      size: 38,
    );
  }
}

/// Valor com os centavos menores, como nas faturas.
class _Valor extends StatelessWidget {
  const _Valor({required this.texto, required this.esmaecido});

  final String texto;
  final bool esmaecido;

  @override
  Widget build(BuildContext context) {
    final tones = context.tones;
    final cor = esmaecido ? tones.muted : context.colors.onSurface;
    final risco = esmaecido ? TextDecoration.lineThrough : null;

    final corte = texto.lastIndexOf(',');
    final inteiro = corte == -1 ? texto : texto.substring(0, corte);
    final centavos = corte == -1 ? '' : texto.substring(corte);

    // O símbolo fica menor que o número: quem lê a coluna procura o valor.
    final simbolo = RegExp(r'^\D+').firstMatch(inteiro)?.group(0) ?? '';
    final numero = inteiro.substring(simbolo.length);

    return Text.rich(
      TextSpan(
        children: [
          if (simbolo.isNotEmpty)
            TextSpan(
              text: simbolo,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: tones.muted,
                decoration: risco,
                decorationColor: tones.muted,
              ),
            ),
          TextSpan(
            text: numero,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: cor,
              decoration: risco,
              decorationColor: tones.muted,
            ),
          ),
          if (centavos.isNotEmpty)
            TextSpan(
              text: centavos,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: tones.muted,
                decoration: risco,
                decorationColor: tones.muted,
              ),
            ),
        ],
      ),
      textAlign: TextAlign.right,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }
}

class _Vazio extends StatelessWidget {
  const _Vazio({required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: EmptyState(
          icon: Icons.autorenew_rounded,
          title: 'Nenhuma assinatura ainda',
          message: 'Marque uma compra como gasto fixo no extrato e ela aparece '
              'aqui. O que é cobrado fora do cartão você cadastra à mão.',
          action: FilledButton.icon(
            onPressed: () => _novaAssinatura(context, state),
            icon: const Icon(Icons.add_rounded, size: 20),
            label: const Text('Nova assinatura'),
          ),
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------
// Ações
// -----------------------------------------------------------------------

/// O que dá para fazer com uma assinatura.
void _abrirAssinatura(
  BuildContext context,
  AppState state,
  Subscription assinatura,
) {
  showModalBottomSheet<void>(
    context: context,
    backgroundColor: context.colors.surface,
    showDragHandle: true,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (sheetContext) => AnimatedBuilder(
      animation: state,
      builder: (_, __) {
        // A lista é recalculada a cada mudança: pega a versão atual desta
        // assinatura, para o texto do menu acompanhar o que foi feito.
        final atual = state
            .subscriptions()
            .where((s) => s.key == assinatura.key)
            .firstOrNull;
        if (atual == null) return const SizedBox.shrink();

        final valor = fmtFiat(
          state.brlToDisplay(atual.monthlyBrl),
          brl: state.showInBrl,
        );

        return SafeArea(
          top: false,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 4, 24, 16),
                  child: Row(
                    children: [
                      _Selo(state: state, assinatura: atual),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(atual.name, style: context.texts.titleMedium),
                            const SizedBox(height: 3),
                            Text(
                              [
                                '$valor/mês',
                                if (atual.dueDay != null)
                                  'vence dia ${atual.dueDay}',
                                if (atual.chargeCount > 0)
                                  '${atual.chargeCount} '
                                      '${atual.chargeCount == 1 ? 'cobrança' : 'cobranças'}',
                                if (atual.cancelled) 'cancelada',
                              ].join(' · '),
                              style: context.texts.bodySmall,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.edit_outlined),
                  title: const Text('Editar'),
                  subtitle: Text(
                    atual.manual
                        ? 'Nome, valor, categoria e vencimento'
                        : 'Nome, categoria e dia do vencimento',
                  ),
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    if (atual.manual) {
                      _editarManual(context, state, atual);
                    } else if (atual.sample != null) {
                      showEntryEditor(
                        context,
                        state: state,
                        entry: atual.sample!,
                      );
                    }
                  },
                ),
                ListTile(
                  leading: Icon(
                    atual.cancelled
                        ? Icons.play_circle_outline_rounded
                        : Icons.pause_circle_outline_rounded,
                  ),
                  title: Text(
                    atual.cancelled
                        ? 'Voltar para as ativas'
                        : 'Marcar como cancelada',
                  ),
                  subtitle: Text(
                    atual.cancelled
                        ? 'Volta a contar no total do mês'
                        : 'Sai do total, mas continua na lista, riscada',
                  ),
                  onTap: () async {
                    await state.setSubscriptionCancelled(
                      atual.key,
                      !atual.cancelled,
                    );
                    if (sheetContext.mounted) {
                      Navigator.of(sheetContext).pop();
                    }
                  },
                ),
                ListTile(
                  leading: Icon(Icons.delete_outline_rounded,
                      color: context.tones.negative),
                  title: Text(
                    'Tirar da lista',
                    style: TextStyle(color: context.tones.negative),
                  ),
                  subtitle: Text(
                    atual.manual
                        ? 'Apaga o cadastro desta assinatura'
                        : 'Volta a ser gasto variável; as compras seguem no '
                            'extrato',
                  ),
                  onTap: () async {
                    await state.removeSubscription(atual);
                    if (sheetContext.mounted) {
                      Navigator.of(sheetContext).pop();
                    }
                  },
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        );
      },
    ),
  );
}

void _novaAssinatura(BuildContext context, AppState state) =>
    _abrirEditorManual(context, state, null);

void _editarManual(
  BuildContext context,
  AppState state,
  Subscription assinatura,
) {
  final id = assinatura.key.replaceFirst('manual:', '');
  final cadastro =
      state.manualSubscriptions.where((m) => m.id == id).firstOrNull;
  if (cadastro != null) _abrirEditorManual(context, state, cadastro);
}

void _abrirEditorManual(
  BuildContext context,
  AppState state,
  ManualSubscription? existente,
) {
  showModalBottomSheet<void>(
    context: context,
    backgroundColor: context.colors.surface,
    showDragHandle: true,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    // Com o teclado aberto o formulário não cabe inteiro: rola, e o campo
    // tocado é trazido para cima do teclado.
    builder: (_) => AcimaDoTeclado(
      child: SingleChildScrollView(
        child: _EditorManual(state: state, existente: existente),
      ),
    ),
  );
}

/// Cadastro de uma assinatura que não passa pelo cartão.
class _EditorManual extends StatefulWidget {
  const _EditorManual({required this.state, this.existente});

  final AppState state;
  final ManualSubscription? existente;

  @override
  State<_EditorManual> createState() => _EditorManualState();
}

class _EditorManualState extends State<_EditorManual> {
  late final _nome = TextEditingController(text: widget.existente?.name ?? '');
  late final _valor = TextEditingController(
    text: widget.existente == null
        ? ''
        : fmtPlain(widget.state.brlToDisplay(widget.existente!.monthlyBrl)),
  );
  late String _categoria = widget.existente?.category ?? '';
  late int? _dia = widget.existente?.dueDay;
  String? _erro;

  @override
  void dispose() {
    _nome.dispose();
    _valor.dispose();
    super.dispose();
  }

  Future<void> _salvar() async {
    final nome = _nome.text.trim();
    if (nome.isEmpty) {
      setState(() => _erro = 'Dê um nome para a assinatura.');
      return;
    }

    final digitado =
        double.tryParse(_valor.text.trim().replaceAll('.', '').replaceAll(',', '.'));
    if (digitado == null || digitado <= 0) {
      setState(() => _erro = 'Informe quanto ela custa por mês.');
      return;
    }

    final emReais = widget.state.displayToBrl(digitado);

    if (widget.existente == null) {
      await widget.state.addManualSubscription(
        name: nome,
        monthlyBrl: emReais,
        category: _categoria,
        dueDay: _dia,
      );
    } else {
      await widget.state.updateManualSubscription(
        widget.existente!.id,
        name: nome,
        monthlyBrl: emReais,
        category: _categoria,
        dueDay: _dia,
        clearDueDay: _dia == null,
      );
    }

    if (mounted) Navigator.of(context).maybePop();
  }

  @override
  Widget build(BuildContext context) {
    final novo = widget.existente == null;

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 4, 24, 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            novo ? 'Nova assinatura' : 'Editar assinatura',
            style: context.texts.headlineSmall,
          ),
          const SizedBox(height: 6),
          Text(
            'Para o que é cobrado fora do cartão da Bybit. O que passa pelo '
            'cartão já entra sozinho.',
            style: context.texts.bodySmall,
          ),
          const SizedBox(height: 20),
          TextField(
            controller: _nome,
            autofocus: novo,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
              labelText: 'Nome',
              hintText: 'Spotify, academia, seguro…',
            ),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _valor,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: 'Valor por mês',
              prefixText: widget.state.displayCurrencySymbol,
            ),
          ),
          const SizedBox(height: 14),
          DropdownButtonFormField<String>(
            initialValue: _categoria.isEmpty ? null : _categoria,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Categoria'),
            items: [
              const DropdownMenuItem<String>(
                value: null,
                child: Text('Sem categoria'),
              ),
              for (final c in widget.state.availableCategories)
                DropdownMenuItem<String>(value: c, child: Text(c)),
            ],
            onChanged: (v) => setState(() => _categoria = v ?? ''),
          ),
          const SizedBox(height: 14),
          DropdownButtonFormField<int?>(
            initialValue: _dia,
            decoration: const InputDecoration(labelText: 'Vence no dia'),
            items: [
              const DropdownMenuItem<int?>(
                value: null,
                child: Text('Não sei'),
              ),
              for (var dia = 1; dia <= 31; dia++)
                DropdownMenuItem<int?>(value: dia, child: Text('Dia $dia')),
            ],
            onChanged: (v) => setState(() => _dia = v),
          ),
          if (_erro != null) ...[
            const SizedBox(height: 12),
            Text(
              _erro!,
              style: context.texts.bodySmall
                  ?.copyWith(color: context.tones.negative),
            ),
          ],
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _salvar,
              child: Text(novo ? 'Cadastrar' : 'Salvar'),
            ),
          ),
        ],
      ),
    );
  }
}
