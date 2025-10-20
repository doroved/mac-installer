import AppKit
import Combine
import Foundation
import SwiftUI

// MARK: - 1. ViewModel (Logic Management)
class InstallerViewModel: NSObject, ObservableObject, URLSessionDownloadDelegate {
    // MARK: - State
    @Published var statusText: String = String(localized: "Initialization...")
    @Published var isInstalling: Bool = false
    @Published var isDownloadComplete: Bool = false
    @Published var isInstalledAppFound: Bool = false

    @Published var installationProgress: Double = 0.0
    @Published var totalWrittenProgress = Int64(0)
    @Published var totalExpectedProgress = Int64(0)

    var installationProgressMegabytes: String {
        let writtenMB = Double(totalWrittenProgress) / (1024 * 1024)
        let expectedMB = Double(totalExpectedProgress) / (1024 * 1024)
        return String(format: "%.2f/%.2f MB", writtenMB, expectedMB)
    }

    private lazy var currentArchitecture: String = {
        #if arch(arm64)
            return "aarch64"
        #elseif arch(x86_64)
            return "x86_64"
        #else
            return "unknown"
        #endif
    }()

    private var tempDirectory: URL!
    private var downloadContinuation: CheckedContinuation<URL, Error>?
    private var downloadTask: URLSessionDownloadTask?
    private var urlSession: URLSession!

    override init() {
        super.init()
        let config = URLSessionConfiguration.default
        urlSession = URLSession(
            configuration: config,
            delegate: self,
            delegateQueue: nil
        )
        checkExistingInstallation()
    }

    // MARK: - Core Methods

    func checkExistingInstallation() {
        if FileManager.default.fileExists(atPath: AppConfig.installedAppPath) {
            self.isInstalledAppFound = true
            self.statusText = String(
                localized:
                    "The application is already installed. You can delete the installation file."
            )
        } else {
            Task { await startInstallation() }
        }
    }

    func openInstalledApp() {
        DispatchQueue.main.async {
            NSWorkspace.shared.openApplication(
                at: URL(fileURLWithPath: AppConfig.installedAppPath),
                configuration: NSWorkspace.OpenConfiguration()
            ) { (app, error) in
                if let error = error {
                    print(
                        "Error launching application: \(error.localizedDescription)"
                    )
                } else {
                    print("Application successfully launched!")
                    print("Close installer...")

                    DispatchQueue.main.async {
                        NSApp.terminate(nil)
                    }
                }
            }
        }
    }

    func cancelInstallationAndCleanup() {
        print("Cancel Install And Cleanup")
        downloadTask?.cancel()
        handleInstallationError(InstallerError.installationCancelled)
    }

    @MainActor
    func startInstallation() async {
        guard !isInstalling && !isInstalledAppFound else { return }

        isInstalling = true

        do {
            print("Architecture: \(currentArchitecture)")

            self.tempDirectory = URL(fileURLWithPath: NSTemporaryDirectory())
                .appendingPathComponent("InstallerTemp_\(UUID().uuidString)")

            print("Temporary directory: \(tempDirectory.path)")

            let downloadURL: URL
            if AppConfig.downloadType == "direct" {
                downloadURL =
                    (currentArchitecture == "aarch64")
                    ? AppConfig.arm64URL
                    : AppConfig.x86_64URL
            } else {
                downloadURL = try await fetchDownloadURL(
                    url: AppConfig.latestReleaseURL
                )
            }
            print("Download URL: \(downloadURL)")

            try FileManager.default.createDirectory(
                at: tempDirectory,
                withIntermediateDirectories: true
            )

            self.statusText = String(localized: "Downloading the app...")
            let finalLocalURL = try await downloadFileWithProgress(
                from: downloadURL
            )

            self.isDownloadComplete = true

            self.statusText = String(localized: "Installing the application...")
            try await mountDmgAndMoveApp(at: finalLocalURL)

            isInstalling = false

            print("Remove temporary directory...")
            try FileManager.default.removeItem(at: tempDirectory)

            openInstalledApp()
        } catch {
            handleInstallationError(error)
            presentAlert(error: error) {
                Task { await self.startInstallation() }
            }
        }
    }

