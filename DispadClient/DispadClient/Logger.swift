import Foundation
import os

enum Log {
    private static let subsystem = "com.dispad.client"

    static let transport = Logger(subsystem: subsystem, category: "transport")
    static let decode    = Logger(subsystem: subsystem, category: "decode")
    static let pipeline  = Logger(subsystem: subsystem, category: "pipeline")
    static let stats     = Logger(subsystem: subsystem, category: "stats")
}
