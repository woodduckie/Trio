// The *UI modules are imported for the CGMManagerUI/PumpManagerUI conformances they declare; without them the
// manager types in this file are not usable as picker entries.
import AccuChekKit
import CGMBLEKit
import CGMBLEKitUI
import DanaKit
import EversenseKit
import Foundation
import G7SensorKit
import G7SensorKitUI
import LibreLoop
import LibreLoopUI
import LibreTransmitter
import LibreTransmitterUI
import LoopKit
import LoopKitUI
import MedtrumKit
import MinimedKit
import MinimedKitUI
import MockKit
import MockKitUI
import OmnipodKit
import UIKit

/// Single source of truth for every CGM and pump Trio can pair with.
///
/// Loop discovers this metadata at runtime from plugin bundle `Info.plist` keys. Trio statically links every
/// kit, so the metadata lives here instead. Adding a device means adding one entry to this file.
///
/// This is intentionally a plain `enum` with no `Resolver` dependency: `BasePluginManager` and
/// `BaseDeviceDataManager` both read it during `injectServices`, so it must not itself be `Injectable`.
enum DeviceCatalog {}

// MARK: - Manufacturer

/// Section grouping for the device picker.
enum DeviceManufacturer: CaseIterable {
    case abbott
    case dexcom
    case insulet
    case medtronic
    case medtrum
    case roche
    case senseonics
    case sooil
    case otherSources
    case simulator

    /// Brand names are deliberately not localized; only the two synthetic groups are.
    var displayName: String {
        switch self {
        case .abbott: return "Abbott"
        case .dexcom: return "Dexcom"
        case .insulet: return "Insulet"
        case .medtronic: return "Medtronic"
        case .medtrum: return "Medtrum"
        case .roche: return "Roche"
        case .senseonics: return "Senseonics"
        case .sooil: return "SOOIL"
        case .otherSources: return String(localized: "Other Sources", comment: "Device picker section for data relays")
        case .simulator: return String(localized: "Simulator", comment: "Device picker section for simulated devices")
        }
    }

    /// Real hardware sorts alphabetically first, then relays, then simulators.
    var sortRank: Int {
        switch self {
        case .otherSources: return 1
        case .simulator: return 2
        default: return 0
        }
    }
}

// MARK: - Entry protocol

/// Display metadata shared by CGM and pump entries so one picker view can render both.
protocol DeviceCatalogEntry: Identifiable, Hashable {
    var id: String { get }
    var manufacturer: DeviceManufacturer { get }
    /// Bold first line, e.g. "Omnipod".
    var name: String { get }
    /// Secondary line, e.g. ["Classic", "DASH", "5"]. Empty collapses the row to one line.
    var supportedModels: [String] { get }
    var iconAssetName: String { get }
    /// Fallback artwork from the statically linked kit.
    var onboardingImage: UIImage? { get }
    var fallbackSymbolName: String { get }
    /// False for the CGM `.none` entry, which `listOfCGM` needs but the picker must never offer.
    var isSelectableInPicker: Bool { get }
}

extension DeviceCatalogEntry {
    var iconAssetName: String { "device_icons/\(id)" }

    /// Comma-joined model list for the picker sub-line and the settings hint text.
    var supportedModelsLine: String? {
        supportedModels.isEmpty ? nil : supportedModels.joined(separator: ", ")
    }

    var hintLine: String {
        guard let models = supportedModelsLine else { return name }
        return "\(name) (\(models))"
    }
}

// MARK: - CGM entries

struct CGMCatalogEntry: DeviceCatalogEntry {
    /// Trio drives CGMs two ways: LoopKit manager types, and its own non-LoopKit glucose sources.
    enum Source: Hashable {
        /// Backed by a `CGMType` case other than `.plugin`.
        case native(CGMType)
        /// Backed by a statically linked `CGMManagerUI`; persisted as `CGMType.plugin`.
        case managed(CGMManagerUI.Type)

        /// The value persisted to `TrioSettings.cgm`.
        var cgmType: CGMType {
            switch self {
            case let .native(type): return type
            case .managed: return .plugin
            }
        }

        /// The value persisted to `TrioSettings.cgmPluginIdentifier` for managed sources.
        var id: String {
            switch self {
            case let .native(type): return type.rawValue
            case let .managed(manager): return manager.pluginIdentifier
            }
        }

