import 'package:flutter/material.dart';

import '../../app_state.dart';
import '../../budget.dart';
import '../../models.dart';
import '../../theme.dart';
import '../../util/categorizer.dart';
import '../../util/format.dart';

/// Ícone de uma categoria principal do planejamento.
///
/// Separado de [categoryIcon] porque os dois níveis têm nomes diferentes: a
/// principal "Comunicação" agrupa a categoria de gasto "Telefonia e
/// internet", e "Alimentação" agrupa mercado e restaurantes.
IconData mainCategoryIcon(String nodeId) {
  switch (nodeId) {
    case 'casa':
      return Icons.home_outlined;
    case 'educacao':
      return Icons.school_outlined;
    case 'lazer':
      return Icons.sports_esports_outlined;
    case 'saude':
      return Icons.favorite_border_rounded;
    case 'alimentacao':
      return Icons.restaurant_rounded;
    case 'transporte':
      return Icons.directions_car_filled_outlined;
    case 'pessoais':
      return Icons.person_outline_rounded;
    case 'comunicacao':
      return Icons.wifi_rounded;
    case 'tarifas':
      return Icons.receipt_long_outlined;
    case 'outros':
      return Icons.more_horiz_rounded;
    case kUncategorizedId:
      return Icons.help_outline_rounded;
    default:
      // Criada pelo usuário.
      return Icons.bookmark_outline_rounded;
  }
}

/// Ícone que representa cada categoria de gasto.
IconData categoryIcon(String category) {
  switch (category) {
    case SpendCategories.assinaturas:
      return Icons.subscriptions_outlined;
    case SpendCategories.telefonia:
      return Icons.wifi_rounded;
    case SpendCategories.transporte:
      return Icons.directions_car_filled_outlined;
    case SpendCategories.mercado:
      return Icons.shopping_cart_outlined;
    case SpendCategories.restaurantes:
      return Icons.restaurant_rounded;
    case SpendCategories.compras:
      return Icons.shopping_bag_outlined;
    case SpendCategories.tecnologia:
      return Icons.memory_rounded;
    case SpendCategories.saude:
      return Icons.favorite_border_rounded;
    case SpendCategories.educacao:
      return Icons.school_outlined;
    case SpendCategories.lazer:
      return Icons.sports_esports_outlined;
    case SpendCategories.vestuario:
      return Icons.checkroom_rounded;
    case SpendCategories.casa:
      return Icons.home_outlined;
    case SpendCategories.servicos:
      return Icons.handyman_outlined;
    case SpendCategories.transferencias:
      return Icons.swap_horiz_rounded;
    default:
      return iconForCategoryName(category);
  }
}

