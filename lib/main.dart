import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'app_bootstrap.dart';
import 'providers/auth_provider.dart';
import 'providers/automation_hub_provider.dart';
import 'providers/notification_provider.dart';
import 'providers/operations_repository.dart';
import 'providers/terminal_state_provider.dart';
import 'providers/theme_provider.dart';
import 'screens/home_screen.dart';
import 'screens/login_screen.dart';
import 'services/port_api_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final bootstrapState = await AppBootstrap.initialize();
  runApp(MyApp(bootstrapState: bootstrapState));
}

class MyApp extends StatelessWidget {
  const MyApp({super.key, required this.bootstrapState});

  final AppBootstrapState bootstrapState;

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ThemeProvider()),
        Provider(
          create: (_) => PortApiService(
            firebaseEnabled: bootstrapState.isFirebaseAvailable,
          ),
        ),
        ChangeNotifierProvider(
          create: (_) => AuthProvider(
            firebaseEnabled: bootstrapState.isFirebaseAvailable,
            statusMessage: bootstrapState.statusMessage,
          ),
        ),
        ChangeNotifierProvider(create: (_) => AutomationHubProvider()),
        ChangeNotifierProvider(create: (_) => NotificationProvider()),
        ChangeNotifierProvider(
          create: (context) => OperationsRepository(
            apiService: context.read<PortApiService>(),
          ),
        ),
        ChangeNotifierProvider(
          create: (context) => TerminalStateProvider(
            apiService: context.read<PortApiService>(),
          ),
        ),
      ],
      child: Consumer2<ThemeProvider, AuthProvider>(
        builder: (context, themeProvider, authProvider, _) {
          return MaterialApp(
            title: 'PortOS NextGen',
            debugShowCheckedModeBanner: false,
            theme: themeProvider.lightTheme,
            darkTheme: themeProvider.darkTheme,
            themeMode: themeProvider.themeMode,
            home: authProvider.isAuthenticated
                ? const HomeScreen()
                : const LoginScreen(),
          );
        },
      ),
    );
  }
}
