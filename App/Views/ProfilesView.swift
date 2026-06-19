import SwiftUI

struct ProfilesView: View {
    @EnvironmentObject var store: ConfigStore
    @State private var showingImport = false
    @State private var editing: Profile?

    var body: some View {
        NavigationStack {
            ZStack {
                AuroraBackground()

                if store.profiles.isEmpty {
                    emptyState
                } else {
                    List {
                        ForEach(store.profiles) { p in
                            row(for: p)
                                .listRowBackground(Color.clear)
                                .listRowSeparator(.hidden)
                                .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                    Button(role: .destructive) { store.delete(p) } label: {
                                        Label("Удалить", systemImage: "trash")
                                    }
                                    Button { editing = p } label: {
                                        Label("Изменить", systemImage: "slider.horizontal.3")
                                    }
                                    .tint(Theme.blue)
                                }
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                }
            }
            .navigationTitle("Профили")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { showingImport = true } label: {
                        Image(systemName: "plus.circle.fill").font(.title3)
                    }
                }
            }
            .sheet(isPresented: $showingImport) { ImportView() }
            .sheet(item: $editing) { p in
                NavigationStack { ProfileEditView(profile: p) }
            }
        }
    }

    private func row(for p: Profile) -> some View {
        let active = store.activeProfileID == p.id
        return Button {
            store.setActive(p)
        } label: {
            HStack(spacing: 13) {
                Image(systemName: p.carrier.glyph)
                    .font(.title3)
                    .foregroundStyle(p.carrier.tint)
                    .frame(width: 44, height: 44)
                    .background(p.carrier.tint.opacity(0.15), in: RoundedRectangle(cornerRadius: 12))

                VStack(alignment: .leading, spacing: 5) {
                    Text(p.name).font(.body.weight(.semibold))
                        .foregroundStyle(Theme.textPrimary)
                    HStack(spacing: 6) {
                        PillLabel(text: p.carrier.rawValue, color: p.carrier.tint)
                        PillLabel(text: p.transport.title, color: Theme.blue)
                    }
                    Text(p.roomID)
                        .font(.caption2).foregroundStyle(Theme.textSecondary)
                        .lineLimit(1).truncationMode(.middle)
                }
                Spacer(minLength: 4)

                if active {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(Theme.statusOn)
                }
            }
            .glassCard(padding: 13)
            .overlay(
                RoundedRectangle(cornerRadius: Theme.radius, style: .continuous)
                    .strokeBorder(active ? AnyShapeStyle(Theme.aurora) : AnyShapeStyle(Color.clear),
                                  lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "tray.full")
                .font(.system(size: 52))
                .foregroundStyle(Theme.teal.opacity(0.7))
            Text("Нет профилей").font(.title3.weight(.semibold))
                .foregroundStyle(Theme.textPrimary)
            Text("Добавь профиль по ссылке olcrtc:// или вручную — кнопка «+» справа сверху.")
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
            Button { showingImport = true } label: {
                Label("Добавить профиль", systemImage: "plus")
            }
            .buttonStyle(GlassButtonStyle())
            .padding(.top, 4)
        }
        .padding(32)
    }
}
