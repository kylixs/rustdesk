// System notification utilities for cross-platform toast/system notifications
// Supports Windows, Linux (notify-send), and macOS (osascript)

use hbb_common::log;

/// Send a system notification with title and message
///
/// # Arguments
/// * `title` - Notification title
/// * `message` - Notification message text
///
/// # Examples
/// ```
/// send_notification("Connection Closed", "Remote desktop disconnected due to inactivity");
/// ```
pub fn send_notification(title: &str, message: &str) {
    #[cfg(windows)]
    send_windows_notification(title, message);

    #[cfg(target_os = "linux")]
    send_linux_notification(title, message);

    #[cfg(target_os = "macos")]
    send_macos_notification(title, message);
}

/// Send Windows Toast notification using PowerShell
/// Uses Windows.UI.Notifications API via PowerShell for reliability
#[cfg(windows)]
fn send_windows_notification(title: &str, message: &str) {
    use std::os::windows::process::CommandExt;
    const CREATE_NO_WINDOW: u32 = 0x08000000;

    // Get current executable path to use as APP_ID
    // This allows Windows to properly identify the application
    let app_id = std::env::current_exe()
        .ok()
        .and_then(|p| p.to_str().map(|s| s.to_owned()))
        .unwrap_or_else(|| "RustDesk".to_string());

    // PowerShell script to show Windows 10+ notification
    // Uses Windows Runtime API for better compatibility
    let ps_script = format!(
        r#"try {{
    [Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime] | Out-Null
    [Windows.UI.Notifications.ToastNotification, Windows.UI.Notifications, ContentType = WindowsRuntime] | Out-Null
    [Windows.Data.Xml.Dom.XmlDocument, Windows.Data.Xml.Dom.XmlDocument, ContentType = WindowsRuntime] | Out-Null

    $APP_ID = '{}'
    $template = @"
<toast>
    <visual>
        <binding template="ToastText02">
            <text id="1">{}</text>
            <text id="2">{}</text>
        </binding>
    </visual>
</toast>
"@

    $xml = New-Object Windows.Data.Xml.Dom.XmlDocument
    $xml.LoadXml($template)
    $toast = New-Object Windows.UI.Notifications.ToastNotification $xml
    [Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier($APP_ID).Show($toast)
    exit 0
}} catch {{
    Write-Error $_
    exit 1
}}
"#,
        app_id,
        escape_powershell_string(title),
        escape_powershell_string(message)
    );

    match std::process::Command::new("powershell")
        .args(&[
            "-NoProfile",
            "-ExecutionPolicy",
            "Bypass",
            "-Command",
            &ps_script,
        ])
        .creation_flags(CREATE_NO_WINDOW)
        .output()
    {
        Ok(output) => {
            if output.status.success() {
                log::info!(
                    "Windows notification sent successfully: title='{}', app_id='{}'",
                    title,
                    app_id
                );
            } else {
                log::error!(
                    "Failed to send Windows notification: {}",
                    String::from_utf8_lossy(&output.stderr)
                );
            }
        }
        Err(e) => {
            log::error!("Failed to execute PowerShell for notification: {:?}", e);
        }
    }
}

/// Send Linux notification using notify-send
/// Requires libnotify to be installed on the system
#[cfg(target_os = "linux")]
fn send_linux_notification(title: &str, message: &str) {
    match std::process::Command::new("notify-send")
        .arg(title)
        .arg(message)
        .arg("--icon=dialog-information")
        .arg("--expire-time=5000") // 5 seconds
        .spawn()
    {
        Ok(_) => {
            log::info!("Linux notification sent: title='{}'", title);
        }
        Err(e) => {
            log::error!("Failed to send Linux notification: {:?}", e);
        }
    }
}

/// Send macOS notification using osascript
/// Uses AppleScript to display native macOS notifications
#[cfg(target_os = "macos")]
fn send_macos_notification(title: &str, message: &str) {
    let script = format!(
        "display notification \"{}\" with title \"{}\"",
        escape_applescript_string(message),
        escape_applescript_string(title)
    );

    match std::process::Command::new("osascript")
        .arg("-e")
        .arg(&script)
        .spawn()
    {
        Ok(_) => {
            log::info!("macOS notification sent: title='{}'", title);
        }
        Err(e) => {
            log::error!("Failed to send macOS notification: {:?}", e);
        }
    }
}

/// Escape special characters in PowerShell strings
/// Doubles quotes to escape them in PowerShell here-strings
#[cfg(windows)]
fn escape_powershell_string(s: &str) -> String {
    s.replace('"', "\"\"")
}

/// Escape special characters in AppleScript strings
/// Escapes quotes and backslashes for AppleScript string literals
#[cfg(target_os = "macos")]
fn escape_applescript_string(s: &str) -> String {
    s.replace('\\', "\\\\").replace('"', "\\\"")
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    #[cfg(windows)]
    fn test_escape_powershell_string() {
        assert_eq!(escape_powershell_string("Hello"), "Hello");
        assert_eq!(escape_powershell_string("Hello \"World\""), "Hello \"\"World\"\"");
        assert_eq!(
            escape_powershell_string("Line 1\nLine 2"),
            "Line 1\nLine 2"
        );
    }

    #[test]
    #[cfg(target_os = "macos")]
    fn test_escape_applescript_string() {
        assert_eq!(escape_applescript_string("Hello"), "Hello");
        assert_eq!(
            escape_applescript_string("Hello \"World\""),
            "Hello \\\"World\\\""
        );
        assert_eq!(escape_applescript_string("C:\\Path"), "C:\\\\Path");
    }
}
