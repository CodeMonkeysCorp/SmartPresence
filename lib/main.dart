import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart'; // Para locale pt_BR
import 'screens/role_selection_screen.dart'; // Tela inicial
import 'package:flutter/foundation.dart'; // Para kDebugMode
import 'package:logging/logging.dart';
import 'package:google_fonts/google_fonts.dart';

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

  // Ativa o sistema de logging
  setupLogging();

  runApp(const SmartPresenceApp());
}

void setupLogging() {
  Logger.root.level = Level.ALL;
  Logger.root.onRecord.listen((record) {
    if (kDebugMode) {
      print(
        '${record.level.name}: ${record.time}: ${record.loggerName}: ${record.message}',
      );
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
        // Tema principal com base em uma cor semente
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF4A00E0)),
        useMaterial3: true,
        // Cor de fundo padrão para Scaffolds
        scaffoldBackgroundColor: const Color(0xFFF0F2F5),
        // Fonte Padrão
        fontFamily: GoogleFonts.inter().fontFamily,
        // Estilo padrão para AppBar
        appBarTheme: AppBarTheme(
          backgroundColor: Colors.white,
          foregroundColor: Colors.black87,
          elevation: 1,
          titleTextStyle: GoogleFonts.inter(
            // Estilo do título
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: Colors.black87,
          ),
        ),
        // Estilo do texto geral
        textTheme: GoogleFonts.interTextTheme(Theme.of(context).textTheme),
        cardTheme: CardThemeData(
          elevation: 2,
          shadowColor: Colors.black.withOpacity(0.1),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16.0),
          ),
          // Define uma margem padrão para os cards
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        ),
      ),
      debugShowCheckedModeBanner: false,
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