/// Ícone deduzido do nome da categoria.
///
/// As categorias criadas pelo usuário não estão em lista nenhuma, e um
/// "..." para todas elas não diz nada. O nome que a pessoa escolheu quase
/// sempre diz do que se trata — "Cursos", "Academia", "Pet" —, então é dele
/// que sai o desenho.
IconData iconForCategoryName(String nome) {
  final n = nome.toLowerCase();
  bool tem(List<String> chaves) => chaves.any(n.contains);
  // Nomes curtos ("luz", "gás") casariam dentro de outras palavras: estes só
  // valem como palavra inteira.
  final palavras = n.split(RegExp(r'[^a-zà-ú0-9]+')).toSet();
  bool palavra(List<String> chaves) => chaves.any(palavras.contains);

  // Contas da casa.
  if (palavra(['luz', 'energia', 'enel', 'cemig', 'copel', 'light', 'celpe']) ||
      tem(['elétric', 'eletric'])) {
    return Icons.lightbulb_outline_rounded;
  }
  if (palavra(['água', 'agua', 'sabesp', 'saneamento', 'esgoto'])) {
    return Icons.water_drop_outlined;
  }
  if (palavra(['gás', 'gas', 'botijão', 'botijao', 'comgás', 'comgas'])) {
    return Icons.local_fire_department_outlined;
  }
  if (tem(['limpeza', 'faxin', 'diarista', 'lavander'])) {
    return Icons.cleaning_services_outlined;
  }
  if (tem(['manuten', 'reforma', 'conserto', 'obra', 'material de constr'])) {
    return Icons.handyman_outlined;
  }
  if (tem(['móve', 'move', 'decora', 'eletrodom'])) {
    return Icons.chair_outlined;
  }
  if (tem(['seguro'])) return Icons.shield_outlined;
  if (tem(['empréstim', 'emprestim', 'financiam', 'parcela', 'dívida', 'divida'])) {
    return Icons.account_balance_outlined;
  }
  if (tem(['cartão', 'cartao', 'fatura'])) return Icons.credit_card_rounded;
  if (tem(['salário', 'salario', 'renda', 'freela'])) {
    return Icons.payments_outlined;
  }
  if (tem(['uber', '99', 'táxi', 'taxi', 'aplicativo de'])) {
    return Icons.local_taxi_outlined;
  }
  if (tem(['estaciona', 'pedágio', 'pedagio', 'ipva', 'multa'])) {
    return Icons.local_parking_rounded;
  }
  if (tem(['metrô', 'metro', 'trem', 'bilhete'])) {
    return Icons.directions_subway_outlined;
  }
  if (tem(['mercado', 'supermerc', 'atacad', 'feira', 'hortifrut', 'açougue', 'acougue'])) {
    return Icons.shopping_cart_outlined;
  }
  if (tem(['restaur', 'almoço', 'almoco', 'jantar', 'comida', 'pizza', 'hamb'])) {
    return Icons.restaurant_rounded;
  }
  if (tem(['doce', 'sorvet', 'confeit'])) return Icons.icecream_outlined;
  if (tem(['music', 'música', 'spotify', 'show', 'concert'])) {
    return Icons.music_note_rounded;
  }
  if (tem(['cinema', 'teatro', 'ingresso'])) return Icons.theaters_rounded;
  if (tem(['hospital', 'exame', 'consulta', 'plano de saúde', 'plano de saude', 'clínic', 'clinic'])) {
    return Icons.local_hospital_outlined;
  }
  if (tem(['ótica', 'otica', 'óculos', 'oculos'])) return Icons.visibility_outlined;
  if (tem(['cosmét', 'cosmet', 'perfum', 'maquia', 'higiene'])) {
    return Icons.spa_outlined;
  }
  if (tem(['celular novo', 'smartphone', 'iphone'])) {
    return Icons.smartphone_rounded;
  }
  if (tem(['software', 'app', 'nuvem', 'icloud', 'google one', 'domínio', 'dominio', 'hospedagem'])) {
    return Icons.cloud_outlined;
  }
  if (tem(['cripto', 'bitcoin', 'bybit', 'corretora', 'ações', 'acoes'])) {
    return Icons.currency_bitcoin_rounded;
  }
  if (tem(['trabalho', 'escritório', 'escritorio', 'empresa', 'negócio', 'negocio'])) {
    return Icons.work_outline_rounded;
  }
  if (tem(['festa', 'evento', 'casamento'])) return Icons.celebration_outlined;
  if (tem(['creche', 'babá', 'baba', 'brinquedo'])) return Icons.toys_outlined;

  if (tem(['curso', 'aula', 'escol', 'facul', 'estud', 'livr', 'ensino'])) {
    return Icons.school_outlined;
  }
  if (tem(['stream', 'assinat', 'filme', 'série', 'serie', 'tv'])) {
    return Icons.play_circle_outline_rounded;
  }
  if (tem(['academ', 'treino', 'fitness', 'gym', 'esporte'])) {
    return Icons.fitness_center_rounded;
  }
  if (tem(['pet', 'veterin', 'animal'])) return Icons.pets_rounded;
  if (tem(['farm', 'remédio', 'remedio', 'médic', 'medic', 'dentist'])) {
    return Icons.medical_services_outlined;
  }
  if (tem(['combust', 'gasolin', 'posto', 'etanol', 'diesel'])) {
    return Icons.local_gas_station_rounded;
  }
  if (tem(['viagem', 'hotel', 'passag', 'voo', 'hosped'])) {
    return Icons.flight_takeoff_rounded;
  }
  if (tem(['café', 'cafe', 'padaria', 'lanche'])) return Icons.coffee_rounded;
  if (tem(['bar', 'cerveja', 'bebida'])) return Icons.local_bar_rounded;
  if (tem(['delivery', 'ifood', 'pedido'])) return Icons.delivery_dining_rounded;
  if (tem(['presente', 'aniversár', 'aniversar'])) {
    return Icons.card_giftcard_rounded;
  }
  if (tem(['beleza', 'salão', 'salao', 'cabelo', 'barbe'])) {
    return Icons.content_cut_rounded;
  }
  if (tem(['jogo', 'game'])) return Icons.sports_esports_outlined;
  if (tem(['invest', 'poupan', 'aport'])) return Icons.trending_up_rounded;
  if (tem(['doaç', 'doac', 'igreja', 'dízimo', 'dizimo'])) {
    return Icons.volunteer_activism_outlined;
  }
  if (tem(['alugu', 'condom', 'casa', 'moradia'])) return Icons.home_outlined;
  if (tem(['internet', 'telefon', 'celular', 'wifi'])) return Icons.wifi_rounded;
  if (tem(['imposto', 'tarifa', 'taxa', 'juros'])) {
    return Icons.receipt_long_outlined;
  }
  if (tem(['criança', 'crianca', 'filho', 'bebê', 'bebe'])) {
    return Icons.child_care_rounded;
  }
  if (tem(['carro', 'moto', 'transport', 'ônibus', 'onibus'])) {
    return Icons.directions_car_filled_outlined;
  }
  if (tem(['tecnolog', 'eletrôn', 'eletron', 'computador', 'notebook'])) {
    return Icons.devices_other_rounded;
  }
  if (tem(['vestu', 'roupa', 'calçad', 'calcad', 'moda'])) {
    return Icons.checkroom_rounded;
  }
  if (tem(['terapia', 'psicól', 'psicol', 'psiqui'])) {
    return Icons.psychology_outlined;
  }
  if (tem(['compra', 'shopping', 'loja'])) {
    return Icons.shopping_bag_outlined;
  }

  // Nada reconhecido: a marcação neutra de categoria criada à mão.
  return Icons.bookmark_outline_rounded;
}

