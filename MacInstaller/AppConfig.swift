import Foundation

// MARK: - Global Installer Configuration
struct AppConfig {
    // Specify the application name, must start with a capital letter
    static let appName = "Proxer"

    // Path to the installed application
    static let installedAppPath = "/Applications/\(appName).app"

    // Application mount point path
    static let mountPoint = "/Volumes/\(appName)Installer"

    // Keep installer window floating on top of other windows
    static let isWindowFloating = true

    // Download type (direct/github)
    static let downloadType = "github"

    // URL to fetch latest release metadata. Use with downloadType = "github"
    static let latestReleaseURL = URL(
        string:
            "https://api.github.com/repos/doroved/proxer-releases/releases/latest"
    )!

    // Direct links to .dmg application files. Use with downloadType = "direct"
    static let arm64URL = URL(
        string:
            "https://app.myapp.com/downloads/release/darwin/aarch64/dmg"
    )!
    static let x86_64URL = URL(
        string:
            "https://app.myapp.com/downloads/release/darwin/x86_64/dmg"
    )!
}
