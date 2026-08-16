// Carregamento do app, sem service worker.
//
// O padrão do Flutter registra um service worker que guarda o app inteiro e
// segue servindo a versão antiga até se convencer de que há uma nova — nem o
// recarregar forçado resolve. Como este app depende da rede para tudo que
// importa (Bybit, cotação, sincronização), o ganho de funcionar sem conexão
// não compensa mostrar dados velhos depois de cada publicação.
//
// Chamar `load()` sem `serviceWorkerSettings` faz o carregador não registrar
// nenhum. A limpeza dos que já foram registrados está no index.html.

{{flutter_js}}
{{flutter_build_config}}

_flutter.loader.load();
