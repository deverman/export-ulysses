enum AppDistribution {
    static var isAppStore: Bool {
        #if APP_STORE
        true
        #else
        false
        #endif
    }

    static var supportsAutomaticBackupDiscovery: Bool {
        !isAppStore
    }
}
