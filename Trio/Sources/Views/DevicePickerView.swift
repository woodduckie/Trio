import LoopKitUI
import SwiftUI

/// A sheet for choosing a CGM or pump to set up, grouped by manufacturer.
///
/// The view never dismisses itself. It reports the choice through `onSelect` and lets the presenter dismiss, so
/// the device setup sheet is only presented once this one is fully gone — presenting a sheet from another sheet
/// mid-dismissal is silently dropped by SwiftUI.
struct DevicePickerView<Entry: DeviceCatalogEntry>: View {
    let title: String
    let entries: [Entry]
    let onSelect: (Entry) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @Environment(AppState.self) private var appState

    private var sections: [(manufacturer: DeviceManufacturer, entries: [Entry])] {
        DeviceCatalog.sections(for: entries)
    }

    var body: some View {
        NavigationView {
            List {
                ForEach(sections, id: \.manufacturer) { section in
                    Section(header: Text(section.manufacturer.displayName)) {
                        ForEach(section.entries) { entry in
                            Button {
                                onSelect(entry)
                            } label: {
                                DevicePickerRow(entry: entry)
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("devicePickerItem-\(entry.id)")
                        }
                    }
                    .listRowBackground(Color.chart)
                }
            }
            .scrollContentBackground(.hidden)
            .background(appState.trioBackgroundColor(for: colorScheme))
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}

private struct DevicePickerRow<Entry: DeviceCatalogEntry>: View {
    let entry: Entry

    var body: some View {
        HStack(spacing: 12) {
            DeviceIconView(entry: entry)

            VStack(alignment: .leading, spacing: 2) {
                Text(entry.name)
                    .font(.headline)
                    .foregroundColor(.primary)

                if let models = entry.supportedModelsLine {
                    Text(models)
                        .font(.callout)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundColor(Color(UIColor.tertiaryLabel))
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

/// Resolves device artwork: Trio's own asset, then the kit's onboarding image, then an SF Symbol.
private struct DeviceIconView<Entry: DeviceCatalogEntry>: View {
    let entry: Entry

    var body: some View {
        Group {
            // UIImage(named:) rather than Image(_:) so a missing asset is detectable — SwiftUI renders an
            // empty box instead of failing, which would silently defeat the fallback chain.
            if let image = UIImage(named: entry.iconAssetName) ?? entry.onboardingImage {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .padding(6)
            } else {
                Image(systemName: entry.fallbackSymbolName)
                    .font(.system(size: 20))
                    .foregroundColor(.accentColor)
            }
        }
        .frame(width: 44, height: 44)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(UIColor.tertiarySystemFill))
        )
    }
}