    // MARK: - Private Helpers

    private func fetchDownloadURL(url: URL) async throws -> URL {
        let (data, response) = try await self.urlSession.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse,
            httpResponse.statusCode == 200
        else {
            throw InstallerError.httpError(
                statusCode: (response as? HTTPURLResponse)?.statusCode ?? 0
            )
        }

        struct Asset: Decodable, Sendable {
            let name: String
            let browser_download_url: String
        }

        struct ReleaseMetadata: Decodable, Sendable {
            let assets: [Asset]
        }

        let metadata = try JSONDecoder().decode(
            ReleaseMetadata.self,
            from: data
        )

        // Define architecture search patterns
        let archPatterns: [String]
        switch self.currentArchitecture {
        case "aarch64":
            archPatterns = ["arm64", "aarch64", "arm"]
        case "x86_64":
            archPatterns = ["x64", "x86", "x86_64", "intel", "amd64"]
        default:
            throw InstallerError.unsupportedArchitecture
        }

        guard
            let asset = metadata.assets.first(where: { asset in
                let assetNameLowercased = asset.name.lowercased()

                // Check for .dmg extension
                let isDmg = assetNameLowercased.hasSuffix(".dmg")
                if !isDmg { return false }

                // 1. Check for correct architecture
                let hasCorrectArch = archPatterns.contains(
                    where: assetNameLowercased.contains
                )

                return hasCorrectArch
            }),
            let downloadURL = URL(string: asset.browser_download_url)
        else {
            // Throw a more specific error if the asset isn't found
            throw InstallerError.downloadAssetNotFound(
                architecture: currentArchitecture
            )
        }

        return downloadURL
    }

    private func downloadFileWithProgress(from url: URL) async throws -> URL {
        let downloadTask = urlSession.downloadTask(with: url)
        self.downloadTask = downloadTask

        return try await withCheckedThrowingContinuation { continuation in
            self.downloadContinuation = continuation
            downloadTask.resume()
        }
    }

    // Runs an external command (e.g., hdiutil) and awaits completion.
    private func runCommand(path: String, arguments: [String]) async throws {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: path)
        task.arguments = arguments

        // Redirect output to pipe to avoid console output on success
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe

