/// Command-line help system for RustDesk
///
/// This module provides comprehensive help information for all RustDesk CLI commands.
/// It supports both primary help (overview of all commands) and secondary help
/// (detailed information for specific commands).

/// Print comprehensive help information for RustDesk command-line interface
pub fn print_help() {
    println!(r#"RustDesk - Remote Desktop Software
Version: {}
Build Date: {}

USAGE:
    rustdesk [OPTIONS] [COMMAND]

GUI MODE:
    --gui                  Start graphical user interface

INFORMATION COMMANDS:
    --version              Display version information
    --build-date           Display build date
    --get-id               Display this device's ID

SERVICE MANAGEMENT:
    --install-service      Install RustDesk as a system service
    --uninstall-service    Uninstall RustDesk system service
    --start-service        Start RustDesk service
    --stop-service         Stop RustDesk service
    --status               Display RustDesk service status
    --service              Run as system service (internal use)
    --server               Run server mode with tray icon
    --tray                 Run system tray only

CONFIGURATION:
    --password <PASSWORD>           Set permanent password (requires root/admin)
    --set-unlock-pin <PIN>          Set unlock PIN (requires root/admin)
    --set-id <ID>                   Set custom device ID (requires root/admin)
    --config <ENCRYPTED_STRING>     Import server config from encrypted string
    --import-config <PATH>          Import configuration from file
    --option [KEY] [VALUE]          Get or set configuration option
                                    Usage: --option <key>         (get value)
                                           --option <key> <value> (set value)
    --list-options                  List all configuration options and their values

CONNECTION:
    --connect <ID>                  Connect to remote device
    --play <ID>                     Play session recording
    --file-transfer <ID>            Start file transfer session
    --port-forward <ID>             Start port forwarding session
    --rdp <ID>                      Start RDP session
    --cm                            Start connection manager with UI
    --cm-no-ui                      Start connection manager without UI
    --whiteboard                    Start whiteboard session

DEVICE MANAGEMENT:
    --assign --token <TOKEN> [OPTIONS]   Assign device to account/group

PLATFORM-SPECIFIC (Windows):
    --install                      Install RustDesk
    --uninstall                    Uninstall RustDesk
    --silent-install               Install silently with default options
    --update                       Update to latest version
    --install-idd                  Install virtual display driver
    --uninstall-amyuni-idd         Uninstall Amyuni virtual display driver
    --install-remote-printer       Install remote printer (Win10+)
    --uninstall-remote-printer     Uninstall remote printer
    --uninstall-cert               Uninstall certificates

PORTABLE PACKER (rustdesk-portable-packer.exe):
    --verify                       Verify extracted files integrity
                                   Optional: --quick (skip MD5 check)
    -v, --verbose                  Enable debug logging
    -vv                            Enable trace logging (more verbose)

PLUGIN MANAGEMENT (if enabled):
    --plugin-install <ID> [URL]    Install plugin by ID or URL
    --plugin-uninstall <ID>        Uninstall plugin by ID

OTHER:
    --no-server                    Start without server functionality
    --check-hwcodec-config         Check hardware codec configuration

EXAMPLES:
    # View help for a specific command
    rustdesk --help --option

    # Set permanent password
    sudo rustdesk --password MySecurePassword

    # Configure custom server
    sudo rustdesk --option custom-rendezvous-server rd-server.example.com

    # Get current server configuration
    rustdesk --option custom-rendezvous-server

    # List all configuration options
    rustdesk --list-options

    # Connect to remote device
    rustdesk --connect 123456789

    # Assign device to account
    rustdesk --assign --token abc123 --user_name john@example.com

For more information, visit: https://rustdesk.com/docs
"#, crate::VERSION, crate::BUILD_DATE);
}

/// Print help information for specific commands
pub fn print_specific_help(command: &str) {
    // Strip leading -- prefix if present to support both formats
    let cmd = command.strip_prefix("--").unwrap_or(command);

    match cmd {
        // Information commands
        "get-id" => print_get_id_help(),
        "version" => print_version_help(),
        "build-date" => print_build_date_help(),

        // Configuration commands
        "password" => print_password_help(),
        "set-unlock-pin" => print_set_unlock_pin_help(),
        "set-id" => print_set_id_help(),
        "option" => print_option_help(),
        "list-options" => print_list_options_help(),
        "config" | "import-config" => print_config_help(),

        // Connection commands
        "connect" => print_connect_help(),
        "file-transfer" => print_file_transfer_help(),
        "port-forward" => print_port_forward_help(),
        "rdp" => print_rdp_help(),
        "play" => print_play_help(),

        // UI mode commands
        "gui" => print_gui_help(),
        "server" => print_server_help(),
        "tray" => print_tray_help(),
        "cm" | "cm-no-ui" => print_cm_help(),
        "whiteboard" => print_whiteboard_help(),

        // Service management
        "service" | "install-service" | "uninstall-service" | "start-service" | "stop-service" | "status" => print_service_help(),

        // Device management
        "assign" => print_assign_help(),

        // Windows-specific
        "install" | "uninstall" | "silent-install" => print_install_help(),

        _ => {
            println!("Unknown command: {}", command);
            println!("Run 'rustdesk --help' for list of available commands.");
        }
    }
}

/// Print help for --password command
fn print_password_help() {
    println!(r#"Set permanent password for unattended access

USAGE:
    sudo rustdesk --password <PASSWORD>

DESCRIPTION:
    Sets a permanent password for remote access. This password persists
    across restarts and allows unattended access to this device.

REQUIREMENTS:
    - RustDesk must be installed (not portable mode)
    - Requires administrative/root privileges

EXAMPLES:
    # Set permanent password
    sudo rustdesk --password MySecurePassword123

    # On Windows (run as Administrator)
    rustdesk.exe --password MySecurePassword123

NOTES:
    - Password is encrypted and stored securely
    - Used for unattended access mode
    - Can be combined with other security options

SEE ALSO:
    --set-unlock-pin    Set unlock PIN for additional security
    --option            Configure other security settings
"#);
}

/// Print help for --option command
fn print_option_help() {
    println!(r#"Get or set configuration options

USAGE:
    rustdesk --option <KEY>              # Get value
    sudo rustdesk --option <KEY> <VALUE> # Set value

DESCRIPTION:
    Manage RustDesk configuration options. Reading options doesn't require
    privileges, but setting options requires administrative/root access.

AVAILABLE OPTIONS:

SERVER CONFIGURATION:
    custom-rendezvous-server <SERVER>    Custom ID/relay server address
    api-server <URL>                     API server URL
    relay-server <SERVER>                Relay server address
    key <PUBLIC_KEY>                     Server public key
    direct-server <Y/N>                  Enable direct IP access mode
    direct-access-port <PORT>            Direct access port number
    allow-websocket <Y/N>                Enable WebSocket connections
    allow-https-21114 <Y/N>              Allow HTTPS on port 21114
    disable-udp <Y/N>                    Disable UDP protocol

SECURITY & ACCESS CONTROL:
    approve-mode <click/password>        Approval mode for incoming connections
    verification-method <METHOD>         Verification method (use-permanent-password, etc.)
    allow-logon-screen-password <Y/N>    Allow password access on login screen
    temporary-password-length <NUM>      Length of temporary password (6-16)
    whitelist <IDS>                      Comma-separated whitelist of allowed IDs
    enable-lan-discovery <Y/N>           Enable LAN device discovery
    enable-trusted-devices <Y/N>         Enable trusted devices feature
    register-device <Y/N>                Allow device registration

SESSION MANAGEMENT:
    allow-auto-disconnect <Y/N>          Enable auto-disconnect for inactive sessions
    auto-disconnect-timeout <MINUTES>    Timeout in minutes for inactive sessions
    allow-only-conn-window-open <Y/N>    Only one connection window at a time
    allow-auto-record-incoming <Y/N>     Auto-record incoming sessions
    allow-auto-record-outgoing <Y/N>     Auto-record outgoing sessions
    video-save-directory <PATH>          Directory for session recordings

FEATURES & PERMISSIONS:
    enable-keyboard <Y/N>                Enable keyboard control
    enable-clipboard <Y/N>               Enable clipboard synchronization
    enable-file-transfer <Y/N>           Enable file transfer
    enable-camera <Y/N>                  Enable camera access
    enable-terminal <Y/N>                Enable terminal access
    terminal-persistent <Y/N>            Keep terminal sessions persistent
    enable-audio <Y/N>                   Enable audio streaming
    enable-tunnel <Y/N>                  Enable port forwarding tunnel
    enable-remote-restart <Y/N>          Enable remote system restart
    enable-record-session <Y/N>          Enable session recording feature
    enable-block-input <Y/N>             Enable input blocking feature
    allow-remote-config-modification <Y/N> Allow remote configuration changes

DISPLAY & RENDERING:
    enable-hwcodec <Y/N>                 Enable hardware codec
    enable-abr <Y/N>                     Enable adaptive bitrate
    allow-remove-wallpaper <Y/N>         Allow wallpaper removal during session
    allow-always-software-render <Y/N>   Force software rendering
    allow-linux-headless <Y/N>           Enable Linux headless mode
    enable-directx-capture <Y/N>         Enable DirectX capture (Windows)
    use-texture-render <Y/N>             Use texture rendering
    allow-d3d-render <Y/N>               Allow Direct3D rendering
    show-virtual-mouse <Y/N>             Show virtual mouse cursor
    show-virtual-joystick <Y/N>          Show virtual joystick (mobile)
    trackpad-speed <NUM>                 Trackpad sensitivity speed

UPDATE & SYNC:
    enable-check-update <Y/N>            Check for updates on startup
    allow-auto-update <Y/N>              Enable automatic updates
    sync-ab-with-recent-sessions <Y/N>   Sync address book with recent sessions
    sync-ab-tags <Y/N>                   Sync address book tags
    filter-ab-by-intersection <Y/N>      Filter address book by intersection

NETWORK:
    enable-udp-punch <Y/N>               Enable UDP hole punching
    enable-ipv6-punch <Y/N>              Enable IPv6 hole punching

UI CUSTOMIZATION:
    hide-tray <Y/N>                      Hide system tray icon
    hide-security-settings <Y/N>         Hide security settings in UI
    hide-network-settings <Y/N>          Hide network settings in UI
    hide-server-settings <Y/N>           Hide server settings in UI
    hide-proxy-settings <Y/N>            Hide proxy settings in UI
    hide-remote-printer-settings <Y/N>   Hide remote printer settings in UI
    hide-websocket-settings <Y/N>        Hide WebSocket settings in UI
    hide-username-on-card <Y/N>          Hide username on connection card
    hide-help-cards <Y/N>                Hide help cards in UI
    hide-powered-by-me <Y/N>             Hide "Powered by" branding
    main-window-always-on-top <Y/N>      Keep main window always on top

ADVANCED:
    access-mode <custom/full>            Access mode configuration
    one-way-clipboard-redirection <Y/N>  One-way clipboard sync
    one-way-file-transfer <Y/N>          One-way file transfer
    default-connect-password <PASSWORD>  Default connection password
    allow-hostname-as-id <Y/N>           Allow hostname as device ID
    allow-numeric-one-time-password <Y/N> Allow numeric OTP

PRESET (FOR DEPLOYMENT):
    preset-address-book-name <NAME>      Preset address book name
    preset-address-book-tag <TAG>        Preset address book tag
    preset-address-book-alias <ALIAS>    Preset address book alias
    preset-address-book-password <PWD>   Preset address book password
    preset-address-book-note <NOTE>      Preset address book note
    preset-device-username <USERNAME>    Preset device username
    preset-device-name <NAME>            Preset device name
    preset-note <TEXT>                   Preset device note
    preset-device-group-name <NAME>      Preset device group name
    preset-user-name <NAME>              Preset user account name
    preset-strategy-name <NAME>          Preset strategy name

EXAMPLES:
    # Configure custom server
    sudo rustdesk --option custom-rendezvous-server rd-server.example.com
    sudo rustdesk --option api-server https://rd-server.example.com
    sudo rustdesk --option relay-server rd-server.example.com

    # Get current server configuration
    rustdesk --option custom-rendezvous-server

    # Configure unattended access mode
    sudo rustdesk --option approve-mode password
    sudo rustdesk --option verification-method use-permanent-password

    # Enable auto-disconnect for inactive sessions
    sudo rustdesk --option allow-auto-disconnect Y
    sudo rustdesk --option auto-disconnect-timeout 15

    # Security settings
    sudo rustdesk --option allow-logon-screen-password Y
    sudo rustdesk --option enable-trusted-devices Y

    # Disable certain features
    sudo rustdesk --option enable-file-transfer N
    sudo rustdesk --option enable-clipboard N

REQUIREMENTS:
    - Setting options requires installation and root/admin privileges
    - Getting options can be done by any user

SERVER CONFIGURATION PRIORITY:
    1. EXE_RENDEZVOUS_SERVER (compiled into binary)
    2. custom-rendezvous-server (this option)
    3. PROD_RENDEZVOUS_SERVER (runtime setting)
    4. CONFIG2.rendezvous_server (config file)
    5. RENDEZVOUS_SERVERS (hardcoded default)

NOTES:
    - Changes take effect immediately
    - Some options may require service restart
    - Options are stored in configuration files
    - Boolean options accept Y/N or true/false

SEE ALSO:
    --config            Import config from encrypted string
    --import-config     Import config from file
    --list-options      List all current option values
"#);
}

/// Print help for --list-options command
fn print_list_options_help() {
    println!(r#"List all configuration options and their values

USAGE:
    rustdesk --list-options

DESCRIPTION:
    Display all current configuration options and their values in a formatted
    table. This command does not require administrative privileges and is
    useful for inspecting the current configuration state.

EXAMPLES:
    # List all options
    rustdesk --list-options

    # Save options to a file
    rustdesk --list-options > options.txt

    # Search for specific options
    rustdesk --list-options | grep server

OUTPUT FORMAT:
    RustDesk Configuration Options:
    ============================================================
    custom-rendezvous-server       = rd-server.example.com
    api-server                     = https://rd-server.example.com
    relay-server                   = rd-server.example.com
    allow-hide-cm                  = Y
    ...
    ============================================================
    Total: N options

COMMON OPTIONS YOU MIGHT SEE:
    custom-rendezvous-server       Custom ID/relay server address
    api-server                     API server URL
    relay-server                   Relay server address
    key                            Server public key
    approve-mode                   Approval mode (click/password)
    verification-method            Verification method
    allow-hide-cm                  Allow hiding connection manager
    allow-logon-screen-password    Allow login screen password

NOTES:
    - Empty values are shown as "(empty)"
    - Options are sorted alphabetically
    - This command shows effective configuration (merged from all sources)
    - Does not require root/admin privileges

SEE ALSO:
    --option            Get or set individual options
    --config            Import config from encrypted string
    --import-config     Import config from file
"#);
}

/// Print help for --set-id command
fn print_set_id_help() {
    println!(r#"Set custom device ID

USAGE:
    sudo rustdesk --set-id <ID>

DESCRIPTION:
    Changes this device's RustDesk ID to a custom value. The ID must be
    numeric and within valid range.

REQUIREMENTS:
    - RustDesk must be installed
    - Requires administrative/root privileges

EXAMPLES:
    # Set custom ID
    sudo rustdesk --set-id 987654321

NOTES:
    - ID must be numeric
    - Changing ID will affect existing connections
    - Remote peers will need to use the new ID to connect

SEE ALSO:
    --get-id    Display current device ID
"#);
}

/// Print help for --assign command
fn print_assign_help() {
    println!(r#"Assign device to account or group

USAGE:
    rustdesk --assign --token <TOKEN> [OPTIONS]

DESCRIPTION:
    Register this device with a RustDesk Pro account or assign it to
    groups and address books.

REQUIRED:
    --token <TOKEN>                Bearer token for authentication

OPTIONAL PARAMETERS:
    --user_name <NAME>             Assign to user account
    --strategy_name <NAME>         Apply strategy policy
    --address_book_name <NAME>     Add to address book
    --address_book_tag <TAG>       Tag in address book
    --address_book_alias <ALIAS>   Alias in address book
    --address_book_password <PWD>  Password for address book entry
    --address_book_note <NOTE>     Note for address book entry
    --device_group_name <NAME>     Add to device group
    --note <TEXT>                  Device note
    --device_username <NAME>       Device username
    --device_name <NAME>           Device display name

REQUIREMENTS:
    - RustDesk must be installed
    - Requires administrative/root privileges
    - Valid API token from RustDesk Pro account

EXAMPLES:
    # Assign to user account
    sudo rustdesk --assign --token abc123xyz --user_name admin@company.com

    # Add to address book and device group
    sudo rustdesk --assign --token abc123xyz \
        --address_book_name "IT Department" \
        --device_group_name "Servers" \
        --device_name "Production Server 1"

    # Full configuration
    sudo rustdesk --assign --token abc123xyz \
        --user_name admin@company.com \
        --address_book_name "IT Servers" \
        --address_book_alias "prod-server-1" \
        --device_group_name "Production" \
        --note "Primary application server"

NOTES:
    - At least one optional parameter is required
    - Changes are synchronized with API server
    - Device must be registrable (check with --get-id)
"#);
}

/// Print help for --connect command
fn print_connect_help() {
    println!(r#"Connect to remote device

USAGE:
    rustdesk --connect <ID> [OPTIONS]

DESCRIPTION:
    Initiate a remote desktop connection to another device.

OPTIONS:
    --password <PASSWORD>    Provide password for connection
    --relay                  Force connection through relay server

EXAMPLES:
    # Simple connection
    rustdesk --connect 123456789

    # Connection with password
    rustdesk --connect 123456789 --password MyPassword

    # Force relay connection
    rustdesk --connect 123456789 --relay

NOTES:
    - ID can be obtained from remote device using --get-id
    - Password is optional if not required by remote device
    - Relay mode may be slower but works through firewalls

SEE ALSO:
    --file-transfer    Start file transfer session
    --port-forward     Start port forwarding session
"#);
}

/// Print help for service management commands
fn print_service_help() {
    println!(r#"Service management commands

USAGE:
    rustdesk --install-service      Install as system service
    rustdesk --uninstall-service    Remove system service
    rustdesk --start-service        Start the service
    rustdesk --stop-service         Stop the service
    rustdesk --status               Display service status
    rustdesk --service              Run as service (internal use)

DESCRIPTION:
    Manage RustDesk as a system service for automatic startup and
    background operation.

INSTALL/UNINSTALL/START/STOP SERVICE:
    On Linux/macOS: MUST run with sudo or as root
    sudo rustdesk --install-service
    sudo rustdesk --uninstall-service

    On Windows    : MUST run as Administrator
    rustdesk-portable.exe --install-service
    "C:\Program Files\RustDesk\RustDesk.exe" --stop-service

CHECK SERVICE STATUS:
    rustdesk --status [--json]

    Comprehensive status check including:
    - Service status (running, PID, uptime, autostart)
    - Configuration validation (unattended mode settings)
    - Network status (rendezvous server, NAT type, IPs)
    - Device information (ID, UUID, active connections)
    - Issue detection and recommendations

    Use --json flag for machine-readable JSON output

REQUIREMENTS:
    - Administrative/root privileges required for install/uninstall
    - RustDesk must be installed (not portable mode)
    - Status command does not require admin privileges

NOTES:
    - Service runs automatically on system startup
    - Required for unattended access
    - Service runs in background without UI
    - Use --server for foreground mode with tray icon

EXAMPLES:
    # Install and check status
    sudo rustdesk --install-service
    rustdesk --status

    # Check status in JSON format (for monitoring)
    rustdesk --status --json

    # Check status before uninstalling
    rustdesk --status
    sudo rustdesk --uninstall-service

    # Use in monitoring scripts
    rustdesk --status --json | jq '.status'

SEE ALSO:
    --server    Run in foreground with tray icon
"#);
}

/// Print help for configuration import commands
fn print_config_help() {
    println!(r#"Configuration import commands

USAGE:
    rustdesk --config <ENCRYPTED_STRING>
    rustdesk --import-config <FILE_PATH>

DESCRIPTION:
    Import server configuration from encrypted strings or files.

--config:
    Import configuration from encrypted string (often embedded in
    custom-named executables for easy deployment).

--import-config:
    Import configuration from TOML file(s). Looks for both <file>.toml
    and <file>2.toml for Config and Config2 structures.

REQUIREMENTS:
    - RustDesk must be installed
    - Requires administrative/root privileges

EXAMPLES:
    # Import from encrypted string
    sudo rustdesk --config "encrypted_config_string_here"

    # Import from file
    sudo rustdesk --import-config /path/to/config.toml

NOTES:
    - Encrypted strings are usually generated during custom builds
    - Config files use TOML format
    - Changes take effect immediately

SEE ALSO:
    --option    Set individual configuration options
"#);
}

// ============================================================================
// INFORMATION COMMANDS
// ============================================================================

/// Print help for --get-id command
fn print_get_id_help() {
    println!(r#"Display this device's ID

USAGE:
    rustdesk --get-id

DESCRIPTION:
    Displays the unique ID of this RustDesk device. This ID is used by
    remote users to connect to this device.

EXAMPLES:
    # Get this device's ID
    rustdesk --get-id

OUTPUT:
    123456789

NOTES:
    - The ID is generated automatically on first run
    - ID can be customized using --set-id (requires admin privileges)
    - Other users need this ID to connect to your device
    - Does not require administrative privileges

SEE ALSO:
    --set-id    Set custom device ID
"#);
}

/// Print help for --version command
fn print_version_help() {
    println!(r#"Display version information

USAGE:
    rustdesk --version

DESCRIPTION:
    Displays the RustDesk version number.

EXAMPLES:
    # Show version
    rustdesk --version

OUTPUT:
    1.4.3

SEE ALSO:
    --build-date    Show build date
"#);
}

/// Print help for --build-date command
fn print_build_date_help() {
    println!(r#"Display build date

USAGE:
    rustdesk --build-date

DESCRIPTION:
    Displays when this RustDesk binary was built.

EXAMPLES:
    # Show build date
    rustdesk --build-date

SEE ALSO:
    --version    Show version number
"#);
}

/// Print help for --set-unlock-pin command
fn print_set_unlock_pin_help() {
    println!(r#"Set unlock PIN for additional security

USAGE:
    sudo rustdesk --set-unlock-pin <PIN>

DESCRIPTION:
    Sets a PIN code required to unlock RustDesk settings on this device.
    This provides an additional layer of security to prevent unauthorized
    configuration changes.

REQUIREMENTS:
    - RustDesk must be installed (not portable mode)
    - Requires administrative/root privileges

EXAMPLES:
    # Set unlock PIN
    sudo rustdesk --set-unlock-pin 1234

    # On Windows (run as Administrator)
    rustdesk.exe --set-unlock-pin 1234

NOTES:
    - PIN should be numeric
    - PIN is stored securely
    - Required to access settings UI after being set
    - Different from connection password

SEE ALSO:
    --password    Set permanent connection password
"#);
}

// ============================================================================
// CONNECTION COMMANDS
// ============================================================================

/// Print help for --file-transfer command
fn print_file_transfer_help() {
    println!(r#"Start file transfer session

USAGE:
    rustdesk --file-transfer <ID> [OPTIONS]

DESCRIPTION:
    Initiate a file transfer session with a remote device. Opens a
    dedicated file manager interface for transferring files between
    local and remote systems.

OPTIONS:
    --password <PASSWORD>    Provide password for connection

EXAMPLES:
    # Start file transfer session
    rustdesk --file-transfer 123456789

    # With password
    rustdesk --file-transfer 123456789 --password MyPassword

FEATURES:
    - Browse remote filesystem
    - Upload/download files and folders
    - Multi-file selection support
    - Progress tracking
    - Resume capability for interrupted transfers

NOTES:
    - File transfer must be enabled on remote device
    - Large file transfers may take time depending on network speed
    - Transfers use secure encrypted connection

SEE ALSO:
    --connect       Standard remote desktop connection
    --port-forward  Port forwarding session
"#);
}

/// Print help for --port-forward command
fn print_port_forward_help() {
    println!(r#"Start port forwarding session

USAGE:
    rustdesk --port-forward <ID>

DESCRIPTION:
    Initiate a port forwarding/tunnel session with a remote device.
    Allows you to access remote network services through the RustDesk
    connection.

EXAMPLES:
    # Start port forwarding session
    rustdesk --port-forward 123456789

USE CASES:
    - Access remote database servers
    - Connect to remote web services
    - Tunnel through firewalls
    - Access services on remote network

NOTES:
    - Port forwarding must be enabled on remote device
    - Configure port mappings in the UI after connection
    - All traffic is encrypted through RustDesk tunnel

SEE ALSO:
    --connect       Standard remote desktop connection
    --file-transfer File transfer session
"#);
}

/// Print help for --rdp command
fn print_rdp_help() {
    println!(r#"Start RDP session

USAGE:
    rustdesk --rdp <ID>

DESCRIPTION:
    Initiate a Remote Desktop Protocol (RDP) session through RustDesk
    to a Windows remote device.

EXAMPLES:
    # Start RDP session
    rustdesk --rdp 123456789

REQUIREMENTS:
    - Remote device must be Windows with RDP enabled
    - RustDesk must be configured to allow RDP
    - Appropriate firewall rules on remote device

NOTES:
    - Uses native Windows RDP protocol
    - May provide better performance for Windows-to-Windows connections
    - Requires RDP to be enabled on remote Windows system

SEE ALSO:
    --connect    Standard RustDesk remote desktop connection
"#);
}

/// Print help for --play command
fn print_play_help() {
    println!(r#"Play session recording

USAGE:
    rustdesk --play <ID_OR_PATH>

DESCRIPTION:
    Play back a recorded RustDesk session. Can play recordings from
    either a remote device ID or a local file path.

EXAMPLES:
    # Play remote device's recordings
    rustdesk --play 123456789

    # Play local recording file
    rustdesk --play /path/to/recording.rdp

FEATURES:
    - Play/pause controls
    - Seek through recording
    - View recorded sessions for review or training

NOTES:
    - Session recording must be enabled for sessions to be recorded
    - Recordings are stored locally on the device that recorded them
    - File format is RustDesk-specific

SEE ALSO:
    --option allow-auto-record-incoming Y    Enable incoming session recording
    --option allow-auto-record-outgoing Y    Enable outgoing session recording
"#);
}

// ============================================================================
// UI MODE COMMANDS
// ============================================================================

/// Print help for --gui command
fn print_gui_help() {
    println!(r#"Start graphical user interface

USAGE:
    rustdesk --gui

DESCRIPTION:
    Start RustDesk with the graphical user interface (GUI). This is
    the default mode when RustDesk is launched without arguments in
    a desktop environment.

EXAMPLES:
    # Start GUI
    rustdesk --gui

NOTES:
    - Opens the main RustDesk window
    - Shows ID, connection history, and settings
    - Allows initiating outgoing connections
    - Default mode for desktop use

SEE ALSO:
    --server    Run in server mode with tray icon
    --tray      Run tray icon only
"#);
}

/// Print help for --server command
fn print_server_help() {
    println!(r#"Run server mode with tray icon

USAGE:
    rustdesk --server

DESCRIPTION:
    Run RustDesk in server/daemon mode with a system tray icon.
    Allows incoming connections and provides tray access to settings
    and status.

EXAMPLES:
    # Start server mode
    rustdesk --server

FEATURES:
    - Accept incoming connections
    - System tray icon for quick access
    - Background operation
    - Can run alongside other RustDesk instances

NOTES:
    - Does not open main window by default
    - Click tray icon to access main window
    - Suitable for unattended access scenarios
    - Runs in foreground (not as system service)

SEE ALSO:
    --install-service    Install as system service
    --tray              Tray icon only (no server)
"#);
}

/// Print help for --tray command
fn print_tray_help() {
    println!(r#"Run system tray only

USAGE:
    rustdesk --tray

DESCRIPTION:
    Run only the system tray icon without server functionality.
    Provides quick access to RustDesk features through the tray.

EXAMPLES:
    # Start tray only
    rustdesk --tray

NOTES:
    - Tray icon provides access to main window
    - Does not accept incoming connections by itself
    - Lightweight option for occasional use
    - Requires service or server mode for incoming connections

SEE ALSO:
    --server    Run server with tray
    --gui       Start main window
"#);
}

/// Print help for --cm command
fn print_cm_help() {
    println!(r#"Start connection manager

USAGE:
    rustdesk --cm          # With UI
    rustdesk --cm-no-ui    # Without UI

DESCRIPTION:
    Start the RustDesk connection manager for managing multiple
    simultaneous connections and address book.

OPTIONS:
    --cm         Start with graphical interface
    --cm-no-ui   Start without UI (background mode)

EXAMPLES:
    # Start connection manager with UI
    rustdesk --cm

    # Start in background
    rustdesk --cm-no-ui

FEATURES:
    - Manage multiple connections
    - Address book integration
    - Connection history
    - Bulk operations
    - Group management

NOTES:
    - Useful for IT administrators
    - Can manage connections to multiple devices
    - Integrates with RustDesk Pro features

SEE ALSO:
    --gui    Standard GUI mode
"#);
}

/// Print help for --whiteboard command
fn print_whiteboard_help() {
    println!(r#"Start whiteboard session

USAGE:
    rustdesk --whiteboard

DESCRIPTION:
    Start a collaborative whiteboard session for real-time drawing
    and annotation with remote participants.

EXAMPLES:
    # Start whiteboard
    rustdesk --whiteboard

FEATURES:
    - Real-time collaborative drawing
    - Multiple drawing tools
    - Text annotation
    - Shape tools
    - Color selection

NOTES:
    - Requires network connectivity
    - Can be used for presentations and collaboration
    - All participants can draw simultaneously

SEE ALSO:
    --connect    Remote desktop connection
"#);
}

// ============================================================================
// WINDOWS-SPECIFIC COMMANDS
// ============================================================================

/// Print help for Windows install/uninstall commands
fn print_install_help() {
    println!(r#"Windows installation commands

USAGE:
    rustdesk --install
    rustdesk --uninstall
    rustdesk --silent-install

DESCRIPTION:
    Install, uninstall, or silently install RustDesk on Windows.

--install:
    Interactive installation wizard. Prompts for installation options
    such as install location, shortcuts, and startup settings.

--silent-install:
    Silent installation with default options. No user interaction
    required. Suitable for automated deployments.

--uninstall:
    Remove RustDesk from the system. Stops all services and removes
    installed files.

REQUIREMENTS:
    - Windows operating system
    - Administrative privileges required
    - For portable executable, use --install to convert to installed version

EXAMPLES:
    # Interactive install
    rustdesk.exe --install

    # Silent install (for deployment)
    rustdesk.exe --silent-install

    # Uninstall
    "C:\Program Files\RustDesk\RustDesk.exe" --uninstall

NOTES:
    - Installation includes service registration
    - Uninstall preserves configuration by default
    - Silent install uses default settings
    - Installed version can auto-update

SEE ALSO:
    --install-service     Install service component only
    --uninstall-service   Remove service component only
"#);
}
