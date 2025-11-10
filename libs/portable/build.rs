fn main() {
    #[cfg(windows)]
    {
        use std::io::Write;

        // Read version from workspace Cargo.toml
        let cargo_toml = std::fs::read_to_string("../../Cargo.toml").unwrap();
        let mut version = String::new();
        for line in cargo_toml.lines() {
            let ab: Vec<&str> = line.split('=').map(|x| x.trim()).collect();
            if ab.len() == 2 && ab[0] == "version" {
                version = ab[1].trim_matches('"').to_string();
                break;
            }
        }

        // Get build timestamp from temporary file (set by build.py) or generate new one
        // This ensures portable packer uses the same timestamp as the Flutter exe it packages
        let build_timestamp = std::fs::read_to_string("../../target/build_timestamp.txt")
            .ok()
            .and_then(|s| {
                let trimmed = s.trim();
                if trimmed.is_empty() {
                    None
                } else {
                    Some(trimmed.to_string())
                }
            })
            .unwrap_or_else(|| chrono::Local::now().format("%Y%m%d-%H%M").to_string());

        // Create full version with build timestamp: 1.4.3-jlc18+20251104-1945
        let full_version = format!("{}+{}", version, build_timestamp);

        println!("cargo:warning=Portable packer version: {}", full_version);

        let mut res = winres::WindowsResource::new();
        res.set_icon("../../res/icon.ico")
            .set_language(winapi::um::winnt::MAKELANGID(
                winapi::um::winnt::LANG_ENGLISH,
                winapi::um::winnt::SUBLANG_ENGLISH_US,
            ))
            .set_manifest_file("../../res/manifest.xml")
            // Set ProductVersion to include build timestamp
            .set("ProductVersion", &full_version);

        match res.compile() {
            Err(e) => {
                write!(std::io::stderr(), "{}", e).unwrap();
                std::process::exit(1);
            }
            Ok(_) => {}
        }
    }
}
