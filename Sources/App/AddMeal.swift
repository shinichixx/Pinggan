import SwiftUI
import PhotosUI
import UIKit
import CoreImage

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
    var box: [Double]? = nil
    var lifted: CIImage? = nil
    var preview: UIImage? = nil
    var mine = true
}

struct ReviewDraft {
    var image: UIImage?
    var info: MealInfo
    var dishes: [DraftDish]
    var note: String?
    var fromAI = true

    static func from(_ found: [FoundDish], image: UIImage, info: MealInfo) -> ReviewDraft {
        let dishes = found.map { DraftDish(dish: $0.dish, box: $0.box, lifted: $0.lifted, preview: $0.preview) }
        if dishes.isEmpty {
            return ReviewDraft(image: image, info: info, dishes: [DraftDish(dish: Dish())],
                               note: "No food was found in the photo. Tap the dish to type what it is.")
        }
        return ReviewDraft(image: image, info: info, dishes: dishes, note: nil)
    }

    static func blank(image: UIImage?, info: MealInfo, note: String?) -> ReviewDraft {
        ReviewDraft(image: image, info: info, dishes: [DraftDish(dish: Dish())], note: note, fromAI: false)
    }
}

enum CaptureMode: Hashable {
    case table, single, label
}

// MARK: - Add meal (camera page)

struct AddMealView: View {
    let request: AddRequest

    @Environment(\.dismiss) private var dismiss
    @StateObject private var loc = LocationHelper()

