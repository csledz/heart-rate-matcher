import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject private var store: RideStore
    @State private var isImporting = false
    @State private var rideAID: Ride.ID?
    @State private var rideBID: Ride.ID?

    private static let fitType = UTType(filenameExtension: "fit") ?? .data
    private static let gpxType = UTType(filenameExtension: "gpx") ?? .xml

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                rideListSection
                Divider()
                pairingSection
            }
            .navigationTitle("Heart Rate Matcher")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        isImporting = true
                    } label: {
                        Label("Import", systemImage: "square.and.arrow.down")
                    }
                }
            }
            .fileImporter(
                isPresented: $isImporting,
                allowedContentTypes: [Self.fitType, Self.gpxType, .xml, .data],
                allowsMultipleSelection: true
            ) { result in
                handleImport(result: result)
            }
            .alert(
                "Import error",
                isPresented: Binding(
                    get: { store.lastError != nil },
                    set: { if !$0 { store.lastError = nil } }
                )
            ) {
                Button("OK", role: .cancel) { store.lastError = nil }
            } message: {
                Text(store.lastError ?? "")
            }
        }
    }

    private var rideListSection: some View {
        Group {
            if store.rides.isEmpty {
                emptyState
            } else {
                List {
                    ForEach(store.rides) { ride in
                        RideRow(ride: ride)
                    }
                    .onDelete { store.remove(at: $0) }
                }
                .listStyle(.insetGrouped)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "bicycle")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("Import a .fit or .gpx ride to get started")
                .font(.headline)
            Text("Tap the import button in the top-right.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var pairingSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Merge two rides")
                .font(.headline)
            HStack {
                ridePicker(label: "Ride A", selection: $rideAID, exclude: rideBID)
                ridePicker(label: "Ride B", selection: $rideBID, exclude: rideAID)
            }
            NavigationLink {
                if let a = store.ride(with: rideAID ?? UUID()),
                   let b = store.ride(with: rideBID ?? UUID()) {
                    MergeView(rideA: a, rideB: b)
                } else {
                    Text("Pick two different rides above.")
                }
            } label: {
                Label("Configure merge", systemImage: "slider.horizontal.3")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(rideAID == nil || rideBID == nil || rideAID == rideBID)
        }
        .padding()
        .background(.thinMaterial)
    }

    private func ridePicker(
        label: String,
        selection: Binding<Ride.ID?>,
        exclude: Ride.ID?
    ) -> some View {
        Menu {
            ForEach(store.rides) { ride in
                Button {
                    selection.wrappedValue = ride.id
                } label: {
                    if ride.id == exclude {
                        Label(ride.name, systemImage: "exclamationmark.triangle")
                    } else {
                        Text(ride.name)
                    }
                }
                .disabled(ride.id == exclude)
            }
        } label: {
            VStack(alignment: .leading) {
                Text(label).font(.caption).foregroundStyle(.secondary)
                Text(selectedName(selection.wrappedValue) ?? "Choose…")
                    .lineLimit(1)
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 8))
        }
    }

    private func selectedName(_ id: Ride.ID?) -> String? {
        guard let id, let ride = store.ride(with: id) else { return nil }
        return ride.name
    }

    private func handleImport(result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            for url in urls {
                store.importRide(from: url)
            }
        case .failure(let err):
            store.lastError = err.localizedDescription
        }
    }
}

private struct RideRow: View {
    let ride: Ride

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(ride.name).font(.headline)
            HStack(spacing: 8) {
                Label(ride.sourceFormat.rawValue.uppercased(), systemImage: "doc")
                    .font(.caption2)
                Text("\(ride.samples.count) samples")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(durationString)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Text(channelSummary)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }

    private var durationString: String {
        let s = Int(ride.duration)
        let h = s / 3600, m = (s % 3600) / 60, sec = s % 60
        return h > 0
            ? String(format: "%d:%02d:%02d", h, m, sec)
            : String(format: "%d:%02d", m, sec)
    }

    private var channelSummary: String {
        let names = ride.availableChannels
            .sorted(by: { $0.rawValue < $1.rawValue })
            .map(\.displayName)
        return names.isEmpty ? "no channels" : names.joined(separator: " · ")
    }
}

#Preview {
    ContentView().environmentObject(RideStore())
}
