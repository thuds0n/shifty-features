import Foundation

protocol DisplayCalibrationStoring: AnyObject {
    var selectiveShiftDisplayIDs: Set<String> { get set }
    func warmthOffset(for displayIdentifier: String) -> Int
    func setWarmthOffset(_ offset: Int, for displayIdentifier: String)
}

final class UserDefaultsDisplayCalibrationStore: DisplayCalibrationStoring {
    private enum Keys {
        static let offsets = "displayWarmthOffsets"
        static let selectiveIDs = "selectiveShiftDisplayIDs"
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var selectiveShiftDisplayIDs: Set<String> {
        get { Set(defaults.stringArray(forKey: Keys.selectiveIDs) ?? []) }
        set { defaults.set(Array(newValue), forKey: Keys.selectiveIDs) }
    }

    func warmthOffset(for displayIdentifier: String) -> Int {
        let offsets = defaults.dictionary(forKey: Keys.offsets) as? [String: Int] ?? [:]
        return offsets[displayIdentifier] ?? 0
    }

    func setWarmthOffset(_ offset: Int, for displayIdentifier: String) {
        var offsets = defaults.dictionary(forKey: Keys.offsets) as? [String: Int] ?? [:]
        offsets[displayIdentifier] = offset
        defaults.set(offsets, forKey: Keys.offsets)
    }
}
