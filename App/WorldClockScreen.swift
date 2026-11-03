import IpduoClockCore
import SwiftUI

struct WorldClockScreen: View {
    @EnvironmentObject private var model: AppModel
    @State private var adding = false
    @State private var columns = NavigationSplitViewVisibility.automatic

    var body: some View {
        NavigationSplitView {
            List(selection: $model.selectedCityID) {
                HereCard()
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                ForEach(model.cities) { city in
                    WorldCityCard(city: city, prominent: false)
                        .tag(city.id)
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                }
                .onDelete(perform: model.removeCities)
            }
            .listStyle(.plain)
            .navigationTitle("World")
            .background(StageBackground(tint: model.accentColor))
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        adding = true
                    } label: {
                        Label("Add City", systemImage: "plus")
                    }
                }
                .duoPriorityHigh()
                ToolbarItem(placement: .automatic) {
                    Button {
                        model.settingsPresented = true
                    } label: {
                        Label("Settings", systemImage: "gearshape")
                    }
                }
                .duoPriorityLow()
            }
        } detail: {
            if let id = model.selectedCityID, let city = model.city(id: id) {
                CityDetail(city: city)
            } else {
                ContentUnavailableView(
                    "World Clock",
                    systemImage: "globe",
                    description: Text("Add a city to see its time, day and night, and how far ahead it is.")
                )
            }
        }
        .navigationSplitViewStyle(.balanced)
        .navigationSplitViewColumnVisibility($columns)
        .onAppear {
            if ScreenshotSession.screen?.hasPrefix("regular-") == true {
                columns = .all
            }
        }
        .sheet(isPresented: $adding) {
            CityPicker()
        }
    }
}

private struct CityDetail: View {
    var city: WorldCity
    @EnvironmentObject private var model: AppModel

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let zone = city.timeZone ?? .current
            let daylight = Solar.daylight(
                latitude: city.latitude,
                longitude: city.longitude,
                on: context.date,
                timeZone: zone
            )
            let day = WorldTime.isDaylight(
                at: context.date,
                timeZone: zone,
                latitude: city.latitude,
                longitude: city.longitude
            )
            let offset = WorldTime.offset(from: .current, to: zone, at: context.date)
            ZStack {
                StageBackground(tint: model.accentColor)
                VStack(spacing: 18) {
                    Image(systemName: day ? "sun.max.fill" : "moon.stars.fill")
                        .font(.system(size: 42))
                        .foregroundStyle(day ? Color.orange : model.accentColor)
                        .accessibilityLabel(day ? "Day" : "Night")
                    Text(city.name)
                        .font(.largeTitle.weight(.semibold))
                        .multilineTextAlignment(.center)
                    Text(city.region)
                        .foregroundStyle(.secondary)
                    Text(ClockFormat.time(from: context.date, use24Hour: model.use24Hour, includingSeconds: model.showSeconds))
                        .font(.system(size: 320, weight: .thin, design: .rounded))
                        .minimumScaleFactor(0.05)
                        .lineLimit(1)
                        .monospacedDigit()
                        .padding(.horizontal)
                    Text(offset.summary)
                        .font(.title3.weight(.medium))
                        .foregroundStyle(.secondary)
                    if let daylight {
                        VStack(spacing: 8) {
                            LabeledContent("Sunrise") {
                                Text(ClockFormat.time(from: daylight.sunrise, use24Hour: model.use24Hour))
                                    .monospacedDigit()
                            }
                            .accessibilityIdentifier("sunrise")
                            LabeledContent("Sunset") {
                                Text(ClockFormat.time(from: daylight.sunset, use24Hour: model.use24Hour))
                                    .monospacedDigit()
                            }
                        }
                        .padding()
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .padding(.horizontal)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding()
            }
        }
        .navigationTitle(city.name)
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct CityPicker: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    private var choices: [WorldCity] {
        let added = Set(model.cityIDs)
        let base = CityCatalog.all.filter { !added.contains($0.id) }
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return base }
        return base.filter {
            $0.name.localizedCaseInsensitiveContains(trimmed) || $0.region.localizedCaseInsensitiveContains(trimmed)
        }
    }

    var body: some View {
        NavigationStack {
            List(choices) { city in
                Button {
                    Haptics.tap(enabled: model.hapticsEnabled)
                    model.addCity(city)
                    dismiss()
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(city.name)
                        Text(city.region)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .searchable(text: $query, prompt: "City or region")
            .navigationTitle("Add City")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Label("Close", systemImage: "xmark")
                    }
                }
                .duoPriorityHigh()
            }
        }
    }
}