    @State private var image: UIImage?
    @State private var mode: CaptureMode = .table
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
    @State private var working: String?
    @State private var errorText: String?
    @State private var draft: ReviewDraft?
    @State private var showReview = false
    @State private var label: LabelBox?

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
            ZStack {
                PageBackground()
                ScrollView {
                    VStack(spacing: 16) {
                        HStack {
                            RoundNavButton(icon: "xmark") { dismiss() }
                            Spacer()
                            Text("What are you eating?").font(.q(19, .bold)).foregroundStyle(.white)
                            Spacer()
                            Color.clear.frame(width: 36, height: 36)
                        }
                        .padding(.top, 4)

                        photoArea

                        PillPicker(options: [(CaptureMode.table, "Whole table"), (CaptureMode.single, "Single dish"), (CaptureMode.label, "Food label")],
                                   selection: $mode)

                        details

                        if let errorText { errorCard(errorText) }

                        controls

                        if image != nil && working == nil && errorText == nil {
                            Button {
                                Task { await process() }
                            } label: {
                                Label(mode == .label ? "Read the label again" : "Find dishes again", systemImage: "sparkles")
                                    .font(.q(14, .bold)).foregroundStyle(Theme.coral)
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 30)
                }
            }
            .toolbar(.hidden, for: .navigationBar)
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
        .sheet(item: $label) { box in
            ProductSheet(product: box.scan.product ?? Product(barcode: box.scan.barcode), source: box.scan.source) { dish, _ in
                labelAdded(dish)
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
        RadialGradient(colors: [Color(hex: 0x7A3B26), Theme.photoBG], center: .center, startRadius: 0, endRadius: 220)
            .frame(height: 280)
            .overlay {
                if let image {
                    Image(uiImage: image).resizable().scaledToFill()
                } else {
                    VStack(spacing: 8) {
                        Image(systemName: mode == .label ? "barcode.viewfinder" : "camera").font(.system(size: 36))
                        Text(mode == .label ? "Photo the nutrition label or barcode" : "Take a photo of your food").font(.q(15, .semibold))
                    }
                    .foregroundStyle(.white.opacity(0.85))
                }
            }
            .overlay {
                if let working {
                    ZStack {
                        Color.black.opacity(0.45)
                        VStack(spacing: 10) {
                            ProgressView().tint(.white)
                            Text(working).font(.q(15, .bold)).foregroundStyle(.white)
                        }
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .contentShape(Rectangle())
            .onTapGesture { if image == nil { showCamera = true } }
            .plateCard(padding: 10)
    }

    private var details: some View {
        VStack(spacing: 0) {
            Button { showPlaces = true } label: {
                HStack {
                    Image(systemName: "mappin.and.ellipse").foregroundStyle(Theme.coral)
                    Text(place.isEmpty ? "Choose where you ate" : place)
                        .foregroundStyle(place.isEmpty ? Theme.brown2 : Theme.brown)
                        .lineLimit(1)
                    Spacer()
                    Text(place.isEmpty ? "" : (placeAuto ? "nearby · change" : "change"))
                        .font(.caption).foregroundStyle(Theme.brown2)
                    Image(systemName: "chevron.right").font(.caption).foregroundStyle(Theme.brown3)
                }
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .padding(.vertical, 12)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Divider().overlay(Theme.line)
            HStack {
                Image(systemName: type.symbol).foregroundStyle(Theme.coral)
                Picker("Meal", selection: $type) {
                    ForEach(MealType.allCases) { Text($0.title).tag($0) }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .tint(Theme.brown)
                Spacer()
                DatePicker("Time", selection: $date)
                    .labelsHidden()
            }
            .padding(.vertical, 6)
        }
        .padding(.horizontal, 14)
        .creamCard(padding: 0)
    }

    private func errorCard(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(text).font(.system(size: 14, weight: .semibold, design: .rounded)).foregroundStyle(Color(hex: 0xC0392B))
            HStack {
                Button("Try again") { Task { await process() } }
                    .buttonStyle(.bordered).tint(Theme.coral)
                Button("Type it in instead") {
                    draft = .blank(image: image, info: info, note: nil)
                    showReview = true
                }
                .buttonStyle(.bordered).tint(Theme.coral)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .creamCard()
    }

    private var controls: some View {
        VStack(spacing: 8) {
            HStack(spacing: 36) {
                PhotosPicker(selection: $pickerItem, matching: .images) {
                    DishIconPlate(icon: "photo")
                }
                Button { showCamera = true } label: {
                    Circle()
                        .fill(Color(hex: 0xFFFAF6))
                        .overlay(Circle().stroke(Color(hex: 0xF4E2D6), lineWidth: 3).padding(10))
                        .overlay(Circle().fill(Theme.button).padding(17).shadow(color: Theme.coral.opacity(0.4), radius: 5, y: 3))
                        .frame(width: 84, height: 84)
                        .shadow(color: Color(hex: 0xC85037).opacity(0.38), radius: 11, y: 6)
                }
                .accessibilityLabel("Take photo")
                Button {
                    draft = .blank(image: nil, info: info, note: "Type what you ate, then let the AI estimate the calories.")
                    showReview = true
                } label: {
                    DishIconPlate(icon: "pencil")
                }
                .accessibilityLabel("Type it in")
            }
            Text("Library · Camera · Type it in").font(.q(12.5, .bold)).foregroundStyle(Theme.brown2)
        }
        .padding(.top, 6)
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
        Task { await process() }
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

    private func process() async {
        guard let img = image else { return }
        errorText = nil
        if mode == .label {
            working = "Reading the label…"
            let scan = await LabelReader.scan(img)
            working = nil
            label = LabelBox(scan: scan)
            return
        }
        working = FoodAI.mode == .claude ? "Asking Claude…" : "Finding your dishes…"
        do {
            let found = try await FoodAI.analyse(img, singleDish: mode == .single)
            working = nil
            draft = .from(found, image: img, info: info)
            showReview = true
        } catch {
            working = nil
            errorText = error.localizedDescription
        }
    }

    private func labelAdded(_ dish: Dish) {
        var lifted: CIImage?
        var preview: UIImage?
        if let img = image, let cg = ImageStore.normalized(img, maxSide: 1024).cgImage, let l = ImageStore.liftAll(cg) {
            lifted = l
            preview = ImageStore.uiImage(l)
        }
        var d = ReviewDraft.blank(image: image, info: info, note: nil)
        d.dishes = [DraftDish(dish: dish, lifted: lifted, preview: preview)]
        draft = d
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { showReview = true }
    }
}

struct LabelBox: Identifiable {
    let id = UUID()
    let scan: LabelScan
}

struct DishIconPlate: View {
    let icon: String
    var body: some View {
        Circle()
            .fill(Color(hex: 0xFFFAF6))
            .overlay(Circle().stroke(Color(hex: 0xF3E4D9), lineWidth: 2).padding(9))
            .overlay(Image(systemName: icon).font(.system(size: 19, weight: .semibold)).foregroundStyle(Theme.brown2))
            .frame(width: 54, height: 54)
            .shadow(color: Color(hex: 0x964632).opacity(0.18), radius: 4, y: 2)
    }
}

// MARK: - Which ones are yours?

struct ReviewView: View {
    let draft: ReviewDraft
    var onSaved: () -> Void

    @Environment(\.dismiss) private var dismiss
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

    private var subtitle: String {
        if !draft.fromAI { return draft.image == nil ? "Type what you ate." : "Check the details, then save." }
        return "\(FoodAI.modeTitle) found \(dishes.count) \(dishes.count == 1 ? "item" : "items"). Only ticked ones are saved."
    }

    var body: some View {
        ZStack {
            PageBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    RoundNavButton(icon: "chevron.left") { dismiss() }
                        .padding(.top, 4)
                    Text(draft.image == nil && !draft.fromAI ? "What did you eat?" : "Which ones are yours?")
                        .font(.q(28, .bold)).foregroundStyle(.white).padding(.top, 10)
                    Text(subtitle).font(.system(size: 14, weight: .semibold, design: .rounded)).foregroundStyle(.white.opacity(0.92))

                    VStack(spacing: 0) {
                        ForEach(dishes) { d in
                            row(d)
                            Divider().overlay(Theme.line).padding(.leading, 76)
                        }
                        Button {
                            let n = DraftDish(dish: Dish())
                            dishes.append(n)
                            editing = n
                        } label: {
                            Label("Add a dish", systemImage: "plus")
                                .font(.q(15, .bold)).foregroundStyle(Theme.coral)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(14)
                        }
                        .buttonStyle(.plain)
                    }
                    .creamCard(padding: 0)
                    .padding(.top, 16)

                    if let note = draft.note {
                        Text(note).font(.system(size: 12.5, weight: .semibold, design: .rounded)).foregroundStyle(Theme.brown2)
                            .padding(.horizontal, 6).padding(.top, 8)
                    }

                    Text("MY COST").font(.q(12.5, .bold)).tracking(0.8).foregroundStyle(Theme.brown2)
                        .padding(.horizontal, 6).padding(.top, 18).padding(.bottom, 7)
                    NumberField(label: "What I paid", value: $cost, decimals: 2, prefix: "RM")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(Theme.brown)
                        .creamCard()
                    Text("Only what you spent on your own food.")
                        .font(.system(size: 12, weight: .semibold, design: .rounded)).foregroundStyle(Theme.brown2)
                        .padding(.horizontal, 6).padding(.top, 7)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 110)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
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
            .padding(.horizontal, 20)
            .padding(.vertical, 8)
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

    private func row(_ d: DraftDish) -> some View {
        HStack(spacing: 12) {
            DishThumb(dish: nil, meal: nil, size: 50, preview: d.preview)
            VStack(alignment: .leading, spacing: 2) {
                Text(d.dish.name.isEmpty ? "Tap to name this dish" : d.dish.name)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(d.dish.name.isEmpty ? Theme.brown2 : Theme.brown)
                Text(d.mine ? Fmt.kcal(d.dish.kcal) : "not mine")
                    .font(.system(size: 12.5, weight: .semibold, design: .rounded)).foregroundStyle(Theme.brown2)
            }
            Spacer()
            Button { toggle(d.id) } label: {
                if d.mine {
                    Image(systemName: "checkmark")
                        .font(.system(size: 14, weight: .bold)).foregroundStyle(.white)
                        .frame(width: 30, height: 30)
                        .background(Circle().fill(Theme.button).shadow(color: Theme.coral.opacity(0.35), radius: 4, y: 2))
                } else {
                    Circle().stroke(Color(hex: 0xE8D3C6), lineWidth: 2).frame(width: 28, height: 28)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(d.mine ? "Mine" : "Not mine")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .opacity(d.mine ? 1 : 0.5)
        .contentShape(Rectangle())
        .onTapGesture { editing = d }
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
                if let lifted = d.lifted {
                    dish.cutout = ImageStore.saveLifted(lifted)
                } else if let img, d.box != nil || chosen.count == 1 {
                    dish.cutout = ImageStore.makeCutout(from: img, box: d.box)
                }
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
