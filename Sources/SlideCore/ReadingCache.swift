import Foundation

/// 保持するDataの合計上限。返却値と解析中の一時領域は含めない。
public struct ReadingCacheStatistics: Sendable, Equatable {
    public let retainedBytes: Int
    /// 複数cacheでは各peakの和。文書全体の同時peakに対する上界。
    public let peakRetainedBytes: Int
    public let hits: Int
    public let misses: Int
    public init(retainedBytes: Int, peakRetainedBytes: Int, hits: Int, misses: Int) { self.retainedBytes = retainedBytes; self.peakRetainedBytes = peakRetainedBytes; self.hits = hits; self.misses = misses }
    package func adding(_ other: Self) -> Self { .init(retainedBytes:retainedBytes+other.retainedBytes,peakRetainedBytes:peakRetainedBytes+other.peakRetainedBytes,hits:hits+other.hits,misses:misses+other.misses) }
}
/// 圧縮bytesと展開索引の合計保持予算。半分ずつ割り当てる。
/// 返却モデルは呼出側が所有し、assetはcacheへ複製しない。RSS制限とは区別する。
public struct ReaderCacheBudget: Sendable, Equatable {
    public let totalBytes: Int
    public init(totalBytes: Int) { self.totalBytes = totalBytes }
}
/// Lockは所有者が取る。辞書でslotを引き、配列内のリンクだけでLRU順を更新する。
package struct LRUDataCache<Key: Hashable> {
    private struct Entry {
        var key: Key?
        var data: Data
        var previous = -1
        var next = -1
    }
    private let limit: Int
    private var indices: [Key: Int] = [:]
    private var entries: [Entry] = []
    private var free: [Int] = []
    private var oldest = -1, newest = -1
    private var size = 0, peak = 0, hits = 0, misses = 0
    package init(limit: Int) { self.limit = max(0, limit) }
    package var statistics: ReadingCacheStatistics {
        .init(retainedBytes: size, peakRetainedBytes: peak, hits: hits, misses: misses)
    }
    package mutating func value(for key: Key) -> Data? {
        guard let index = indices[key] else { misses += 1; return nil }
        hits += 1
        if newest != index { unlink(index); append(index) }
        return entries[index].data
    }
    package mutating func insert(_ data: Data, for key: Key) {
        if let index = indices[key] { remove(index) }
        // Empty payloads must not retain unbounded key/link metadata, even with a zero budget.
        guard !data.isEmpty, data.count <= limit else { return }
        while size > limit - data.count { remove(oldest) }
        let index: Int
        if let slot = free.popLast() { index = slot; entries[index] = Entry(key: key, data: data) }
        else { index = entries.count; entries.append(Entry(key: key, data: data)) }
        indices[key] = index
        append(index)
        size += data.count; peak = max(peak, size)
    }
    private mutating func remove(_ index: Int) {
        unlink(index)
        indices.removeValue(forKey: entries[index].key!)
        size -= entries[index].data.count
        entries[index] = Entry(key: nil, data: Data())
        free.append(index)
    }
    private mutating func unlink(_ index: Int) {
        let previous = entries[index].previous, next = entries[index].next
        if previous >= 0 { entries[previous].next = next } else { oldest = next }
        if next >= 0 { entries[next].previous = previous } else { newest = previous }
    }
    private mutating func append(_ index: Int) {
        entries[index].previous = newest; entries[index].next = -1
        if newest >= 0 { entries[newest].next = index } else { oldest = index }
        newest = index
    }
}

package final class ReadingDataCache: @unchecked Sendable {
    private let lock = NSLock()
    private var cache: LRUDataCache<String>
    package init(limit: Int) { cache = .init(limit: limit) }
    package var statistics: ReadingCacheStatistics { lock.withLock { cache.statistics } }
    package func value(for key: String) -> Data? { lock.withLock { cache.value(for: key) } }
    package func insert(_ data: Data, for key: String) { lock.withLock { cache.insert(data, for: key) } }
}
