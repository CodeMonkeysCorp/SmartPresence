import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // Para travar orientação
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart'; // Para locale pt_BR
import 'screens/role_selection_screen.dart'; // Tela inicial
import 'package:flutter/foundation.dart'; // Para kDebugMode
import 'package:logging/logging.dart';

Future<void> main() async {
  // Garante que os bindings do Flutter foram inicializados
  WidgetsFlutterBinding.ensureInitialized();

  // Define as orientações preferidas (trava em modo retrato)
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  // Define o locale padrão para pt_BR (afeta formatação de datas/horas)
  Intl.defaultLocale = 'pt_BR';

  // *** ADICIONE ESTA LINHA ***
  // Ativa o sistema de logging
  setupLogging();

  runApp(const SmartPresenceApp());
}

void setupLogging() {
  Logger.root.level = Level.ALL; // Define o nível mais baixo
  Logger.root.onRecord.listen((record) {
    // Em modo debug, imprime tudo no console
    if (kDebugMode) {
      print(
        '${record.level.name}: ${record.time}: ${record.loggerName}: ${record.message}',
      );
    }

    // Em modo release (produção), você pode enviar logs de erro
    // para um serviço como Firebase Crashlyrics ou Sentry.
    if (kReleaseMode && record.level >= Level.SEVERE) {
      // myCrashReportingService.logError(record.message, record.stackTrace);
    }
  });
}

class SmartPresenceApp extends StatelessWidget {
  const SmartPresenceApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SmartPresence',
      theme: ThemeData(
        // Tema principal com base em uma cor semente (Material 3)
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF4A00E0)),
        useMaterial3: true,
        // Cor de fundo padrão para Scaffolds
        scaffoldBackgroundColor: const Color(0xFFF0F2F5),
        // Estilo padrão para AppBar
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.white,
          foregroundColor: Colors.black87, // Cor do título e ícones
          elevation: 1, // Pequena sombra
          titleTextStyle: TextStyle(
            // Estilo do título
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: Colors.black87,
          ),
        ),
        // Opcional: Definir uma fonte padrão
        // fontFamily: 'Inter',
      ),
      debugShowCheckedModeBanner: false, // Remove o banner de debug
      // Configurações de localização para pt_BR
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [
        Locale('pt', 'BR'), // Suporta apenas Português do Brasil
      ],
      home: const RoleSelectionScreen(), // Define a tela inicial
    );
  }
}
