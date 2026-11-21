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
            if let prefix { Text(prefix).foregroundStyle(Theme.brown2) }
            TextField("0", text: $text)
                .keyboardType(decimals > 0 ? .decimalPad : .numberPad)
                .multilineTextAlignment(.trailing)
                .font(.q(17, .bold))
                .frame(width: 100)
            if !unit.isEmpty { Text(unit).foregroundStyle(Theme.brown2) }
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

/// A dish shown on a small round plate, like the icon.
struct DishThumb: View {
    let dish: Dish?
    let meal: Meal?
    var size: CGFloat = 50
    var preview: UIImage? = nil

    var body: some View {
        Circle()
            .fill(Color(hex: 0xFFFAF6))
            .overlay(Circle().stroke(Color(hex: 0xF3E4D9), lineWidth: max(1, size * 0.04)).padding(size * 0.2))
            .overlay {
                if let img = preview ?? ImageStore.cutoutImage(dish?.cutout) {
                    Image(uiImage: img).resizable().scaledToFit().padding(size * 0.12)
                } else if let img = ImageStore.load(meal?.thumb) {
                    Image(uiImage: img).resizable().scaledToFill()
                        .frame(width: size * 0.84, height: size * 0.84)
                        .clipShape(Circle())
                } else {
                    Image(systemName: "fork.knife").font(.system(size: size * 0.32, weight: .semibold)).foregroundStyle(Theme.brown3)
                }
            }
            .frame(width: size, height: size)
            .shadow(color: Color(hex: 0x964632).opacity(0.18), radius: 4, y: 2)
    }
}

struct MealRow: View {
    let meal: Meal

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 5) {
                Image(systemName: meal.type.symbol).font(.system(size: 12, weight: .semibold))
                Text(meal.caption).lineLimit(1)
            }
            .font(.system(size: 12.5, weight: .semibold, design: .rounded))
            .foregroundStyle(Theme.brown2)
            HStack(spacing: 8) {
                if meal.dishes.isEmpty {
                    DishThumb(dish: nil, meal: meal)
                } else {
                    ForEach(meal.dishes.prefix(4)) { d in DishThumb(dish: d, meal: meal) }
                    if meal.dishes.count > 4 {
                        Text("+\(meal.dishes.count - 4)").font(.q(13, .bold)).foregroundStyle(Theme.brown2)
                    }
                }
                Spacer(minLength: 4)
                VStack(alignment: .trailing, spacing: 2) {
                    Text(Fmt.kcal(meal.kcal)).font(.q(17, .bold)).foregroundStyle(Theme.brown)
                    if meal.cost > 0 {
                        Text(Fmt.rm(meal.cost)).font(.system(size: 12, weight: .semibold, design: .rounded)).foregroundStyle(Theme.brown2)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .creamCard(padding: 13)
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
    @State private var remember = true

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Dish name, e.g. nasi lemak ayam", text: $dish.name)
                        .font(.q(17, .semibold))
                }
                .listRowBackground(Theme.cream)
                Section {
                    NumberField(label: "Calories", value: $dish.kcal, unit: "kcal")
                    NumberField(label: "Protein", value: $dish.protein, unit: "g")
                    NumberField(label: "Carbs", value: $dish.carbs, unit: "g")
                    NumberField(label: "Fat", value: $dish.fat, unit: "g")
                } header: {
                    Text("Nutrition (estimate)").foregroundStyle(Theme.brown2)
                }
                .listRowBackground(Theme.cream)
                Section {
                    Button {
                        Task { await estimate() }
                    } label: {
                        HStack {
                            Label("Estimate from the name (\(FoodAI.modeTitle))", systemImage: "sparkles")
                                .foregroundStyle(Theme.coral)
                            if estimating { Spacer(); ProgressView() }
                        }
                    }
                    .disabled(estimating || dish.name.trimmingCharacters(in: .whitespaces).isEmpty)
                    Toggle("Remember for next time", isOn: $remember)
                        .tint(Theme.coral)
                    if let errorText {
                        Text(errorText).font(.footnote).foregroundStyle(.red)
                    }
                } footer: {
                    Text("Remembered dishes get these numbers automatically when the AI finds the same name again.")
                        .foregroundStyle(Theme.brown2)
                }
                .listRowBackground(Theme.cream)
                if let onDelete {
                    Section {
                        Button("Remove dish", role: .destructive) {
                            onDelete()
                            dismiss()
                        }
                    }
                    .listRowBackground(Theme.cream)
                }
            }
            .creamList()
            .navigationTitle(dish.name.isEmpty ? "New dish" : "Edit dish")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        if remember { Pantry.shared.remember(dish) }
                        onSave(dish)
                        dismiss()
                    }
                    .fontWeight(.bold)
                }
            }
        }
    }

    private func estimate() async {
        estimating = true
        errorText = nil
        do {
            if let d = try await FoodAI.estimate(dish.name) {
                dish.kcal = d.kcal
                dish.protein = d.protein
                dish.carbs = d.carbs
                dish.fat = d.fat
            } else {
                errorText = "The AI didn't recognise that as food."
            }
        } catch {
            errorText = error.localizedDescription
        }
        estimating = false
    }
}

