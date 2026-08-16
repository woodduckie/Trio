import Foundation
import LoopKitUI
import Testing
@testable import Trio

@Suite("Device Catalog Tests") struct DeviceCatalogTests {
    // MARK: - Integrity

    @Test("Catalog identifiers are unique") func testIdentifiersAreUnique() {
        let cgmIDs = DeviceCatalog.cgms.map(\.id)
        #expect(Set(cgmIDs).count == cgmIDs.count, "Duplicate CGM identifier in catalog: \(cgmIDs)")

        let pumpIDs = DeviceCatalog.pumps.map(\.id)
        #expect(Set(pumpIDs).count == pumpIDs.count, "Duplicate pump identifier in catalog: \(pumpIDs)")
    }

    @Test("Pump entry ids match their manager's plugin identifier") func testPumpIdentifiersMatchManagers() {
        for entry in DeviceCatalog.pumps {
            #expect(
                entry.id == entry.manager.pluginIdentifier,
                "\(entry.name) id \(entry.id) != \(entry.manager.pluginIdentifier)"
            )
        }
    }

    @Test("Every entry has a display name") func testEntriesHaveNames() {
        for entry in DeviceCatalog.cgms {
            #expect(!entry.name.isEmpty, "CGM \(entry.id) has an empty name")
        }
        for entry in DeviceCatalog.pumps {
            #expect(!entry.name.isEmpty, "Pump \(entry.id) has an empty name")
        }
    }

    // MARK: - Persisted identifier resolution

    @Test("Legacy Omnipod identifiers resolve to the universal Omnipod manager") func testLegacyOmnipodIdentifiers() {
        // OmniKit persisted "Omnipod" and OmniBLE persisted "Omnipod-DASH" before OmnipodKit unified them.
        for identifier in ["Omni", "Omnipod", "Omnipod-DASH"] {
            let entry = DeviceCatalog.pumpEntry(forPersistedIdentifier: identifier)
            #expect(entry?.name == "Omnipod", "\(identifier) should resolve to Omnipod, got \(entry?.name ?? "nil")")
        }
    }

    @Test("MiniMed resolves by its real plugin identifier") func testMinimedIdentifier() {
        // MinimedPumpManager.pluginIdentifier is "Minimed500", not "Minimed".
        #expect(DeviceCatalog.pumpEntry(forPersistedIdentifier: "Minimed500")?.name == "MiniMed")
        #expect(DeviceCatalog.pumpEntry(forPersistedIdentifier: "Minimed") == nil)
    }

    @Test("Unknown identifiers do not resolve") func testUnknownIdentifier() {
        #expect(DeviceCatalog.pumpEntry(forPersistedIdentifier: "NotARealPump") == nil)
    }

    // MARK: - CGM source mapping

    @Test("Managed CGM entries persist as .plugin, native entries persist as themselves") func testCGMSourceMapping() {
        for entry in DeviceCatalog.cgms {
            if entry.managerType != nil {
                #expect(entry.cgmType == .plugin, "\(entry.name) is manager-backed so it must persist as .plugin")
                #expect(entry.id == entry.managerType?.pluginIdentifier)
            } else {
                #expect(entry.cgmType.rawValue == entry.id, "\(entry.name) id must be its CGMType raw value")
            }
        }
    }

    @Test("Every CGMType case is represented in the catalog") func testAllCGMTypesCovered() {
        for type in CGMType.allCases where type != .plugin {
            #expect(
                DeviceCatalog.cgms.contains { $0.cgmType == type },
                "CGMType.\(type.rawValue) is missing from the catalog"
            )
        }
    }

    // MARK: - Picker presentation

    @Test("The 'none' CGM is in the catalog but never offered in the picker") func testNoneIsNotSelectable() {
        #expect(DeviceCatalog.cgms.contains { $0.cgmType == .none }, "listOfCGM needs a .none entry")

        let offered = DeviceCatalog.sections(for: DeviceCatalog.cgms).flatMap(\.entries)
        #expect(!offered.contains { $0.cgmType == .none }, ".none must never render as a picker row")
    }

    @Test("Simulator sections sort last") func testSimulatorSortsLast() {
        let cgmSections = DeviceCatalog.sections(for: DeviceCatalog.cgms)
        #expect(cgmSections.last?.manufacturer == .simulator)

        let pumpSections = DeviceCatalog.sections(for: DeviceCatalog.pumps)
        #expect(pumpSections.last?.manufacturer == .simulator)
    }

    @Test("Data relays sort after hardware but before simulators") func testOtherSourcesRank() {
        #expect(DeviceManufacturer.dexcom.sortRank < DeviceManufacturer.otherSources.sortRank)
        #expect(DeviceManufacturer.otherSources.sortRank < DeviceManufacturer.simulator.sortRank)
    }

    @Test("Sections contain every selectable entry exactly once") func testSectionsArePartition() {
        let selectable = DeviceCatalog.cgms.filter(\.isSelectableInPicker).map(\.id).sorted()
        let sectioned = DeviceCatalog.sections(for: DeviceCatalog.cgms).flatMap(\.entries).map(\.id).sorted()
        #expect(selectable == sectioned)
    }

    // MARK: - Model sub-lines

    @Test("Model sub-lines render as a comma-joined list") func testSupportedModelsLine() {
        let omnipod = DeviceCatalog.pumps.first { $0.name == "Omnipod" }
        #expect(omnipod?.supportedModelsLine == "Classic, DASH, 5")
        #expect(omnipod?.hintLine == "Omnipod (Classic, DASH, 5)")

        let g5 = DeviceCatalog.cgms.first { $0.name == "Dexcom G5" }
        #expect(g5?.supportedModelsLine == nil, "An empty model list must collapse the row to one line")
        #expect(g5?.hintLine == "Dexcom G5")
    }

    // MARK: - Guards against the catalog drifting from its consumers

    @Test("Onboarding pump options cover every non-simulator pump") func testOnboardingOptionsCoverCatalog() {
        // PumpOptionForOnboardingUnits drives basal increment defaults and is maintained separately.
        let catalogCount = DeviceCatalog.pumps.filter { $0.manufacturer != .simulator }.count
        #expect(
            PumpOptionForOnboardingUnits.allCases.count == catalogCount,
            "A pump was added to the catalog without updating PumpOptionForOnboardingUnits"
        )
    }
}
