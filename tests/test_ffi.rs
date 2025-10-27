// Simple test to verify FFI functions work
#[cfg(test)]
mod ffi_test {
    use librustdesk::flutter_ffi::{main_get_device_list, main_save_device_list};

    #[test]
    fn test_get_device_list() {
        let result = main_get_device_list();
        println!("Device list JSON: {}", result);
        assert!(!result.is_empty());
        // Should be valid JSON
        assert!(serde_json::from_str::<serde_json::Value>(&result).is_ok());
    }

    #[test]
    fn test_save_device_list() {
        let test_json = r#"{
            "version": "1.0",
            "default_connection_mode": "id",
            "devices": [
                {
                    "name": "FFI Test Device",
                    "id": "111222333",
                    "ip": "",
                    "port": 21118,
                    "password": "",
                    "platform": "Test",
                    "note": "FFI test",
                    "username": "",
                    "hostname": ""
                }
            ]
        }"#;

        let result = main_save_device_list(test_json.to_string());
        println!("Save result: {}", result);
        assert_eq!(result, "OK");

        // Verify it was saved
        let loaded = main_get_device_list();
        assert!(loaded.contains("FFI Test Device"));
    }
}
