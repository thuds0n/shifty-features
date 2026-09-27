//
//  BrightnessSystemClient+Shifty.swift
//  Shifty
//
//  Created by Enrico Ghirardi on 02/01/2018.
//

import Foundation

extension BrightnessSystemClient {
    func sunriseSunsetData() -> [String: Any]? {
        if let sunriseSunsetProperty = copyProperty(forKey: "BlueLightSunSchedule" as CFString),
            let sunriseSunsetDict = sunriseSunsetProperty as? [String: Any] {
            return sunriseSunsetDict
        }
        return nil
    }
    
    private func sunriseSunsetProperty(forKey key: String) -> Any? {
        if let data = sunriseSunsetData(),
            let property = data[key] {
            return property
        }
        return nil
    }
    
    var sunrise: Date? {
        sunriseSunsetProperty(forKey: "sunrise") as? Date
    }

    var sunset: Date? {
        sunriseSunsetProperty(forKey: "sunset") as? Date
    }
}
