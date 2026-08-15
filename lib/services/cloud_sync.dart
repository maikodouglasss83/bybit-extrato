import 'package:supabase_flutter/supabase_flutter.dart';

import '../models.dart';
import 'supabase_config.dart';

/// Sincronização com o Supabase.
///
/// Guarda o que é seu — apelidos, categorias, ocultos, planejamento e o
/// arquivo de transações — para valer em todos os aparelhos.
///
/// A chave da Bybit não passa por aqui de propósito: ela dá acesso de leitura
/// à conta inteira, então fica só no cofre de cada dispositivo.
class CloudSync {
  SupabaseClient? _client;

  /// Liga o cliente. Sem configuração, o app segue funcionando offline.
  Future<void> init() async {
    if (!SupabaseConfig.enabled) return;
    await Supabase.initialize(
      url: SupabaseConfig.url,
      publishableKey: SupabaseConfig.publishableKey,
    );
    _client = Supabase.instance.client;
  }

  bool get available => _client != null;

  Session? get _session => _client?.auth.currentSession;

  bool get signedIn => _session != null;

  String? get userEmail => _client?.auth.currentUser?.email;

  String? get _userId => _client?.auth.currentUser?.id;

  /// Avisa quando o usuário entra ou sai, para a tela acompanhar.
  Stream<AuthState>? get authChanges => _client?.auth.onAuthStateChange;

  /// Envia o link de acesso por e-mail. Sem senha para lembrar ou vazar.
  ///
  /// [redirectTo] é o endereço para onde o link devolve o usuário — precisa
  /// estar na lista de URLs permitidas do projeto.
  Future<void> sendMagicLink(String email, {String? redirectTo}) async {
    final client = _client;
    if (client == null) throw StateError('Sincronização não configurada.');
    await client.auth.signInWithOtp(
      email: email.trim(),
      emailRedirectTo: redirectTo,
    );
  }

  Future<void> signOut() async => _client?.auth.signOut();

  // -------------------------------------------------------------------------
  // Preferências
  // -------------------------------------------------------------------------

  /// Lê todos os ajustes guardados na nuvem, por chave.
  Future<Map<String, dynamic>> pullPreferences() async {
    final client = _client;
    final userId = _userId;
    if (client == null || userId == null) return const {};

    final linhas = await client
        .from('preferencias')
        .select('chave, valor')
        .eq('user_id', userId);

    return {
      for (final linha in linhas as List)
        linha['chave'].toString(): linha['valor'],
    };
  }

  /// Grava um ajuste. O banco carimba a hora sozinho.
  Future<void> pushPreference(String chave, dynamic valor) async {
    final client = _client;
    final userId = _userId;
    if (client == null || userId == null) return;

    await client.from('preferencias').upsert(
      {'user_id': userId, 'chave': chave, 'valor': valor},
      onConflict: 'user_id,chave',
    );
  }

  // -------------------------------------------------------------------------
  // Arquivo de transações
  // -------------------------------------------------------------------------

  /// Traz o arquivo inteiro — inclusive os meses que a Bybit já apagou.
  Future<List<LedgerEntry>> pullEntries() async {
    final client = _client;
    final userId = _userId;
    if (client == null || userId == null) return const [];

    final linhas = await client
        .from('transacoes')
        .select('dados')
        .eq('user_id', userId)
        .order('ocorrido_em', ascending: false);

    return [
      for (final linha in linhas as List)
        LedgerEntry.fromCache(Map<String, dynamic>.from(linha['dados'] as Map)),
    ];
  }

  /// Sobe os lançamentos. Repetir é inofensivo: a chave primária é o par
  /// usuário + lançamento, então reenviar apenas atualiza a mesma linha.
  Future<void> pushEntries(List<LedgerEntry> entries) async {
    final client = _client;
    final userId = _userId;
    if (client == null || userId == null || entries.isEmpty) return;

    // Em blocos, para não estourar o limite de tamanho da requisição.
    const tamanhoDoBloco = 400;
    for (var i = 0; i < entries.length; i += tamanhoDoBloco) {
      final bloco = entries.skip(i).take(tamanhoDoBloco).map((e) => {
            'user_id': userId,
            'id_lancamento': e.id,
            'ocorrido_em': e.time.toUtc().toIso8601String(),
            'dados': e.toJson(),
          });
      await client
          .from('transacoes')
          .upsert(bloco.toList(), onConflict: 'user_id,id_lancamento');
    }
  }
}
