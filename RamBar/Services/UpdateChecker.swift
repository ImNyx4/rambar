import Foundation
import AppKit

final class UpdateChecker {

    private struct GitHubRelease: Decodable {
        let tag_name: String
        let assets: [Asset]

        struct Asset: Decodable {
            let name: String
            let browser_download_url: String
        }
    }

    static var localVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
    }

    /// Called on launch — respects the auto-update preference.
    static func checkForUpdates() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            guard UserDefaults.standard.object(forKey: "autoUpdateEnabled") as? Bool ?? true else { return }
            performCheck(manual: false)
        }
    }

    /// Called manually from Settings — always runs regardless of preference.
    static func checkNow() {
        performCheck(manual: true)
    }

    private static func performCheck(manual isManualCheck: Bool) {
        guard let url = URL(string: "https://api.github.com/repos/ImNyx4/rambar/releases/latest") else { return }

        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 10

        URLSession.shared.dataTask(with: request) { data, response, error in
            guard let data, error == nil else { return }
            guard let release = try? JSONDecoder().decode(GitHubRelease.self, from: data) else { return }

            let remoteVersion = release.tag_name.trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
            let localVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"

            guard isVersion(remoteVersion, newerThan: localVersion) else {
                if isManualCheck {
                    DispatchQueue.main.async { showUpToDate() }
                }
                return
            }

            guard let dmgAsset = release.assets.first(where: { $0.name.hasSuffix(".dmg") }),
                  let dmgURL = URL(string: dmgAsset.browser_download_url) else { return }

            DispatchQueue.main.async {
                promptAndUpdate(remoteVersion: remoteVersion, dmgURL: dmgURL)
            }
        }.resume()
    }

    private static func isVersion(_ remote: String, newerThan local: String) -> Bool {
        let r = remote.split(separator: ".").compactMap { Int($0) }
        let l = local.split(separator: ".").compactMap { Int($0) }
        for i in 0..<max(r.count, l.count) {
            let rv = i < r.count ? r[i] : 0
            let lv = i < l.count ? l[i] : 0
            if rv > lv { return true }
            if rv < lv { return false }
        }
        return false
    }

    private static func promptAndUpdate(remoteVersion: String, dmgURL: URL) {
        let alert = NSAlert()
        alert.messageText = "Update Available"
        alert.informativeText = "RamBar v\(remoteVersion) is available. Would you like to update now?"
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Update")
        alert.addButton(withTitle: "Later")

        guard alert.runModal() == .alertFirstButtonReturn else { return }

        downloadAndInstall(dmgURL: dmgURL)
    }

    private static func downloadAndInstall(dmgURL: URL) {
        let task = URLSession.shared.downloadTask(with: dmgURL) { tempURL, _, error in
            guard let tempURL, error == nil else {
                DispatchQueue.main.async { showError("Download failed. Please try again later.") }
                return
            }

            let dmgPath = NSTemporaryDirectory() + "RamBar-update.dmg"
            try? FileManager.default.removeItem(atPath: dmgPath)
            do {
                try FileManager.default.moveItem(at: tempURL, to: URL(fileURLWithPath: dmgPath))
            } catch {
                DispatchQueue.main.async { showError("Could not save update.") }
                return
            }

            DispatchQueue.main.async {
                installFromDMG(dmgPath: dmgPath)
            }
        }
        task.resume()
    }

    private static func installFromDMG(dmgPath: String) {
        guard let appBundlePath = Bundle.main.bundlePath as String? else { return }

        // Shell script: mount DMG, copy new app over current, relaunch
        let script = """
        #!/bin/bash
        MOUNT_POINT=$(hdiutil attach "\(dmgPath)" -nobrowse -noverify | grep "/Volumes" | awk '{print substr($0, index($0, "/Volumes"))}')
        if [ -z "$MOUNT_POINT" ]; then exit 1; fi
        sleep 1
        rm -rf "\(appBundlePath)"
        cp -R "$MOUNT_POINT/RamBar.app" "\(appBundlePath)"
        hdiutil detach "$MOUNT_POINT" -quiet
        rm -f "\(dmgPath)"
        open "\(appBundlePath)"
        """

        let scriptPath = NSTemporaryDirectory() + "rambar-update.sh"
        do {
            try script.write(toFile: scriptPath, atomically: true, encoding: .utf8)
        } catch {
            showError("Could not prepare update script.")
            return
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [scriptPath]
        try? process.run()

        // Quit current app so the script can replace it
        NSApplication.shared.terminate(nil)
    }

    private static func showUpToDate() {
        let alert = NSAlert()
        alert.messageText = "You're Up to Date"
        alert.informativeText = "RamBar v\(localVersion) is the latest version."
        alert.alertStyle = .informational
        alert.runModal()
    }

    private static func showError(_ message: String) {
        let alert = NSAlert()
        alert.messageText = "Update Error"
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.runModal()
    }
}
