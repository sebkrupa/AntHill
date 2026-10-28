import Foundation

/// Checks whether an online shop looks honest before you pay. Ported from
/// the Scripts repo, Security/ShopCheck/shopcheck.py: the CERT Polska warning list, domain name and age,
/// the web archive, red flags on the pages, and the company (NIP, KRS) in the VAT white list and KRS.
/// Pages are read as plain HTML, without JavaScript or cookies. A domain on the CERT list is never opened.
public enum ShopCheck {
    public struct Finding: Codable, Hashable, Sendable {
        public enum Kind: String, Codable, Sendable { case bad, ok, info }
        public let kind: Kind
        /// Risk points; only red flags have them.
        public let points: Int
        public let text: String

        public init(kind: Kind, points: Int, text: String) { self.kind = kind; self.points = points; self.text = text }
    }

    /// Something to check by hand, with a link when there is one.
    public struct Hint: Codable, Hashable, Sendable {
        public let text: String
        public let url: URL?

        public init(text: String, url: URL?) { self.text = text; self.url = url }
    }

    public enum Verdict: Sendable {
        case clear, risky, fraud

        public var title: String {
            switch self {
            case .clear: "No Strong Fraud Signs"
            case .risky: "Higher Risk"
            case .fraud: "Probably a Scam"
            }
        }

        public var advice: String {
            switch self {
            case .clear: "Still pay by card or with buyer protection."
            case .risky: "Check the points below by hand before you pay."
            case .fraud: "Don’t buy here."
            }
        }
    }

    public struct Report: Codable, Identifiable, Hashable, Sendable {
        public let id: UUID
        /// The registrable domain, like sklep.com.pl.
        public let domain: String
        public let date: Date
        public let findings: [Finding]
        public let hints: [Hint]

        public init(domain: String, date: Date, findings: [Finding], hints: [Hint]) {
            id = UUID(); self.domain = domain; self.date = date; self.findings = findings; self.hints = hints
        }

        public var score: Int { findings.reduce(0) { $0 + $1.points } }
        /// 7 points or more: probably a scam. 4 or more: higher risk.
        public var verdict: Verdict { score >= 7 ? .fraud : score >= 4 ? .risky : .clear }
    }

    /// A downloaded page: the address after redirects, and its text.
    public struct Page: Sendable {
        public let url: URL
        public let text: String
        public init(url: URL, text: String) { self.url = url; self.text = text }
    }

    /// The server answered with an HTTP error.
    public struct HTTPStatus: LocalizedError {
        public let code: Int
        public init(code: Int) { self.code = code }
        public var errorDescription: String? { "HTTP \(code)" }
    }

    /// Downloads a URL within a timeout. Tests pass a fake one.
    public typealias Fetch = @Sendable (URL, TimeInterval) async throws -> Page

    /// The https address to check, from what the person typed; nil when it is no web address.
    public static func target(_ address: String) -> URL? {
        let text = address.trimmingCharacters(in: .whitespacesAndNewlines)
        let rest = text.range(of: "://").map { String(text[$0.upperBound...]) } ?? text
        // Always try HTTPS first.
        guard !rest.isEmpty, let url = URL(string: "https://" + rest), let host = url.host(), host.contains(".") else { return nil }
        return url
    }

    /// Runs every step and returns the report. `step` names each step as it starts.
    public static func run(_ url: URL, today: Date = .now, fetch: @escaping Fetch = download,
                           step: @Sendable (String) async -> Void = { _ in }) async -> Report {
        let host = url.host() ?? ""
        let reg = registrable(host)
        let notes = Notes()
        await step("CERT Polska warning list")
        let listed = await notes.safe("CERT Polska warning list") { try await onCertList(host, fetch) }
        if listed == true {
            notes.bad(10, "The domain is on the CERT Polska warning list (https://cert.pl/lista-ostrzezen/). It’s a scam.")
            return report(reg, today, notes, company: nil, terms: "")
        }
        if listed == false { notes.ok("The domain is not on the CERT Polska warning list.") }
        notes.findings += checkDomainName(host)
        await step("Domain age and history")
        await checkDomainHistory(reg, today: today, notes, fetch)
        await step("Shop pages")
        var company: Company?
        var terms = ""
        let pages = await fetchPages(url, notes, fetch)
        if !pages.isEmpty {
            let content = analyzeContent(pages, host: host)
            notes.findings += content.findings
            terms = content.terms
            await step("Company registers")
            company = await checkRegistry(content, label: reg.components(separatedBy: ".")[0], today: today, notes, fetch)
        }
        return report(reg, today, notes, company: company, terms: terms)
    }

