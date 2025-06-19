//
//  RuleManager.swift
//
//
//  Created by Saagar Jha on 1/14/18.
//

import Cocoa
import ScriptingBridge
import SwiftLog

class RuleManager {
    static var shared = RuleManager()

    var knownDisplays: [CGDirectDisplayID: String]

    init() {
        if let appData = UserDefaults.standard.value(
            forKey: Keys.currentAppDisableRules
        ) as? Data {
            do {
                currentAppDisableRules = try PropertyListDecoder().decode(
                    Set<AppRule>.self,
                    from: appData
                )
            } catch {
                logw("Error: \(error.localizedDescription)")
            }
        }

        if let appData = UserDefaults.standard.value(
            forKey: Keys.runningAppDisableRules
        ) as? Data {
            do {
                runningAppDisableRules = try PropertyListDecoder().decode(
                    Set<AppRule>.self,
                    from: appData
                )
            } catch let error {
                logw("Error: \(error.localizedDescription)")
            }
        }

        if let browserData = UserDefaults.standard.value(
            forKey: Keys.browserRules
        ) as? Data {
            do {
                browserRules = try PropertyListDecoder().decode(
                    Set<BrowserRule>.self,
                    from: browserData
                )
            } catch let error {
                logw("Error: \(error.localizedDescription)")
            }
        }

        if let displayData = UserDefaults.standard.value(
            forKey: Keys.displayRules
        ) as? Data {
            do {
                displayRules = try PropertyListDecoder().decode(
                    Set<DisplayRule>.self,
                    from: displayData
                )
            } catch let error {
                logw("Error: \(error.localizedDescription)")
            }
        }

        knownDisplays = [:]
        for displayInfo in getOnlineDisplays() {
            knownDisplays[displayInfo.displayID] = displayInfo.uuid
        }

        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: nil
        ) { notification in
            self.appSwitched(notification: notification)
        }

        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didLaunchApplicationNotification,
            object: nil,
            queue: nil
        ) { notification in
            self.appSwitched(notification: notification)
        }

        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification,
            object: nil,
            queue: nil
        ) { notification in
            self.appSwitched(notification: notification)
        }

        CGDisplayRegisterReconfigurationCallback(
            displayReconfigurationCallback,
            Unmanaged.passUnretained(self).toOpaque()
        )
    }

    deinit {
        CGDisplayRemoveReconfigurationCallback(
            displayReconfigurationCallback,
            Unmanaged.passUnretained(self).toOpaque()
        )
    }

    let displayReconfigurationCallback: CGDisplayReconfigurationCallBack = {
        (display, flags, userInfo) in
        let mySelf = Unmanaged<RuleManager>.fromOpaque(userInfo!)
            .takeUnretainedValue()
        mySelf.displaysChanged(display: display, flags: flags)
    }

    var currentAppDisableRules = Set<AppRule>() {
        didSet {
            UserDefaults.standard.set(
                try? PropertyListEncoder().encode(currentAppDisableRules),
                forKey: Keys.currentAppDisableRules
            )
        }
    }

    var runningAppDisableRules = Set<AppRule>() {
        didSet {
            UserDefaults.standard.set(
                try? PropertyListEncoder().encode(runningAppDisableRules),
                forKey: Keys.runningAppDisableRules
            )
        }
    }

    var browserRules = Set<BrowserRule>() {
        didSet(newValue) {
            UserDefaults.standard.set(
                try? PropertyListEncoder().encode(browserRules),
                forKey: Keys.browserRules
            )
        }
    }

    var displayRules = Set<DisplayRule>() {
        didSet(newValue) {
            UserDefaults.standard.set(
                try? PropertyListEncoder().encode(displayRules),
                forKey: Keys.displayRules
            )
        }
    }

    var currentApp: NSRunningApplication? {
        NSWorkspace.shared.menuBarOwningApplication
    }

    var runningApps: [NSRunningApplication] {
        NSWorkspace.shared.runningApplications
    }

    var displays: [DisplayInfo] {
        getOnlineDisplays()
    }

    var isDisabledForCurrentApp: Bool {
        guard let bundleIdentifier = currentApp?.bundleIdentifier else {
            logw("Could not obtain bundle identifier of current application")
            return false
        }
        return currentAppDisableRules.filter {
            $0.bundleIdentifier == bundleIdentifier
        }.count > 0
    }

    func addCurrentAppDisableRule(forApp app: NSRunningApplication) {
        guard let bundleID = app.bundleIdentifier else { return }
        let rule = AppRule(bundleIdentifier: bundleID, fullScreenOnly: false)
        currentAppDisableRules.insert(rule)
        NightShiftManager.shared.respond(to: .nightShiftDisableRuleActivated)
    }

    func removeCurrentAppDisableRule(forApp app: NSRunningApplication) {
        guard let bundleID = app.bundleIdentifier,
            let index = currentAppDisableRules.firstIndex(where: {
                $0.bundleIdentifier == bundleID
            })
        else { return }

        currentAppDisableRules.remove(at: index)
        NightShiftManager.shared.respond(to: .nightShiftDisableRuleDeactivated)
    }

    var isDisabledForRunningApp: Bool {
        disabledCurrentlyRunningApps.count > 0
    }

    /// The currently running apps that Night Shift is disabled for
    var disabledCurrentlyRunningApps: [NSRunningApplication] {
        let disabledBundleIDs = Set(
            runningAppDisableRules.map { $0.bundleIdentifier }
        )
        return runningApps.filter {
            guard let bundleID = $0.bundleIdentifier else { return false }
            return disabledBundleIDs.contains(bundleID)
        }
    }

    func isDisabledWhenRunningApp(_ app: NSRunningApplication) -> Bool {
        guard let bundleID = app.bundleIdentifier else { return false }
        return runningAppDisableRules.contains(where: {
            $0.bundleIdentifier == bundleID
        })
    }

    func addRunningAppDisableRule(forApp app: NSRunningApplication) {
        guard let bundleID = app.bundleIdentifier else { return }
        let rule = AppRule(bundleIdentifier: bundleID, fullScreenOnly: false)

        runningAppDisableRules.insert(rule)
        NightShiftManager.shared.respond(to: .nightShiftDisableRuleActivated)
    }

    func removeRunningAppDisableRule(forApp app: NSRunningApplication) {
        guard let bundleID = app.bundleIdentifier,
            let index = runningAppDisableRules.firstIndex(where: {
                $0.bundleIdentifier == bundleID
            })
        else { return }

        runningAppDisableRules.remove(at: index)
        NightShiftManager.shared.respond(to: .nightShiftDisableRuleDeactivated)
    }

    var isDisabledForDomain: Bool {
        guard let currentDomain = BrowserManager.shared.currentDomain else {
            return false
        }
        let disabledDomain =
            browserRules.filter {
                $0.type == .domain && $0.host == currentDomain
            }.count > 0
        return disabledDomain
    }

    func addDomainDisableRule(forDomain domain: String) {
        let rule = BrowserRule(type: .domain, host: domain)
        browserRules.insert(rule)

        NightShiftManager.shared.respond(to: .nightShiftDisableRuleActivated)
    }

    func removeDomainDisableRule(forDomain domain: String) {
        let rule = BrowserRule(type: .domain, host: domain)
        guard let index = browserRules.firstIndex(of: rule) else { return }
        browserRules.remove(at: index)

        if let currentSubdomain = BrowserManager.shared.currentSubdomain,
            getSubdomainRule(forSubdomain: currentSubdomain) == .enabled
        {
            setSubdomainRule(.none, forSubdomain: currentSubdomain)
        }

        NightShiftManager.shared.respond(to: .nightShiftDisableRuleDeactivated)
    }

    func getSubdomainRule(forSubdomain subdomain: String) -> SubdomainRuleType {
        if isDisabledForDomain {
            let isEnabled =
                (browserRules.filter {
                    $0.type == .subdomainEnabled
                        && $0.host == subdomain
                }.count > 0)
            if isEnabled {
                return .enabled
            }
        } else {
            let isDisabled =
                (browserRules.filter {
                    $0.type == .subdomainDisabled
                        && $0.host == subdomain
                }.count > 0)
            if isDisabled {
                return .disabled
            }
        }
        return .none
    }

    var ruleForCurrentSubdomain: SubdomainRuleType {
        guard let currentSubdomain = BrowserManager.shared.currentSubdomain
        else { return .none }
        return getSubdomainRule(forSubdomain: currentSubdomain)
    }

    func setSubdomainRule(
        _ ruleType: SubdomainRuleType,
        forSubdomain subdomain: String
    ) {
        switch ruleType {
        case .disabled:
            let rule = BrowserRule(type: .subdomainDisabled, host: subdomain)
            browserRules.insert(rule)
            NightShiftManager.shared.respond(
                to: .nightShiftDisableRuleActivated
            )
        case .enabled:
            let rule = BrowserRule(type: .subdomainEnabled, host: subdomain)
            browserRules.insert(rule)
            NightShiftManager.shared.respond(to: .nightShiftEnableRuleActivated)
        case .none:
            var rule: BrowserRule
            let prevValue = getSubdomainRule(forSubdomain: subdomain)

            //Remove rule from set before triggering NightShiftEvent
            switch prevValue {
            case .disabled:
                rule = BrowserRule(type: .subdomainDisabled, host: subdomain)
            case .enabled:
                rule = BrowserRule(type: .subdomainEnabled, host: subdomain)
            case .none:
                return
            }
            guard let index = browserRules.firstIndex(of: rule) else { return }
            browserRules.remove(at: index)

            switch prevValue {
            case .disabled:
                NightShiftManager.shared.respond(
                    to: .nightShiftDisableRuleDeactivated
                )
            case .enabled:
                NightShiftManager.shared.respond(
                    to: .nightShiftEnableRuleDeactivated
                )
            case .none:
                break
            }
        }
    }

    private func getOnlineDisplays() -> [DisplayInfo] {
        var displays: [DisplayInfo] = []

        let maxDisplays: UInt32 = 32
        var displayIDs = [CGDirectDisplayID](
            repeating: 0,
            count: Int(maxDisplays)
        )
        var displayCount: UInt32 = 0

        let result = CGGetOnlineDisplayList(
            maxDisplays,
            &displayIDs,
            &displayCount
        )

        guard result == .success else {
            logw("Error: Could not get display list")
            return displays
        }

        for displayID in displayIDs[0..<Int(displayCount)] {
            guard let uuid = getDisplayUUID(displayID: displayID) else {
                continue
            }
            let displayName = getDisplayName(displayID: displayID)

            let displayInfo = DisplayInfo(
                name: displayName,
                uuid: uuid,
                displayID: displayID
            )

            displays.append(displayInfo)
        }

        return displays
    }

    private func getDisplayUUID(displayID: CGDirectDisplayID) -> String? {
        guard let cfUuid = CGDisplayCreateUUIDFromDisplayID(displayID)
        else {
            return knownDisplays[displayID]
        }
        let uuid =
            CFUUIDCreateString(
                kCFAllocatorDefault,
                cfUuid.takeRetainedValue()
            ) as String
        knownDisplays[displayID] = uuid
        return uuid
    }

    private func getDisplayName(displayID: CGDirectDisplayID) -> String {
        let screenNumberKey = NSDeviceDescriptionKey.init("NSScreenNumber")
        for screen in NSScreen.screens {
            if screen.deviceDescription[screenNumberKey] as? UInt32 == displayID
            {
                return screen.localizedName
            }
        }

        // Can happen when mirroring
        return "(display: \(displayID))"
    }

    func isDisabledForDisplay(forDisplay uuid: String) -> Bool {
        return displayRules.filter { $0.uuid == uuid }.count > 0
    }

    var isDisabledForAnyDisplay: Bool {
        !onlineDisabledDisplays.isEmpty
    }

    private var onlineDisabledDisplays: Set<String> {
        let onlineUUIDs = Set(getOnlineDisplays().map { $0.uuid })
        return onlineUUIDs.intersection(displayRules.map { $0.uuid })
    }

    func addDisplayDisableRule(forDisplay uuid: String) {
        let rule = DisplayRule(uuid: uuid)
        displayRules.insert(rule)
        NightShiftManager.shared.respond(to: .nightShiftDisableRuleActivated)
    }

    func removeDisplayDisableRule(forDisplay uuid: String) {
        guard
            let index = displayRules.firstIndex(where: {
                $0.uuid == uuid
            })
        else { return }

        displayRules.remove(at: index)
        NightShiftManager.shared.respond(to: .nightShiftDisableRuleDeactivated)
    }

    var disableRuleIsActive: Bool {
        return isDisabledForCurrentApp || isDisabledForRunningApp
            || (isDisabledForDomain && ruleForCurrentSubdomain != .enabled)
            || ruleForCurrentSubdomain == .disabled || isDisabledForAnyDisplay
    }

    func removeRulesForCurrentState() {
        if let currentApp = currentApp {
            removeCurrentAppDisableRule(forApp: currentApp)
            for app in disabledCurrentlyRunningApps {
                removeRunningAppDisableRule(forApp: app)
            }
        }
        if let currentDomain = BrowserManager.shared.currentDomain {
            removeDomainDisableRule(forDomain: currentDomain)
        }
        if let currentSubdomain = BrowserManager.shared.currentSubdomain {
            setSubdomainRule(.none, forSubdomain: currentSubdomain)
        }
        for display in onlineDisabledDisplays {
            removeDisplayDisableRule(forDisplay: display)
        }
    }

    private func appSwitched(notification: Notification) {
        BrowserManager.shared.stopBrowserWatcher()
        if isDisabledForCurrentApp || isDisabledForRunningApp {
            NightShiftManager.shared.respond(
                to: .nightShiftDisableRuleActivated
            )
        } else if BrowserManager.shared.currentAppIsSupportedBrowser {
            BrowserManager.shared.updateForSupportedBrowser()
        } else {
            NightShiftManager.shared.respond(
                to: .nightShiftDisableRuleDeactivated
            )
        }
    }

    private func displaysChanged(
        display: CGDirectDisplayID,
        flags: CGDisplayChangeSummaryFlags
    ) {
        guard let uuid = getDisplayUUID(displayID: display) else { return }

        if !displayRules.contains(where: {
            $0.uuid == uuid
        }) {
            return
        }

        if flags.contains(.enabledFlag) {
            NightShiftManager.shared.respond(
                to: .nightShiftDisableRuleActivated
            )
        } else if flags.contains(.disabledFlag) {
            NightShiftManager.shared.respond(
                to: .nightShiftDisableRuleDeactivated
            )
        }
    }

}

