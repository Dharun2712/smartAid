import 'package:flutter/material.dart';
import '../services/auth_service.dart';

enum UserRole { client, driver, admin }

class MultiRoleRegisterPage extends StatefulWidget {
  const MultiRoleRegisterPage({Key? key}) : super(key: key);

  @override
  State<MultiRoleRegisterPage> createState() => _MultiRoleRegisterPageState();
}

class _MultiRoleRegisterPageState extends State<MultiRoleRegisterPage> {
  final _formKey = GlobalKey<FormState>();
  final _authService = AuthService();

  UserRole _selectedRole = UserRole.client;
  bool _isLoading = false;

  // Common fields
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  // Driver-specific fields
  final _driverIdController = TextEditingController();
  final _vehicleTypeController = TextEditingController();
  final _vehiclePlateController = TextEditingController();
  final _vehicleModelController = TextEditingController();
  final _licenseNumberController = TextEditingController();

  // Hospital-specific fields
  final _hospitalCodeController = TextEditingController();
  final _hospitalNameController = TextEditingController();
  final _addressController = TextEditingController();

  // Client medical information
  String? _selectedBloodGroup;
  bool _hasMedicalAllergies = false;
  
  final List<String> _bloodGroups = [
    'A+', 'A-', 'B+', 'B-', 'AB+', 'AB-', 'O+', 'O-'
  ];

  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _driverIdController.dispose();
    _vehicleTypeController.dispose();
    _vehiclePlateController.dispose();
    _vehicleModelController.dispose();
    _licenseNumberController.dispose();
    _hospitalCodeController.dispose();
    _hospitalNameController.dispose();
    _addressController.dispose();
    super.dispose();
  }

  Future<void> _handleRegister() async {
    if (!_formKey.currentState!.validate()) return;

    if (_passwordController.text != _confirmPasswordController.text) {
      _showError('Passwords do not match');
      return;
    }

    setState(() => _isLoading = true);

    try {
      AuthResult result;

      switch (_selectedRole) {
        case UserRole.client:
          final identifier = _emailController.text.trim().isNotEmpty
              ? _emailController.text.trim()
              : _phoneController.text.trim();
          result = await _authService.registerClient(
            name: _nameController.text.trim(),
            identifier: identifier,
            password: _passwordController.text,
            bloodGroup: _selectedBloodGroup,
            hasMedicalAllergies: _hasMedicalAllergies,
          );
          break;

        case UserRole.driver:
          result = await _authService.registerDriver(
            name: _nameController.text.trim(),
            email: _emailController.text.trim(),
            phone: _phoneController.text.trim(),
            password: _passwordController.text,
            driverId: _driverIdController.text.trim(),
            vehicleType: _vehicleTypeController.text.trim(),
            vehiclePlate: _vehiclePlateController.text.trim(),
            vehicleModel: _vehicleModelController.text.trim(),
            licenseNumber: _licenseNumberController.text.trim(),
          );
          break;

        case UserRole.admin:
          result = await _authService.registerHospital(
            name: _nameController.text.trim(),
            email: _emailController.text.trim(),
            phone: _phoneController.text.trim(),
            password: _passwordController.text,
            hospitalCode: _hospitalCodeController.text.trim(),
            hospitalName: _hospitalNameController.text.trim(),
            address: _addressController.text.trim(),
          );
          break;
      }

      if (result.success && result.token != null && mounted) {
        await _authService.saveAuthData(
          token: result.token!,
          role: result.role!,
          userId: result.userId!,
        );

        _showSuccess('Registration successful! Redirecting...');
        await Future.delayed(const Duration(seconds: 1));

        if (!mounted) return;

        // Navigate to appropriate dashboard
        switch (_selectedRole) {
          case UserRole.client:
            Navigator.pushReplacementNamed(context, '/client');
            break;
          case UserRole.driver:
            Navigator.pushReplacementNamed(context, '/driver');
            break;
          case UserRole.admin:
            Navigator.pushReplacementNamed(context, '/hospital');
            break;
        }
      } else if (mounted) {
        _showError(result.errorMessage ?? 'Registration failed');
      }
    } catch (e) {
      if (mounted) {
        _showError('Error: $e');
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red),
    );
  }

  void _showSuccess(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.green),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Create Account'),
        backgroundColor: Colors.green,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Register',
                  style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),

                // Role selection
                const Text(
                  'Account Type',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  children: [
                    _buildRoleChip(UserRole.client, 'Client', Icons.person),
                    _buildRoleChip(UserRole.driver, 'Driver', Icons.local_shipping),
                    _buildRoleChip(UserRole.admin, 'Hospital', Icons.local_hospital),
                  ],
                ),
                const SizedBox(height: 24),

                // Common fields
                ..._buildCommonFields(),

                // Role-specific fields
                if (_selectedRole == UserRole.client) ..._buildClientFields(),
                if (_selectedRole == UserRole.driver) ..._buildDriverFields(),
                if (_selectedRole == UserRole.admin) ..._buildHospitalFields(),

                const SizedBox(height: 24),

                // Register button
                ElevatedButton(
                  onPressed: _isLoading ? null : _handleRegister,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  child: _isLoading
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation(Colors.white),
                          ),
                        )
                      : const Text(
                          'Register',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                ),
                const SizedBox(height: 16),

                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Already have an account? Login'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildRoleChip(UserRole role, String label, IconData icon) {
    final isSelected = _selectedRole == role;
    return ChoiceChip(
      label: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: isSelected ? Colors.white : Colors.grey),
          const SizedBox(width: 4),
          Text(label),
        ],
      ),
      selected: isSelected,
      onSelected: (selected) {
        if (selected) setState(() => _selectedRole = role);
      },
      selectedColor: Colors.green,
      labelStyle: TextStyle(
        color: isSelected ? Colors.white : Colors.black87,
        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
      ),
    );
  }

  List<Widget> _buildCommonFields() {
    return [
      TextFormField(
        controller: _nameController,
        decoration: const InputDecoration(
          labelText: 'Full Name *',
          prefixIcon: Icon(Icons.person),
          border: OutlineInputBorder(),
        ),
        validator: (v) => (v == null || v.trim().isEmpty) ? 'Name is required' : null,
      ),
      const SizedBox(height: 16),
      TextFormField(
        controller: _emailController,
        decoration: const InputDecoration(
          labelText: 'Email *',
          prefixIcon: Icon(Icons.email),
          border: OutlineInputBorder(),
        ),
        keyboardType: TextInputType.emailAddress,
        validator: (v) {
          if (v == null || v.trim().isEmpty) return 'Email is required';
          if (!RegExp(r'^[^@]+@[^@]+\.[^@]+').hasMatch(v)) return 'Invalid email';
          return null;
        },
      ),
      const SizedBox(height: 16),
      TextFormField(
        controller: _phoneController,
        decoration: const InputDecoration(
          labelText: 'Phone Number *',
          prefixIcon: Icon(Icons.phone),
          border: OutlineInputBorder(),
        ),
        keyboardType: TextInputType.phone,
        validator: (v) => (v == null || v.trim().length < 10) ? 'Valid phone required' : null,
      ),
      const SizedBox(height: 16),
      TextFormField(
        controller: _passwordController,
        obscureText: _obscurePassword,
        decoration: InputDecoration(
          labelText: 'Password *',
          prefixIcon: const Icon(Icons.lock),
          border: const OutlineInputBorder(),
          suffixIcon: IconButton(
            icon: Icon(_obscurePassword ? Icons.visibility : Icons.visibility_off),
            onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
          ),
        ),
        validator: (v) => (v == null || v.length < 6) ? 'Min 6 characters' : null,
      ),
      const SizedBox(height: 16),
      TextFormField(
        controller: _confirmPasswordController,
        obscureText: _obscureConfirmPassword,
        decoration: InputDecoration(
          labelText: 'Confirm Password *',
          prefixIcon: const Icon(Icons.lock_outline),
          border: const OutlineInputBorder(),
          suffixIcon: IconButton(
            icon: Icon(_obscureConfirmPassword ? Icons.visibility : Icons.visibility_off),
            onPressed: () => setState(() => _obscureConfirmPassword = !_obscureConfirmPassword),
          ),
        ),
        validator: (v) => (v == null || v.isEmpty) ? 'Confirm password' : null,
      ),
      const SizedBox(height: 16),
    ];
  }

  List<Widget> _buildClientFields() {
    return [
      // Blood Group Dropdown
      DropdownButtonFormField<String>(
        value: _selectedBloodGroup,
        decoration: const InputDecoration(
          labelText: 'Blood Group',
          prefixIcon: Icon(Icons.bloodtype),
          border: OutlineInputBorder(),
        ),
        items: _bloodGroups.map((String bloodGroup) {
          return DropdownMenuItem<String>(
            value: bloodGroup,
            child: Text(bloodGroup),
          );
        }).toList(),
        onChanged: (String? newValue) {
          setState(() {
            _selectedBloodGroup = newValue;
          });
        },
        validator: (value) {
          if (value == null || value.isEmpty) {
            return 'Please select your blood group';
          }
          return null;
        },
      ),
      const SizedBox(height: 16),
      
      // Medical Allergies
      Container(
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey.shade400),
          borderRadius: BorderRadius.circular(4),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            const Icon(Icons.medical_information, color: Colors.grey),
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                'Do you have any medical allergies?',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            Row(
              children: [
                Radio<bool>(
                  value: true,
                  groupValue: _hasMedicalAllergies,
                  onChanged: (bool? value) {
                    setState(() {
                      _hasMedicalAllergies = value ?? false;
                    });
                  },
                ),
                const Text('Yes'),
                const SizedBox(width: 12),
                Radio<bool>(
                  value: false,
                  groupValue: _hasMedicalAllergies,
                  onChanged: (bool? value) {
                    setState(() {
                      _hasMedicalAllergies = value ?? false;
                    });
                  },
                ),
                const Text('No'),
              ],
            ),
          ],
        ),
      ),
      const SizedBox(height: 16),
    ];
  }

  List<Widget> _buildDriverFields() {
    return [
      TextFormField(
        controller: _driverIdController,
        decoration: const InputDecoration(
          labelText: 'Driver ID *',
          prefixIcon: Icon(Icons.badge),
          border: OutlineInputBorder(),
        ),
        validator: (v) => (v == null || v.trim().isEmpty) ? 'Driver ID required' : null,
      ),
      const SizedBox(height: 16),
      TextFormField(
        controller: _licenseNumberController,
        decoration: const InputDecoration(
          labelText: 'License Number *',
          prefixIcon: Icon(Icons.credit_card),
          border: OutlineInputBorder(),
        ),
        validator: (v) => (v == null || v.trim().isEmpty) ? 'License number required' : null,
      ),
      const SizedBox(height: 16),
      TextFormField(
        controller: _vehicleTypeController,
        decoration: const InputDecoration(
          labelText: 'Vehicle Type *',
          prefixIcon: Icon(Icons.local_shipping),
          border: OutlineInputBorder(),
          hintText: 'e.g., ambulance',
        ),
        validator: (v) => (v == null || v.trim().isEmpty) ? 'Vehicle type required' : null,
      ),
      const SizedBox(height: 16),
      TextFormField(
        controller: _vehiclePlateController,
        decoration: const InputDecoration(
          labelText: 'Vehicle Plate *',
          prefixIcon: Icon(Icons.confirmation_number),
          border: OutlineInputBorder(),
        ),
        validator: (v) => (v == null || v.trim().isEmpty) ? 'Plate number required' : null,
      ),
      const SizedBox(height: 16),
      TextFormField(
        controller: _vehicleModelController,
        decoration: const InputDecoration(
          labelText: 'Vehicle Model *',
          prefixIcon: Icon(Icons.directions_car),
          border: OutlineInputBorder(),
        ),
        validator: (v) => (v == null || v.trim().isEmpty) ? 'Vehicle model required' : null,
      ),
      const SizedBox(height: 16),
    ];
  }

  List<Widget> _buildHospitalFields() {
    return [
      TextFormField(
        controller: _hospitalCodeController,
        decoration: const InputDecoration(
          labelText: 'Hospital Code *',
          prefixIcon: Icon(Icons.qr_code),
          border: OutlineInputBorder(),
        ),
        validator: (v) => (v == null || v.trim().isEmpty) ? 'Hospital code required' : null,
      ),
      const SizedBox(height: 16),
      TextFormField(
        controller: _hospitalNameController,
        decoration: const InputDecoration(
          labelText: 'Hospital Name *',
          prefixIcon: Icon(Icons.local_hospital),
          border: OutlineInputBorder(),
        ),
        validator: (v) => (v == null || v.trim().isEmpty) ? 'Hospital name required' : null,
      ),
      const SizedBox(height: 16),
      TextFormField(
        controller: _addressController,
        decoration: const InputDecoration(
          labelText: 'Hospital Address *',
          prefixIcon: Icon(Icons.location_on),
          border: OutlineInputBorder(),
        ),
        maxLines: 2,
        validator: (v) => (v == null || v.trim().isEmpty) ? 'Address required' : null,
      ),
      const SizedBox(height: 16),
    ];
  }
}
