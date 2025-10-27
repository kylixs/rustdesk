import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/device_list_model.dart';
import 'dragable_divider.dart';
import 'device_edit_dialog.dart';

/// Device list panel widget for desktop
class DeviceListPanel extends StatefulWidget {
  /// Optional callback when device connect button is clicked
  /// If provided, this callback will be used instead of the default connection logic
  final Future<void> Function(DeviceConfig)? onDeviceConnect;

  const DeviceListPanel({
    Key? key,
    this.onDeviceConnect,
  }) : super(key: key);

  @override
  State<DeviceListPanel> createState() => _DeviceListPanelState();
}

class _DeviceListPanelState extends State<DeviceListPanel> {
  bool _expanded = true; // Default to expanded to show device list
  // Default height for content: 2 rows (36px each) = 72px when expanded
  // Total with header: 72 + 40 = 112px when expanded
  double _contentHeight = 72.0;
  final TextEditingController _searchController = TextEditingController();

  // Height constraints
  static const double minContentHeight = 0.0; // Collapsed: no content, only header
  static const double maxContentHeight = 360.0; // Max 10 rows
  static const double headerHeight = 40.0;
  static const double rowHeight = 36.0;

  @override
  void initState() {
    super.initState();
    // Load device list on initialization
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<DeviceListModel>().load();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FocusScope(
      // Separate focus scope for device list panel
      // This prevents focus from interfering with remote desktop
      canRequestFocus: _expanded,  // Only allow focus when expanded
      skipTraversal: true,  // Skip in focus traversal to avoid stealing focus
      child: Container(
        color: Theme.of(context).colorScheme.surface,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Draggable divider
            DraggableDivider(
              axis: Axis.horizontal,
              thickness: 2.0,
              onPointerMove: (delta) {
                setState(() {
                  _contentHeight = (_contentHeight - delta).clamp(minContentHeight, maxContentHeight);
                });
              },
            ),
            // Panel content with animation
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              height: _expanded ? (headerHeight + _contentHeight) : headerHeight,
              child: Column(
                children: [
                  _buildPanelHeader(),
                  if (_expanded) Expanded(child: _buildDeviceTable()),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Build panel header with search box and controls
  Widget _buildPanelHeader() {
    return Container(
      height: headerHeight,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.3),
        border: Border(
          bottom: BorderSide(
            color: Theme.of(context).dividerColor,
            width: 1,
          ),
        ),
      ),
      child: Row(
        children: [
          // Icon and title
          Icon(
            Icons.devices,
            size: 20,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(width: 8),
          Text(
            'Device List',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
          const SizedBox(width: 16),
          // Device count
          Consumer<DeviceListModel>(
            builder: (context, model, child) {
              if (model.totalDevices == 0) return const SizedBox.shrink();
              return Text(
                '(${model.filteredDevices}/${model.totalDevices})',
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                ),
              );
            },
          ),
          const SizedBox(width: 16),
          // Search box
          Expanded(
            child: SizedBox(
              height: 28,
              child: TextField(
                controller: _searchController,
                // Disable focus when panel is collapsed to allow keyboard input to remote desktop
                enabled: _expanded,
                autofocus: false,  // Never auto-focus to avoid stealing focus from remote desktop
                decoration: InputDecoration(
                  hintText: 'Search devices...',
                  hintStyle: TextStyle(fontSize: 12),
                  prefixIcon: Icon(Icons.search, size: 16),
                  suffixIcon: _searchController.text.isNotEmpty
                      ? IconButton(
                          icon: Icon(Icons.clear, size: 16),
                          padding: EdgeInsets.zero,
                          constraints: BoxConstraints(),
                          onPressed: () {
                            _searchController.clear();
                            context.read<DeviceListModel>().clearSearch();
                          },
                        )
                      : null,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(4),
                    borderSide: BorderSide(width: 1),
                  ),
                  contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  isDense: true,
                ),
                style: TextStyle(fontSize: 12),
                onChanged: (value) {
                  context.read<DeviceListModel>().updateSearch(value);
                },
              ),
            ),
          ),
          const SizedBox(width: 8),
          // Refresh button
          IconButton(
            icon: Icon(Icons.refresh, size: 18),
            tooltip: 'Refresh',
            padding: EdgeInsets.all(4),
            constraints: BoxConstraints(),
            onPressed: () {
              context.read<DeviceListModel>().load();
            },
          ),
          // Add button
          IconButton(
            icon: Icon(Icons.add, size: 18),
            tooltip: 'Add Device',
            padding: EdgeInsets.all(4),
            constraints: BoxConstraints(),
            onPressed: _showAddDeviceDialog,
          ),
          // Collapse/Expand button
          IconButton(
            icon: Icon(
              _expanded ? Icons.keyboard_arrow_down : Icons.keyboard_arrow_up,
              size: 18,
            ),
            tooltip: _expanded ? 'Collapse' : 'Expand',
            padding: EdgeInsets.all(4),
            constraints: BoxConstraints(),
            onPressed: () {
              setState(() {
                _expanded = !_expanded;
              });
            },
          ),
        ],
      ),
    );
  }

  /// Build device table
  Widget _buildDeviceTable() {
    return Consumer<DeviceListModel>(
      builder: (context, model, child) {
        if (model.isLoading) {
          return Center(
            child: CircularProgressIndicator(),
          );
        }

        if (model.errorMessage != null) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.error_outline, color: Colors.red, size: 32),
                SizedBox(height: 8),
                Text(
                  model.errorMessage!,
                  style: TextStyle(color: Colors.red),
                  textAlign: TextAlign.center,
                ),
                SizedBox(height: 8),
                ElevatedButton(
                  onPressed: () => model.load(),
                  child: Text('Retry'),
                ),
              ],
            ),
          );
        }

        if (model.devices.isEmpty) {
          return _buildEmptyState();
        }

        return _buildDeviceList(model.devices);
      },
    );
  }

  /// Build empty state
  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.devices_other,
            size: 48,
            color: Theme.of(context).colorScheme.onSurface.withOpacity(0.3),
          ),
          SizedBox(height: 8),
          Text(
            _searchController.text.isNotEmpty
                ? 'No devices match your search'
                : 'No devices found',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5),
            ),
          ),
          if (_searchController.text.isEmpty) ...[
            SizedBox(height: 8),
            Text(
              'Use --import-devices to add devices',
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.onSurface.withOpacity(0.4),
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// Build device list
  Widget _buildDeviceList(List<DeviceConfig> devices) {
    return Container(
      color: Theme.of(context).colorScheme.surface,
      child: ListView.builder(
        itemCount: devices.length,
        itemBuilder: (context, index) {
          return _buildDeviceRow(devices[index], index);
        },
      ),
    );
  }

  /// Build table header
  Widget _buildTableHeader() {
    return Container(
      height: 32,
      padding: EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.5),
        border: Border(
          bottom: BorderSide(
            color: Theme.of(context).dividerColor,
            width: 1,
          ),
        ),
      ),
      child: Row(
        children: [
          _buildHeaderCell('Name', flex: 2),
          _buildHeaderCell('IP/ID', flex: 2),
          _buildHeaderCell('Platform', flex: 1),
          _buildHeaderCell('Note', flex: 2),
          _buildHeaderCell('Actions', flex: 2),
        ],
      ),
    );
  }

  Widget _buildHeaderCell(String text, {int flex = 1}) {
    return Expanded(
      flex: flex,
      child: Text(
        text,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
        ),
      ),
    );
  }

  /// Build device row
  Widget _buildDeviceRow(DeviceConfig device, int index) {
    final backgroundColor = index.isEven
        ? Theme.of(context).colorScheme.surface
        : Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.2);

    return Container(
      height: 36,
      padding: EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: backgroundColor,
        border: Border(
          bottom: BorderSide(
            color: Theme.of(context).dividerColor.withOpacity(0.3),
            width: 0.5,
          ),
        ),
      ),
      child: Row(
        children: [
          // Name
          _buildCell(
            device.name,
            flex: 2,
            bold: true,
          ),
          // IP/ID
          _buildCell(
            device.displayTarget,
            flex: 2,
            mono: true,
          ),
          // Platform
          _buildCell(
            device.platform,
            flex: 1,
            icon: _getPlatformIcon(device.platform),
          ),
          // Note
          _buildCell(
            device.note,
            flex: 2,
            tooltip: device.note,
          ),
          // Actions - Connect, Edit, Delete buttons
          Expanded(
            flex: 2,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SizedBox(
                  height: 24,
                  child: ElevatedButton(
                    onPressed: () => _connectToDevice(device),
                    style: ElevatedButton.styleFrom(
                      padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      minimumSize: Size(50, 24),
                      backgroundColor: Theme.of(context).colorScheme.primary,
                      foregroundColor: Theme.of(context).colorScheme.onPrimary,
                    ),
                    child: Text(
                      'Connect',
                      style: TextStyle(fontSize: 10),
                    ),
                  ),
                ),
                SizedBox(width: 4),
                IconButton(
                  icon: Icon(Icons.edit, size: 16),
                  tooltip: 'Edit',
                  padding: EdgeInsets.all(4),
                  constraints: BoxConstraints(),
                  onPressed: () => _showEditDeviceDialog(device),
                ),
                IconButton(
                  icon: Icon(Icons.delete, size: 16),
                  tooltip: 'Delete',
                  padding: EdgeInsets.all(4),
                  constraints: BoxConstraints(),
                  onPressed: () => _confirmDeleteDevice(device),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCell(
    String text, {
    int flex = 1,
    bool bold = false,
    bool mono = false,
    IconData? icon,
    String? tooltip,
  }) {
    Widget content = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[
          Icon(icon, size: 14, color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6)),
          SizedBox(width: 4),
        ],
        Flexible(
          child: Text(
            text,
            style: TextStyle(
              fontSize: 12,
              fontWeight: bold ? FontWeight.w600 : FontWeight.normal,
              fontFamily: mono ? 'monospace' : null,
              color: Theme.of(context).colorScheme.onSurface,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );

    if (tooltip != null && tooltip.isNotEmpty) {
      content = Tooltip(
        message: tooltip,
        child: content,
      );
    }

    return Expanded(
      flex: flex,
      child: content,
    );
  }

  IconData? _getPlatformIcon(String platform) {
    switch (platform.toLowerCase()) {
      case 'windows':
        return Icons.computer;
      case 'linux':
        return Icons.dns;
      case 'macos':
        return Icons.laptop_mac;
      default:
        return null;
    }
  }

  /// Connect to device
  void _connectToDevice(DeviceConfig device) async {
    try {
      // Use custom callback if provided, otherwise use default connection logic
      if (widget.onDeviceConnect != null) {
        await widget.onDeviceConnect!(device);
      } else {
        await context.read<DeviceListModel>().connectDevice(device, context);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Connecting to ${device.name}...'),
              duration: Duration(seconds: 2),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to connect: $e'),
            backgroundColor: Colors.red,
            duration: Duration(seconds: 3),
          ),
        );
      }
    }
  }

  /// Show add device dialog
  void _showAddDeviceDialog() async {
    final model = context.read<DeviceListModel>();
    final existingNames = model.devices.map((d) => d.name).toList();

    final device = await showDialog<DeviceConfig>(
      context: context,
      builder: (context) => DeviceEditDialog(
        existingNames: existingNames,
      ),
    );

    if (device != null && mounted) {
      try {
        await model.addDevice(device);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Device "${device.name}" added successfully'),
              backgroundColor: Colors.green,
              duration: Duration(seconds: 2),
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Failed to add device: $e'),
              backgroundColor: Colors.red,
              duration: Duration(seconds: 3),
            ),
          );
        }
      }
    }
  }

  /// Show edit device dialog
  void _showEditDeviceDialog(DeviceConfig device) async {
    final model = context.read<DeviceListModel>();
    final existingNames = model.devices
        .where((d) => d.name != device.name) // Exclude current device
        .map((d) => d.name)
        .toList();

    final editedDevice = await showDialog<DeviceConfig>(
      context: context,
      builder: (context) => DeviceEditDialog(
        device: device,
        existingNames: existingNames,
      ),
    );

    if (editedDevice != null && mounted) {
      try {
        await model.updateDevice(device.name, editedDevice);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Device "${editedDevice.name}" updated successfully'),
              backgroundColor: Colors.green,
              duration: Duration(seconds: 2),
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Failed to update device: $e'),
              backgroundColor: Colors.red,
              duration: Duration(seconds: 3),
            ),
          );
        }
      }
    }
  }

  /// Confirm and delete device
  void _confirmDeleteDevice(DeviceConfig device) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete Device'),
        content: Text(
          'Are you sure you want to delete "${device.name}"?\n\n'
          'This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      try {
        await context.read<DeviceListModel>().removeDevice(device.name);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Device "${device.name}" deleted successfully'),
              backgroundColor: Colors.orange,
              duration: Duration(seconds: 2),
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Failed to delete device: $e'),
              backgroundColor: Colors.red,
              duration: Duration(seconds: 3),
            ),
          );
        }
      }
    }
  }
}
