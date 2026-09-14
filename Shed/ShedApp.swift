// Copyright (c) 2026 Kharis Destian Maulana. All rights reserved.
import SwiftUI

@main
struct ShedApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @AppStorage("appLanguage") private var appLanguage = "en"
    @AppStorage("appAppearance") private var appAppearance = "system"
    
    var colorScheme: ColorScheme? {
        if appAppearance == "dark" { return .dark }
        if appAppearance == "light" { return .light }
        return nil
    }
    
    var body: some Scene {
        WindowGroup {
            if hasCompletedOnboarding {
                MainSplitView()
                    .frame(minWidth: 800, minHeight: 600)
                    .environment(\.locale, Locale(identifier: appLanguage))
                    .preferredColorScheme(colorScheme)
            } else {
                OnboardingView()
                    .frame(minWidth: 800, minHeight: 600)
                    .environment(\.locale, Locale(identifier: appLanguage))
                    .preferredColorScheme(colorScheme)
            }
        }
        
        Settings {
            SettingsView()
                .environment(\.locale, Locale(identifier: appLanguage))
                .preferredColorScheme(colorScheme)
        }
    }
}
