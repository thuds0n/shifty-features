//
//  PrefAboutViewController.swift
//  Shifty
//
//  Created by Nate Thompson on 11/10/17.
//

import Cocoa
import MASPreferences_Shifty

@objcMembers
class PrefAboutViewController: NSViewController, MASPreferencesViewController {
    let integrations = SystemIntegration.shared

    override var nibName: NSNib.Name {
        get { return "PrefAboutViewController" }
    }

    var viewIdentifier: String = "PrefAboutViewController"

    var toolbarItemImage: NSImage? {
        NSImage(systemSymbolName: "info.circle", accessibilityDescription: nil)
    }

    var toolbarItemLabel: String? {
        get {
            view.layoutSubtreeIfNeeded()
            return NSLocalizedString("prefs.about", comment: "About")
        }
    }

    var hasResizableWidth = false
    var hasResizableHeight = false

    @IBOutlet weak var nameLabel: NSTextField!
    @IBOutlet weak var versionLabel: NSTextField!

    override func viewDidLoad() {
        super.viewDidLoad()

        let bundleDisplayName = Bundle.main.localizedInfoDictionary?["CFBundleDisplayName"]
        nameLabel.stringValue = bundleDisplayName as? String ?? ""

        let versionObject = Bundle.main.infoDictionary?["CFBundleShortVersionString"]
        versionLabel.stringValue = versionObject as? String ?? ""
    }

    @IBAction func checkUpdateClicked(_ sender: NSButton) {
        integrations.updater.checkForUpdates(sender)
        Event.checkForUpdatesClicked.record()
    }

    @IBAction func visitWebsiteClicked(_ sender: NSButton) {
        guard let url = URL(string: "https://shifty.natethompson.io") else { return }
        NSWorkspace.shared.open(url)
        Event.websiteButtonClicked.record()
    }

    @IBAction func submitFeedbackClicked(_ sender: NSButton) {
        guard let url = URL(string: "mailto:feedback@natethompson.io?subject=Shifty%20Feedback") else { return }
        NSWorkspace.shared.open(url)
        Event.feedbackButtonClicked.record()
    }
    
    @IBAction func twitterButtonClicked(_ sender: Any) {
        guard let url = URL(string: "https://natethompson.io/twitter") else { return }
        NSWorkspace.shared.open(url)
        Event.twitterButtonClicked.record()
    }
    
    @IBAction func translateButtonClicked(_ sender: NSButton) {
        guard let url = URL(string: "https://shifty.natethompson.io/translate") else { return }
        NSWorkspace.shared.open(url)
        Event.translateButtonClicked.record()
    }

    @IBAction func donateButtonClicked(_ sender: NSButton) {
        guard let url = URL(string: "https://shifty.natethompson.io/donate") else { return }
        NSWorkspace.shared.open(url)
        Event.donateButtonClicked.record()
    }

    @IBAction func creditsButtonClicked(_ sender: Any) {
        guard let path = Bundle.main.path(forResource: "credits", ofType: "rtfd") else { return }
        NSWorkspace.shared.open(URL(fileURLWithPath: path))
        Event.creditsClicked.record()
    }
}


class LinkButton: NSButton {
    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    override func resetCursorRects() {
        addCursorRect(self.bounds, cursor: .pointingHand)
    }
}
