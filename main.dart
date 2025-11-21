import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'pages/login_page.dart';
import 'pages/register_page.dart';
import 'pages/multi_role_register_page.dart';
import 'pages/client_dashboard.dart';
import 'pages/driver_dashboard.dart';
import 'pages/admin_dashboard.dart';
// Enhanced dashboards with full Smart Ambulance features
import 'pages/client_dashboard_enhanced.dart';
import 'pages/driver_dashboard_enhanced.dart';
import 'pages/admin_dashboard_enhanced.dart';
// V2 Enhanced dashboards with beautiful UI (not used by default)
// import 'pages/client_dashboard_v2.dart';
// import 'pages/driver_dashboard_v2.dart';
import 'pages/driver_queue_screen.dart';
import 'services/auth_service.dart';
import 'config/app_theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Load environment variables for backend configuration
  try {
    await dotenv.load(fileName: '.env');
  } catch (e) {
    print('Warning: .env file not found. Using defaults.');
  }
  
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Smart Ambulance',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      home: const AuthWrapper(),
      routes: {
        '/login': (context) => const LoginPage(),
        '/register': (context) => const RegisterPage(),
        '/multi-register': (context) => const MultiRoleRegisterPage(),
        // Enhanced dashboards (V1) - default with full Smart Ambulance features
        '/client': (context) => const ClientDashboardEnhanced(),
        '/driver': (context) => const DriverDashboardEnhanced(),
        '/admin': (context) => const AdminDashboardEnhanced(),
        '/driver_queue': (context) => const DriverQueueScreen(),
        // Hospital is the new label for admin dashboard
        '/hospital': (context) => const AdminDashboardEnhanced(),
        // Basic dashboards (legacy)
        '/client_basic': (context) => const ClientDashboard(),
        '/driver_basic': (context) => const DriverDashboard(),
        '/admin_basic': (context) => const AdminDashboard(),
        // V2 dashboards (not used by default)
        // '/client_v2': (context) => const ClientDashboardV2(),
        // '/driver_v2': (context) => const DriverDashboardV2(),
      },
    );
  }
}

/// Wrapper widget to check authentication status on app startup
class AuthWrapper extends StatefulWidget {
  const AuthWrapper({super.key});

  @override
  State<AuthWrapper> createState() => _AuthWrapperState();
}

class _AuthWrapperState extends State<AuthWrapper> {
  final _authService = AuthService();
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _checkAuthStatus();
  }

  Future<void> _checkAuthStatus() async {
    // Check if user is already logged in
    final isLoggedIn = await _authService.isLoggedIn();
    
    if (isLoggedIn) {
      final role = await _authService.getRole();
      
      if (mounted) {
        // Navigate to appropriate dashboard based on role
        switch (role) {
          case 'client':
            Navigator.pushReplacementNamed(context, '/client');
            break;
          case 'driver':
            Navigator.pushReplacementNamed(context, '/driver');
            break;
          case 'admin':
            // Route alias for Hospital dashboard
            Navigator.pushReplacementNamed(context, '/hospital');
            break;
          default:
            setState(() => _isLoading = false);
        }
      }
    } else {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(),
        ),
      );
    }
    
    return const LoginPage();
  }
}
