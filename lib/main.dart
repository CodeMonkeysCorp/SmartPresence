import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'providers/session_provider.dart';
import 'screens/login_page.dart';

void main() {
  runApp(const SmartPresenceApp());
}

class SmartPresenceApp extends StatelessWidget {
  const SmartPresenceApp({super.key});
  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => SessionProvider(),
      child: MaterialApp(
        title: 'SmartPresence',
        theme: ThemeData(primarySwatch: Colors.indigo),
        debugShowCheckedModeBanner: false,
        home: const LoginPage(),
      ),
    );
  }
}
