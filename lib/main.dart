import 'package:flutter/material.dart';

import 'home/home_page.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const DocScanApp());
}

class DocScanApp extends StatelessWidget {
  const DocScanApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '拍照扫描',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF2F6BFF),
          brightness: Brightness.light,
        ),
        scaffoldBackgroundColor: const Color(0xFFF5F6FA),
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.white,
          foregroundColor: Color(0xFF1F2329),
          elevation: 0,
          centerTitle: true,
          titleTextStyle: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w600,
            color: Color(0xFF1F2329),
          ),
        ),
        snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
      ),
      home: const HomePage(),
    );
  }
}