        var managerType: CGMManagerUI.Type? {
            guard case let .managed(manager) = self else { return nil }
            return manager
        }

        static func == (lhs: Source, rhs: Source) -> Bool { lhs.id == rhs.id }
        func hash(into hasher: inout Hasher) { hasher.combine(id) }
    }

    let source: Source
    let manufacturer: DeviceManufacturer
    private let rawName: String?
    let supportedModels: [String]

    var id: String { source.id }
    var cgmType: CGMType { source.cgmType }
    var managerType: CGMManagerUI.Type? { source.managerType }

    /// Localized names must be computed, not stored: a `String(localized:)` baked into a `static let` resolves
    /// once per process and would not follow an in-session language change.
    var name: String { rawName ?? source.cgmType.displayName }

    /// Manager-backed sources have no meaningful `CGMType.subtitle` (they all share `.plugin`), so they fall
    /// back to their own name, matching what `BasePluginManager` produced before.
    var subtitle: String {
        if let models = supportedModelsLine { return models }
        return source.managerType == nil ? source.cgmType.subtitle : name
    }

    var onboardingImage: UIImage? { source.managerType?.onboardingImage }
    var fallbackSymbolName: String { "sensor.tag.radiowaves.forward" }
    var isSelectableInPicker: Bool { source.cgmType != .none }

    init(
        _ source: Source,
        manufacturer: DeviceManufacturer,
        name: String? = nil,
        supportedModels: [String] = []
    ) {
        self.source = source
        self.manufacturer = manufacturer
        rawName = name
        self.supportedModels = supportedModels
    }
}

// MARK: - Pump entries

struct PumpCatalogEntry: DeviceCatalogEntry {
    let manager: PumpManagerUI.Type
    let manufacturer: DeviceManufacturer
    let name: String
    let supportedModels: [String]

    /// Identifiers written by older managers that this entry now handles.
    ///
    /// Omnipod carries "Omni" so that pump state persisted by the retired OmniKit ("Omnipod") and OmniBLE
    /// ("Omnipod-DASH") managers still resolves to the universal OmnipodKit manager.
    let legacyIdentifierPrefixes: [String]

    let allowedInsulinTypes: [InsulinType]

    var id: String { manager.pluginIdentifier }
    var onboardingImage: UIImage? { manager.onboardingImage }
    var fallbackSymbolName: String { "ivfluid.bag" }
    var isSelectableInPicker: Bool { true }

    init(
        _ manager: PumpManagerUI.Type,
        manufacturer: DeviceManufacturer,
        name: String,
        supportedModels: [String] = [],
        legacyIdentifierPrefixes: [String] = [],
        allowedInsulinTypes: [InsulinType] = DeviceCatalog.defaultAllowedInsulinTypes
    ) {
        self.manager = manager
        self.manufacturer = manufacturer
        self.name = name
        self.supportedModels = supportedModels
        self.legacyIdentifierPrefixes = legacyIdentifierPrefixes
        self.allowedInsulinTypes = allowedInsulinTypes
    }

    static func == (lhs: PumpCatalogEntry, rhs: PumpCatalogEntry) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

// MARK: - The catalog

extension DeviceCatalog {
    static let defaultAllowedInsulinTypes: [InsulinType] = [.apidra, .humalog, .novolog, .fiasp, .lyumjev]

