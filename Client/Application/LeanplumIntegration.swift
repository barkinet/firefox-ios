/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

import Foundation
import AdSupport
import Shared
import Leanplum

private let LeanplumEnvironmentKey = "LeanplumEnvironment"
private let LeanplumAppIdKey = "LeanplumAppId"
private let LeanplumKeyKey = "LeanplumKey"

private let log = Logger.browserLogger

private enum LeanplumEnvironment: String {
    case development = "development"
    case production = "production"
}

enum LeanplumEventName: String {
    case firstRun = "E_First_Run"
    case secondRun = "E_Second_Run"
    case openedApp = "E_Opened_App"
    case openedLogins = "Opened Login Manager"
    case openedBookmark = "E_Opened_Bookmark"
    case openedNewTab = "E_Opened_New_Tab"
    case interactWithURLBar = "E_Interact_With_Search_URL_Area"
    case savedBookmark = "E_Saved_Bookmark"
    case openedTelephoneLink = "Opened Telephone Link"
    case openedMailtoLink = "E_Opened_Mailto_Link"
    case saveImage = "E_Download_Media_Saved_Image"
    case savedLoginAndPassword = "E_Saved_Login_And_Password"
    case clearPrivateData = "E_Cleared_Private_Data"
}

enum UserAttributeKeyName: String {
    case focusInstalled = "Focus Installed"
    case klarInstalled = "Klar Installed"
    case signedInSync = "Signed In Sync"
    case mailtoIsDefault = "Mailto Is Default"
    case telemetryOptIn = "Telemetry Opt In"
}

private enum SupportedLocales: String {
    case US = "en_US"
    case DE = "de"
    case UK = "en_GB"
    case CA_EN = "en_CA"
    case AU = "en_AU"
    case TW = "zh_TW"
    case HK = "en_HK"
    case SG_EN = "en_SG"
}

private struct LeanplumSettings {
    var environment: LeanplumEnvironment
    var appId: String
    var key: String
}

class LeanplumIntegration {
    static let sharedInstance = LeanplumIntegration()

    // Setup

    fileprivate weak var profile: Profile?
    private var enabled: Bool = false
    
    func shouldSendToLP() -> Bool {
        // Need to be run on main thread since isInPrivateMode requires to be on the main thread.
        assert(Thread.isMainThread)
        return enabled && Leanplum.hasStarted() && !UIApplication.isInPrivateMode
    }

    func setup(profile: Profile) {
        self.profile = profile
    }

    fileprivate func start() {
        self.enabled = self.profile?.prefs.boolForKey("settings.sendUsageData") ?? true
        if !self.enabled {
            return
        }
        
        guard SupportedLocales(rawValue: Locale.current.identifier) != nil else {
            return
        }

        if Leanplum.hasStarted() {
            log.error("LeanplumIntegration - Already initialized")
            return
        }

        guard let settings = getSettings() else {
            log.error("LeanplumIntegration - Could not load settings from Info.plist")
            return
        }

        switch settings.environment {
        case .development:
            log.info("LeanplumIntegration - Setting up for Development")
            Leanplum.setDeviceId(UIDevice.current.identifierForVendor?.uuidString)
            Leanplum.setAppId(settings.appId, withDevelopmentKey: settings.key)
        case .production:
            log.info("LeanplumIntegration - Setting up for Production")
            Leanplum.setAppId(settings.appId, withProductionKey: settings.key)
        }
        Leanplum.syncResourcesAsync(true)

        var userAttributesDict = [AnyHashable: Any]()
        userAttributesDict[UserAttributeKeyName.mailtoIsDefault.rawValue] = mailtoIsDefault()
        userAttributesDict[UserAttributeKeyName.focusInstalled.rawValue] = !canInstallFocus()
        userAttributesDict[UserAttributeKeyName.klarInstalled.rawValue] = !canInstallKlar()
        userAttributesDict[UserAttributeKeyName.signedInSync.rawValue] = profile?.hasAccount()

        Leanplum.start(userAttributes: userAttributesDict)

        Leanplum.track(LeanplumEventName.openedApp.rawValue)
    }

    // Events

    func track(eventName: LeanplumEventName) {
        DispatchQueue.main.async(execute: {
            if self.shouldSendToLP() {
                Leanplum.track(eventName.rawValue)
            }
        })
    }

    func track(eventName: LeanplumEventName, withParameters parameters: [String: AnyObject]) {
        DispatchQueue.main.async(execute: {
            if self.shouldSendToLP() {
                Leanplum.track(eventName.rawValue, withParameters: parameters)
            }
        })
    }

    // Utils
    
    func setEnabled(_ enabled: Bool) {
        // Setting up Test Mode stops sending things to server.
        if enabled { start() }
        Leanplum.setTestModeEnabled(!enabled)
    }

    func canInstallFocus() -> Bool {
        guard let focus = URL(string: "firefox-focus://") else {
            return false
        }
        return !UIApplication.shared.canOpenURL(focus)
    }

    func canInstallKlar() -> Bool {
        guard let klar = URL(string: "firefox-klar://") else {
            return false
        }
        return !UIApplication.shared.canOpenURL(klar)
    }

    func mailtoIsDefault() -> Bool {
        return self.profile?.prefs.stringForKey(PrefsKeys.KeyMailToOption) == "mailto:"
    }

    func setUserAttributes(attributes: [AnyHashable : Any]) {
        DispatchQueue.main.async(execute: {
            if self.shouldSendToLP() {
                Leanplum.setUserAttributes(attributes)
            }
        })
    }

    // Private

    private func getSettings() -> LeanplumSettings? {
        let bundle = Bundle.main
        guard let environmentString = bundle.object(forInfoDictionaryKey: LeanplumEnvironmentKey) as? String,
              let environment = LeanplumEnvironment(rawValue: environmentString),
              let appId = bundle.object(forInfoDictionaryKey: LeanplumAppIdKey) as? String,
              let key = bundle.object(forInfoDictionaryKey: LeanplumKeyKey) as? String else {
            return nil
        }
        return LeanplumSettings(environment: environment, appId: appId, key: key)
    }
}
