//
//  XMPService.swift
//  rawpreview
//

import Foundation

/// Reads and writes star ratings in `.xmp` sidecars (`DSC_0001.NEF` →
/// `DSC_0001.xmp`), the format Lightroom Classic and Capture One both pick up
/// for RAW files.
///
/// Existing sidecars are edited in place: only `xmp:Rating` and
/// `xmp:MetadataDate` change, so develop settings, keywords etc. written by
/// other apps survive. A sidecar that can't be parsed is never overwritten.
actor XMPService {
    static let shared = XMPService()

    enum XMPError: LocalizedError {
        case unreadableSidecar(URL)

        var errorDescription: String? {
            switch self {
            case .unreadableSidecar(let url):
                String(localized: "\(url.lastPathComponent) exists but isn't valid XMP, so it was left untouched.")
            }
        }
    }

    nonisolated static let xmpNamespace = "http://ns.adobe.com/xap/1.0/"
    nonisolated static let rdfNamespace = "http://www.w3.org/1999/02/22-rdf-syntax-ns#"

    /// Writes are serialised by the actor, so mashing 1…5 lands in key order.
    func setRating(_ rating: Rating, sidecar url: URL) throws {
        let document: XMLDocument
        if let data = try? Data(contentsOf: url) {
            guard let existing = try? XMLDocument(data: data, options: [.nodePreserveAll]),
                  Self.firstDescription(in: existing) != nil
            else { throw XMPError.unreadableSidecar(url) }
            document = existing
        } else {
            document = try XMLDocument(xmlString: Self.emptyPacket, options: [.nodePreserveAll])
        }

        guard let description = Self.firstDescription(in: document) else {
            throw XMPError.unreadableSidecar(url)
        }
        Self.setXMPProperty("Rating", to: String(rating.rawValue), in: document)
        Self.setXMPProperty("MetadataDate", to: Self.timestamp(), in: document, preferring: description)

        let xml = document.xmlString(options: [.nodePrettyPrint, .nodePreserveEmptyElements])
        try Data(xml.utf8).write(to: url, options: .atomic)
    }

    /// Ratings for every sidecar in `urls` that exists and has one.
    @concurrent
    nonisolated func readRatings(_ urls: [URL]) async -> [URL: Rating] {
        var ratings: [URL: Rating] = [:]
        for (index, url) in urls.enumerated() {
            if index.isMultiple(of: 64), Task.isCancelled { break }
            guard let data = try? Data(contentsOf: url),
                  let rating = Self.rating(in: data),
                  rating.isRated
            else { continue }
            ratings[url] = rating
        }
        return ratings
    }

    nonisolated static func rating(in data: Data) -> Rating? {
        guard let document = try? XMLDocument(data: data),
              let value = xmpProperty("Rating", in: document),
              let stars = Int(value.trimmingCharacters(in: .whitespaces))
        else { return nil }
        // Lightroom writes -1 for "rejected"; treat anything out of range as unrated.
        return Rating(rawValue: stars) ?? Rating.none
    }

    // MARK: - XML helpers

    /// Same shape as Lightroom's own sidecars: a bare `x:xmpmeta` root (the
    /// `<?xpacket?>` wrapper is only needed for XMP embedded in binary files).
    private static let emptyPacket = """
        <x:xmpmeta xmlns:x="adobe:ns:meta/" x:xmptk="RawPreview">
         <rdf:RDF xmlns:rdf="\(rdfNamespace)">
          <rdf:Description rdf:about="" xmlns:xmp="\(xmpNamespace)"/>
         </rdf:RDF>
        </x:xmpmeta>
        """

    private static func descriptions(in document: XMLDocument) -> [XMLElement] {
        var result: [XMLElement] = []
        func walk(_ node: XMLNode) {
            if let element = node as? XMLElement,
               element.localName == "Description",
               element.uri == rdfNamespace {
                result.append(element)
            }
            node.children?.forEach(walk)
        }
        if let root = document.rootElement() { walk(root) }
        return result
    }

    private static func firstDescription(in document: XMLDocument) -> XMLElement? {
        descriptions(in: document).first
    }

    /// XMP allows a simple property either as an attribute
    /// (`xmp:Rating="3"`) or as a child element (`<xmp:Rating>3</xmp:Rating>`),
    /// on any of several `rdf:Description`s. Finds whichever form is present.
    private static func xmpProperty(_ name: String, in document: XMLDocument) -> String? {
        for description in descriptions(in: document) {
            if let attribute = description.attribute(forLocalName: name, uri: xmpNamespace) {
                return attribute.stringValue
            }
            if let element = description.elements(forLocalName: name, uri: xmpNamespace).first {
                return element.stringValue
            }
        }
        return nil
    }

    /// Updates the property where it already lives; otherwise adds it as an
    /// attribute on `preferring` (or the first description), declaring the
    /// `xmp` namespace there if needed.
    private static func setXMPProperty(
        _ name: String,
        to value: String,
        in document: XMLDocument,
        preferring preferred: XMLElement? = nil
    ) {
        let all = descriptions(in: document)
        for description in all {
            if let attribute = description.attribute(forLocalName: name, uri: xmpNamespace) {
                attribute.stringValue = value
                return
            }
            if let element = description.elements(forLocalName: name, uri: xmpNamespace).first {
                element.stringValue = value
                return
            }
        }

        guard let target = preferred ?? all.first else { return }
        let prefix = target.resolvePrefix(forNamespaceURI: xmpNamespace) ?? {
            target.addNamespace(XMLNode.namespace(withName: "xmp", stringValue: xmpNamespace) as! XMLNode)
            return "xmp"
        }()
        let attribute = XMLNode.attribute(withName: "\(prefix):\(name)", uri: xmpNamespace, stringValue: value) as! XMLNode
        target.addAttribute(attribute)
    }

    private static func timestamp() -> String {
        Date.now.ISO8601Format() // e.g. 2026-10-30T13:05:00Z, a valid XMP date
    }
}
