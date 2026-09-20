import os

// This distribution never writes application diagnostics or lid history.
enum Diagnostics {
    static let geometry = Logger(OSLog.disabled)
    static let lid = Logger(OSLog.disabled)
}
