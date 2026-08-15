/// Endereço e chave publicável do projeto Supabase.
///
/// A chave fica aqui no código de propósito. Ela é embutida no JavaScript que
/// roda no navegador, então qualquer pessoa consegue lê-la do app publicado —
/// tratá-la como segredo seria teatro. O próprio Supabase a classifica como
/// "safe to share publicly".
///
/// Quem protege os dados é a política de segurança por linha no banco, que
/// recusa leitura e escrita fora do usuário autenticado. Ver
/// `supabase/schema.sql`. O que nunca pode aparecer aqui é a *secret key* do
/// Supabase, que ignora essas políticas — nem ela, nem a chave da Bybit.
///
/// Os valores podem ser trocados na compilação com `--dart-define`, para
/// apontar para outro projeto sem mexer no fonte.
class SupabaseConfig {
  static const _urlPadrao = 'https://qiounskjblncfdldwiui.supabase.co';
  static const _chavePadrao = 'sb_publishable_yTD5qyNmiyYZVyusTGeupA_S8FjeSjH';

  static const _urlDoAmbiente = String.fromEnvironment('SUPABASE_URL');
  static const _chaveDoAmbiente = String.fromEnvironment('SUPABASE_KEY');

  static String get url =>
      _urlDoAmbiente.isNotEmpty ? _urlDoAmbiente : _urlPadrao;

  static String get publishableKey =>
      _chaveDoAmbiente.isNotEmpty ? _chaveDoAmbiente : _chavePadrao;

  /// Sem os dois valores, o app funciona igual, só que sem sincronizar.
  static bool get enabled => url.isNotEmpty && publishableKey.isNotEmpty;
}
