//
//  Log.swift
//  Shifty
//

import os

private let logger = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "io.natethompson.Shifty",
    category: "general"
)

func logw(_ text: String) {
    logger.info("\(text, privacy: .public)")
}
