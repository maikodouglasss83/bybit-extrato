# Extrato Bybit

App de finanças pessoais que lê a conta e o cartão da Bybit pela API v5.
Um único código roda no navegador, no celular e no computador.

## Telas

- **Visão geral** — patrimônio das duas carteiras, evolução dos gastos mês a
  mês (1 mês a tudo), alocação por moeda, cartão Bybit com pontos, cashback e
  progresso rumo à meta do nível.
- **Gastos** — distribuição por categoria no mês, com rosca, ranking e as
  compras de cada categoria.
- **Planejamento** — metas por categoria e subcategoria, comparadas com o
  gasto real, em gráfico horizontal.
- **Extrato** — todos os lançamentos agrupados por dia, com busca e filtros.
- **Ajustes** — chave da API, moeda de exibição, logos, tema e ajustes seus.

## Segurança

- A chave é usada **somente para leitura**. O app não envia ordens nem saques.
- As credenciais ficam no cofre criptografado do próprio dispositivo
  (Keychain no iOS, Keystore no Android, DPAPI no Windows, WebCrypto no
  navegador) e **nunca saem dele** — nem quando o app está publicado na web.
- Não existe servidor intermediário: as requisições vão direto para
  `api.bybit.com`.
- Publicar o app não expõe dado nenhum: cada aparelho guarda a própria chave,
  e quem abrir a página sem chave vê apenas a tela de conexão.

Ao gerar a chave na Bybit (Perfil › API), marque apenas leitura de **Wallet**,
**Assets** e **BitCard**. Não habilite Trade nem Withdraw.

## Publicar no GitHub Pages

O repositório já traz o fluxo pronto em `.github/workflows/deploy.yml`.

```bash
git remote add origin https://github.com/SEU_USUARIO/bybit-extrato.git
git push -u origin main
```

Depois, em **Settings › Pages**, escolha **GitHub Actions** como origem. Cada
push na `main` recompila e republica. O endereço fica
`https://SEU_USUARIO.github.io/bybit-extrato/`.

O repositório precisa ser **público** para o Pages funcionar no plano
gratuito. Isso não expõe nada: não há credencial no código.

## Rodar localmente

```bash
flutter pub get
flutter run -d chrome
```

Para servir uma build de release já compilada:

```bash
flutter build web --release
node tool/serve.js 8099
```

Outras plataformas:

```bash
flutter run -d windows
flutter build apk --release
```

## Particularidades da API da Bybit

Coisas descobertas testando contra uma conta real, que explicam decisões do
código:

| Situação | Como o app lida |
| --- | --- |
| O saldo unificado não mostra a carteira de fundos | Consulta também `query-account-coins-balance` |
| As transações do cartão não têm endpoint próprio utilizável | Vêm do histórico de recompensas, que traz estabelecimento e valor |
| Esse histórico mistura compras com movimentos de pontos | Só entram registros com valor e data válidos |
| A Bybit mantém uma janela móvel de ~6 meses | O app guarda os lançamentos no dispositivo e só acrescenta |
| O campo de categoria vem sempre vazio | Categorização automática pelo nome do estabelecimento |
| Relógio adiantado faz a API recusar tudo | Sincroniza com a hora do servidor antes de assinar |

## Estrutura

```
lib/
  main.dart                 entrada, tema e atualização ao voltar ao app
  app_state.dart            estado: credenciais, saldos, extrato, planejamento
  models.dart               modelos e conversão das respostas da API
  budget.dart               categorias, subcategorias e metas
  theme.dart                paleta, tipografia e componentes de tema
  services/
    bybit_client.dart       API v5 (assinatura HMAC e sincronia de relógio)
    credentials.dart        armazenamento criptografado da chave
    preferences.dart        ajustes e histórico guardado
    fx.dart                 cotação USD/BRL
  ui/                       telas e componentes
  util/                     formatação, categorização e marcas
```
