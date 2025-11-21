// lib/pages/login_page.dart

import 'package:flutter/material.dart';
import '../services/auth_service.dart';

enum UserRole { client, driver, admin }

class LoginPage extends StatefulWidget {
  const LoginPage({Key? key}) : super(key: key);

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  UserRole _selectedRole = UserRole.client;
  final _formKey = GlobalKey<FormState>();
  final _authService = AuthService();
  bool _isLoading = false;
  String _errorMessage = '';

  // Form field controllers
  final _identifierController = TextEditingController();
  final _passwordController = TextEditingController();
  final _driverIdController = TextEditingController();
  final _hospitalCodeController = TextEditingController();

  @override
  void dispose() {
    _identifierController.dispose();
    _passwordController.dispose();
    _driverIdController.dispose();
    _hospitalCodeController.dispose();
    super.dispose();
  }

  void _showError(String message) {
    setState(() => _errorMessage = message);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.redAccent,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _showSuccess(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.green,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _handleLogin() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });

    try {
      AuthResult result;

      switch (_selectedRole) {
        case UserRole.client:
          result = await _authService.loginClient(
            identifier: _identifierController.text.trim(),
            password: _passwordController.text,
          );
          break;
        case UserRole.driver:
          result = await _authService.loginDriver(
            driverId: _driverIdController.text.trim(),
            password: _passwordController.text,
          );
          break;
        case UserRole.admin:
          result = await _authService.loginAdmin(
            hospitalCode: _hospitalCodeController.text.trim(),
            password: _passwordController.text,
          );
          break;
      }

      if (result.success && result.token != null) {
        // Save auth data
        await _authService.saveAuthData(
          token: result.token!,
          role: result.role!,
          userId: result.userId!,
        );

        _showSuccess('Login successful!');

        // Navigate based on role
        if (!mounted) return;
        switch (result.role) {
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
            _showError('Unknown role: ${result.role}');
        }
      } else {
        _showError(result.errorMessage ?? 'Login failed');
      }
    } catch (e) {
      _showError('Error: ${e.toString()}');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Widget _buildRoleSelector() {
    // Use Wrap to avoid horizontal overflow on small screens
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 8,
      runSpacing: 8,
      children: [
        _buildRoleChip(UserRole.client, 'Client', Icons.person),
        _buildRoleChip(UserRole.driver, 'Driver', Icons.local_shipping),
        // Rename Admin to Hospital in UI while keeping role value as 'admin'
        _buildRoleChip(UserRole.admin, 'Hospital', Icons.local_hospital),
      ],
    );
  }

