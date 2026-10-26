import Foundation

/// A store property backed by the store's UserDefaults: reads come from the defaults (or `defaultValue`),
/// writes go straight back and notify SwiftUI. `didSet` observers on the property still run.
/// `clamp` keeps numbers in range on both read and write, so a bad stored value can't leak into the UI.
@propertyWrapper
struct Setting<Value: SettingValue> {
    let key: String
    let defaultValue: Value
    let clamp: ((Value) -> Value)?

    init(wrappedValue: Value, _ key: String, clamp: ((Value) -> Value)? = nil) {
        self.key = key
        self.defaultValue = wrappedValue
        self.clamp = clamp
    }

    @MainActor
    static subscript(
        _enclosingInstance store: SchichtaStore,
        wrapped wrappedKeyPath: ReferenceWritableKeyPath<SchichtaStore, Value>,
        storage storageKeyPath: ReferenceWritableKeyPath<SchichtaStore, Setting<Value>>
    ) -> Value {
        get {
            let setting = store[keyPath: storageKeyPath]
            let value = store.defaults.object(forKey: setting.key).flatMap { Value(storedValue: $0) } ?? setting.defaultValue
            return setting.clamp?(value) ?? value
        }
        set {
            let setting = store[keyPath: storageKeyPath]
            store.objectWillChange.send()
            store.defaults.set((setting.clamp?(newValue) ?? newValue).storedValue, forKey: setting.key)
        }
    }

    @available(*, unavailable, message: "Setting only works on SchichtaStore properties")
    var wrappedValue: Value {
        get { fatalError() }
        set { fatalError() }
    }
}

/// A type a `Setting` can keep in UserDefaults.
protocol SettingValue {
    init?(storedValue: Any)
    var storedValue: Any { get }
}

extension SettingValue {
    init?(storedValue: Any) {
        guard let value = storedValue as? Self else { return nil }
        self = value
    }
    var storedValue: Any { self }
}

extension Int: SettingValue {}
extension Bool: SettingValue {}
extension String: SettingValue {}

/// Enums are stored by their raw value.
extension SettingValue where Self: RawRepresentable, RawValue == String {
    init?(storedValue: Any) {
        guard let raw = storedValue as? String else { return nil }
        self.init(rawValue: raw)
    }
    var storedValue: Any { rawValue }
}

extension AppLanguage: SettingValue {}
extension CheckInMode: SettingValue {}

/// Stored as a sorted array; an empty set reads as missing, so the default applies.
extension Set: SettingValue where Element == Int {
    init?(storedValue: Any) {
        guard let array = storedValue as? [Int], !array.isEmpty else { return nil }
        self.init(array)
    }
    var storedValue: Any { sorted() }
}

/// Stored as JSON data.
extension Array: SettingValue where Element == TrackedRepo {
    init?(storedValue: Any) {
        guard let data = storedValue as? Data, let repos = try? JSONDecoder().decode([TrackedRepo].self, from: data) else { return nil }
        self = repos
    }
    var storedValue: Any { (try? JSONEncoder().encode(self)) ?? Data() }
}