    /// Order here is the order shown in the picker, within each manufacturer section.
    static let cgms: [CGMCatalogEntry] = [
        CGMCatalogEntry(.native(.none), manufacturer: .otherSources),

        // Both Libre names carry their variants inline, matching the titles the driver authors chose upstream.
        CGMCatalogEntry(
            .managed(LibreTransmitterManagerV3.self),
            manufacturer: .abbott,
            name: "FreeStyle Libre 1 / 2 / 2+"
        ),
        // "(Beta)" stays in the bold first line: it is a maturity warning about a driver feeding dosing
        // decisions, so it must not be demoted to the secondary line.
        CGMCatalogEntry(
            .managed(LibreLoopCGMManager.self),
            manufacturer: .abbott,
            name: "FreeStyle Libre 3 / 3+ (Beta)"
        ),

        // Dexcom rebrands rather than versioning, so the "/" names carry the variants and a sub-line would
        // just repeat them.
        CGMCatalogEntry(.managed(G5CGMManager.self), manufacturer: .dexcom, name: "Dexcom G5"),
        CGMCatalogEntry(.managed(G6CGMManager.self), manufacturer: .dexcom, name: "Dexcom G6 / ONE"),
        CGMCatalogEntry(.managed(G7CGMManager.self), manufacturer: .dexcom, name: "Dexcom G7 / ONE+"),

        CGMCatalogEntry(
            .native(.enlite),
            manufacturer: .medtronic,
            name: "Medtronic Enlite",
            supportedModels: ["MiniLink transmitter"]
        ),

        CGMCatalogEntry(
            .managed(AccuChekCgmManager.self),
            manufacturer: .roche,
            name: "Accu-Chek SmartGuide"
        ),

        CGMCatalogEntry(
            .managed(EversenseCGMManager.self),
            manufacturer: .senseonics,
            name: "Eversense",
            supportedModels: ["E3", "E365"]
        ),

        CGMCatalogEntry(.native(.nightscout), manufacturer: .otherSources),
        CGMCatalogEntry(.native(.xdrip), manufacturer: .otherSources),

        CGMCatalogEntry(.native(.simulator), manufacturer: .simulator)
    ]

    static let pumps: [PumpCatalogEntry] = [
        PumpCatalogEntry(
            OmniPumpManager.self,
            manufacturer: .insulet,
            name: "Omnipod",
            supportedModels: ["Classic", "DASH", "5"],
            legacyIdentifierPrefixes: ["Omni"]
        ),
        PumpCatalogEntry(
            MinimedPumpManager.self,
            manufacturer: .medtronic,
            name: "MiniMed",
            supportedModels: ["x15", "x22", "x23", "x54"]
        ),
        PumpCatalogEntry(
            MedtrumPumpManager.self,
            manufacturer: .medtrum,
            name: "Medtrum Nano",
            supportedModels: ["200U", "300U"]
        ),
        PumpCatalogEntry(
            DanaKitPumpManager.self,
            manufacturer: .sooil,
            name: "Dana",
            supportedModels: ["DanaRS", "Dana-i"]
        ),
        PumpCatalogEntry(
            MockPumpManager.self,
            manufacturer: .simulator,
            name: String(localized: "Pump Simulator", comment: "Simulated pump in the device picker")
        )
    ]
}

// MARK: - Lookups

extension DeviceCatalog {
    static let cgmManagerEntries: [CGMCatalogEntry] = cgms.filter { $0.managerType != nil }

    static let pumpManagersByIdentifier: [String: PumpManagerUI.Type] = pumps.reduce(into: [:]) { result, entry in
        result[entry.id] = entry.manager
    }

    /// The list backing the CGM settings screen. Includes `.none`; the picker filters it out.
    static var cgmModels: [CGMModel] {
        cgms.map(CGMModel.init)
    }

    static func cgmEntry(id: String) -> CGMCatalogEntry? {
        cgms.first { $0.id == id }
    }

    static func pumpEntry(id: String) -> PumpCatalogEntry? {
        pumps.first { $0.id == id }
    }

    /// Resolves an identifier read back from persisted pump state, including ones written by retired managers.
    ///
    /// Note the identifier used for alert routing is *not* always this one: `AlertCatalogRegistry` keys MiniMed
    /// entries under "Minimed" while `MinimedPumpManager.pluginIdentifier` is "Minimed500". Do not unify them —
    /// see TrioTests/MinimedKitAlertEmissionTests.swift.
    static func pumpEntry(forPersistedIdentifier identifier: String) -> PumpCatalogEntry? {
        if let exact = pumpEntry(id: identifier) {
            return exact
        }
        return pumps.first { entry in
            entry.legacyIdentifierPrefixes.contains { identifier.hasPrefix($0) }
        }
    }

    /// Groups entries into picker sections, ordered by `sortRank` then manufacturer name.
    static func sections<Entry: DeviceCatalogEntry>(
        for entries: [Entry]
    ) -> [(manufacturer: DeviceManufacturer, entries: [Entry])] {
        Dictionary(grouping: entries.filter(\.isSelectableInPicker), by: \.manufacturer)
            .map { (manufacturer: $0.key, entries: $0.value) }
            .sorted { lhs, rhs in
                (lhs.manufacturer.sortRank, lhs.manufacturer.displayName)
                    < (rhs.manufacturer.sortRank, rhs.manufacturer.displayName)
            }
    }
}
