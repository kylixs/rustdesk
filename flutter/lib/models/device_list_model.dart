import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_hbb/common.dart';
import 'package:flutter_hbb/models/platform_model.dart';
import 'package:flutter_hbb/utils/multi_window_manager.dart';

/// Device configuration for remote connections
class DeviceConfig {
  final String name;
  final String id;
  final String ip;
  final int port;
  final String password;
  final String platform;
  final String note;
  final String username;
  final String hostname;
  final bool passwordNeedEncrypt; // Internal flag, not saved to JSON

  DeviceConfig({
    required this.name,
    this.id = '',
    this.ip = '',
    this.port = 21118,
    this.password = '',
    this.platform = '',
    this.note = '',
    this.username = '',
    this.hostname = '',
    this.passwordNeedEncrypt = false,
  });

  /// Create DeviceConfig from JSON
  factory DeviceConfig.fromJson(Map<String, dynamic> json) {
    return DeviceConfig(
      name: json['name'] ?? '',
      id: json['id'] ?? '',
      ip: json['ip'] ?? '',
      port: json['port'] ?? 21118,
      password: json['password'] ?? '',
      platform: json['platform'] ?? '',
      note: json['note'] ?? '',
      username: json['username'] ?? '',
      hostname: json['hostname'] ?? '',
    );
  }

  /// Convert DeviceConfig to JSON
  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'id': id,
      'ip': ip,
      'port': port,
      'password': password,
      'platform': platform,
      'note': note,
      'username': username,
      'hostname': hostname,
    };
  }

  /// Get display target (IP or ID)
  /// Priority: IP > ID
  String get displayTarget {
    if (ip.isNotEmpty) {
      return ip;
    }
    return id;
  }

  /// Get connection target for establishing connection
  /// Returns (target_string, is_ip_connection)
  (String, bool) get connectionTarget {
    if (ip.isNotEmpty) {
      // IP connection: "ip:port"
      return ('$ip:$port', true);
    } else {
      // ID connection: just the ID
      return (id, false);
    }
  }

  /// Check if device matches search query
  bool matchesSearch(String query) {
    if (query.isEmpty) return true;

    final q = query.toLowerCase();
    return name.toLowerCase().contains(q) ||
        id.toLowerCase().contains(q) ||
        ip.toLowerCase().contains(q) ||
        platform.toLowerCase().contains(q) ||
        note.toLowerCase().contains(q) ||
        username.toLowerCase().contains(q) ||
        hostname.toLowerCase().contains(q);
  }

  /// Validate device configuration
  String? validate() {
    if (name.trim().isEmpty) {
      return 'Device name cannot be empty';
    }

    if (id.trim().isEmpty && ip.trim().isEmpty) {
      return 'Either ID or IP must be provided for device "$name"';
    }

    if (id.trim().isNotEmpty) {
      // RustDesk ID should be 9 digits
      if (!RegExp(r'^\d{9}$').hasMatch(id)) {
        return 'Invalid ID format for device "$name": ID must be exactly 9 digits';
      }
    }

    if (port < 1 || port > 65535) {
      return 'Invalid port for device "$name": port must be between 1-65535';
    }

    return null; // Valid
  }

  @override
  String toString() {
    return 'DeviceConfig(name: $name, id: $id, ip: $ip, port: $port)';
  }
}

/// Device list configuration
class DeviceListConfig {
  final String version;
  final String defaultConnectionMode;
  final List<DeviceConfig> devices;

  DeviceListConfig({
    this.version = '1.0',
    this.defaultConnectionMode = 'id',
    this.devices = const [],
  });

  /// Create DeviceListConfig from JSON
  factory DeviceListConfig.fromJson(Map<String, dynamic> json) {
    final devicesList = (json['devices'] as List<dynamic>?)
            ?.map((d) => DeviceConfig.fromJson(d as Map<String, dynamic>))
            .toList() ??
        [];

    return DeviceListConfig(
      version: json['version'] ?? '1.0',
      defaultConnectionMode: json['default_connection_mode'] ?? 'id',
      devices: devicesList,
    );
  }

  /// Convert DeviceListConfig to JSON
  Map<String, dynamic> toJson() {
    return {
      'version': version,
      'default_connection_mode': defaultConnectionMode,
      'devices': devices.map((d) => d.toJson()).toList(),
    };
  }

  /// Create a copy with modified devices list
  DeviceListConfig copyWith({
    String? version,
    String? defaultConnectionMode,
    List<DeviceConfig>? devices,
  }) {
    return DeviceListConfig(
      version: version ?? this.version,
      defaultConnectionMode: defaultConnectionMode ?? this.defaultConnectionMode,
      devices: devices ?? this.devices,
    );
  }
}

/// Device list state management
class DeviceListModel extends ChangeNotifier {
  List<DeviceConfig> _allDevices = [];
  String _searchQuery = '';
  String _defaultConnectionMode = 'id';
  bool _isLoading = false;
  String? _errorMessage;

  // Getters
  List<DeviceConfig> get devices {
    if (_searchQuery.isEmpty) {
      return _allDevices;
    }
    return _allDevices.where((d) => d.matchesSearch(_searchQuery)).toList();
  }

