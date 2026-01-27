import 'package:flutter/material.dart';
import 'package:ingeo_app/features/dashboard_screen.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({Key? key}) : super(key: key);

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();

  final _nameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _emailController = TextEditingController();
  final _institutionController = TextEditingController();
  final _specialtyController = TextEditingController();
  final _passwordController = TextEditingController();
  final _repeatPasswordController = TextEditingController();

  final List<String> _specialties = [
    'Geografía',
    'Ingeniería Civil',
    'Topografía',
    'Geología',
    'Otra',
  ];
  String? _selectedSpecialty;

  bool _obscurePassword = true;
  bool _obscureRepeatPassword = true;
  bool _isLoading = false;

  @override
  void dispose() {
    _nameController.dispose();
    _lastNameController.dispose();
    _emailController.dispose();
    _institutionController.dispose();
    _specialtyController.dispose();
    _passwordController.dispose();
    _repeatPasswordController.dispose();
    super.dispose();
  }

  Future<void> _register() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
    });

    // Simular llamada a backend / registro
    await Future.delayed(const Duration(seconds: 2));

    if (!mounted) return;

    setState(() {
      _isLoading = false;
    });

    // Aquí iría la lógica real de registro (API, guardado local, etc.)
    // Por ahora, asumimos registro exitoso y vamos al Dashboard.
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (context) => const DashboardScreen()),
    );
  }

  InputDecoration _buildUnderlineDecoration(String label) {
    return InputDecoration(
      labelText: label,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.grey.shade300),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Colors.teal, width: 2),
      ),
    );
  }

  void _showSpecialtyBottomSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        final height = MediaQuery.of(context).size.height * 0.5;
        return SizedBox(
          height: height,
          child: Column(
            children: [
              const SizedBox(height: 8),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Seleccionar Especialidad',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: ListView.builder(
                  itemCount: _specialties.length,
                  itemBuilder: (context, index) {
                    final specialty = _specialties[index];
                    final selected = specialty == _selectedSpecialty;
                    return ListTile(
                      title: Text(specialty),
                      trailing: selected
                          ? const Icon(Icons.check, color: Colors.teal)
                          : null,
                      onTap: () {
                        setState(() {
                          _selectedSpecialty = specialty;
                          _specialtyController.text = specialty;
                        });
                        Navigator.pop(context);
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Logo arriba a la derecha (similar a la imagen)
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [Image.asset('assets/icon/icon.png', height: 60)],
                  ),
                  const SizedBox(height: 32),

                  // Nombre
                  TextFormField(
                    controller: _nameController,
                    decoration: _buildUnderlineDecoration('Nombre'),
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Ingrese su nombre';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 12),

                  // Apellidos
                  TextFormField(
                    controller: _lastNameController,
                    decoration: _buildUnderlineDecoration('Apellidos'),
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Ingrese sus apellidos';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 12),

                  // Correo electrónico
                  TextFormField(
                    controller: _emailController,
                    decoration: _buildUnderlineDecoration('Correo electrónico'),
                    keyboardType: TextInputType.emailAddress,
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Ingrese su correo electrónico';
                      }
                      if (!value.contains('@')) {
                        return 'Ingrese un correo válido';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 12),

                  // Institución u Organización
                  TextFormField(
                    controller: _institutionController,
                    decoration: _buildUnderlineDecoration(
                      'Institución u Organización',
                    ),
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Ingrese su institución u organización';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 12),

                  // Especialidad (Selector con modal)
                  TextFormField(
                    controller: _specialtyController,
                    readOnly: true,
                    decoration: _buildUnderlineDecoration(
                      'Especialidad',
                    ).copyWith(suffixIcon: const Icon(Icons.arrow_drop_down)),
                    onTap: _showSpecialtyBottomSheet,
                    validator: (_) {
                      if (_selectedSpecialty == null ||
                          _selectedSpecialty!.isEmpty) {
                        return 'Seleccione una especialidad';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 12),

                  // Contraseña
                  TextFormField(
                    controller: _passwordController,
                    obscureText: _obscurePassword,
                    decoration: _buildUnderlineDecoration('Contraseña')
                        .copyWith(
                          suffixIcon: IconButton(
                            icon: Icon(
                              _obscurePassword
                                  ? Icons.visibility_outlined
                                  : Icons.visibility_off_outlined,
                              color: Colors.grey[600],
                            ),
                            onPressed: () {
                              setState(() {
                                _obscurePassword = !_obscurePassword;
                              });
                            },
                          ),
                        ),
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Ingrese una contraseña';
                      }
                      if (value.length < 6) {
                        return 'La contraseña debe tener al menos 6 caracteres';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 12),

                  // Repetir Contraseña
                  TextFormField(
                    controller: _repeatPasswordController,
                    obscureText: _obscureRepeatPassword,
                    decoration: _buildUnderlineDecoration('Repetir Contraseña')
                        .copyWith(
                          suffixIcon: IconButton(
                            icon: Icon(
                              _obscureRepeatPassword
                                  ? Icons.visibility_outlined
                                  : Icons.visibility_off_outlined,
                              color: Colors.grey[600],
                            ),
                            onPressed: () {
                              setState(() {
                                _obscureRepeatPassword =
                                    !_obscureRepeatPassword;
                              });
                            },
                          ),
                        ),
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Repita la contraseña';
                      }
                      if (value != _passwordController.text) {
                        return 'Las contraseñas no coinciden';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 32),

                  // Botón Crear Cuenta (teal tipo pill, como en la imagen)
                  SizedBox(
                    height: 50,
                    child: ElevatedButton(
                      onPressed: _isLoading ? null : _register,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.teal,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(24),
                        ),
                        elevation: 2,
                      ),
                      child: _isLoading
                          ? const SizedBox(
                              height: 24,
                              width: 24,
                              child: CircularProgressIndicator(
                                color: Colors.white,
                                strokeWidth: 2,
                              ),
                            )
                          : const Text(
                              'Crear Cuenta',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