        return try await withCheckedThrowingContinuation { continuation in
            task.terminationHandler = { process in
                if process.terminationStatus == 0 {
                    continuation.resume(returning: ())
                } else {
                    // Read output for diagnostics if the command failed
                    let data = pipe.fileHandleForReading.readDataToEndOfFile()
                    let output =
                        String(data: data, encoding: .utf8)?.trimmingCharacters(
                            in: .whitespacesAndNewlines
                        ) ?? ""

                    let errorMessage =
                        "Command failed (\(path) \(arguments.joined(separator: " "))): Status \(process.terminationStatus).\nOutput: \(output)"

                    continuation.resume(
                        throwing: InstallerError.runCommandFailed(
                            command: path,
                            output: errorMessage
                        )
                    )
                }
            }

            do {
                try task.run()
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    // Mounts DMG, moves .app from mount point to /Applications, then unmounts.
    private func mountDmgAndMoveApp(at dmgURL: URL) async throws {
        let mountPoint = await AppConfig.mountPoint

        // 1. Mount the .dmg. Use -mountpoint for explicit location.
        print("Mounting DMG: \(dmgURL.lastPathComponent) to \(mountPoint)")

        let attachArgs = [
            "attach",
            "-nobrowse",
            "-mountpoint", mountPoint,
            dmgURL.path,
        ]
        try await runCommand(path: "/usr/bin/hdiutil", arguments: attachArgs)

        defer {
            // 3. Unmount in any case
            print("Unmounting \(mountPoint)...")

            // Use detached Task to ignore potential hdiutil detach errors (e.g., if mount point already gone)
            Task.detached {
                let detachArgs = ["detach", mountPoint, "-force"]
                // Use try? runCommand to ignore errors during unmounting
                try? await self.runCommand(
                    path: "/usr/bin/hdiutil",
                    arguments: detachArgs
                )
            }
        }

        // 2. Move the .app
        let fm = FileManager.default
        let mountedDir = URL(fileURLWithPath: mountPoint)

        // Find the .app file in the mounted image.
        guard
            let appURL = try fm.contentsOfDirectory(
                at: mountedDir,
                includingPropertiesForKeys: nil
            )
            .first(where: { $0.pathExtension == "app" })
        else { throw InstallerError.appNotFound }

        let finalAppURL = await URL(fileURLWithPath: AppConfig.installedAppPath)

        // Move the application from the mount point to /Applications
        print("Moving APP: \(appURL.path) to \(finalAppURL.path)")
        try fm.copyItem(at: appURL, to: finalAppURL)
    }

    private func handleInstallationError(_ error: Error) {
        DispatchQueue.main.async {
            self.isInstalling = false
        }
        try? FileManager.default.removeItem(at: tempDirectory)
        print("Installation Error: \(error.localizedDescription)")
    }

    private func presentAlert(error: Error, retryHandler: @escaping () -> Void) {
        let alert = NSAlert()
        alert.messageText = String(localized: "Installation Error")
        alert.informativeText =
            (error as? InstallerError)?.errorDescription
            ?? error.localizedDescription

        alert.addButton(withTitle: String(localized: "Repeat"))
        alert.addButton(withTitle: String(localized: "Close"))

        DispatchQueue.main.async {
            if alert.runModal() == .alertFirstButtonReturn {
                retryHandler()
            } else {
                NSApp.terminate(nil)
            }
        }
    }

    // MARK: URLSessionDownloadDelegate
    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        if totalBytesExpectedToWrite > 0 {
            // Download progress update
            let installationValue =
                Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)

            DispatchQueue.main.async {
                self.totalWrittenProgress = totalBytesWritten
                self.totalExpectedProgress = totalBytesExpectedToWrite
                self.installationProgress = installationValue
            }
        }
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        defer {
            self.downloadContinuation = nil
            self.downloadTask = nil
        }

        // Determine filename
        let suggestedFilename =
            downloadTask.response?.suggestedFilename ?? "downloaded_file.dmg"

        // New destination with the correct filename
        let destinationURL = self.tempDirectory.appendingPathComponent(
            suggestedFilename
        )

        do {
            // Remove existing file if present
            if FileManager.default.fileExists(atPath: destinationURL.path) {
                try FileManager.default.removeItem(at: destinationURL)
            }

            // Move downloaded file to tempDirectory with the correct name
            try FileManager.default.moveItem(at: location, to: destinationURL)

            // Resume continuation with the correct URL
            downloadContinuation?.resume(returning: destinationURL)
        } catch {
            downloadContinuation?.resume(throwing: error)
        }
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        // 1. Check if there was an error. If not, do nothing (success handled elsewhere).
        guard let error = error else {
            return
        }

        // 2. Check if the error is a user cancellation (NSURLErrorCancelled, code -999).
        if (error as NSError).code == NSURLErrorCancelled {
            return
        }

        // 3. If any other error, propagate it through the Continuation.
        downloadContinuation?.resume(throwing: error)
    }
}

// MARK: - 2. Errors

enum InstallerError: LocalizedError {
    case appNotFound, missingDownloadDestination, unsupportedArchitecture
    case httpError(statusCode: Int)
    case installationCancelled
    case runCommandFailed(command: String, output: String)
    case downloadAssetNotFound(architecture: String)

    var errorDescription: String? {
        switch self {
        case .appNotFound:
            return String(localized: "Application file (.app) not found.")

        case .downloadAssetNotFound(let arch):
            return String(
                localized:
                    "Could not find the .dmg file for architecture \(arch) in the release assets."
            )

        case .missingDownloadDestination:
            return String(
                localized:
                    "Internal error: Failed to determine the file save location."
            )

        case .unsupportedArchitecture:
            return String(localized: "Architecture is not supported.")

        case .httpError(let code):
            return String(
                localized: "Network error: HTTP \(code)."
            )

        case .installationCancelled:
            return String(localized: "Installation canceled by the user.")

        case .runCommandFailed(let command, let output):
            return String(
                localized:
                    "Command execution failed: \(command). Output: \(output)"
            )
        }
    }
}

