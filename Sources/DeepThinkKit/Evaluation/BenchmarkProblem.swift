import Foundation

// MARK: - Benchmark Problem

public struct BenchmarkProblem: Identifiable, Sendable {
    public let id: String
    public let question: String
    public let expectedAnswer: String
    public let acceptableAnswers: [String]
    public let category: Category
    public let difficulty: Difficulty

    public enum Category: String, Sendable, CaseIterable {
        case arithmetic
        case logic
        case trickQuestion
        case multiStep
        case spatial
    }

    public enum Difficulty: String, Sendable {
        case easy
        case medium
        case hard
    }

    public init(
        id: String = UUID().uuidString,
        question: String,
        expectedAnswer: String,
        acceptableAnswers: [String] = [],
        category: Category,
        difficulty: Difficulty = .medium
    ) {
        self.id = id
        self.question = question
        self.expectedAnswer = expectedAnswer
        self.acceptableAnswers = acceptableAnswers.isEmpty ? [expectedAnswer] : acceptableAnswers
        self.category = category
        self.difficulty = difficulty
    }
}

// MARK: - Standard Benchmark Set

extension BenchmarkProblem {
    /// Problems exploiting single-pass weaknesses:
    /// conditional branching, entity swaps, and step-by-step state tracking.
    public static let standardSet: [BenchmarkProblem] = [
        // 5-step conditional chain with 2 conditions
        // 8→16→16>10→16-6=10→10*2=20→20 is even→20/2=10
        BenchmarkProblem(
            id: "cond-5step",
            question: "Start with 8. Step 1: double it. Step 2: if result > 10, subtract 6; otherwise add 4. Step 3: multiply by 2. Step 4: if even, divide by 2; if odd, add 1. Step 5: subtract 3. What is the final number?",
            expectedAnswer: "7",
            category: .multiStep
        ),
        // Explicit 6-step even/odd chain
        // 7→14→7→14→7→14→7
        BenchmarkProblem(
            id: "evenodd-6",
            question: "Start with 7. Apply this rule 6 times in a row: if the current number is even, divide it by 2; if it is odd, multiply it by 2. What is the number after all 6 applications?",
            expectedAnswer: "7",
            category: .multiStep,
            difficulty: .hard
        ),
        // 4 swaps with 4 positions: harder tracking
        // A=1,B=2,C=3,D=4 → A↔D → A=4,B=2,C=3,D=1 → B↔C → A=4,B=3,C=2,D=1
        // → A↔B → A=3,B=4,C=2,D=1 → C↔D → A=3,B=4,C=1,D=2
        BenchmarkProblem(
            id: "swap-4",
            question: "Four cards labeled 1,2,3,4 are in slots A,B,C,D. Swap A and D. Swap B and C. Swap A and B. Swap C and D. What card is in slot A?",
            expectedAnswer: "3",
            category: .logic,
            difficulty: .hard
        ),
        // Multi-variable update: must track x and y through 3 changes
        // x=3,y=5 → x=8,y=5 → x=8,y=3 → x=24,y=3 → 24-3=21
        BenchmarkProblem(
            id: "2var",
            question: "x starts at 3, y starts at 5. Step 1: set x = x + y. Step 2: set y = x - y. Step 3: set x = x * y. What is x minus y?",
            expectedAnswer: "21",
            category: .multiStep
        ),
        // Letter-by-letter conditional accumulator
        // C(+1)=1, A(+5)=6, B(-2)=4, B(-2)=2, A(+5)=7, G(+1)=8, E(+5)=13
        BenchmarkProblem(
            id: "letter-acc",
            question: "Start a counter at 0. Go through each letter of 'CABBAGE' one by one. For each letter: if it is A or E, add 5 to the counter. If it is B, subtract 2. For any other letter, add 1. What is the final counter value?",
            expectedAnswer: "13",
            category: .multiStep,
            difficulty: .hard
        ),
        // 6-stop bus with mixed operations
        // 0+10=10, 10-4+3=9, 9→odd→+1=10, 10/2=5, 5+8=13, 13-5=8
        BenchmarkProblem(
            id: "bus-6",
            question: "A bus starts empty. Stop 1: 10 board. Stop 2: 4 exit, 3 board. Stop 3: if passenger count is odd, 1 more boards; if even, nobody. Stop 4: half the passengers exit. Stop 5: 8 board. Stop 6: 5 exit. How many passengers?",
            expectedAnswer: "8",
            category: .multiStep,
            difficulty: .hard
        ),
        // Japanese: conditional even/odd chain (5 iterations)
        // 50→25→26→13→14→7
        BenchmarkProblem(
            id: "jp-cond",
            question: "数字の50から始めます。偶数なら2で割り、奇数なら1を足します。この操作を5回繰り返すと最後の数字はいくつですか？",
            expectedAnswer: "7",
            category: .multiStep,
            difficulty: .hard
        ),
        // 4-step price chain with conditional discount
        // 60*2=120 → 120>100→-25%→90 → 90-15=75 → 75>70→tax 10%→82.5→round=82
        // Actually let me make all integer: 60*2=120, 120>100→-20=100, 100/2=50, 50+6=56
        BenchmarkProblem(
            id: "price-4step",
            question: "An item costs $60. Step 1: double the price. Step 2: if over $100, subtract $20; otherwise add $10. Step 3: take half. Step 4: add $6. What is the final price?",
            expectedAnswer: "56",
            acceptableAnswers: ["56", "$56"],
            category: .multiStep
        ),
        // 4 cup swaps (harder than 3)
        // A=coin,B,C,D empty → A↔C:C=coin → B↔D:no change → A↔D:no change → B↔C:B=coin
        BenchmarkProblem(
            id: "cup-4swap",
            question: "A coin is under Cup A. Cups B, C, D are empty. Swap A and C. Then swap B and D. Then swap A and D. Then swap B and C. Which cup has the coin?",
            expectedAnswer: "B",
            acceptableAnswers: ["B", "Cup B", "b"],
            category: .logic,
            difficulty: .hard
        ),
        // 5-step with 2 variables and multiple conditions
        // x=5,y=8 → x=13,y=8 → 13 odd→y=y-3=5 → x=13-5=8,y=5 → 8 even→x=x/2=4 → x+y=9
        BenchmarkProblem(
            id: "cond-5var",
            question: "x=5, y=8. Step 1: x = x + y. Step 2: if x is odd, set y = y - 3; if x is even, set y = y + 3. Step 3: x = x - y. Step 4: if x is even, set x = x / 2; if x is odd, set x = x * 2. What is x + y?",
            expectedAnswer: "9",
            category: .multiStep,
            difficulty: .hard
        ),
        // Catch-up / pursuit problem requiring relative velocity concept
        // John head start: 4km/h × 1h = 4km. Relative speed: 6-4 = 2km/h. Time: 4/2 = 2h after Mike starts = 3h after John left
        BenchmarkProblem(
            id: "catchup",
            question: "John walks at 4 km/h. One hour later, Mike chases him at 6 km/h. How many hours after John left does Mike catch up?",
            expectedAnswer: "3",
            acceptableAnswers: ["3", "3 hours", "3時間"],
            category: .multiStep
        ),
        // Japanese version of catch-up problem
        // 太郎の先行距離: 4×1=4km, 速度差: 6-4=2km/h, 追いつく: 4÷2=2h後(次郎出発から), 太郎出発から3時間
        BenchmarkProblem(
            id: "catchup-jp",
            question: "太郎は時速4kmで歩いている。1時間後に次郎が時速6kmで追いかけた。太郎が出発して何時間後に追いつく？",
            expectedAnswer: "3",
            acceptableAnswers: ["3", "3時間", "3時間後"],
            category: .multiStep
        ),
    ]
}

