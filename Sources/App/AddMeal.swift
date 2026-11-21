import SwiftUI
import PhotosUI
import UIKit

struct AddRequest: Identifiable {
    let id = UUID()
    var type: MealType? = nil
    var day: Date? = nil
    var startWithCamera = true
}

struct MealInfo {
    var date: Date
    var type: MealType
    var place: String
    var lat: Double?
    var lon: Double?
}

struct DraftDish: Identifiable {
    let id = UUID()
    var dish: Dish
    var box: [Double]?
    var preview: UIImage?
    var mine = true
}

struct ReviewDraft {
    var image: UIImage?
    var info: MealInfo
    var dishes: [DraftDish]
    var note: String?

    static func from(_ found: [AIDish], image: UIImage, info: MealInfo) -> ReviewDraft {
        let base = ImageStore.normalized(image, maxSide: 1024)
        let dishes = found.map { a in
            DraftDish(dish: Dish(name: a.name, kcal: a.kcal ?? 0, protein: a.protein_g ?? 0, carbs: a.carbs_g ?? 0, fat: a.fat_g ?? 0),
                      box: a.box,
                      preview: ImageStore.crop(base, box: a.box, maxSide: 160))
        }
        if dishes.isEmpty {
            return ReviewDraft(image: image, info: info, dishes: [DraftDish(dish: Dish())],
                               note: "No food was found in the photo. Tap the dish to type what it is.")
        }
        return ReviewDraft(image: image, info: info, dishes: dishes, note: nil)
    }

    static func blank(image: UIImage?, info: MealInfo, note: String?) -> ReviewDraft {
        ReviewDraft(image: image, info: info, dishes: [DraftDish(dish: Dish())], note: note)
    }
}

// MARK: - Add meal (camera page)

struct AddMealView: View {
    let request: AddRequest

    @Environment(\.dismiss) private var dismiss
    @StateObject private var loc = LocationHelper()

    @State private var image: UIImage?
    @State private var singleDish = false
    @State private var date: Date
    @State private var type: MealType
    @State private var place = ""
    @State private var lat: Double?
    @State private var lon: Double?
    @State private var placeAuto = true
    @State private var useCurrentLocation = true
    @State private var nearby: [PlaceChoice] = []

    @State private var showCamera = false
    @State private var openedCamera = false
    @State private var pickerItem: PhotosPickerItem?
    @State private var showPlaces = false
    @State private var analysing = false
    @State private var errorText: String?
    @State private var draft: ReviewDraft?
    @State private var showReview = false

    init(request: AddRequest) {
        self.request = request
        var start = Date()
        if let day = request.day, !Calendar.current.isDateInToday(day) {
            let hour = (request.type ?? .lunch).usualHour
            start = Calendar.current.date(bySettingHour: hour, minute: 0, second: 0, of: day) ?? day
        }
        _date = State(initialValue: start)
        _type = State(initialValue: request.type ?? MealType.guess(for: start))
    }