// MARK: - 3. AppDelegate (Window & Exit Management)

class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var viewModel: InstallerViewModel?
    private var window: NSWindow?

    private func presentExitConfirmationAlert(viewModel: InstallerViewModel)
        -> NSApplication.TerminateReply
    {
        let alert = NSAlert()
        alert.messageText = String(localized: "Installation not complete!")
        alert.informativeText = String(
            localized:
                "Are you sure you want to exit? Installation will be canceled."
        )

        alert.addButton(withTitle: String(localized: "Continue installation"))
        alert.addButton(withTitle: String(localized: "Exit"))

        let response = alert.runModal()

        if response == .alertFirstButtonReturn {
            return .terminateCancel
        } else {
            viewModel.isInstalling = false
            viewModel.cancelInstallationAndCleanup()

            return .terminateNow
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        self.viewModel = AppModelWrapper.sharedViewModel

        if let window = NSApplication.shared.windows.first {
            self.window = window
            window.delegate = self

            window.title = String(localized: "\(AppConfig.appName) Installer")
            window.standardWindowButton(.zoomButton)?.isEnabled = false

            if AppConfig.isWindowFloating {
                window.level = .floating
            } else {
                window.standardWindowButton(.miniaturizeButton)?.isEnabled =
                    false
            }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(
        _ sender: NSApplication
    ) -> Bool {
        return true
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard let viewModel = viewModel, viewModel.isInstalling else {
            return true
        }

        let reply = presentExitConfirmationAlert(viewModel: viewModel)

        if reply == .terminateNow {
            return true
        } else {
            return false
        }
    }

    func applicationShouldTerminate(_ sender: NSApplication)
        -> NSApplication.TerminateReply
    {
        guard let viewModel = viewModel, viewModel.isInstalling else {
            return .terminateNow  // Allow termination
        }

        // If installation is in progress, show alert and return result.
        return presentExitConfirmationAlert(viewModel: viewModel)
    }
}

// MARK: - 4. SwiftUI View (Interface)

struct ContentView: View {
    @ObservedObject public var viewModel: InstallerViewModel

    var body: some View {
        HStack(spacing: 10) {

            Image(nsImage: NSImage(named: "AppIcon") ?? NSImage())
                .resizable()
                .scaledToFill()
                .frame(width: 64, height: 64)
                .shadow(radius: 8)

            VStack(alignment: .leading, spacing: 10) {
                if viewModel.isInstalledAppFound {
                    Text(viewModel.statusText)
                } else {
                    ProgressView(
                        value: viewModel.isInstalling
                            && !viewModel.isDownloadComplete
                            ? viewModel.installationProgress
                            : nil
                    ) {
                        HStack {
                            Text(viewModel.statusText).lineLimit(1)

                            // Show MB count only during active download
                            if viewModel.isInstalling
                                && !viewModel.isDownloadComplete
                                && viewModel.totalExpectedProgress != 0
                            {
                                Spacer()
                                Text(viewModel.installationProgressMegabytes)
                                    .foregroundStyle(Color.secondary)
                                    .fontWeight(.medium)
                            }
                        }
                    }
                    .id(
                        viewModel.isDownloadComplete ? "Indefinite" : "Definite"
                    )
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(20)
        .frame(width: 420)
    }
}
// MARK: - 5. App (Launch)

class AppModelWrapper {
    // Make it static for AppDelegate access
    static var sharedViewModel: InstallerViewModel?
}

@main
struct MacInstallerApp: App {
    // Create a single ViewModel instance managed by the App lifecycle
    @ObservedObject var viewModel = InstallerViewModel()

    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    // Initialize the shared reference
    init() {
        // Set the reference to the created SwiftUI instance
        AppModelWrapper.sharedViewModel = viewModel
    }

    var body: some Scene {
        WindowGroup {
            // Pass the created instance to ContentView
            ContentView(viewModel: viewModel)
        }
        .windowResizability(.contentSize)
    }
}
