//
//  PrefRulesViewController.swift
//  Shifty
//
//  Created by Ben Kurtovic on 6/14/25.
//

import Cocoa
import MASPreferences_Shifty
import MASShortcut

@objcMembers
class PrefRulesViewController: NSViewController, MASPreferencesViewController {

    let statusMenuController =
        (NSApplication.shared.delegate as? AppDelegate)?.statusMenu.delegate
        as? StatusMenuController

    override var nibName: NSNib.Name {
        return "PrefRulesViewController"
    }

    var viewIdentifier: String = "PrefRulesViewController"

    var toolbarItemImage: NSImage? {
        if #available(macOS 11.0, *) {
            return NSImage(
                systemSymbolName: "list.bullet",
                accessibilityDescription: nil
            )
        } else {
            return NSImage(named: "NSActionTemplate")
        }
    }

    var toolbarItemLabel: String? {
        view.layoutSubtreeIfNeeded()
        return NSLocalizedString("prefs.rules", comment: "Rules")
    }

    var hasResizableWidth = false
    var hasResizableHeight = false

    @IBOutlet weak var rulesTextField: NSTextField!

    override func viewWillAppear() {
        super.viewWillAppear()

        updateRulesText()
    }

    func updateRulesText() {
        var descriptions: [String] = []

        let currentAppRules = RuleManager.shared.currentAppDisableRules
        if !currentAppRules.isEmpty {
            let rulesText = currentAppRules.map {
                $0.description
            }.sorted().joined(separator: "\n")
            descriptions.append("Disable when app is active:\n\(rulesText)")
        }

        let runningAppRules = RuleManager.shared.runningAppDisableRules
        if !runningAppRules.isEmpty {
            let rulesText = runningAppRules.map {
                $0.description
            }.sorted().joined(separator: "\n")
            descriptions.append("Disable when app is running:\n\(rulesText)")
        }

        let browserRules = RuleManager.shared.browserRules
        if !browserRules.isEmpty {
            let rulesText = browserRules.map {
                $0.description
            }.sorted().joined(separator: "\n")
            descriptions.append("Browser rules:\n\(rulesText)")
        }

        let displayRules = RuleManager.shared.displayRules
        if !displayRules.isEmpty {
            let rulesText = displayRules.map {
                $0.description
            }.sorted().joined(separator: "\n")
            descriptions.append("Display rules:\n\(rulesText)")
        }

        rulesTextField.stringValue = descriptions.joined(separator: "\n\n")
    }
}
