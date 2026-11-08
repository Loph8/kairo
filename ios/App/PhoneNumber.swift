import Foundation

/// Phone numbers as the server stores them: E.164, "+" then country code and number, no spaces.
enum PhoneNumber {
    /// Dialing codes for the regions Kairos families most often live in. Others start with just "+".
    private static let dialCodes: [String: String] = [
        "US": "1", "CA": "1", "KR": "82", "JP": "81", "CN": "86", "TW": "886", "HK": "852", "SG": "65",
        "GB": "44", "DE": "49", "FR": "33", "ES": "34", "IT": "39", "AU": "61", "NZ": "64", "IN": "91",
        "PH": "63", "VN": "84", "TH": "66", "ID": "62", "MX": "52", "BR": "55", "ET": "251", "NG": "234",
        "KE": "254", "ZA": "27",
    ]

    /// "+1 " for a phone set to the US, so people only type the rest.
    static func dialPrefix(region: String? = Locale.current.region?.identifier) -> String {
        guard let region, let code = dialCodes[region] else { return "+" }
        return "+\(code) "
    }

    /// "+1 (919) 555-0123" → "+19195550123". Nil unless it has a country code and a plausible length,
    /// matching the server's check.
    static func normalized(_ raw: String) -> String? {
        let stripped = raw.filter { !" -().".contains($0) }
        guard stripped.first == "+" else { return nil }
        let digits = stripped.dropFirst()
        guard (7...15).contains(digits.count), digits.allSatisfy(\.isASCII), digits.allSatisfy(\.isNumber),
              digits.first != "0" else { return nil }
        return stripped
    }
}
