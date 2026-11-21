import SwiftUI
import UIKit

/// A number typed as text, so it is never lost when you tap Save while the keyboard is up.
struct NumberField: View {
    let label: String
    @Binding var value: Double
    var unit: String = ""
    var decimals: Int = 0
    var prefix: String? = nil

    @State private var text = ""

    var body: some View {
        HStack {
            Text(label)
            Spacer()
            if let prefix { Text(prefix).foregroundStyle(.secondary) }
            TextField("0", text: $text)
                .keyboardType(decimals > 0 ? .decimalPad : .numberPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 100)
            if !unit.isEmpty { Text(unit).foregroundStyle(.secondary) }
        }
        .onAppear { text = format(value) }
        .onChange(of: text) {
            let parsed = Double(text.replacingOccurrences(of: ",", with: ".")) ?? 0
            if parsed != value { value = parsed }
        }
        .onChange(of: value) {
            let parsed = Double(text.replacingOccurrences(of: ",", with: ".")) ?? 0
            if parsed != value { text = format(value) }
        }
    }

    private func format(_ v: Double) -> String {
        if v == 0 { return "" }
        return decimals > 0 ? String(format: "%.\(decimals)f", v) : String(Int(v.rounded()))
    }
}

struct DishThumb: View {
    let dish: Dish?
    let meal: Meal?
    var size: CGFloat = 46
    var preview: UIImage? = nil

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
        Color.clear
            .frame(width: size, height: size)
            .background(shape.fill(Theme.tile))
            .overlay {
                if let img = preview {
                    Image(uiImage: img).resizable().scaledToFill().frame(width: size, height: size).clipShape(shape)
                } else if let img = ImageStore.cutoutImage(dish?.cutout) {
                    Image(uiImage: img).resizable().scaledToFit().padding(size * 0.06)
                } else if let img = ImageStore.load(meal?.thumb) {
                    Image(uiImage: img).resizable().scaledToFill().frame(width: size, height: size).clipShape(shape)
                } else {
                    Image(systemName: "fork.knife").font(.system(size: size * 0.36)).foregroundStyle(.secondary)
                }
            }
    }
}

struct MealRow: View {
    let meal: Meal

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(meal.caption).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            HStack(spacing: 8) {
                if meal.dishes.isEmpty {
                    DishThumb(dish: nil, meal: meal)
                } else {
                    ForEach(meal.dishes.prefix(4)) { d in DishThumb(dish: d, meal: meal) }
                    if meal.dishes.count > 4 {
                        Text("+\(meal.dishes.count - 4)").font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 4)
                VStack(alignment: .trailing, spacing: 2) {
                    Text(Fmt.kcal(meal.kcal)).font(.subheadline.weight(.semibold))
                    if meal.cost > 0 {
                        Text(Fmt.rm(meal.cost)).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.card))
        .contentShape(Rectangle())
    }
}

struct DishEditor: View {
    @State var dish: Dish
    var onSave: (Dish) -> Void
    var onDelete: (() -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @State private var estimating = false
    @State private var errorText: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Dish name, e.g. nasi lemak ayam", text: $dish.name)
                }
                Section {
                    NumberField(label: "Calories", value: $dish.kcal, unit: "kcal")
                    NumberField(label: "Protein", value: $dish.protein, unit: "g")
                    NumberField(label: "Carbs", value: $dish.carbs, unit: "g")
                    NumberField(label: "Fat", value: $dish.fat, unit: "g")
                } header: {
                    Text("Nutrition (estimate)")
                }
                Section {
                    Button {
                        Task { await estimate() }
                    } label: {
                        HStack {
                            Label("Estimate from the name with AI", systemImage: "sparkles")
                            if estimating { Spacer(); ProgressView() }
                        }
                    }
                    .disabled(estimating || dish.name.trimmingCharacters(in: .whitespaces).isEmpty)
                    if let errorText {
                        Text(errorText).font(.footnote).foregroundStyle(.red)
                    }
                }
                if let onDelete {
                    Section {
                        Button("Remove dish", role: .destructive) {
                            onDelete()
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle(dish.name.isEmpty ? "New dish" : "Edit dish")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(dish)
                        dismiss()
                    }
                }
            }
        }
    }

    private func estimate() async {
        estimating = true
        errorText = nil
        do {
            let found = try await ClaudeClient.estimate(dish.name)
            if !found.isEmpty {
                dish.kcal = found.reduce(0) { $0 + ($1.kcal ?? 0) }
                dish.protein = found.reduce(0) { $0 + ($1.protein_g ?? 0) }
                dish.carbs = found.reduce(0) { $0 + ($1.carbs_g ?? 0) }
                dish.fat = found.reduce(0) { $0 + ($1.fat_g ?? 0) }
            } else {
                errorText = "Claude didn't recognise that as food."
            }
        } catch {
            errorText = error.localizedDescription
        }
        estimating = false
    }
}

struct PhotoViewer: View {
    let image: UIImage
    @Environment(\.dismiss) private var dismiss
    @State private var scale: CGFloat = 1

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .scaleEffect(scale)
                .gesture(MagnificationGesture().onChanged { scale = max(1, $0) }.onEnded { _ in withAnimation { scale = 1 } })
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            Button { dismiss() } label: {
                Image(systemName: "xmark").font(.headline).foregroundStyle(.white)
                    .frame(width: 40, height: 40).background(Circle().fill(.white.opacity(0.2)))
            }
            .padding()
        }
    }
}