// MARK: - Answer Extraction

public enum AnswerExtractor {
    /// Extract the final answer from model output text.
    public static func extract(from text: String) -> String? {
        let lines = text.components(separatedBy: .newlines)

        // Scan from bottom for explicit answer markers
        let markers = [
            "Final Answer:", "final answer:", "Answer:", "answer:",
            "答え:", "答え：", "最終回答:", "最終回答：",
            "ANSWER:", "FINAL ANSWER:",
        ]

        for line in lines.reversed() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            for marker in markers {
                if let range = trimmed.range(of: marker, options: .caseInsensitive) {
                    let answer = trimmed[range.upperBound...]
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    if !answer.isEmpty {
                        return cleanAnswer(answer)
                    }
                }
            }
        }

        // Fallback: extract the last number from the text (more permissive)
        let pattern = #"(\d+(?:\.\d+)?)"#
        if let regex = try? NSRegularExpression(pattern: pattern) {
            let matches = regex.matches(
                in: text, range: NSRange(text.startIndex..., in: text)
            )
            if let lastMatch = matches.last,
               let range = Range(lastMatch.range(at: 1), in: text) {
                return String(text[range])
            }
        }

        return nil
    }

    private static func cleanAnswer(_ answer: String) -> String {
        var result = answer
        while result.hasSuffix(".") || result.hasSuffix("。")
            || result.hasSuffix("!") || result.hasSuffix("！") {
            result = String(result.dropLast())
        }
        result = result.replacingOccurrences(of: "**", with: "")
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - Answer Matching

public enum AnswerMatcher {
    public static func matches(
        actual: String?,
        expected: String,
        acceptableAnswers: [String]
    ) -> Bool {
        guard let actual else { return false }
        let normalizedActual = normalize(actual)

        for acceptable in acceptableAnswers {
            let normalizedExpected = normalize(acceptable)

            // Exact match
            if normalizedActual == normalizedExpected { return true }

            // Contains match — only for answers longer than 2 chars
            if normalizedActual.count > 2, normalizedActual.contains(normalizedExpected) { return true }
            if normalizedExpected.count > 2, normalizedExpected.contains(normalizedActual),
               normalizedActual.count > 2 { return true }

            // Numeric match
            if let actualNum = Double(normalizedActual),
               let expectedNum = Double(normalizedExpected),
               abs(actualNum - expectedNum) < 0.001 {
                return true
            }
        }

        return false
    }

    private static func normalize(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "　", with: " ")
    }
}