    /// The real network: a browser user agent, Polish first, no cookies.
    public static let download: Fetch = { url, timeout in
        var request = URLRequest(url: url, timeoutInterval: timeout)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("pl,en;q=0.8", forHTTPHeaderField: "Accept-Language")
        request.httpShouldHandleCookies = false
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, http.statusCode >= 400 { throw HTTPStatus(code: http.statusCode) }
        let encoding = response.textEncodingName.map {
            String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringConvertIANACharSetNameToEncoding($0 as CFString)))
        }
        let text = encoding.flatMap { String(data: data, encoding: $0) } ?? String(decoding: data, as: UTF8.self)
        return Page(url: response.url ?? url, text: text)
    }

    // MARK: - Rules

    static let userAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0 Safari/537.36"
    static let halfYear = 183
    // shortcut: a short list instead of the Public Suffix List; add a suffix when a domain comes out wrong.
    static let secondLevel: Set = ["com.pl", "net.pl", "org.pl", "info.pl", "biz.pl", "sklep.pl", "shop.pl", "waw.pl", "co.uk", "org.uk"]
    static let riskyTLDs: Set = ["shop", "store", "top", "online", "site", "xyz", "buzz", "cfd", "sbs", "icu", "click", "live",
                                 "fun", "cyou", "bond", "vip", "monster", "best", "rest", "lat"]
    static let brands = ["nike", "adidas", "apple", "iphone", "samsung", "xiaomi", "zara", "lego", "dyson", "rolex", "puma",
                         "newbalance", "northface", "rayban", "ikea", "allegro", "inpost", "decathlon", "zalando", "pandora",
                         "lacoste", "moncler", "mediaexpert", "mediamarkt", "rtveuroagd"]
    static let domainBait = Rx("outlet|sale|promo|tanio|tanie|wyprzedaz|discount|cheap|okazj|black-?friday|clearance|official")
    static let freeMail: Set = ["gmail.com", "googlemail.com", "wp.pl", "o2.pl", "onet.pl", "op.pl", "interia.pl", "poczta.fm",
                                "gazeta.pl", "outlook.com", "hotmail.com", "live.com", "yahoo.com", "icloud.com", "proton.me",
                                "protonmail.com", "gmx.com", "mail.ru", "yandex.ru"]
    static let infoLink = Rx("regulamin|terms|warunki|kontakt|contact|o-nas|about|zwrot|dostaw|faq", .caseInsensitive)
    static let termsLink = Rx("regulamin|terms|warunki", .caseInsensitive)
    static let email = Rx(#"[\w.+-]+@([a-z0-9-]+(?:\.[a-z0-9-]+)+)"#, .caseInsensitive)
    static let gateways = Rx(#"payu|przelewy24|tpay|paypal|stripe|dotpay|imoje|paynow|klarna|adyen|autopay|blue ?media"#
                             + #"|paypo|twisto|apple ?pay|google ?pay|\bvisa\b|mastercard|za pobraniem|przy odbiorze"#)
    static let pressure = Rx(#"countdown|odliczani|zosta[lł][oy] tylko|ostatnie sztuki|tylko dzi[sś]|(oferta|promocja) ko[nń]czy si"#
                             + #"|hurry|only \d+ left|limited time"#)
    static let closing = Rx(#"likwidacj\w* sklep|zamkni[eę]ci\w* sklep|zamykamy sklep|wyprzeda[zż] likwidacyjn"#
                            + #"|closing down|store closing|we are closing"#)
    static let crypto = Rx(#"\b(bitcoin|usdt|ethereum|kryptowalut\w*|cryptocurrenc\w*)\b"#)
    /// The NIP of these companies often stands in a shop's terms. It is not the seller's NIP.
    static let operators = Rx("PAYU|PAYPRO|KRAJOWY INTEGRATOR|BLUE MEDIA|AUTOPAY|DOTPAY|PAYNOW|INPOST|POCZTA POLSKA|DPD|DHL|GLS|ALLEGRO")

    static func registrable(_ host: String) -> String {
        var name = host.lowercased()
        if name.hasPrefix("www.") { name.removeFirst(4) }
        let parts = name.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
        let lastTwo = parts.suffix(2).joined(separator: ".")
        return parts.suffix(secondLevel.contains(lastTwo) ? 3 : 2).joined(separator: ".")
    }

    static func nipOK(_ nip: String) -> Bool {
        let digits = nip.compactMap(\.wholeNumberValue)
        guard digits.count == 10, nip.count == 10 else { return false }
        return zip([6, 5, 7, 2, 3, 4, 5, 6, 7], digits).reduce(0) { $0 + $1.0 * $1.1 } % 11 == digits[9]
    }

    static func ibanOK(_ iban: String) -> Bool {
        let moved = iban.dropFirst(4) + iban.prefix(4)
        var rest = 0
        for character in moved {
            guard let value = character.isASCII ? Int(String(character), radix: 36) : nil else { return false }
            for digit in String(value) { rest = (rest * 10 + digit.wholeNumberValue!) % 97 }
        }
        return rest == 1
    }

    static func pageText(_ raw: String) -> String {
        let noCode = Rx(#"<(script|style|noscript)\b.*?</\1>"#, [.caseInsensitive, .dotMatchesLineSeparators]).replace(raw, " ")
        return Rx(#"\s+"#).replace(unescape(Rx("<[^>]+>").replace(noCode, " ")), " ")
    }

    /// HTML entities to text.
    /// shortcut: numeric entities and the common named ones only; add a name when a shop's text comes out wrong.
    static func unescape(_ text: String) -> String {
        guard text.contains("&") else { return text }
        let named = ["amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'", "nbsp": " ", "oacute": "ó", "Oacute": "Ó",
                     "ndash": "–", "mdash": "—", "euro": "€", "copy": "©"]
        let pattern = Rx(#"&(#[0-9]+|#[xX][0-9a-fA-F]+|[a-zA-Z]+);"#)
        var result = ""
        var last = text.startIndex
        for match in pattern.re.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
            guard let whole = Range(match.range, in: text), let nameRange = Range(match.range(at: 1), in: text) else { continue }
            let name = String(text[nameRange])
            let scalar: String? = name.hasPrefix("#x") || name.hasPrefix("#X")
                ? UInt32(name.dropFirst(2), radix: 16).flatMap(Unicode.Scalar.init).map(String.init)
                : name.hasPrefix("#") ? UInt32(name.dropFirst()).flatMap(Unicode.Scalar.init).map(String.init) : named[name]
            result += text[last..<whole.lowerBound] + (scalar ?? String(text[whole]))
            last = whole.upperBound
        }
        return result + text[last...]
    }

    /// (Polish 26-digit NRB accounts, foreign IBANs). Only numbers with a correct checksum.
    static func findAccounts(_ text: String) -> (Set<String>, Set<String>) {
        var polish = Set<String>(), foreign = Set<String>()
        for match in Rx(#"\b(?:PL ?)?(\d{2}(?: ?\d{4}){6})\b"#).all(text) {
            let nrb = match[0].replacingOccurrences(of: " ", with: "")
            if ibanOK("PL" + nrb) { polish.insert(nrb) }
        }
        for match in Rx(#"\b([A-Z]{2}\d{2}(?: ?[A-Z0-9]{4}){2,7}(?: ?\d{1,3})?)\b"#).all(text) {
            let iban = match[0].replacingOccurrences(of: " ", with: "")
            if !iban.hasPrefix("PL") && ibanOK(iban) { foreign.insert(iban) }
        }
        return (polish, foreign)
    }

    static func checkDomainName(_ host: String) -> [Finding] {
        let reg = registrable(host)
        let label = reg.components(separatedBy: ".")[0], tld = reg.components(separatedBy: ".").last ?? ""
        var found: [Finding] = []
        if riskyTLDs.contains(tld) { found.append(.init(kind: .bad, points: 1, text: "The .\(tld) ending is often used by fake shops.")) }
        if let bait = domainBait.first(label) { found.append(.init(kind: .bad, points: 1, text: "The domain has the bait word “\(bait)”.")) }
        if let brand = brands.first(where: { label.contains($0) && label != $0 }) {
            found.append(.init(kind: .bad, points: 2, text: "The domain has the brand “\(brand)”, but it is not the brand’s own domain."))
        }
        return found
    }

    static func checkDomainHistory(_ domain: String, today: Date, _ notes: Notes, _ fetch: Fetch) async {
        let created = await notes.safe("Domain age (RDAP)") { try await domainCreated(domain, fetch) }
        if let created {
            let age = days(from: created, to: today)
            if age < halfYear {
                notes.bad(3, "The domain is new: registered \(day(created)) (\(age) days ago).")
            } else if age < 365 {
                notes.bad(1, "The domain is less than a year old: registered \(day(created)).")
            } else {
                notes.ok("Domain registered \(day(created)).")
            }
        }
        let first = await notes.safe("Web archive (web.archive.org)") { try await firstSnapshot(domain, fetch) }
        switch first {
        case .some(.none):
            notes.bad(1, "The site is not in web.archive.org. It has no history at all.")
        case .some(.some(let first)):
            notes.ok("First copy in web.archive.org: \(day(first)).")
            if let created, days(from: first, to: created) > 365 {
                notes.bad(2, "The archive knows the domain since \(day(first)), but the current registration is from \(day(created)). "
                    + "The domain may have expired and been taken over. Look in the archive at what was here before.")
            }
        case .none: break
        }
    }

    /// Links to the terms, contact, and similar pages on the same domain; the terms first, at most 6.
    static func infoLinks(base: URL, raw: String, host: String) -> [(URL, Bool)] {
        var links: [URL: Bool] = [:]
        for match in Rx(#"<a\b[^>]*?href=["']([^"'#]+)["'][^>]*>(.*?)</a>"#, [.caseInsensitive, .dotMatchesLineSeparators]).all(raw) {
            guard let url = URL(string: unescape(match[0]).trimmingCharacters(in: .whitespaces), relativeTo: base)?.absoluteURL,
                  let scheme = url.scheme, scheme == "http" || scheme == "https",
                  let linkHost = url.host(), registrable(linkHost) == registrable(host) else { continue }
            let label = url.path + " " + match[1]
            if infoLink.test(label) { links[url] = (links[url] ?? false) || termsLink.test(label) }
        }
        return links.sorted { ($0.value ? 0 : 1, $0.key.absoluteString) < ($1.value ? 0 : 1, $1.key.absoluteString) }
            .prefix(6).map { ($0.key, $0.value) }
    }

    /// The home page and up to 6 subpages: (url, html, is the terms).
    static func fetchPages(_ url: URL, _ notes: Notes, _ fetch: Fetch) async -> [(URL, String, Bool)] {
        let page: Page
        do {
            page = try await fetch(url, 20)
            if page.url.scheme == "https" {
                notes.info("The site has HTTPS (the padlock). That is only encryption, no proof the shop is honest.")
            } else {
                notes.bad(2, "The site redirects to HTTP without encryption. Don’t enter any data here.")
            }
        } catch let error as HTTPStatus {
            notes.info("The site answers HTTP \(error.code) (it may block scripts). Its content was not checked.")
            return []
        } catch {
            var plain = URLComponents(url: url, resolvingAgainstBaseURL: false)
            plain?.scheme = "http"
            guard let http = plain?.url, let answer = try? await fetch(http, 20) else {
                notes.info("The site does not answer (\(error.localizedDescription)). Its content was not checked.")
                return []
            }
            page = answer
            notes.bad(2, "HTTPS does not work (\(error.localizedDescription)). Don’t enter any data here.")
        }
        let host = page.url.host() ?? ""
        if registrable(host) != registrable(url.host() ?? "") { notes.info("The site redirects to another domain: \(host).") }
        var pages = [(page.url, page.text, false)]
        for (link, isTerms) in infoLinks(base: page.url, raw: page.text, host: host) {
            // The link is there even when its content did not come.
            pages.append((link, (try? await fetch(link, 20))?.text ?? "", isTerms))
        }
        return pages
    }

    /// What the pages say: red flags and the company's NIP, KRS, and bank accounts.
    struct Content {
        var findings: [Finding] = []
        var nips: [String] = []
        var krss: [String] = []
        var accounts: Set<String> = []
        var terms = ""
    }

    static func analyzeContent(_ pages: [(URL, String, Bool)], host: String) -> Content {
        let notes = Notes()
        var content = Content()
        let text = pages.map { pageText($0.1) }.joined(separator: " ")
        let low = text.lowercased()
        let rawLow = pages.map(\.1).joined(separator: " ").lowercased()
        content.terms = pages.filter(\.2).map { pageText($0.1) }.joined(separator: " ")
        let reg = registrable(host)
        if text.count < 500 {
            notes.info("The page has little text in its HTML (it is probably built with JavaScript). Some flags may be false.")
        }

        let found = unique(Rx(#"NIP(?:\s*/\s*VAT(?:\s*UE)?)?\W{0,6}(?:PL)?\s?(\d{3}[-\s]?\d{2,3}[-\s]?\d{2,3}[-\s]?\d{2,3})"#, .caseInsensitive)
            .all(text).map { $0[0].filter(\.isNumber) }.filter { $0.count == 10 })
        content.nips = found.filter(nipOK)
        content.krss = unique(Rx(#"\bKRS\W{0,3}(?:pod\s+)?(?:numerem|nr|no)?\W{0,3}(\d{4,10})\b"#, .caseInsensitive)
            .all(text).map { String(repeating: "0", count: max(0, 10 - $0[0].count)) + $0[0] })
        if !found.isEmpty && content.nips.isEmpty {
            notes.bad(3, "The NIP on the site (\(found.joined(separator: ", "))) has a wrong checksum. That NIP does not exist.")
        } else if content.nips.isEmpty && content.krss.isEmpty {
            let abroad = reg.hasSuffix(".pl") ? "" : " A foreign shop? Check the company in VIES or OpenCorporates."
            notes.bad(3, "No NIP or KRS on the site. Nobody knows who runs the shop.\(abroad)")
        }

        if pages.contains(where: \.2) {
            if content.terms.trimmingCharacters(in: .whitespaces).isEmpty {
                notes.info("The shop has terms, but they could not be downloaded.")
            } else if !(Rx("odst[aą]p|withdraw", .caseInsensitive).test(content.terms)
                        && Rx(#"14\s*(dni|days)|czternast|fourteen"#, .caseInsensitive).test(content.terms)) {
                notes.bad(1, "The terms don’t mention 14 days to withdraw from the purchase. For a consumer that is against the law.")
            } else {
                notes.ok("The shop has terms, and they mention 14 days to withdraw from the purchase.")
            }
        } else {
            notes.bad(2, "No link to the shop’s terms (regulamin).")
        }

        let paid = Set(gateways.all(rawLow, whole: true).map { $0[0].trimmingCharacters(in: .whitespaces) }).sorted()
        if paid.isEmpty {
            notes.bad(1, "No known payment (PayU, Przelewy24, card) or cash on delivery. They may show only in the cart. "
                + "Never send a transfer to a private account.")
        } else {
            notes.ok("Known payments: \(paid.joined(separator: ", ")).")
        }
        if let word = crypto.first(low) { notes.bad(2, "The site mentions cryptocurrency (“\(word)”).") }
        if let word = pressure.first(low) ?? pressure.first(rawLow) { notes.bad(1, "Time pressure on the site (“\(word)”).") }
        if let word = closing.first(low) { notes.bad(1, "A “closing down” sale (“\(word)”).") }
        let discounts = Rx(#"[-–]\s?(\d{2})\s?%|(?<!\d)(\d{2})\s?%\s*(?:taniej|rabat|zni[zż]k|off)"#).all(text).flatMap { $0 }.compactMap { Int($0) }
        if let most = discounts.max(), most >= 50 { notes.bad(1, "Very large discounts (up to \(most)%).") }
        if reg.hasSuffix(".pl") && !low.contains("zł") && !Rx(#"\bpln\b"#).test(low) && Rx(#"[€$]|\beur\b|\busd\b"#).test(low) {
            notes.bad(1, "A Polish domain, but the prices are not in złoty.")
        }

        let mailtos = Rx(#"mailto:([^"'?\s]+)"#).all(rawLow).map { $0[0] }.joined(separator: " ")
        let mails = Set(email.all(text + " " + mailtos).map { $0[0].lowercased() }
            .filter { !$0.hasSuffix(".png") && !$0.hasSuffix(".jpg") && !$0.hasSuffix(".jpeg") && !$0.hasSuffix(".webp")
                && !$0.hasSuffix(".gif") && !$0.hasSuffix(".svg") })
        let whatsapp = rawLow.contains("wa.me/") || rawLow.contains("api.whatsapp.com")
        if mails.contains(where: { $0 == reg || $0.hasSuffix("." + reg) }) {
            notes.ok("There is an email address on the shop’s domain (@\(reg)).")
        } else if !mails.isDisjoint(with: freeMail) || whatsapp {
            let free = mails.intersection(freeMail).sorted().joined(separator: ", ")
            notes.bad(1, "Contact only through free email or WhatsApp (\(free.isEmpty ? "WhatsApp" : free)).")
        }

        let (accounts, foreign) = findAccounts(text)
        content.accounts = accounts
        if !foreign.isEmpty && reg.hasSuffix(".pl") {
            notes.bad(1, "A Polish shop, but a foreign bank account: \(foreign.sorted().joined(separator: ", ")).")
        }
        content.findings = notes.findings
        return content
    }

    /// A company in the VAT white list (wl-api.mf.gov.pl).
    public struct Company: Codable, Hashable, Sendable {
        let name: String
        let nip: String?
        let statusVat: String?
        let registrationLegalDate: String?
        let accountNumbers: [String]?
        let hasVirtualAccounts: Bool?
        let krs: String?
        let workingAddress: String?
        let residenceAddress: String?

        var address: String { workingAddress ?? residenceAddress ?? "?" }
    }

    /// A company in KRS (api-krs.ms.gov.pl).
    struct KRSEntry {
        let name: String
        let nip: String?
        let divisions: Set<String>
        let main: String
        let registered: Date?
    }

    /// The VAT white list and KRS. Returns the company from the white list.
    static func checkRegistry(_ content: Content, label: String, today: Date, _ notes: Notes, _ fetch: Fetch) async -> Company? {
        var company: Company?
        var registered: Date?
        var krss = content.krss
        let nips = content.nips
        if !nips.isEmpty, let found = await notes.safe("VAT white list", { try await whiteList(Array(nips.prefix(30)), today: today, fetch) }) {
            let subjects = nips.compactMap { found[$0] ?? nil }
            company = subjects.first { operators.first($0.name) == nil || $0.name.contains(label.uppercased()) }
            if company == nil, let first = subjects.first {
                notes.bad(3, "The site shows only the NIP of an operator (\(first.name)), not the seller’s.")
            } else if company == nil {
                notes.bad(2, "NIP \(nips.joined(separator: ", ")) is not in the VAT white list.")
            }
        }
        if let company {
            notes.ok("Company in the VAT white list: \(company.name), NIP \(company.nip ?? "?"), "
                + "status \(company.statusVat ?? "?"), address: \(company.address).")
            if let status = company.statusVat, status != "Czynny" && status != "Zwolniony" {
                notes.bad(2, "The company’s VAT status: \(status).")
            }
            registered = company.registrationLegalDate.flatMap { date($0, "yyyy-MM-dd") }
            let known = Set(company.accountNumbers ?? [])
            if !content.accounts.isEmpty && !known.isEmpty && company.hasVirtualAccounts != true {
                let alien = content.accounts.subtracting(known)
                if alien.isEmpty {
                    notes.ok("The bank account on the site belongs to this company (VAT white list).")
                } else {
                    notes.bad(3, "The bank account on the site (\(alien.sorted().joined(separator: ", "))) does not belong to this company "
                        + "according to the VAT white list. The details don’t match.")
                }
            }
            if let krs = company.krs, !krss.contains(krs) { krss.append(krs) }
        }
        if let krs = krss.first, let lookup = await notes.safe("KRS", { try await krsLookup(krs, fetch) }) {
            if let entry = lookup {
                if !nips.isEmpty, !nips.contains(entry.nip ?? "") {
                    notes.bad(3, "KRS \(krs) belongs to \(entry.name), with another NIP (\(entry.nip ?? "?")) than the site shows.")
                } else {
                    notes.ok("Company in KRS: \(entry.name).")
                }
                if entry.divisions.isDisjoint(with: ["46", "47"]) {
                    notes.bad(1, "The company’s trade in KRS (PKD) does not include selling goods. Main trade: \(entry.main).")
                } else {
                    notes.ok("The company’s trade in KRS (PKD) includes selling goods.")
                }
                registered = registered ?? entry.registered
            } else {
                notes.bad(2, "KRS \(krs) does not exist in the register of companies.")
            }
        }
        if let registered, days(from: registered, to: today) < halfYear {
            notes.bad(1, "The company was registered recently: \(day(registered)).")
        }
        return company
    }

    // MARK: - Sources

    static func onCertList(_ host: String, _ fetch: Fetch) async throws -> Bool {
        let listed = Set(try await fetch(URL(string: "https://hole.cert.pl/domains/v2/domains.txt")!, 30).text
            .split(whereSeparator: \.isWhitespace).map(String.init))
        let parts = host.lowercased().components(separatedBy: ".")
        return (0..<max(parts.count - 1, 0)).contains { listed.contains(parts[$0...].joined(separator: ".")) }
    }

    static func domainCreated(_ domain: String, _ fetch: Fetch) async throws -> Date {
        struct RDAP: Decodable { struct Event: Decodable { let eventAction: String?; let eventDate: String? }; let events: [Event]? }
        let rdap = try JSONDecoder().decode(RDAP.self, from: Data(try await fetch(URL(string: "https://rdap.org/domain/\(domain)")!, 20).text.utf8))
        guard let text = rdap.events?.first(where: { $0.eventAction == "registration" })?.eventDate,
              let created = date(String(text.prefix(10)), "yyyy-MM-dd") else { throw Missing(what: "no registration date in RDAP") }
        return created
    }

    /// The first web archive copy; nil when the archive has none.
    static func firstSnapshot(_ domain: String, _ fetch: Fetch) async throws -> Date? {
        let url = URL(string: "https://web.archive.org/cdx/search/cdx?url=\(domain)&limit=1&output=json&fl=timestamp")!
        let text = try await fetch(url, 30).text
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return nil }
        let rows = try JSONDecoder().decode([[String]].self, from: Data(text.utf8))
        guard rows.count > 1, let stamp = rows[1].first else { return nil }
        return date(String(stamp.prefix(8)), "yyyyMMdd")
    }

    static func whiteList(_ nips: [String], today: Date, _ fetch: Fetch) async throws -> [String: Company?] {
        struct Answer: Decodable {
            struct Result: Decodable { struct Entry: Decodable { let identifier: String; let subjects: [Company]? }; let entries: [Entry] }
            let result: Result
        }
        let url = URL(string: "https://wl-api.mf.gov.pl/api/search/nips/\(nips.joined(separator: ","))?date=\(day(today))")!
        let answer = try JSONDecoder().decode(Answer.self, from: Data(try await fetch(url, 20).text.utf8))
        return Dictionary(answer.result.entries.map { ($0.identifier, $0.subjects?.first) }, uniquingKeysWith: { a, _ in a })
    }

    /// The company with this KRS number; nil when KRS has none.
    static func krsLookup(_ krs: String, _ fetch: Fetch) async throws -> KRSEntry? {
        struct Answer: Decodable {
            struct Item: Decodable { let kodDzial: String; let opis: String }
            struct PKD: Decodable { let przedmiotPrzewazajacejDzialalnosci: [Item]?; let przedmiotPozostalejDzialalnosci: [Item]? }
            struct Subject: Decodable { struct IDs: Decodable { let nip: String? }; let nazwa: String; let identyfikatory: IDs }
            struct Data: Decodable {
                struct Part1: Decodable { let danePodmiotu: Subject }
                struct Part3: Decodable { let przedmiotDzialalnosci: PKD }
                let dzial1: Part1
                let dzial3: Part3
            }
            struct Header: Decodable { let dataRejestracjiWKRS: String }
            struct Extract: Decodable { let dane: Data; let naglowekA: Header }
            let odpis: Extract
        }
        let text: String
        do {
            text = try await fetch(URL(string: "https://api-krs.ms.gov.pl/api/krs/OdpisAktualny/\(krs)?rejestr=P&format=json")!, 20).text
        } catch let error as HTTPStatus where error.code == 404 {
            return nil
        }
        let odpis = try JSONDecoder().decode(Answer.self, from: Data(text.utf8)).odpis
        let main = odpis.dane.dzial3.przedmiotDzialalnosci.przedmiotPrzewazajacejDzialalnosci ?? []
        let other = odpis.dane.dzial3.przedmiotDzialalnosci.przedmiotPozostalejDzialalnosci ?? []
        return KRSEntry(name: odpis.dane.dzial1.danePodmiotu.nazwa, nip: odpis.dane.dzial1.danePodmiotu.identyfikatory.nip,
                        divisions: Set((main + other).map(\.kodDzial)), main: main.first?.opis ?? "?",
                        registered: date(odpis.naglowekA.dataRejestracjiWKRS, "dd.MM.yyyy"))
    }

    // MARK: - Report

    static func report(_ reg: String, _ today: Date, _ notes: Notes, company: Company?, terms: String) -> Report {
        let order: [Finding.Kind: Int] = [.bad: 0, .ok: 1, .info: 2]
        let findings = notes.findings.enumerated().sorted { (order[$0.element.kind]!, $0.offset) < (order[$1.element.kind]!, $1.offset) }.map(\.element)
        return Report(domain: reg, date: today, findings: findings, hints: hints(reg, company: company, terms: terms))
    }

    /// What the check can’t do: links to check by hand.
    static func hints(_ reg: String, company: Company?, terms: String) -> [Hint] {
        func search(_ query: String) -> URL? {
            var parts = URLComponents(string: "https://www.google.com/search")!
            parts.queryItems = [URLQueryItem(name: "q", value: query)]
            return parts.url
        }
        var hints: [Hint] = [
            .init(text: "Product photos: search by image in Google Lens, TinEye, or Yandex Images.", url: nil),
            .init(text: "Reviews outside the shop: Trustpilot", url: URL(string: "https://www.trustpilot.com/review/\(reg)")),
            .init(text: "Reviews outside the shop: Google", url: search(reg + " opinie")),
        ]
        if let company {
            var maps = URLComponents(string: "https://www.google.com/maps/search/")!
            maps.queryItems = [URLQueryItem(name: "api", value: "1"), URLQueryItem(name: "query", value: company.address)]
            hints.append(.init(text: "The company’s address in Street View", url: maps.url))
            if company.krs == nil {
                hints.append(.init(text: "A sole trader (no KRS): check the trade in CEIDG", url: URL(string: "https://aplikacja.ceidg.gov.pl")))
            }
        }
        if let fragment = termsFragment(terms) {
            hints.append(.init(text: "Are the terms copied from another shop?", url: search("\"\(fragment)\"")))
        }
        hints.append(.init(text: "Look at the site without opening it: urlscan.io", url: URL(string: "https://urlscan.io/search/#domain:\(reg)")))
        hints.append(.init(text: "Already paid? Call your bank (chargeback). Report the site to CERT Polska", url: URL(string: "https://incydent.cert.pl")))
        return hints
    }

    /// The first 12 words of a terms sentence of 10 to 40 words: menus and footers have no full stops,
    /// so they come out too long or too short.
    static func termsFragment(_ terms: String) -> String? {
        for sentence in Rx(#"(?<=[.;])\s"#).replace(terms, "\n").split(separator: "\n") {
            let words = sentence.split(whereSeparator: \.isWhitespace)
            if (10...40).contains(words.count), Rx("sprzedawc|zam[oó]wieni|klient|seller|order", .caseInsensitive).test(String(sentence)) {
                return words.prefix(12).joined(separator: " ")
            }
        }
        return nil
    }

    // MARK: - Helpers

    struct Missing: LocalizedError {
        let what: String
        var errorDescription: String? { what }
    }

    /// Collects findings while the check runs.
    final class Notes {
        var findings: [Finding] = []
        func bad(_ points: Int, _ text: String) { findings.append(.init(kind: .bad, points: points, text: text)) }
        func ok(_ text: String) { findings.append(.init(kind: .ok, points: 0, text: text)) }
        func info(_ text: String) { findings.append(.init(kind: .info, points: 0, text: text)) }

        /// A network or API failure loses one result, never the rest of the check.
        func safe<T>(_ what: String, _ body: () async throws -> T) async -> T? {
            do { return try await body() } catch {
                info("\(what): not checked (\(error.localizedDescription)).")
                return nil
            }
        }
    }

    static func unique(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.filter { seen.insert($0).inserted }
    }

    static func date(_ text: String, _ format: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = format
        return formatter.date(from: text)
    }

    static func day(_ date: Date) -> String {
        date.formatted(Date.ISO8601FormatStyle(timeZone: TimeZone(identifier: "UTC")!).year().month().day())
    }

    static func days(from start: Date, to end: Date) -> Int {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar.dateComponents([.day], from: calendar.startOfDay(for: start), to: calendar.startOfDay(for: end)).day ?? 0
    }
}

/// NSRegularExpression with the few calls the rules need. Python's re and ICU agree on these patterns.
struct Rx: @unchecked Sendable {
    let re: NSRegularExpression

    init(_ pattern: String, _ options: NSRegularExpression.Options = []) {
        re = try! NSRegularExpression(pattern: pattern, options: options)
    }

    func first(_ text: String) -> String? {
        re.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)).flatMap { Range($0.range, in: text) }.map { String(text[$0]) }
    }

    func test(_ text: String) -> Bool { first(text) != nil }

    /// Every match's groups, "" for a group that did not take part; the whole match when there are no groups or `whole` is set.
    func all(_ text: String, whole: Bool = false) -> [[String]] {
        re.matches(in: text, range: NSRange(text.startIndex..., in: text)).map { match in
            let groups = whole || match.numberOfRanges == 1 ? [0] : Array(1..<match.numberOfRanges)
            return groups.map { Range(match.range(at: $0), in: text).map { String(text[$0]) } ?? "" }
        }
    }

    func replace(_ text: String, _ template: String) -> String {
        re.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: template)
    }
}
