import SwiftUI

struct MealDetailView: View {
    let mealID: UUID

    @ObservedObject private var store = MealStore.shared
    @Environment(\.dismiss) private var dismiss
    @State private var editing: Dish?
    @State private var addingDish = false
    @State private var showPlaces = false
    @State private var confirmDelete = false
    @State private var showPhoto = false

    private var meal: Meal? { store.meals.first { $0.id == mealID } }

    var body: some View {
        Group {
            if let meal {
                content(meal)
            } else {
                ContentUnavailableView("Meal removed", systemImage: "fork.knife")
            }
        }
        .navigationTitle(meal?.type.title ?? "Meal")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func update(_ change: (inout Meal) -> Void) {
        guard var m = meal else { return }
        change(&m)
        store.upsert(m)
    }

    @ViewBuilder
    private func content(_ meal: Meal) -> some View {
        List {
            Section {
                VStack(spacing: 4) {
                    Text([Fmt.dayShort.string(from: meal.date), Fmt.time.string(from: meal.date), meal.place]
                        .filter { !$0.isEmpty }.joined(separator: " · "))
                        .font(.footnote).foregroundStyle(.secondary)
                    if let img = ImageStore.load(meal.photo) {
                        Image(uiImage: img)
                            .resizable()
                            .scaledToFit()
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .onTapGesture { showPhoto = true }
                    }
                }
                .frame(maxWidth: .infinity)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 6, trailing: 0))

                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("AI estimate").font(.caption).foregroundStyle(Theme.kcalLabel)
                        Text(Fmt.kcal(meal.kcal)).font(.system(size: 26, weight: .bold, design: .rounded)).foregroundStyle(Theme.kcalFG)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 1) {
                        Text("Protein \(Fmt.num(meal.protein)) g")
                        Text("Carbs \(Fmt.num(meal.carbs)) g")
                        Text("Fat \(Fmt.num(meal.fat)) g")
                    }
                    .font(.caption).foregroundStyle(Theme.kcalLabel)
                }
                .padding(14)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.kcalBG))
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
            }

            Section {
                ForEach(meal.dishes) { d in
                    HStack(spacing: 12) {
                        DishThumb(dish: d, meal: meal, size: 46)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(d.name)
                            Text(Fmt.kcal(d.kcal)).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button {
                            update { m in
                                if let i = m.dishes.firstIndex(where: { $0.id == d.id }) { m.dishes[i].favourite.toggle() }
                            }
                        } label: {
                            Image(systemName: d.favourite ? "star.fill" : "star")
                                .foregroundStyle(d.favourite ? Color.orange : Color.secondary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(d.favourite ? "Unstar" : "Star for the monthly recap")
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { editing = d }
                }
                .onDelete { idx in
                    let removed = idx.map { meal.dishes[$0] }
                    removed.forEach { ImageStore.deleteCutout($0.cutout) }
                    update { $0.dishes.remove(atOffsets: idx) }
                }
                Button { addingDish = true } label: { Label("Add a dish", systemImage: "plus") }
            } header: {
                Text("Dishes")
            } footer: {
                Text("Tap a dish to correct its name or calories. Star one to show it in the monthly recap.")
            }

            Section("Details") {
                Picker("Meal", selection: Binding(get: { meal.type }, set: { v in update { $0.type = v } })) {
                    ForEach(MealType.allCases) { Text($0.title).tag($0) }
                }
                DatePicker("Time", selection: Binding(get: { meal.date }, set: { v in update { $0.date = v } }))
                Button { showPlaces = true } label: {
                    HStack {
                        Text("Place").foregroundStyle(Color.primary)
                        Spacer()
                        Text(meal.place.isEmpty ? "Add" : meal.place).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                NumberField(label: "My cost",
                            value: Binding(get: { meal.cost }, set: { v in update { $0.cost = v } }),
                            decimals: 2, prefix: "RM")
                TextField("Note", text: Binding(get: { meal.note }, set: { v in update { $0.note = v } }), axis: .vertical)
            }

            Section {
                Button("Delete meal", role: .destructive) { confirmDelete = true }
            }
        }
        .sheet(item: $editing) { d in
            DishEditor(dish: d, onSave: { new in
                update { m in
                    if let i = m.dishes.firstIndex(where: { $0.id == new.id }) { m.dishes[i] = new }
                }
            }, onDelete: {
                ImageStore.deleteCutout(d.cutout)
                update { m in m.dishes.removeAll { $0.id == d.id } }
            })
        }
        .sheet(isPresented: $addingDish) {
            DishEditor(dish: Dish(), onSave: { new in update { $0.dishes.append(new) } })
        }
        .sheet(isPresented: $showPlaces) {
            PlacePicker(lat: meal.latitude, lon: meal.longitude) { c in
                update { m in
                    m.place = c.name
                    if let la = c.lat, let lo = c.lon { m.latitude = la; m.longitude = lo }
                }
            }
        }
        .confirmationDialog("Delete this meal?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                store.delete(meal)
                dismiss()
            }
        }
        .fullScreenCover(isPresented: $showPhoto) {
            if let img = ImageStore.load(meal.photo) { PhotoViewer(image: img) }
        }
    }
}
