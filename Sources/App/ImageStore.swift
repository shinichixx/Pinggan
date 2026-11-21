import UIKit
import Vision
import CoreImage
import CoreImage.CIFilterBuiltins
import ImageIO
import UniformTypeIdentifiers

struct PhotoMeta {
    var date: Date?
    var lat: Double?
    var lon: Double?
}

/// Photos, thumbnails and dish cut-outs, all kept in Documents/Pinggan/Images.
enum ImageStore {
    static let cache: NSCache<NSString, UIImage> = {
        let c = NSCache<NSString, UIImage>()
        c.countLimit = 400
        return c
    }()
    static let ci = CIContext(options: [.cacheIntermediates: false])

    static func url(_ name: String) -> URL { Paths.images.appendingPathComponent(name) }

    // MARK: Loading

    static func load(_ name: String?) -> UIImage? {
        guard let name, !name.isEmpty else { return nil }
        if let c = cache.object(forKey: name as NSString) { return c }
        guard let img = UIImage(contentsOfFile: url(name).path) else { return nil }
        cache.setObject(img, forKey: name as NSString)
        return img
    }

    /// A dish cut-out with a transparent background (or the plain crop if no mask was made).
    static func cutoutImage(_ base: String?) -> UIImage? {
        guard let base, !base.isEmpty else { return nil }
        let key = ("cut-" + base) as NSString
        if let c = cache.object(forKey: key) { return c }
        let colorURL = url(base + ".heic")
        let maskURL = url(base + ".mask.png")
        guard let color = CIImage(contentsOf: colorURL) else { return nil }
        var result: UIImage?
        if let mask = CIImage(contentsOf: maskURL) {
            let f = CIFilter.blendWithMask()
            f.inputImage = color
            f.backgroundImage = CIImage.empty()
            f.maskImage = mask
            if let out = f.outputImage?.cropped(to: color.extent),
               let cg = ci.createCGImage(out, from: color.extent) {
                result = UIImage(cgImage: cg)
            }
        }
        if result == nil, let cg = ci.createCGImage(color, from: color.extent) {
            result = UIImage(cgImage: cg)
        }
        if let result { cache.setObject(result, forKey: key) }
        return result
    }

    // MARK: Resizing and encoding

    /// Redraws the image upright, with its longest side at most `maxSide` pixels.
    static func normalized(_ image: UIImage, maxSide: CGFloat, opaque: Bool = true) -> UIImage {
        let w = image.size.width * image.scale
        let h = image.size.height * image.scale
        let longest = max(w, h)
        let s = longest > maxSide ? maxSide / longest : 1
        let size = CGSize(width: max(1, (w * s).rounded()), height: max(1, (h * s).rounded()))
        let fmt = UIGraphicsImageRendererFormat()
        fmt.scale = 1
        fmt.opaque = opaque
        return UIGraphicsImageRenderer(size: size, format: fmt).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
    }

    static func encode(_ cg: CGImage, type: UTType, quality: CGFloat? = nil) -> Data? {
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(data as CFMutableData, type.identifier as CFString, 1, nil) else { return nil }
        var props: [CFString: Any] = [:]
        if let quality { props[kCGImageDestinationLossyCompressionQuality] = quality }
        CGImageDestinationAddImage(dest, cg, props as CFDictionary)
        return CGImageDestinationFinalize(dest) ? data as Data : nil
    }

    private static func compressed(_ image: UIImage, quality: CGFloat) -> (Data, String)? {
        if let cg = image.cgImage, let d = encode(cg, type: .heic, quality: quality) { return (d, "heic") }
        if let d = image.jpegData(compressionQuality: quality + 0.1) { return (d, "jpg") }
        return nil
    }

    private static func write(_ data: Data, name: String) -> Bool {
        do { try data.write(to: url(name), options: .atomic); return true } catch { return false }
    }

    /// Saves the meal photo (HEIC, longest side `maxSide`) and a 360 px thumbnail.
    static func savePhoto(_ image: UIImage, maxSide: CGFloat) -> (photo: String?, thumb: String?) {
        let id = UUID().uuidString
        var photo: String?
        var thumb: String?
        let big = normalized(image, maxSide: maxSide)
        if let r = compressed(big, quality: 0.6) {
            let n = id + "." + r.1
            if write(r.0, name: n) { photo = n }
        }
        let small = normalized(big, maxSide: 360)
        if let r = compressed(small, quality: 0.6) {
            let n = id + "-t." + r.1
            if write(r.0, name: n) { thumb = n }
        }
        return (photo, thumb)
    }