  Widget _buildRoleChip(UserRole role, String label, IconData icon) {
    final isSelected = _selectedRole == role;
    return FilterChip(
      label: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: isSelected ? Colors.white : Colors.grey[700]),
          const SizedBox(width: 4),
          Text(label),
        ],
      ),
      selected: isSelected,
      onSelected: (_) {
        setState(() {
          _selectedRole = role;
          _errorMessage = '';
        });
      },
      selectedColor: Colors.red.shade600,
      backgroundColor: Colors.grey.shade200,
      labelStyle: TextStyle(
        color: isSelected ? Colors.white : Colors.grey[700],
        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
      ),
    );
  }

  Widget _buildClientForm() {
    return Column(
      children: [
        TextFormField(
          controller: _identifierController,
          decoration: InputDecoration(
            labelText: 'Email or Phone',
            prefixIcon: const Icon(Icons.person_outline),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            filled: true,
            fillColor: Colors.grey.shade50,
          ),
          keyboardType: TextInputType.emailAddress,
          textInputAction: TextInputAction.next,
          validator: (value) {
            if (value == null || value.trim().isEmpty) {
              return 'Email or phone is required';
            }
            final trimmed = value.trim();
            if (trimmed.contains('@')) {
              // Email validation
              final emailRegex = RegExp(r'^[^@]+@[^@]+\.[^@]+');
              if (!emailRegex.hasMatch(trimmed)) {
                return 'Enter a valid email';
              }
            } else {
              // Phone validation
              final phoneRegex = RegExp(r'^[0-9]{6,15}$');
              if (!phoneRegex.hasMatch(trimmed)) {
                return 'Enter a valid phone number';
              }
            }
            return null;
          },
        ),
        const SizedBox(height: 16),
        TextFormField(
          controller: _passwordController,
          decoration: InputDecoration(
            labelText: 'Password',
            prefixIcon: const Icon(Icons.lock_outline),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            filled: true,
            fillColor: Colors.grey.shade50,
          ),
          obscureText: true,
          textInputAction: TextInputAction.done,
          onFieldSubmitted: (_) => _handleLogin(),
          validator: (value) {
            if (value == null || value.length < 6) {
              return 'Password must be at least 6 characters';
            }
            return null;
          },
        ),
      ],
    );
  }

  Widget _buildDriverForm() {
    return Column(
      children: [
        TextFormField(
          controller: _driverIdController,
          decoration: InputDecoration(
            labelText: 'Driver ID',
            prefixIcon: const Icon(Icons.badge_outlined),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            filled: true,
            fillColor: Colors.grey.shade50,
          ),
          textInputAction: TextInputAction.next,
          validator: (value) {
            if (value == null || value.trim().isEmpty) {
              return 'Driver ID is required';
            }
            return null;
          },
        ),
        const SizedBox(height: 16),
        TextFormField(
          controller: _passwordController,
          decoration: InputDecoration(
            labelText: 'Password',
            prefixIcon: const Icon(Icons.lock_outline),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            filled: true,
            fillColor: Colors.grey.shade50,
          ),
          obscureText: true,
          textInputAction: TextInputAction.done,
          onFieldSubmitted: (_) => _handleLogin(),
          validator: (value) {
            if (value == null || value.length < 6) {
              return 'Password must be at least 6 characters';
            }
            return null;
          },
        ),
      ],
    );
  }

  Widget _buildAdminForm() {
    return Column(
      children: [
        TextFormField(
          controller: _hospitalCodeController,
          decoration: InputDecoration(
            labelText: 'Hospital Code',
            prefixIcon: const Icon(Icons.local_hospital_outlined),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            filled: true,
            fillColor: Colors.grey.shade50,
          ),
          textInputAction: TextInputAction.next,
          validator: (value) {
            if (value == null || value.trim().isEmpty) {
              return 'Hospital code is required';
            }
            return null;
          },
        ),
        const SizedBox(height: 16),
        TextFormField(
          controller: _passwordController,
          decoration: InputDecoration(
            labelText: 'Password',
            prefixIcon: const Icon(Icons.lock_outline),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            filled: true,
            fillColor: Colors.grey.shade50,
          ),
          obscureText: true,
          textInputAction: TextInputAction.done,
          onFieldSubmitted: (_) => _handleLogin(),
          validator: (value) {
            if (value == null || value.length < 6) {
              return 'Password must be at least 6 characters';
            }
            return null;
          },
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 600),
              child: Card(
                elevation: 8,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Header
                        Column(
                          children: [
                            Icon(
                              Icons.local_hospital,
                              size: 64,
                              color: Colors.red.shade600,
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'Smart Ambulance',
                              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: Colors.grey.shade800,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Secure login — select role and sign in',
                              style: TextStyle(
                                color: Colors.grey.shade600,
                                fontSize: 14,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                        const SizedBox(height: 24),

                        // Role selector
                        _buildRoleSelector(),
                        const SizedBox(height: 24),

                        // Form fields based on role
                        if (_selectedRole == UserRole.client) _buildClientForm(),
                        if (_selectedRole == UserRole.driver) _buildDriverForm(),
                        if (_selectedRole == UserRole.admin) _buildAdminForm(),

                        const SizedBox(height: 24),

                        // Login button
                        _isLoading
                            ? const Center(child: CircularProgressIndicator())
                            : ElevatedButton(
                                onPressed: _handleLogin,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.red.shade600,
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(vertical: 16),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  elevation: 2,
                                ),
                                child: const Text(
                                  'Sign In',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),

                        // Register link for clients
                        if (_selectedRole == UserRole.client) ...[
                          const SizedBox(height: 12),
                          TextButton(
                            onPressed: () {
                              // Navigate to multi-role registration page
                              Navigator.pushNamed(context, '/multi-register');
                            },
                            child: const Text("Don't have an account? Register"),
                          ),
                        ],

                        // Error message
                        if (_errorMessage.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 16),
                            child: Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.red.shade50,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: Colors.red.shade200),
                              ),
                              child: Row(
                                children: [
                                  Icon(Icons.error_outline, color: Colors.red.shade700, size: 20),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      _errorMessage,
                                      style: TextStyle(
                                        color: Colors.red.shade700,
                                        fontSize: 13,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
