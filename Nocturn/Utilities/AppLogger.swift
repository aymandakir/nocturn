import OSLog

enum AppLogger {
    private static let subsystem = "com.aymandakir.nocturn"

    static let app = Logger(subsystem: subsystem, category: "app")
    static let audio = Logger(subsystem: subsystem, category: "audio")
    static let ui = Logger(subsystem: subsystem, category: "ui")
}
