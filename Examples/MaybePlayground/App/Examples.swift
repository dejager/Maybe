import Foundation

/// Original, deliberately small programs. The demo provider simulates every model call.
enum Example: String, CaseIterable, Identifiable {
    case urgency, jargon, chaos

    var id: String { rawValue }
    var title: String {
        switch self {
        case .urgency: "Inbox"
        case .jargon: "Rewrite"
        case .chaos: "Chaos"
        }
    }
    var filename: String {
        switch self {
        case .urgency: "inbox.prob"
        case .jargon: "rewrite.prob"
        case .chaos: "chaos.prob"
        }
    }
    var symbol: String {
        switch self {
        case .urgency: "tray"
        case .jargon: "text.quote"
        case .chaos: "dice"
        }
    }
    var input: String {
        switch self {
        case .urgency: "Can we talk about the launch sometime today?"
        case .jargon: "Let's leverage our synergies to move the needle."
        case .chaos: "A social network for your houseplants."
        }
    }
    var source: String {
        switch self {
        case .urgency:
            """
            // Uncertainty gets its own branch.
            if input() feels "urgent" with confidence 80% {
              print("Put down the coffee. This needs you.")
            } otherwise maybe {
              print("The computer would like more context. Relatable.")
            } else {
              print("Your coffee remains the priority.")
            }
            """
        case .jargon:
            """
            // The demo rewrite uses simple replacement rules.
            let draft = llm "Rewrite plainly in one short sentence." using input()
            print("A sentence has escaped the strategy deck:")
            print(draft)
            """
        case .chaos:
            """
            // Sample a branch. Keep the receipt.
            chaos {
              match input() {
                "a brilliant idea" => {
                  print("Someone get this fern a pitch deck.")
                }
                "a terrible idea" => {
                  print("The fern has declined to comment.")
                }
              }
            }
            """
        }
    }
}
