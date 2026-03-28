import 'package:flutter/material.dart';

import 'screens/home_screen.dart';

@Deprecated('Use HomeScreen from lib/screens/home_screen.dart instead.')
class Dashboard extends StatelessWidget {
  const Dashboard({super.key});

  @override
  Widget build(BuildContext context) {
    return const HomeScreen();
  }
}
