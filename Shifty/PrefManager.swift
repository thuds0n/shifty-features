//
//  PrefManager.swift
//  Shifty
//
//  Created by Nate Thompson on 5/6/17.
//

import Foundation

enum Keys {
    static let isStatusToggleEnabled = "isStatusToggleEnabled"
    static let isAutoLaunchEnabled = "isAutoLaunchEnabled"
    static let isIconSwitchingEnabled = "isIconSwitchingEnabled"
    static let isDarkModeSyncEnabled = "isDarkModeSyncEnabled"
    static let isWebsiteControlEnabled = "isWebsiteControlEnabled"
    static let trueToneControl = "trueToneControl"
    static let currentAppDisableRules = "disabledApps"
    static let runningAppDisableRules = "disabledRunningApps"
    static let browserRules = "browserRules"
    static let isCircadianModeEnabled = "isCircadianModeEnabled"
    static let circadianConfiguration = "circadianConfiguration"

    static let toggleNightShiftShortcut = "toggleNightShiftShortcut"
    static let incrementColorTempShortcut = "incrementColorTempShortcut"
    static let decrementColorTempShortcut = "decrementColorTempShortcut"
    static let disableAppShortcut = "disableAppShortcut"
    static let disableDomainShortcut = "disableDomainShortcut"
    static let disableSubdomainShortcut = "disableSubdomainShortcut"
    static let disableHourShortcut = "disableHourShortcut"
    static let disableCustomShortcut = "disableCustomShortcut"
    static let toggleTrueToneShortcut = "toggleTrueToneShortcut"
    static let toggleDarkModeShortcut = "toggleDarkModeShortcut"
    static let showKelvinInMenuSlider = "showKelvinInMenuSlider"

    static let lastInstalledShiftyVersion = "lastInstalledShiftyVersion"
    static let hasSetupWindowShown = "hasSetupWindowShown"
}

final class PrefManager {
    static let shared = PrefManager()

    private init() {
        registerFactoryDefaults()
    }

    private var userDefaults: UserDefaults {
        UserDefaults.standard
    }

    private func registerFactoryDefaults() {
        let factoryDefaults = [
            Keys.isAutoLaunchEnabled: NSNumber(value: false),
            Keys.isStatusToggleEnabled: NSNumber(value: false),
            Keys.isIconSwitchingEnabled: NSNumber(value: false),
            Keys.isDarkModeSyncEnabled: NSNumber(value: false),
            Keys.isWebsiteControlEnabled: NSNumber(value: false),
            Keys.trueToneControl: NSNumber(value: false),
            Keys.currentAppDisableRules: NSData(),
            Keys.runningAppDisableRules: NSData(),
            Keys.browserRules: NSData(),
            Keys.isCircadianModeEnabled: NSNumber(value: false),
            Keys.showKelvinInMenuSlider: NSNumber(value: false),
            Keys.hasSetupWindowShown: NSNumber(value: false)
        ] as [String: Any]

        userDefaults.register(defaults: factoryDefaults)
    }
}
