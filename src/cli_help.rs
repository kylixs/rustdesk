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

INFORMATION COMMANDS:
    --version              Display version information
    --build-date           Display build date
    --get-id               Display this device's ID

SERVICE MANAGEMENT:
    --install-service      Install RustDesk as a system service
    --uninstall-service    Uninstall RustDesk system service
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
        "set-id" | "--set-id" => print_set_id_help(),
        "assign" | "--assign" => print_assign_help(),
        "connect" | "--connect" => print_connect_help(),
        "service" | "--service" | "--install-service" | "--uninstall-service" => print_service_help(),
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

COMMON OPTIONS:
    custom-rendezvous-server <SERVER>    Set custom ID/relay server
    api-server <URL>                     Set API server URL
    relay-server <SERVER>                Set relay server address
    key <PUBLIC_KEY>                     Set server public key
    approve-mode <MODE>                  Set approval mode (click/password)
    verification-method <METHOD>         Set verification method
    allow-hide-cm <Y/N>                  Allow hiding connection manager
    allow-logon-screen-password <Y/N>    Allow login screen password

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
    sudo rustdesk --option allow-hide-cm Y

    # Security settings
    sudo rustdesk --option allow-logon-screen-password Y

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

SEE ALSO:
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
    rustdesk --service              Run as service (internal use)

DESCRIPTION:
    Manage RustDesk as a system service for automatic startup and
    background operation.

INSTALL SERVICE:
    sudo rustdesk --install-service

    On Windows (as Administrator):
    rustdesk.exe --install-service

UNINSTALL SERVICE:
    sudo rustdesk --uninstall-service

    On Windows (as Administrator):
    rustdesk.exe --uninstall-service

REQUIREMENTS:
    - Administrative/root privileges required
    - RustDesk must be installed (not portable mode)

NOTES:
    - Service runs automatically on system startup
    - Required for unattended access
    - Service runs in background without UI
    - Use --server for foreground mode with tray icon

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