/// Barra de mês: setas para os lados e o mês escolhido no meio.
///
/// O mês é o mesmo em todas as páginas — trocar aqui troca no resto do app,
/// que é o que se espera de um período escolhido uma vez.
class MonthPicker extends StatelessWidget {
  const MonthPicker({
    super.key,
    required this.state,
    this.trailing,
    this.enabled = true,
  });

  final AppState state;

  /// Controle extra no canto direito, quando a página precisa de um.
  final Widget? trailing;

  /// Falso quando a página está mostrando tudo: o mês continua à vista, mas
  /// não manda em nada enquanto o filtro estiver desligado.
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        IconButton(
          onPressed: enabled ? () => state.shiftMonth(-1) : null,
          icon: const Icon(Icons.chevron_left_rounded),
          tooltip: 'Mês anterior',
        ),
        Expanded(
          child: Text(
            fmtMonthYear(state.selectedMonth),
            textAlign: TextAlign.center,
            style: context.texts.titleMedium?.copyWith(
              color: enabled ? null : context.tones.muted,
            ),
          ),
        ),
        IconButton(
          onPressed: enabled && state.canGoToNextMonth
              ? () => state.shiftMonth(1)
              : null,
          icon: const Icon(Icons.chevron_right_rounded),
          tooltip: 'Próximo mês',
        ),
        if (trailing != null) trailing!,
      ],
    );
  }
}

/// Cartão padrão do app.
class AppCard extends StatelessWidget {
  const AppCard({super.key, required this.child, this.padding, this.onTap});

  final Widget child;
  final EdgeInsetsGeometry? padding;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: padding ?? const EdgeInsets.all(20),
          child: child,
        ),
      ),
    );
  }
}

