import 'package:flutter/material.dart';
import 'theme/app_theme.dart';
import 'services/api_service.dart';
import 'screens/home_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  final apiService = ApiService();
  apiService.connectWebSocket();

  runApp(SplitBetApp(apiService: apiService));
}

class SplitBetApp extends StatelessWidget {
  final ApiService apiService;

  const SplitBetApp({super.key, required this.apiService});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SplitBet',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.darkTheme,
      home: ResponsiveScaffold(
        child: HomeScreen(apiService: apiService),
      ),
    );
  }
}

/// Centers the mobile view on wide desktop/web monitors while keeping native full-screen on mobile
class ResponsiveScaffold extends StatelessWidget {
  final Widget child;

  const ResponsiveScaffold({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth > 520) {
          return Scaffold(
            backgroundColor: const Color(0xFF070709),
            body: Center(
              child: Container(
                width: 480,
                decoration: BoxDecoration(
                  color: AppTheme.background,
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.6),
                      blurRadius: 40,
                      spreadRadius: 10,
                    ),
                  ],
                ),
                clipBehavior: Clip.antiAlias,
                child: child,
              ),
            ),
          );
        }
        return child;
      },
    );
  }
}