enum RuleType: String, Codable {
    case domain
    case subdomainDisabled
    case subdomainEnabled
}

enum SubdomainRuleType: String, Codable {
    case none
    case disabled
    case enabled
}

struct AppRule: CustomStringConvertible, Hashable, Codable {
    var bundleIdentifier: BundleIdentifier
    // Currently unused
    var fullScreenOnly: Bool

    var description: String {
        return
            "Rule for \(bundleIdentifier); full screen only: \(fullScreenOnly)"
    }

    static func == (lhs: AppRule, rhs: AppRule) -> Bool {
        return lhs.bundleIdentifier == rhs.bundleIdentifier
            && lhs.fullScreenOnly == rhs.fullScreenOnly
    }
}

struct BrowserRule: CustomStringConvertible, Hashable, Codable {
    var type: RuleType
    var host: String

    var description: String {
        return "Rule type: \(type) for host: \(host)"
    }

    static func == (lhs: BrowserRule, rhs: BrowserRule) -> Bool {
        return lhs.type == rhs.type
            && lhs.host == rhs.host
    }
}

struct DisplayInfo {
    let name: String
    let uuid: String
    let displayID: CGDirectDisplayID
}

struct DisplayRule: CustomStringConvertible, Hashable, Codable {
    var uuid: String

    var description: String {
        return "Rule for \(uuid)"
    }

    static func == (lhs: DisplayRule, rhs: DisplayRule) -> Bool {
        return lhs.uuid == rhs.uuid
    }
}