/// Rótulo pequeno em caixa alta usado acima das seções.
class SectionLabel extends StatelessWidget {
  const SectionLabel(this.text, {super.key, this.trailing});

  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Expanded(
            child: Text(text.toUpperCase(), style: context.texts.labelSmall),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

/// Ícone circular que representa o tipo de movimentação.
class KindAvatar extends StatelessWidget {
  const KindAvatar({
    super.key,
    required this.kind,
    required this.isIn,
    this.size = 42,
    this.overrideIcon,
  });

  final LedgerKind kind;
  final bool isIn;
  final double size;

  /// Substitui o ícone padrão do tipo, usado para mostrar o ramo da compra.
  final IconData? overrideIcon;

  @override
  Widget build(BuildContext context) {
    final tones = context.tones;
    final color = switch (kind) {
      LedgerKind.deposit || LedgerKind.transferIn => tones.positive,
      LedgerKind.withdraw || LedgerKind.transferOut => tones.negative,
      LedgerKind.internalTransfer => AppColors.accent,
      LedgerKind.cardPurchase => tones.negative,
      LedgerKind.cardRefund => tones.positive,
      LedgerKind.trade => AppColors.accent,
      LedgerKind.funding || LedgerKind.interest => AppColors.warning,
      LedgerKind.fee => tones.muted,
      LedgerKind.bonus => AppColors.accent,
      LedgerKind.settlement => AppColors.warning,
      LedgerKind.other => isIn ? tones.positive : tones.muted,
    };

    final icon = switch (kind) {
      LedgerKind.deposit => Icons.south_west_rounded,
      LedgerKind.withdraw => Icons.north_east_rounded,
      LedgerKind.transferIn => Icons.call_received_rounded,
      LedgerKind.transferOut => Icons.call_made_rounded,
      LedgerKind.internalTransfer => Icons.swap_vert_rounded,
      LedgerKind.cardPurchase => Icons.credit_card_rounded,
      LedgerKind.cardRefund => Icons.replay_rounded,
      LedgerKind.trade => Icons.swap_horiz_rounded,
      LedgerKind.funding => Icons.autorenew_rounded,
      LedgerKind.fee => Icons.receipt_long_rounded,
      LedgerKind.interest => Icons.percent_rounded,
      LedgerKind.bonus => Icons.card_giftcard_rounded,
      LedgerKind.settlement => Icons.gavel_rounded,
      LedgerKind.other => Icons.circle_outlined,
    };

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(size / 3),
      ),
      child: Icon(overrideIcon ?? icon, color: color, size: size * 0.5),
    );
  }
}

/// Sigla da moeda em um círculo, com cor derivada do próprio nome.
class CoinBadge extends StatelessWidget {
  const CoinBadge({super.key, required this.coin, this.size = 40});

  final String coin;
  final double size;

  static const _palette = [
    Color(0xFFF7931A), // laranja
    Color(0xFF627EEA), // azul
    Color(0xFF22D3A6), // verde-água
    Color(0xFFF4436B), // rosa
    Color(0xFFA78BFA), // roxo
    Color(0xFF38BDF8), // ciano
    Color(0xFFF5A524), // âmbar
  ];

  @override
  Widget build(BuildContext context) {
    final color = _palette[coin.hashCode.abs() % _palette.length];
    final label = coin.length <= 4 ? coin : coin.substring(0, 4);
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        shape: BoxShape.circle,
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w700,
          fontSize: label.length >= 4 ? size * 0.26 : size * 0.32,
        ),
      ),
    );
  }
}

/// Estado vazio com ícone, título e explicação.
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.action,
  });

  final IconData icon;
  final String title;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: context.tones.surfaceAlt,
                  borderRadius: BorderRadius.circular(22),
                ),
                child: Icon(icon, size: 30, color: context.tones.muted),
              ),
              const SizedBox(height: 18),
              Text(title, style: context.texts.titleMedium, textAlign: TextAlign.center),
              const SizedBox(height: 8),
              Text(message, style: context.texts.bodySmall, textAlign: TextAlign.center),
              if (action != null) ...[const SizedBox(height: 20), action!],
            ],
          ),
        ),
      ),
    );
  }
}

/// Faixa de erro discreta, com opção de tentar de novo.
class ErrorBanner extends StatelessWidget {
  const ErrorBanner({super.key, required this.message, this.onRetry});

  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final tones = context.tones;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
      decoration: BoxDecoration(
        color: tones.negative.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: tones.negative.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline_rounded, color: tones.negative, size: 20),
          const SizedBox(width: 12),
          Expanded(child: Text(message, style: context.texts.bodySmall)),
          if (onRetry != null)
            TextButton(onPressed: onRetry, child: const Text('Tentar de novo')),
        ],
      ),
    );
  }
}

/// Substitui o valor por pontos quando o usuário esconde os saldos.
class MaskedValue extends StatelessWidget {
  const MaskedValue({
    super.key,
    required this.value,
    required this.hidden,
    required this.style,
    this.maskLength = 6,
  });

  final String value;
  final bool hidden;
  final TextStyle? style;
  final int maskLength;

  @override
  Widget build(BuildContext context) {
    return Text(hidden ? '•' * maskLength : value, style: style);
  }
}
