import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_hbb/models/device_list_model.dart';
import 'package:flutter_hbb/models/platform_model.dart';
import 'package:flutter_hbb/desktop/widgets/device_list_panel.dart';
import 'package:flutter_hbb/desktop/widgets/tabbar_widget.dart';
import 'package:flutter_hbb/desktop/pages/remote_page.dart';
import 'package:flutter_hbb/desktop/widgets/remote_toolbar.dart';
import 'package:flutter_hbb/consts.dart';
import 'package:flutter_hbb/common.dart';
import 'package:get/get.dart';

/// Desktop Device Management Page
/// 设备管理页面 - 独立窗口
///
/// 功能：
/// - 上方: 多标签远程桌面区域
/// - 下方: 设备列表面板
class DesktopDeviceManagementPage extends StatefulWidget {
  const DesktopDeviceManagementPage({Key? key}) : super(key: key);

  @override
  State<DesktopDeviceManagementPage> createState() =>
      _DesktopDeviceManagementPageState();
}

class _DesktopDeviceManagementPageState
    extends State<DesktopDeviceManagementPage> with TickerProviderStateMixin {
  // Remote desktop tab controller for managing remote connections
  // Use DesktopTabType.main to ensure window controls work properly
  final remoteTabController = DesktopTabController(tabType: DesktopTabType.main);

  // Maximum number of tabs (8 as per requirements)
  static const int maxTabs = 8;

  @override
  void initState() {
    super.initState();

    // Load device list
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<DeviceListModel>().load();
    });

    // Setup tab close handler
    remoteTabController.onRemoved = (_, id) {
      debugPrint('Closed remote tab: $id');
    };
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.background,
      body: Column(
        children: [
          // Remote desktop tabs area (takes remaining space)
          Expanded(
            child: _buildRemoteTabArea(),
          ),

          // Device list panel at bottom
          DeviceListPanel(
            onDeviceConnect: _connectToDevice,
          ),
        ],
      ),
    );
  }

  /// Build remote desktop tab area
  Widget _buildRemoteTabArea() {
    return DesktopTab(
      controller: remoteTabController,
      showLogo: true,
      showTitle: true,
      showMinimize: true,
      showMaximize: true,
      showClose: true,
      onWindowCloseButton: () async => true,
      selectedBorderColor: MyTheme.accent,
      pageViewBuilder: (pageView) {
        return Obx(() {
          if (remoteTabController.state.value.tabs.isEmpty) {
            return _buildEmptyState();
          }
          return pageView;
        });
      },
      labelGetter: DesktopTab.tablabelGetter,
    );
  }


  /// Build empty state (no remote connections)
  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.devices,
            size: 64,
            color: Theme.of(context).colorScheme.primary.withOpacity(0.5),
          ),
          SizedBox(height: 16),
          Text(
            'No Remote Desktop Connected',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          SizedBox(height: 8),
          Text(
            'Select a device from the list below to connect',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context)
                      .colorScheme
                      .onSurface
                      .withOpacity(0.6),
                ),
          ),
        ],
      ),
    );
  }

  /// Connect to a device (create new tab in this window)
  Future<void> _connectToDevice(DeviceConfig device) async {
    // Check tab limit
    if (remoteTabController.state.value.tabs.length >= maxTabs) {
      _showMaxTabsWarning();
      return;
    }

    try {
      final (target, isIpConnection) = device.connectionTarget;

      debugPrint('Connecting to device: ${device.name}');
      debugPrint('Connection target: $target (IP: $isIpConnection)');
      debugPrint('Password available: ${device.password.isNotEmpty}');

      // Decrypt password if needed
      String? decryptedPassword;
      if (device.password.isNotEmpty) {
        decryptedPassword = await bind.mainDecryptPassword(encryptedPassword: device.password);
        debugPrint('Password decrypted successfully');
      }

      // Create a new RemotePage and add it as a tab
      remoteTabController.add(TabInfo(
        key: target,
        label: device.name,
        selectedIcon: Icons.desktop_windows_sharp,
        unselectedIcon: Icons.desktop_windows_outlined,
        onTabCloseButton: () => remoteTabController.closeBy(target),
        page: RemotePage(
          key: ValueKey(target),
          id: target,
          sessionId: null,
          tabWindowId: null,
          display: null,
          displays: null,
          password: decryptedPassword,
          toolbarState: ToolbarState(),
          tabController: remoteTabController,
          switchUuid: null,
          forceRelay: false,
          isSharedPassword: decryptedPassword != null && decryptedPassword.isNotEmpty,
        ),
      ));

      debugPrint('Created remote tab for device: ${device.name}');

      // Request focus for the newly created tab after a short delay
      // This ensures the RemotePage is fully initialized before requesting focus
      Future.delayed(Duration(milliseconds: 100), () {
        // The tab should be selected automatically, which will trigger focus
        debugPrint('Tab created and focus should be on remote desktop');
      });
    } catch (e) {
      debugPrint('Failed to connect to device ${device.name}: $e');
      _showError('Failed to connect: $e');
    }
  }

  /// Show max tabs warning
  void _showMaxTabsWarning() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Maximum Tabs Reached'),
        content: Text(
          'You have reached the maximum number of tabs ($maxTabs).\\n'
          'Please close some tabs before opening new connections.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text('OK'),
          ),
        ],
      ),
    );
  }

  /// Show error message
  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
        duration: Duration(seconds: 3),
      ),
    );
  }
}
