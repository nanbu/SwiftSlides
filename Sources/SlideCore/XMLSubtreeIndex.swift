import Foundation

/// XMLParserによる検証後、要素の通し番号をUTF-8 byte範囲に対応させる。
/// comment/CDATA/引用符を飛ばし、本文のDOMや文字列をページ数分複製しない。
package enum XMLSubtreeIndex {
    package static func utf8(_ data: Data) throws -> Data {
        let b = Array(data.prefix(4))
        let encoding: String.Encoding?
        if b == [0,0,0,60] { encoding = .utf32BigEndian }
        else if b == [60,0,0,0] { encoding = .utf32LittleEndian }
        else if b.count >= 2, b[0] == 0 && b[1] == 60 { encoding = .utf16BigEndian }
        else if b.count >= 2, b[0] == 60 && b[1] == 0 { encoding = .utf16LittleEndian }
        else { encoding = nil }
        if let encoding, let string = String(data:data,encoding:encoding) { return Data(string.utf8) }
        if String(data:data,encoding:.utf8) != nil { return data }
        for encoding: String.Encoding in [.utf32,.utf16] { if let text = String(data:data,encoding:encoding) { return Data(text.utf8) } }
        throw SlideError.invalidXML(part:"content.xml",detail:"XML索引の文字コード")
    }
    package static func ranges(_ data: Data, selected: Set<Int>) throws -> [Int:Range<Int>] {
        try data.withUnsafeBytes { (b: UnsafeRawBufferPointer) in
        var offset = 0, ordinal = 0, stack: [(Int,Int)] = [], result: [Int:Range<Int>] = [:]
        func starts(_ text: StaticString, _ i: Int) -> Bool {
            text.withUTF8Buffer { bytes in i <= b.count - bytes.count && b[i..<i + bytes.count].elementsEqual(bytes) }
        }
        func skip(_ terminator: StaticString) throws { while offset < b.count, !starts(terminator,offset) { offset += 1 }; guard offset < b.count else { throw SlideError.corruptedPackage("XML索引境界") }; offset += terminator.utf8CodeUnitCount }
        while offset < b.count {
            try Task.checkCancellation()
            guard b[offset] == 60 else { offset += 1; continue }
            if starts("<!--",offset) { offset += 4; try skip("-->"); continue }
            if starts("<![CDATA[",offset) { offset += 9; try skip("]]>"); continue }
            if starts("<?",offset) { offset += 2; try skip("?>"); continue }
            guard !starts("<!",offset) else { throw SlideError.corruptedPackage("XML索引の宣言") }
            let start = offset, closing = starts("</",offset); offset += 1
            var quote: UInt8?
            while offset < b.count {
                let c = b[offset]
                if let delimiter = quote { if c == delimiter { quote = nil } }
                else if c == 34 || c == 39 { quote = c }
                else if c == 62 { break }
                offset += 1
            }
            guard offset < b.count else { throw SlideError.corruptedPackage("XML索引tag切断") }
            let empty = b[offset-1] == 47; offset += 1
            if closing {
                guard let (id,begin) = stack.popLast() else { throw SlideError.corruptedPackage("XML索引の閉じtag") }
                if selected.contains(id) { result[id] = begin..<offset }
            } else {
                ordinal += 1
                if empty { if selected.contains(ordinal) { result[ordinal] = start..<offset } }
                else { stack.append((ordinal,start)) }
            }
        }
        guard stack.isEmpty, result.count == selected.count else { throw SlideError.corruptedPackage("XML索引の欠落") }; return result
        }
    }
}
