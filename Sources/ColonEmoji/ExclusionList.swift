import AppKit

/// Where the user is typing: the app, and the website when the app is a browser or a web-wrapper like Slack.
struct TypingContext {
    let appBundleId: String
    let appName: String
    let host: String?
}

final class ExclusionList {
    private let disabledBundleIdsKey = "disabledBundleIds"
    private let disabledHostsKey = "disabledHosts"

    var disabledBundleIds: [String] {
        (UserDefaults.standard.stringArray(forKey: disabledBundleIdsKey) ?? []).sorted()
    }

    var disabledHosts: [String] {
        (UserDefaults.standard.stringArray(forKey: disabledHostsKey) ?? []).sorted()
    }

    func isDisabled(in context: TypingContext) -> Bool {
        if isAppDisabled(context.appBundleId) {
            return true
        }
        guard let host = context.host else {
            return false
        }
        return disabledHosts.contains { disabledHost in
            host == disabledHost || host.hasSuffix("." + disabledHost)
        }
    }

    func isAppDisabled(_ bundleId: String) -> Bool {
        disabledBundleIds.contains(bundleId)
    }

    func isHostDisabled(_ host: String) -> Bool {
        disabledHosts.contains(host)
    }

    func setApp(_ bundleId: String, disabled: Bool) {
        setMembership(of: bundleId, inListAt: disabledBundleIdsKey, included: disabled)
    }

    func setHost(_ host: String, disabled: Bool) {
        setMembership(of: host, inListAt: disabledHostsKey, included: disabled)
    }

    static func displayName(forBundleId bundleId: String) -> String {
        guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) else {
            return bundleId
        }
        return FileManager.default.displayName(atPath: appURL.path).replacingOccurrences(of: ".app", with: "")
    }

    private func setMembership(of value: String, inListAt key: String, included: Bool) {
        var values = Set(UserDefaults.standard.stringArray(forKey: key) ?? [])
        if included {
            values.insert(value)
        } else {
            values.remove(value)
        }
        UserDefaults.standard.set(Array(values), forKey: key)
    }
}
