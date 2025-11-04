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
    --assign --token <TOKEN> [OPTIONS]
                                    Assign device to account/group
                                    Required: --token <bearer_token>
                                    Optional: --user_name <name>
                                             --strategy_name <name>
                                             --address_book_name <name>
                                             --address_book_tag <tag>
                                             --address_book_alias <alias>
                                             --address_book_password <pwd>
                                             --address_book_note <note>
                                             --device_group_name <name>
                                             --note <text>
                                             --device_username <name>
                                             --device_name <name>

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

    # start as gui application
    rustdesk --gui

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
    match command {
        "password" | "--password" => print_password_help(),
        "option" | "--option" => print_option_help(),
        "list-options" | "--list-options" => print_list_options_help(),
        "set-id" | "--set-id" => print_set_id_help(),
        "assign" | "--assign" => print_assign_help(),
        "connect" | "--connect" => print_connect_help(),
        "service" | "--service" | "--install-service" | "--uninstall-service" | "--start-service" | "--stop-service" | "--status" => print_service_help(),
        "config" | "--config" | "--import-config" => print_config_help(),
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