    /// Re-saves an older photo smaller. Keeps the same file name.
    static func shrink(_ name: String, maxSide: CGFloat) -> Bool {
        let u = url(name)
        guard let img = UIImage(contentsOfFile: u.path) else { return false }
        let longest = max(img.size.width * img.scale, img.size.height * img.scale)
        if longest <= maxSide + 1 { return true }
        let small = normalized(img, maxSide: maxSide)
        guard let r = compressed(small, quality: 0.6) else { return false }
        do {
            try r.0.write(to: u, options: .atomic)
            cache.removeObject(forKey: name as NSString)
            return true
        } catch {
            return false
        }
    }

    static func delete(_ name: String?) {
        guard let name, !name.isEmpty else { return }
        try? FileManager.default.removeItem(at: url(name))
        cache.removeObject(forKey: name as NSString)
    }

    static func deleteCutout(_ base: String?) {
        guard let base, !base.isEmpty else { return }
        try? FileManager.default.removeItem(at: url(base + ".heic"))
        try? FileManager.default.removeItem(at: url(base + ".mask.png"))
        cache.removeObject(forKey: ("cut-" + base) as NSString)
    }

    static func clearCache() { cache.removeAllObjects() }

    static func folderBytes() -> Int64 {
        guard let e = FileManager.default.enumerator(at: Paths.root, includingPropertiesForKeys: [.fileSizeKey]) else { return 0 }
        var total: Int64 = 0
        for case let u as URL in e {
            total += Int64((try? u.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        }
        return total
    }

    // MARK: Crops and cut-outs

    /// Pixel rect for an AI box [x, y, w, h] (fractions, top-left origin), padded a little.
    private static func rect(for box: [Double]?, in cg: CGImage, pad: Double = 0.05) -> CGRect? {
        guard let b = box, b.count == 4, b.allSatisfy({ $0 >= 0 && $0 <= 1.01 }) else { return nil }
        let x = max(0, b[0] - pad)
        let y = max(0, b[1] - pad)
        let w = min(1 - x, b[2] + 2 * pad)
        let h = min(1 - y, b[3] + 2 * pad)
        guard w > 0.04, h > 0.04 else { return nil }
        let W = Double(cg.width), H = Double(cg.height)
        return CGRect(x: x * W, y: y * H, width: w * W, height: h * H).integral
    }

    /// Small preview of one dish for the "Which ones are yours?" list.
    static func crop(_ image: UIImage, box: [Double]?, maxSide: CGFloat) -> UIImage? {
        guard let cg = image.cgImage, let r = rect(for: box, in: cg), let c = cg.cropping(to: r) else { return nil }
        return normalized(UIImage(cgImage: c), maxSide: maxSide)
    }

    /// Lifts the dish out of its background with Vision and saves it as a small HEIC plus a greyscale mask.
    /// Returns the base file name, or nil if nothing could be saved.
    static func makeCutout(from image: UIImage, box: [Double]?) -> String? {
        let base = normalized(image, maxSide: 1400)
        guard let cg = base.cgImage else { return nil }
        var crop = cg
        if let r = rect(for: box, in: cg), let c = cg.cropping(to: r) { crop = c }
        if let lifted = liftAll(crop), let name = saveLifted(lifted) { return name }
        return plainCrop(crop, name: UUID().uuidString)
    }

    /// Saves an already cut-out dish (transparent background) as HEIC colour + PNG mask, at most 320 px.
    static func saveLifted(_ lifted: CIImage) -> String? {
        let name = UUID().uuidString
        let e = lifted.extent
        guard e.width >= 8, e.height >= 8 else { return nil }
        let s = min(1, 320 / max(e.width, e.height))
        let scaled = lifted
            .transformed(by: CGAffineTransform(translationX: -e.origin.x, y: -e.origin.y))
            .transformed(by: CGAffineTransform(scaleX: s, y: s))
        let ext = CGRect(x: 0, y: 0, width: (e.width * s).rounded(.down), height: (e.height * s).rounded(.down))
        guard ext.width >= 8, ext.height >= 8 else { return nil }

        let white = CIImage(color: CIColor(red: 1, green: 1, blue: 1)).cropped(to: ext)
        let color = scaled.composited(over: white).cropped(to: ext)

        let m = CIFilter.colorMatrix()
        m.inputImage = scaled
        m.rVector = CIVector(x: 0, y: 0, z: 0, w: 1)
        m.gVector = CIVector(x: 0, y: 0, z: 0, w: 1)
        m.bVector = CIVector(x: 0, y: 0, z: 0, w: 1)
        m.aVector = CIVector(x: 0, y: 0, z: 0, w: 0)
        m.biasVector = CIVector(x: 0, y: 0, z: 0, w: 1)

        guard let colorCG = ci.createCGImage(color, from: ext),
              let colorData = encode(colorCG, type: .heic, quality: 0.65),
              let maskCI = m.outputImage?.cropped(to: ext),
              let maskCG = ci.createCGImage(maskCI, from: ext, format: .L8, colorSpace: CGColorSpaceCreateDeviceGray()),
              let maskData = encode(maskCG, type: .png),
              write(colorData, name: name + ".heic"),
              write(maskData, name: name + ".mask.png") else { return nil }
        return name
    }

    /// Small UIImage (with transparency) of a cut-out, for previews.
    static func uiImage(_ ciImage: CIImage, maxSide: CGFloat = 200) -> UIImage? {
        let e = ciImage.extent
        guard e.width > 0, e.height > 0 else { return nil }
        let s = min(1, maxSide / max(e.width, e.height))
        let scaled = ciImage
            .transformed(by: CGAffineTransform(translationX: -e.origin.x, y: -e.origin.y))
            .transformed(by: CGAffineTransform(scaleX: s, y: s))
        let ext = CGRect(x: 0, y: 0, width: (e.width * s).rounded(.down), height: (e.height * s).rounded(.down))
        guard let cg = ci.createCGImage(scaled, from: ext) else { return nil }
        return UIImage(cgImage: cg)
    }

    struct InstancePart {
        let focus: CGImage
        let lifted: CIImage
        let preview: UIImage?
    }

    /// Each separate object (plate, bowl, cup) Vision finds in the photo, biggest first.
    static func splitInstances(_ cg: CGImage) -> [InstancePart] {
        let req = VNGenerateForegroundInstanceMaskRequest()
        let handler = VNImageRequestHandler(cgImage: cg, options: [:])
        guard (try? handler.perform([req])) != nil, let obs = req.results?.first else { return [] }
        let total = Double(cg.width * cg.height)
        var parts: [(Double, InstancePart)] = []
        for idx in obs.allInstances {
            guard let buf = try? obs.generateMaskedImage(ofInstances: IndexSet(integer: idx), from: handler, croppedToInstancesExtent: true) else { continue }
            let lifted = CIImage(cvPixelBuffer: buf)
            let e = lifted.extent
            let area = Double(e.width * e.height)
            guard area / total > 0.015 else { continue }
            let white = CIImage(color: CIColor(red: 1, green: 1, blue: 1)).cropped(to: e)
            guard let focus = ci.createCGImage(lifted.composited(over: white).cropped(to: e), from: e) else { continue }
            parts.append((area, InstancePart(focus: focus, lifted: lifted, preview: uiImage(lifted))))
        }
        return parts.sorted { $0.0 > $1.0 }.map { $0.1 }
    }

    private static func plainCrop(_ cg: CGImage, name: String) -> String? {
        let small = normalized(UIImage(cgImage: cg), maxSide: 320)
        guard let scg = small.cgImage, let data = encode(scg, type: .heic, quality: 0.65) ?? small.jpegData(compressionQuality: 0.7) else { return nil }
        return write(data, name: name + ".heic") ? name : nil
    }

    /// Foreground (the plate) cut out of its background, cropped to the object. nil if Vision finds nothing.
    static func liftAll(_ cg: CGImage) -> CIImage? {
        let req = VNGenerateForegroundInstanceMaskRequest()
        let handler = VNImageRequestHandler(cgImage: cg, options: [:])
        do {
            try handler.perform([req])
            guard let obs = req.results?.first, !obs.allInstances.isEmpty else { return nil }
            let buf = try obs.generateMaskedImage(ofInstances: obs.allInstances, from: handler, croppedToInstancesExtent: true)
            return CIImage(cvPixelBuffer: buf)
        } catch {
            return nil
        }
    }

    // MARK: Photo metadata

    static func metadata(from data: Data) -> PhotoMeta {
        var meta = PhotoMeta()
        guard let src = CGImageSourceCreateWithData(data as CFData, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any] else { return meta }
        if let exif = props[kCGImagePropertyExifDictionary] as? [CFString: Any],
           let s = exif[kCGImagePropertyExifDateTimeOriginal] as? String {
            let f = DateFormatter()
            f.dateFormat = "yyyy:MM:dd HH:mm:ss"
            f.locale = Locale(identifier: "en_US_POSIX")
            meta.date = f.date(from: s)
        }
        if let gps = props[kCGImagePropertyGPSDictionary] as? [CFString: Any],
           let lat = gps[kCGImagePropertyGPSLatitude] as? Double,
           let lon = gps[kCGImagePropertyGPSLongitude] as? Double {
            let latRef = gps[kCGImagePropertyGPSLatitudeRef] as? String ?? "N"
            let lonRef = gps[kCGImagePropertyGPSLongitudeRef] as? String ?? "E"
            meta.lat = latRef == "S" ? -lat : lat
            meta.lon = lonRef == "W" ? -lon : lon
        }
        return meta
    }
}