  String get defaultConnectionMode => _defaultConnectionMode;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  int get totalDevices => _allDevices.length;
  int get filteredDevices => devices.length;

  /// Load device list from FFI
  Future<void> load() async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      // Call FFI to get device list
      final jsonStr = await _getDeviceListFromFFI();

      if (jsonStr.isEmpty || jsonStr == '{}') {
        _allDevices = [];
        _defaultConnectionMode = 'id';
      } else {
        final json = jsonDecode(jsonStr) as Map<String, dynamic>;
        final config = DeviceListConfig.fromJson(json);
        _allDevices = config.devices;
        _defaultConnectionMode = config.defaultConnectionMode;
      }

      _isLoading = false;
      notifyListeners();
    } catch (e) {
      _errorMessage = 'Failed to load device list: $e';
      _isLoading = false;
      notifyListeners();
      debugPrint(_errorMessage);
    }
  }

  /// Save device list via FFI
  Future<void> save() async {
    try {
      final config = DeviceListConfig(
        version: '1.0',
        defaultConnectionMode: _defaultConnectionMode,
        devices: _allDevices,
      );

      final jsonStr = jsonEncode(config.toJson());
      final result = await _saveDeviceListToFFI(jsonStr);

      if (result != 'OK') {
        throw Exception(result);
      }
    } catch (e) {
      _errorMessage = 'Failed to save device list: $e';
      notifyListeners();
      debugPrint(_errorMessage);
      rethrow;
    }
  }

  /// Update search query
  void updateSearch(String query) {
    _searchQuery = query;
    notifyListeners();
  }

  /// Clear search query
  void clearSearch() {
    _searchQuery = '';
    notifyListeners();
  }

  /// Add a new device
  Future<void> addDevice(DeviceConfig device) async {
    // Validate device
    final error = device.validate();
    if (error != null) {
      throw Exception(error);
    }

    // Check for duplicate name
    if (_allDevices.any((d) => d.name == device.name)) {
      throw Exception('Device with name "${device.name}" already exists');
    }

    // Encrypt password if needed
    DeviceConfig finalDevice = device;
    if (device.passwordNeedEncrypt && device.password.isNotEmpty) {
      final encryptedPassword = await bind.mainEncryptPassword(password: device.password);
      finalDevice = DeviceConfig(
        name: device.name,
        id: device.id,
        ip: device.ip,
        port: device.port,
        password: encryptedPassword,
        platform: device.platform,
        note: device.note,
        username: device.username,
        hostname: device.hostname,
        passwordNeedEncrypt: false, // Already encrypted
      );
    }

    _allDevices.add(finalDevice);
    await save();
    notifyListeners();
  }

  /// Update an existing device
  Future<void> updateDevice(String name, DeviceConfig newDevice) async {
    final index = _allDevices.indexWhere((d) => d.name == name);
    if (index == -1) {
      throw Exception('Device "$name" not found');
    }

    // Validate device
    final error = newDevice.validate();
    if (error != null) {
      throw Exception(error);
    }

    // Encrypt password if needed
    DeviceConfig finalDevice = newDevice;
    if (newDevice.passwordNeedEncrypt && newDevice.password.isNotEmpty) {
      final encryptedPassword = await bind.mainEncryptPassword(password: newDevice.password);
      finalDevice = DeviceConfig(
        name: newDevice.name,
        id: newDevice.id,
        ip: newDevice.ip,
        port: newDevice.port,
        password: encryptedPassword,
        platform: newDevice.platform,
        note: newDevice.note,
        username: newDevice.username,
        hostname: newDevice.hostname,
        passwordNeedEncrypt: false, // Already encrypted
      );
    }

    _allDevices[index] = finalDevice;
    await save();
    notifyListeners();
  }

  /// Remove a device by name
  Future<void> removeDevice(String name) async {
    final originalLength = _allDevices.length;
    _allDevices.removeWhere((d) => d.name == name);

    if (_allDevices.length < originalLength) {
      await save();
      notifyListeners();
    }
  }

  /// Connect to a device
  /// Requires a BuildContext to show dialogs and navigate
  Future<void> connectDevice(DeviceConfig device, BuildContext context) async {
    try {
      final (target, isIpConnection) = device.connectionTarget;

      debugPrint('Connecting to device: ${device.name}');
      debugPrint('Connection target: $target (IP: $isIpConnection)');
      debugPrint('Password available: ${device.password.isNotEmpty}');

      // For device management window, directly create new remote desktop window
      if (isDesktop) {
        await rustDeskWinManager.newRemoteDesktop(
          target,
          password: device.password.isNotEmpty ? device.password : null,
          isSharedPassword: device.password.isNotEmpty,
        );
      } else {
        // For mobile, use the standard connect function
        await connect(
          context,
          target,
          password: device.password.isNotEmpty ? device.password : null,
          isSharedPassword: device.password.isNotEmpty,
        );
      }
    } catch (e) {
      debugPrint('Failed to connect to device ${device.name}: $e');
      rethrow;
    }
  }

  // FFI interface methods
  Future<String> _getDeviceListFromFFI() async {
    return await bind.mainGetDeviceList();
  }

  Future<String> _saveDeviceListToFFI(String jsonStr) async {
    return await bind.mainSaveDeviceList(jsonStr: jsonStr);
  }
}
