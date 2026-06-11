import SwiftUI

struct ProfilesView: View {
    @EnvironmentObject var store: ConfigStore
    @State private var showingImport = false

    var body: some View {
        NavigationStack {
            List {
                ForEach(store.profiles) { p in
                    Button {
                        store.setActive(p)
                    } label: {
                        HStack {
                            VStack(alignment: .leading) {
                                Text(p.name).font(.body)
                                Text("\(p.carrier.rawValue) \u{00B7} \(p.transport.rawValue) \u{00B7} \(p.roomID)")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if store.activeProfileID == p.id {
                                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                            }
                        }
                    }
                    .tint(.primary)
                }
                .onDelete { idx in
                    idx.map { store.profiles[$0] }.forEach(store.delete)
                }
            }
            .navigationTitle("Профили")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { showingImport = true } label: { Image(systemName: "plus") }
                }
            }
            .sheet(isPresented: $showingImport) { ImportView() }
            .overlay {
                if store.profiles.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "tray")
                            .font(.largeTitle)
                            .foregroundStyle(.secondary)
                        Text("Нет профилей")
                            .font(.headline)
                        Text("Добавь профиль через olcrtc:// или вручную")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding()
                }
            }
        }
    }
}