/// Confirm a packaged product read from its label or barcode, and how much of it you had.
struct ProductSheet: View {
    @State var product: Product
    let source: String
    var onAdd: (Dish, Product) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var servings: Double = 1
    @State private var save = true

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if !source.isEmpty {
                        Label(source, systemImage: "checkmark.seal").foregroundStyle(Theme.coral).font(.q(15, .bold))
                    }
                    TextField("Product name", text: $product.name)
                    TextField("Brand", text: $product.brand)
                    HStack {
                        Text("Serving")
                        Spacer()
                        TextField("1 serving", text: $product.serving).multilineTextAlignment(.trailing)
                    }
                    if let code = product.barcode {
                        HStack { Text("Barcode"); Spacer(); Text(code).foregroundStyle(Theme.brown2) }
                    }
                }
                .listRowBackground(Theme.cream)
                Section {
                    NumberField(label: "Calories", value: $product.kcal, unit: "kcal")
                    NumberField(label: "Protein", value: $product.protein, unit: "g", decimals: 1)
                    NumberField(label: "Carbs", value: $product.carbs, unit: "g", decimals: 1)
                    NumberField(label: "Fat", value: $product.fat, unit: "g", decimals: 1)
                } header: {
                    Text("Per serving (\(product.serving))").foregroundStyle(Theme.brown2)
                }
                .listRowBackground(Theme.cream)
                Section {
                    Stepper(value: $servings, in: 0.25...20, step: 0.25) {
                        HStack {
                            Text("I had")
                            Spacer()
                            Text("\(servings.formatted()) × \(product.serving)").font(.q(16, .bold))
                        }
                    }
                    HStack {
                        Text("That's")
                        Spacer()
                        Text(Fmt.kcal(product.kcal * servings)).font(.q(18, .bold)).foregroundStyle(Theme.coral)
                    }
                    Toggle("Save product for next time", isOn: $save).tint(Theme.coral)
                } footer: {
                    Text("Saved products fill in instantly when you scan the same barcode again, even offline.")
                        .foregroundStyle(Theme.brown2)
                }
                .listRowBackground(Theme.cream)
            }
            .creamList()
            .navigationTitle("Check the label")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        let d = Dish(name: product.displayName,
                                     kcal: product.kcal * servings, protein: product.protein * servings,
                                     carbs: product.carbs * servings, fat: product.fat * servings)
                        if save { Pantry.shared.upsert(product) }
                        onAdd(d, product)
                        dismiss()
                    }
                    .fontWeight(.bold)
                    .disabled(product.kcal <= 0)
                }
            }
        }
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
                .gesture(MagnifyGesture().onChanged { scale = max(1, $0.magnification) }.onEnded { _ in withAnimation { scale = 1 } })
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            Button { dismiss() } label: {
                Image(systemName: "xmark").font(.headline).foregroundStyle(.white)
                    .frame(width: 40, height: 40).background(Circle().fill(.white.opacity(0.2)))
            }
            .padding()
        }
    }
}
