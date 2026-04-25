import SwiftUI
import UniformTypeIdentifiers

struct MergeView: View {
    let rideA: Ride
    let rideB: Ride

    @State private var configuration: MergeConfiguration
    @State private var exportFormat: RideSourceFormat = .gpx
    @State private var exportURL: URL?
    @State private var showShareSheet = false
    @State private var lastError: String?

    init(rideA: Ride, rideB: Ride) {
        self.rideA = rideA
        self.rideB = rideB
        _configuration = State(initialValue: .defaultConfiguration(for: rideA, rideB: rideB))
    }

    var body: some View {
        Form {
            Section("Primary timeline") {
                Picker("Output timestamps follow", selection: $configuration.primary) {
                    Text(rideA.name).tag(RideSource.rideA)
                    Text(rideB.name).tag(RideSource.rideB)
                }
                Picker("Alignment", selection: $configuration.alignment) {
                    ForEach(AlignmentStrategy.allCases) { strategy in
                        Text(strategy.label).tag(strategy)
                    }
                }
            }

            Section("Speed tuning") {
                SpeedTuner(label: rideA.name, transform: $configuration.transformA)
                SpeedTuner(label: rideB.name, transform: $configuration.transformB)
                Text("A positive percentage compresses the time axis (ride finishes faster) and scales the recorded speed channel by the same factor.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Channel sources") {
                ForEach(RideChannel.allCases) { channel in
                    ChannelRow(
                        channel: channel,
                        rideA: rideA,
                        rideB: rideB,
                        selection: Binding(
                            get: { configuration.source(for: channel) },
                            set: { configuration.setSource($0, for: channel) }
                        )
                    )
                }
            }

            Section("Export format") {
                Picker("Format", selection: $exportFormat) {
                    Text("GPX").tag(RideSourceFormat.gpx)
                    Text("FIT").tag(RideSourceFormat.fit)
                }
                .pickerStyle(.segmented)
                Text(exportFormat == .fit
                     ? "FIT preserves power, cadence, and HR with full precision and uploads directly to Garmin Connect."
                     : "GPX is a text format accepted by Strava and most platforms.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Button {
                    runExport()
                } label: {
                    Label(
                        "Merge & export \(exportFormat.rawValue.uppercased())",
                        systemImage: "square.and.arrow.up"
                    )
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .navigationTitle("Configure merge")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showShareSheet) {
            if let url = exportURL {
                ShareSheet(items: [url])
            }
        }
        .alert(
            "Export failed",
            isPresented: Binding(
                get: { lastError != nil },
                set: { if !$0 { lastError = nil } }
            )
        ) {
            Button("OK", role: .cancel) { lastError = nil }
        } message: {
            Text(lastError ?? "")
        }
    }

    private func runExport() {
        do {
            let merged = RideMerger().merge(rideA: rideA, rideB: rideB, configuration: configuration)
            let data: Data
            let ext: String
            switch exportFormat {
            case .gpx:
                data = GPXExporter().export(ride: merged)
                ext = "gpx"
            case .fit:
                data = FITExporter().export(ride: merged)
                ext = "fit"
            }
            let filename = sanitize(merged.name) + "." + ext
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
            try data.write(to: url, options: .atomic)
            exportURL = url
            showShareSheet = true
        } catch {
            lastError = error.localizedDescription
        }
    }

    private func sanitize(_ name: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(.init(charactersIn: " -_"))
        return String(name.unicodeScalars.map { allowed.contains($0) ? Character($0) : "_" })
    }
}

private struct ChannelRow: View {
    let channel: RideChannel
    let rideA: Ride
    let rideB: Ride
    @Binding var selection: RideSource

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(channel.displayName)
                Text(availabilityLabel)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Picker("", selection: $selection) {
                Text("A").tag(RideSource.rideA)
                    .disabled(!rideA.availableChannels.contains(channel))
                Text("B").tag(RideSource.rideB)
                    .disabled(!rideB.availableChannels.contains(channel))
            }
            .pickerStyle(.segmented)
            .frame(width: 110)
        }
    }

    private var availabilityLabel: String {
        let inA = rideA.availableChannels.contains(channel)
        let inB = rideB.availableChannels.contains(channel)
        switch (inA, inB) {
        case (true, true):   return "in both rides"
        case (true, false):  return "only in A"
        case (false, true):  return "only in B"
        case (false, false): return "missing in both"
        }
    }
}

private struct SpeedTuner: View {
    let label: String
    @Binding var transform: RideTransform

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(label).lineLimit(1)
                Spacer()
                Text(formatted)
                    .monospacedDigit()
                    .foregroundStyle(transform.isIdentity ? .secondary : .primary)
            }
            Slider(
                value: Binding(
                    get: { transform.percentDelta },
                    set: { transform.percentDelta = $0 }
                ),
                in: -50...100,
                step: 0.5
            ) {
                Text("Speed")
            } minimumValueLabel: {
                Text("-50%").font(.caption2)
            } maximumValueLabel: {
                Text("+100%").font(.caption2)
            }
            HStack(spacing: 8) {
                Button("Reset") { transform.percentDelta = 0 }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                Stepper("Fine tune", value: Binding(
                    get: { transform.percentDelta },
                    set: { transform.percentDelta = $0 }
                ), in: -50...100, step: 0.5)
                .labelsHidden()
            }
        }
        .padding(.vertical, 2)
    }

    private var formatted: String {
        let delta = transform.percentDelta
        if abs(delta) < 0.05 { return "+0.0% (unchanged)" }
        let sign = delta > 0 ? "+" : ""
        return String(format: "%@%.1f%% speed", sign, delta)
    }
}

private struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
