import Foundation
import Testing
@testable import AntHillKit

// Ported from Scripts/Security/ShopCheck/test_shopcheck.py. No network.

private let scam = """
    <html><body><h1>NIKE OUTLET - likwidacja sklepu!</h1>
    <div class="countdown">Oferta konczy sie za 00:09:59</div>
    <p>Air Max 799 zl <b>-80%</b> tylko 159 zl. Zostaly tylko 2 sztuki!</p>
    <p>Platnosc: przelew lub Bitcoin. Kontakt: nikeoutlet.pl.sklep@gmail.com</p>
    <a href="/kontakt">Kontakt</a></body></html>
    """

private let legit = """
    <html><body><footer>Sklep Kowalski Sp. z o.o., NIP: 956-230-77-19, KRS 0000514685,
    konto 53 1020 5011 0000 9002 0270 6323, sklep@kowalski.pl. Platnosci PayU i za pobraniem. Ceny w zl.
    <a href="/regulamin">Regulamin</a></footer></body></html>
    """
private let terms = "<p>Klient moze odstapic od umowy w terminie 14 dni od otrzymania towaru.</p>"

private func score(_ findings: [ShopCheck.Finding]) -> Int { findings.reduce(0) { $0 + $1.points } }

@Test func nipChecksum() {
    #expect(ShopCheck.nipOK("9562307719"))
    #expect(!ShopCheck.nipOK("9562307718"))
}

@Test func ibanAndAccounts() {
    #expect(ShopCheck.ibanOK("PL53102050110000900202706323"))
    let (polish, foreign) = ShopCheck.findAccounts("PL53 1020 5011 0000 9002 0270 6323 oraz DE89 3704 0044 0532 0130 00 tel 12 3456")
    #expect(polish == ["53102050110000900202706323"])
    #expect(foreign == ["DE89370400440532013000"])
}

@Test func registrableDomain() {
    #expect(ShopCheck.registrable("www.sklep.com.pl") == "sklep.com.pl")
    #expect(ShopCheck.registrable("a.b.x-kom.pl") == "x-kom.pl")
}

@Test func domainName() {
    #expect(score(ShopCheck.checkDomainName("nike-outlet.shop")) == 4)  // .shop + "outlet" + brand
    #expect(score(ShopCheck.checkDomainName("nike.com")) == 0)
}

@Test func scamPage() {
    let content = ShopCheck.analyzeContent([(URL(string: "https://nikeoutlet.pl/")!, scam, false)], host: "nikeoutlet.pl")
    #expect(content.nips.isEmpty && content.krss.isEmpty && content.accounts.isEmpty)
    #expect(score(content.findings) >= 7)
}

@Test func legitPage() {
    let pages = [(URL(string: "https://kowalski.pl/")!, legit, false), (URL(string: "https://kowalski.pl/regulamin")!, terms, true)]
    let content = ShopCheck.analyzeContent(pages, host: "kowalski.pl")
    #expect(content.nips == ["9562307719"])
    #expect(content.krss == ["0000514685"])
    #expect(content.accounts == ["53102050110000900202706323"])
    #expect(score(content.findings) == 0, "\(content.findings)")
}

@Test func addressToTarget() {
    #expect(ShopCheck.target("http://sklep.pl/x")?.absoluteString == "https://sklep.pl/x")
    #expect(ShopCheck.target(" sklep.pl ")?.absoluteString == "https://sklep.pl")
    #expect(ShopCheck.target("hello") == nil)
    #expect(ShopCheck.target("") == nil)
}

@Test func unescapesEntities() {
    #expect(ShopCheck.unescape("Sp&oacute;&#322;ka &amp; &#x142;") == "Spółka & ł")
}

/// Answers from a fake network: the longest matching URL start to the page text, everything else a 404.
private func network(_ pages: [String: String]) -> ShopCheck.Fetch {
    { url, _ in
        guard let text = pages.filter({ url.absoluteString.hasPrefix($0.key) }).max(by: { $0.key.count < $1.key.count })?.value
        else { throw ShopCheck.HTTPStatus(code: 404) }
        return ShopCheck.Page(url: url, text: text)
    }
}

@Test func certListedShopIsNeverOpened() async {
    let report = await ShopCheck.run(ShopCheck.target("www.fake-shop.pl")!, fetch: network([
        "https://hole.cert.pl": "other.pl\nfake-shop.pl\n",
        "https://www.fake-shop.pl": "should not be read",
    ]))
    #expect(report.verdict == .fraud && report.findings.count == 1)
}

@Test func fullCheckOfAnHonestShop() async {
    let today = ShopCheck.date("2026-10-28", "yyyy-MM-dd")!
    let report = await ShopCheck.run(ShopCheck.target("kowalski.pl")!, today: today, fetch: network([
        "https://hole.cert.pl": "other.pl",
        "https://rdap.org": #"{"events":[{"eventAction":"registration","eventDate":"2012-03-01T10:00:00Z"}]}"#,
        "https://web.archive.org": #"[["timestamp"],["20120401000000"]]"#,
        "https://kowalski.pl/regulamin": terms,
        "https://kowalski.pl": legit,
        "https://wl-api.mf.gov.pl": #"{"result":{"entries":[{"identifier":"9562307719","subjects":[{"name":"SKLEP KOWALSKI SP. Z O.O.","nip":"9562307719","statusVat":"Czynny","registrationLegalDate":"2012-01-10","accountNumbers":["53102050110000900202706323"],"hasVirtualAccounts":false,"krs":"0000514685","workingAddress":"UL. DŁUGA 1, 00-001 WARSZAWA","residenceAddress":null}]}]}}"#,
        "https://api-krs.ms.gov.pl": #"{"odpis":{"naglowekA":{"dataRejestracjiWKRS":"10.01.2012"},"dane":{"dzial1":{"danePodmiotu":{"nazwa":"SKLEP KOWALSKI SP. Z O.O.","identyfikatory":{"nip":"9562307719"}}},"dzial3":{"przedmiotDzialalnosci":{"przedmiotPrzewazajacejDzialalnosci":[{"kodDzial":"47","opis":"SPRZEDAŻ DETALICZNA"}]}}}}}"#,
    ]))
    #expect(report.score == 0, "\(report.findings)")
    #expect(report.verdict == .clear)
    #expect(report.findings.contains { $0.text.contains("belongs to this company") })
    #expect(report.hints.contains { $0.text.contains("Street View") })
}
