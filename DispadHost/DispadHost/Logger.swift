import Foundation
import os

enum Log {
    private static let subsystem = "com.dispad.host"

    static let transport = Logger(subsystem: subsystem, category: "transport")
    static let capture   = Logger(subsystem: subsystem, category: "capture")
    static let encode    = Logger(subsystem: subsystem, category: "encode")
    static let pipeline  = Logger(subsystem: subsystem, category: "pipeline")
    static let stats     = Logger(subsystem: subsystem, category: "stats")
}