    private var info: MealInfo { MealInfo(date: date, type: type, place: place, lat: lat, lon: lon) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    photoArea
                    Picker("Photo", selection: $singleDish) {
                        Text("Whole table").tag(false)
                        Text("Single dish").tag(true)
                    }
                    .pickerStyle(.segmented)

                    details

                    if let errorText {
                        VStack(alignment: .leading, spacing: 10) {
                            Text(errorText).font(.subheadline).foregroundStyle(.red)
                            HStack {
                                Button("Try again") { Task { await analyse() } }
                                    .buttonStyle(.bordered)
                                Button("Continue without AI") {
                                    draft = .blank(image: image, info: info, note: nil)
                                    showReview = true
                                }
                                .buttonStyle(.bordered)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                        .background(RoundedRectangle(cornerRadius: 14).fill(Color.red.opacity(0.08)))
                    }

                    controls

                    if image != nil && !analysing && errorText == nil {
                        Button {
                            Task { await analyse() }
                        } label: {
                            Label("Find dishes again", systemImage: "sparkles")
                        }
                        .font(.subheadline)
                    }
                }
                .padding()
            }
            .navigationTitle("What are you eating?")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }
                        .accessibilityLabel("Close")
                }
            }
            .navigationDestination(isPresented: $showReview) {
                if let draft {
                    ReviewView(draft: draft, onSaved: { dismiss() })
                }
            }
        }
        .fullScreenCover(isPresented: $showCamera) {
            CameraPicker { img in
                useCurrentLocation = true
                took(img, meta: nil)
            }
            .ignoresSafeArea()
        }
        .sheet(isPresented: $showPlaces) {
            PlacePicker(lat: lat ?? loc.coordinate?.latitude, lon: lon ?? loc.coordinate?.longitude, initial: nearby) { c in
                place = c.name
                if let la = c.lat, let lo = c.lon { lat = la; lon = lo }
                placeAuto = false
            }
        }
        .onAppear {
            loc.request()
            if request.startWithCamera && !openedCamera {
                openedCamera = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { showCamera = true }
            }
        }
        .onChange(of: loc.coordinate?.latitude) {
            guard useCurrentLocation, let c = loc.coordinate else { return }
            Task { await loadNearby(lat: c.latitude, lon: c.longitude) }
        }
        .onChange(of: pickerItem) {
            Task { await loadPicked() }
        }
    }

    // MARK: Pieces

    private var photoArea: some View {
        Theme.photoBG
            .frame(height: 260)
            .overlay {
                if let image {
                    Image(uiImage: image).resizable().scaledToFill()
                } else {
                    VStack(spacing: 8) {
                        Image(systemName: "camera").font(.system(size: 34))
                        Text("Take a photo of your food").font(.subheadline)
                    }
                    .foregroundStyle(.white.opacity(0.85))
                }
            }
            .overlay {
                if analysing {
                    ZStack {
                        Color.black.opacity(0.45)
                        VStack(spacing: 10) {
                            ProgressView().tint(.white)
                            Text("Finding your dishes…").font(.subheadline).foregroundStyle(.white)
                        }
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .contentShape(Rectangle())
            .onTapGesture { if image == nil { showCamera = true } }
    }

    private var details: some View {
        VStack(spacing: 0) {
            Button { showPlaces = true } label: {
                HStack {
                    Image(systemName: "mappin.and.ellipse").foregroundStyle(Theme.accent)
                    Text(place.isEmpty ? "Choose where you ate" : place)
                        .foregroundStyle(place.isEmpty ? Color.secondary : Color.primary)
                        .lineLimit(1)
                    Spacer()
                    Text(place.isEmpty ? "" : (placeAuto ? "nearby · change" : "change"))
                        .font(.caption).foregroundStyle(.secondary)
                    Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                }
                .padding(.vertical, 12)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Divider()
            HStack {
                Image(systemName: type.symbol).foregroundStyle(Theme.accent)
                Picker("Meal", selection: $type) {
                    ForEach(MealType.allCases) { Text($0.title).tag($0) }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                Spacer()
                DatePicker("Time", selection: $date)
                    .labelsHidden()
            }
            .padding(.vertical, 6)
        }
        .padding(.horizontal, 14)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.card))
    }

    private var controls: some View {
        VStack(spacing: 6) {
            HStack(spacing: 34) {
                PhotosPicker(selection: $pickerItem, matching: .images) {
                    circleIcon("photo.on.rectangle")
                }
                Button { showCamera = true } label: {
                    ZStack {
                        Circle().stroke(Theme.accent, lineWidth: 4).frame(width: 70, height: 70)
                        Circle().fill(Theme.accent).frame(width: 56, height: 56)
                    }
                }
                .accessibilityLabel("Take photo")
                Button {
                    draft = .blank(image: nil, info: info, note: "Type what you ate, then let the AI estimate the calories.")
                    showReview = true
                } label: {
                    circleIcon("square.and.pencil")
                }
                .accessibilityLabel("Type it in")
            }
            Text("Library · Camera · Type it in").font(.caption).foregroundStyle(.secondary)
        }
        .padding(.top, 4)
    }

    private func circleIcon(_ name: String) -> some View {
        Image(systemName: name)
            .font(.system(size: 20))
            .foregroundStyle(.primary)
            .frame(width: 48, height: 48)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.card))
    }

    // MARK: Actions

    private func took(_ img: UIImage, meta: PhotoMeta?) {
        image = img
        errorText = nil
        if let meta {
            if let d = meta.date {
                date = d
                if request.type == nil { type = MealType.guess(for: d) }
            }
            if let la = meta.lat, let lo = meta.lon {
                lat = la
                lon = lo
                placeAuto = true
                place = ""
                Task { await loadNearby(lat: la, lon: lo) }
            }
        } else if let c = loc.coordinate, place.isEmpty {
            Task { await loadNearby(lat: c.latitude, lon: c.longitude) }
        }
        Task { await analyse() }
    }

    private func loadPicked() async {
        guard let item = pickerItem else { return }
        defer { pickerItem = nil }
        guard let data = try? await item.loadTransferable(type: Data.self), let img = UIImage(data: data) else {
            errorText = "That photo couldn't be opened."
            return
        }
        useCurrentLocation = false
        took(img, meta: ImageStore.metadata(from: data))
    }

    private func loadNearby(lat la: Double, lon lo: Double) async {
        let list = await Places.nearby(lat: la, lon: lo)
        nearby = list
        guard placeAuto else { return }
        if let first = list.first {
            place = first.name
            lat = first.lat
            lon = first.lon
        } else {
            lat = la
            lon = lo
        }
    }

    private func analyse() async {
        guard let img = image else { return }
        guard ClaudeClient.hasKey else {
            draft = .blank(image: img, info: info,
                           note: "Add your Claude API key in Settings so dishes are named and calories counted for you.")
            showReview = true
            return
        }
        analysing = true
        errorText = nil
        do {
            let found = try await ClaudeClient.analysePhoto(img, singleDish: singleDish)
            analysing = false
            draft = .from(found, image: img, info: info)
            showReview = true
        } catch {
            analysing = false
            errorText = error.localizedDescription
        }
    }
}

