/// 入力順を保つ構造化並行処理。結果全体のmemory budgetではない。
@concurrent package func boundedMap<Input: Sendable, Output: Sendable>(
    _ inputs: [Input], maxConcurrent: Int,
    operation: @escaping @Sendable (Input) async throws -> Output
) async throws -> [Output] {
    guard maxConcurrent > 0 else { throw SlideError.invalidModel("同時読取数は正の整数が必要です") }
    try Task.checkCancellation()
    return try await withThrowingTaskGroup(of: (Int, Output).self) { group in
        defer { group.cancelAll() }
        var results = [Output?](repeating: nil, count: inputs.count)
        var next = 0
        func submit(_ index: Int) throws {
            let input = inputs[index]
            guard group.addTaskUnlessCancelled(operation: {
                try Task.checkCancellation()
                return (index, try await operation(input))
            }) else { throw CancellationError() }
        }
        while next < min(maxConcurrent, inputs.count) { try submit(next); next += 1 }
        while let (index, value) = try await group.next() {
            try Task.checkCancellation()
            results[index] = value
            if next < inputs.count { try submit(next); next += 1 }
        }
        try Task.checkCancellation()
        // 全入力を一度だけsubmitし、全結果を受け取った経路のみ到達する。
        return results.map { $0! }
    }
}
