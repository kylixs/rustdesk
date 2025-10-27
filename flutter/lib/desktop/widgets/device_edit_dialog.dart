import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../models/device_list_model.dart';

/// Dialog for adding or editing a device
class DeviceEditDialog extends StatefulWidget {
  final DeviceConfig? device; // null for add mode, non-null for edit mode
  final List<String> existingNames; // List of existing device names for validation

  const DeviceEditDialog({
    Key? key,
    this.device,
    this.existingNames = const [],
  }) : super(key: key);

  @override
  State<DeviceEditDialog> createState() => _DeviceEditDialogState();
}

class _DeviceEditDialogState extends State<DeviceEditDialog> {
  final _formKey = GlobalKey<FormState>();

  // Controllers for form fields
  late TextEditingController _nameController;
  late TextEditingController _idController;
  late TextEditingController _ipController;
  late TextEditingController _portController;
  late TextEditingController _passwordController;
  late TextEditingController _platformController;
  late TextEditingController _noteController;
  late TextEditingController _usernameController;
  late TextEditingController _hostnameController;

  bool _isEditMode = false;
  bool _passwordVisible = false;
  bool _passwordChanged = false;
  String _originalPassword = '';

  @override
  void initState() {
    super.initState();

    _isEditMode = widget.device != null;
    final device = widget.device;

    _nameController = TextEditingController(text: device?.name ?? '');
    _idController = TextEditingController(text: device?.id ?? '');
    _ipController = TextEditingController(text: device?.ip ?? '');
    _portController = TextEditingController(text: device?.port.toString() ?? '21118');
    // Don't show password in edit mode, keep original encrypted password
    _originalPassword = device?.password ?? '';
    _passwordController = TextEditingController(text: '');
    _platformController = TextEditingController(text: device?.platform ?? '');
    _noteController = TextEditingController(text: device?.note ?? '');
    _usernameController = TextEditingController(text: device?.username ?? '');
    _hostnameController = TextEditingController(text: device?.hostname ?? '');

    // Monitor password changes
    _passwordController.addListener(() {
      if (!_passwordChanged && _passwordController.text.isNotEmpty) {
        _passwordChanged = true;
      }
    });
  }

  @override
  void dispose() {
    _nameController.dispose();
    _idController.dispose();
    _ipController.dispose();
    _portController.dispose();
    _passwordController.dispose();
    _platformController.dispose();
    _noteController.dispose();
    _usernameController.dispose();
    _hostnameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(_isEditMode ? 'Edit Device' : 'Add Device'),
      content: SizedBox(
        width: 500,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildTextField(
                  controller: _nameController,
                  label: 'Device Name *',
                  hint: 'My Computer',
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Device name is required';
                    }
                    // Check duplicate name (skip current device in edit mode)
                    if (!_isEditMode || value != widget.device?.name) {
                      if (widget.existingNames.contains(value)) {
                        return 'Device with this name already exists';
                      }
                    }
                    return null;
                  },
                ),
                SizedBox(height: 12),
                _buildTextField(
                  controller: _idController,
                  label: 'RustDesk ID',
                  hint: '123456789',
                  validator: (value) {
                    if (value != null && value.trim().isNotEmpty) {
                      if (!RegExp(r'^\d{9}$').hasMatch(value)) {
                        return 'ID must be exactly 9 digits';
                      }
                    }
                    // Either ID or IP must be provided
                    if ((value == null || value.trim().isEmpty) &&
                        _ipController.text.trim().isEmpty) {
                      return 'Either ID or IP must be provided';
                    }
                    return null;
                  },
                ),
                SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: _buildTextField(
                        controller: _ipController,
                        label: 'IP Address',
                        hint: '192.168.1.100',
                        validator: (value) {
                          // Either ID or IP must be provided
                          if ((value == null || value.trim().isEmpty) &&
                              _idController.text.trim().isEmpty) {
                            return 'Either ID or IP must be provided';
                          }
                          return null;
                        },
                      ),
                    ),
                    SizedBox(width: 12),
                    Expanded(
                      flex: 1,
                      child: _buildTextField(
                        controller: _portController,
                        label: 'Port',
                        hint: '21118',
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                        ],
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'Required';
                          }
                          final port = int.tryParse(value);
                          if (port == null || port < 1 || port > 65535) {
                            return 'Invalid port';
                          }
                          return null;
                        },
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 12),
                _buildTextField(
                  controller: _passwordController,
                  label: 'Password',
                  hint: _isEditMode ? 'Leave empty to keep current password' : 'Optional',
                  obscureText: !_passwordVisible,
                  suffixIcon: IconButton(
                    icon: Icon(
                      _passwordVisible ? Icons.visibility : Icons.visibility_off,
                      size: 18,
                    ),
                    onPressed: () {
                      setState(() {
                        _passwordVisible = !_passwordVisible;
                      });
                    },
                  ),
                ),
                SizedBox(height: 12),
                _buildTextField(
                  controller: _platformController,
                  label: 'Platform',
                  hint: 'Windows, Linux, macOS',
                ),
                SizedBox(height: 12),
                _buildTextField(
                  controller: _usernameController,
                  label: 'Username',
                  hint: 'Optional',
                ),
                SizedBox(height: 12),
                _buildTextField(
                  controller: _hostnameController,
                  label: 'Hostname',
                  hint: 'Optional',
                ),
                SizedBox(height: 12),
                _buildTextField(
                  controller: _noteController,
                  label: 'Note',
                  hint: 'Optional notes',
                  maxLines: 2,
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _saveDevice,
          child: Text(_isEditMode ? 'Save' : 'Add'),
        ),
      ],
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    String? hint,
    String? Function(String?)? validator,
    bool obscureText = false,
    TextInputType? keyboardType,
    List<TextInputFormatter>? inputFormatters,
    int maxLines = 1,
    Widget? suffixIcon,
  }) {
    return TextFormField(
      controller: controller,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        border: OutlineInputBorder(),
        isDense: true,
        suffixIcon: suffixIcon,
      ),
      validator: validator,
      obscureText: obscureText,
      keyboardType: keyboardType,
      inputFormatters: inputFormatters,
      maxLines: maxLines,
      style: TextStyle(fontSize: 14),
    );
  }

  void _saveDevice() {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    // Determine which password to use
    String finalPassword;
    if (_isEditMode && !_passwordChanged) {
      // Keep original encrypted password
      finalPassword = _originalPassword;
    } else if (_passwordController.text.isNotEmpty) {
      // Use new password (will be encrypted in the model)
      finalPassword = _passwordController.text;
    } else {
      // No password
      finalPassword = '';
    }

    final device = DeviceConfig(
      name: _nameController.text.trim(),
      id: _idController.text.trim(),
      ip: _ipController.text.trim(),
      port: int.parse(_portController.text.trim()),
      password: finalPassword,
      platform: _platformController.text.trim(),
      note: _noteController.text.trim(),
      username: _usernameController.text.trim(),
      hostname: _hostnameController.text.trim(),
      passwordNeedEncrypt: _passwordChanged, // Flag to indicate if password needs encryption
    );

    Navigator.of(context).pop(device);
  }
}