// MARK: - Which ones are yours?

struct ReviewView: View {
    let draft: ReviewDraft
    var onSaved: () -> Void

    @State private var dishes: [DraftDish]
    @State private var cost: Double = 0
    @State private var editing: DraftDish?
    @State private var saving = false
    @State private var autoOpened = false

    init(draft: ReviewDraft, onSaved: @escaping () -> Void) {
        self.draft = draft
        self.onSaved = onSaved
        _dishes = State(initialValue: draft.dishes)
    }

    private var mine: [DraftDish] { dishes.filter { $0.mine } }
    private var mineKcal: Double { mine.reduce(0) { $0 + $1.dish.kcal } }

    var body: some View {
        List {
            Section {
                ForEach(dishes) { d in
                    HStack(spacing: 12) {
                        DishThumb(dish: nil, meal: nil, size: 48, preview: d.preview)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(d.dish.name.isEmpty ? "Tap to name this dish" : d.dish.name)
                                .foregroundStyle(d.dish.name.isEmpty ? Color.secondary : Color.primary)
                            Text(d.mine ? Fmt.kcal(d.dish.kcal) : "not mine")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button { toggle(d.id) } label: {
                            Image(systemName: d.mine ? "checkmark.circle.fill" : "circle")
                                .font(.title2)
                                .foregroundStyle(d.mine ? Theme.accent : Color.secondary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(d.mine ? "Mine" : "Not mine")
                    }
                    .opacity(d.mine ? 1 : 0.55)
                    .contentShape(Rectangle())
                    .onTapGesture { editing = d }
                }
                Button {
                    let n = DraftDish(dish: Dish())
                    dishes.append(n)
                    editing = n
                } label: {
                    Label("Add a dish", systemImage: "plus")
                }
            } header: {
                Text(draft.image == nil ? "What did you eat?" : "AI found \(dishes.count) \(dishes.count == 1 ? "item" : "items"). Only ticked ones are saved.")
            } footer: {
                if let note = draft.note { Text(note) }
            }

            Section {
                NumberField(label: "What I paid", value: $cost, decimals: 2, prefix: "RM")
            } header: {
                Text("My cost")
            } footer: {
                Text("Only what you spent on your own food.")
            }
        }
        .navigationTitle("Which ones are yours?")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            Button {
                Task { await save() }
            } label: {
                HStack(spacing: 8) {
                    if saving { ProgressView().tint(.white) }
                    Text(saving ? "Saving…" : "Save \(draft.info.type.title.lowercased()) · \(Fmt.kcal(mineKcal))")
                }
            }
            .buttonStyle(AccentButtonStyle())
            .disabled(saving || mine.isEmpty)
            .opacity(mine.isEmpty ? 0.5 : 1)
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(.bar)
        }
        .sheet(item: $editing) { d in
            DishEditor(dish: d.dish, onSave: { new in
                if let i = dishes.firstIndex(where: { $0.id == d.id }) { dishes[i].dish = new }
            }, onDelete: {
                dishes.removeAll { $0.id == d.id }
            })
        }
        .onAppear {
            if !autoOpened, draft.image == nil, dishes.count == 1, dishes[0].dish.name.isEmpty {
                autoOpened = true
                editing = dishes[0]
            }
        }
    }

    private func toggle(_ id: UUID) {
        if let i = dishes.firstIndex(where: { $0.id == id }) { dishes[i].mine.toggle() }
    }

    private func save() async {
        saving = true
        let chosen = mine
        let info = draft.info
        let img = draft.image
        let cost = self.cost
        let side = CGFloat(max(640, UserDefaults.standard.integer(forKey: Keys.photoSide)))
        let meal: Meal = await Task.detached(priority: .userInitiated) { () -> Meal in
            var m = Meal(date: info.date, type: info.type)
            m.place = info.place
            m.latitude = info.lat
            m.longitude = info.lon
            m.cost = cost
            if let img {
                let saved = ImageStore.savePhoto(img, maxSide: side)
                m.photo = saved.photo
                m.thumb = saved.thumb
            }
            m.dishes = chosen.map { d in
                var dish = d.dish
                if dish.name.trimmingCharacters(in: .whitespaces).isEmpty { dish.name = "Food" }
                if let img { dish.cutout = ImageStore.makeCutout(from: img, box: d.box) }
                return dish
            }
            return m
        }.value
        MealStore.shared.upsert(meal)
        saving = false
        onSaved()
    }
}

// MARK: - Camera

struct CameraPicker: UIViewControllerRepresentable {
    var onImage: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let p = UIImagePickerController()
        p.sourceType = UIImagePickerController.isSourceTypeAvailable(.camera) ? .camera : .photoLibrary
        p.delegate = context.coordinator
        return p
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraPicker
        init(_ parent: CameraPicker) { self.parent = parent }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let img = info[.originalImage] as? UIImage { parent.onImage(img) }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}
