import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'core/constants.dart';
import 'providers/auth_provider.dart';
import 'providers/convos_provider.dart';
import 'screens/splash_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    systemNavigationBarColor: Color(AppConstants.backgroundColorHex),
    systemNavigationBarIconBrightness: Brightness.light,
  ));
  runApp(const PotyGramApp());
}

class PotyGramApp extends StatelessWidget {
  const PotyGramApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthProvider()),
        ChangeNotifierProvider(create: (_) => ConvosProvider()),
      ],
      child: MaterialApp(
        title: AppConstants.appTitle,
        debugShowCheckedModeBanner: false,
        theme: ThemeData.dark().copyWith(
          scaffoldBackgroundColor: const Color(AppConstants.backgroundColorHex),
          primaryColor: const Color(AppConstants.primaryColorHex),
          colorScheme: const ColorScheme.dark(
            primary: Color(AppConstants.primaryColorHex),
            secondary: Color(AppConstants.primaryColorHex),
            surface: Color(AppConstants.cardColorHex),
          ),
          cardTheme: const CardThemeData(
            color: Color(AppConstants.cardColorHex),
            elevation: 0,
          ),
          appBarTheme: const AppBarTheme(
            backgroundColor: Color(AppConstants.cardColorHex),
            elevation: 0,
            iconTheme: IconThemeData(color: Colors.white),
            titleTextStyle: TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          inputDecorationTheme: InputDecorationTheme(
            filled: true,
            fillColor: const Color(AppConstants.cardColorHex),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide.none,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: Colors.white10),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: Color(AppConstants.primaryColorHex)),
            ),
            labelStyle: const TextStyle(color: Colors.white60),
            hintStyle: const TextStyle(color: Colors.white38),
          ),
        ),
        home: const SplashScreen(),
      ),
    );
  }
}
