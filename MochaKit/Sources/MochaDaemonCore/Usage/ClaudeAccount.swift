import Foundation

public struct ClaudeAccount: Sendable, Equatable {
    public var plan: String?
    public var account: String?

    public init(plan: String? = nil, account: String? = nil) {
        self.plan = plan
        self.account = account
    }

    public static func parse(_ data: Data) -> ClaudeAccount {
        guard let file = try? JSONDecoder().decode(AccountFile.self, from: data) else { return ClaudeAccount() }
        return ClaudeAccount(
            plan: file.oauthAccount?.organizationRateLimitTier.flatMap(plan(forTier:)),
            account: file.oauthAccount?.emailAddress.flatMap(maskedEmail)
        )
    }

    public static func plan(forTier tier: String) -> String? {
        let tier = tier.lowercased()
        if tier.contains("max_20x") {
            return "Max 20x"
        }
        if tier.contains("max_5x") {
            return "Max 5x"
        }
        if tier.contains("pro") {
            return "Pro"
        }
        return nil
    }

    public static func maskedEmail(_ email: String) -> String? {
        let parts = email.split(separator: "@", omittingEmptySubsequences: false)
        guard parts.count == 2, let userInitial = parts[0].first, let domainInitial = parts[1].first else { return nil }
        let labels = parts[1].split(separator: ".", omittingEmptySubsequences: false)
        let suffix = labels.count > 1 ? "." + (labels.last ?? "") : ""
        return "\(userInitial)•••@\(domainInitial)•••\(suffix)"
    }

    private struct AccountFile: Decodable {
        struct OAuthAccount: Decodable {
            let organizationRateLimitTier: String?
            let emailAddress: String?

            init(from decoder: any Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)
                organizationRateLimitTier = try? container.decodeIfPresent(String.self, forKey: .organizationRateLimitTier)
                emailAddress = try? container.decodeIfPresent(String.self, forKey: .emailAddress)
            }

            enum CodingKeys: String, CodingKey {
                case organizationRateLimitTier
                case emailAddress
            }
        }

        let oauthAccount: OAuthAccount?

        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            oauthAccount = try? container.decodeIfPresent(OAuthAccount.self, forKey: .oauthAccount)
        }

        enum CodingKeys: String, CodingKey {
            case oauthAccount
        }
    }
}
