import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'app_state.dart';
import 'theme.dart';
import 'ui/shell.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('pt_BR', null);
  runApp(const BybitStatementApp());
}

class BybitStatementApp extends StatefulWidget {
  const BybitStatementApp({super.key});

  @override
  State<BybitStatementApp> createState() => _BybitStatementAppState();
}

class _BybitStatementAppState extends State<BybitStatementApp>
    with WidgetsBindingObserver {
  final AppState _state = AppState();
  ThemeMode _themeMode = ThemeMode.dark;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _state.boot();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _state.dispose();
    super.dispose();
  }

  /// Voltar ao app é o momento em que se quer ver a compra recém-feita, então
  /// ele busca dados novos sozinho — respeitando um intervalo mínimo para não
  /// castigar a API a cada troca de janela.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _state.refreshIfStale();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Extrato Bybit',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(Brightness.light),
      darkTheme: buildTheme(Brightness.dark),
      themeMode: _themeMode,
      home: AnimatedBuilder(
        animation: _state,
        builder: (context, _) => AppShell(
          state: _state,
          themeMode: _themeMode,
          onThemeModeChanged: (mode) => setState(() => _themeMode = mode),
        ),
      ),
    );
  }
}
