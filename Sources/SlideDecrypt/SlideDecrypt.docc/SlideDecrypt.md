# ``SlideDecrypt``

パスワード付きのプレゼンテーションを平文snapshotへ復号する任意製品です。

## Overview

`Package.swift`の依存製品に`SlideDecrypt`を追加すると、`SwiftSlides`の共通モデルと通常codecも利用できます。
通常の`SwiftSlides`だけをリンクするアプリには復号処理を追加しません。

```swift
import SlideDecrypt

let result = try Presentation.read(encryptedBytes, password: password)
print(result.presentation.slides)
print(result.diagnostics)
```

OOXML Agile/StandardのAES、ODF AES-CBC、現行Keynoteのiwpv2 v2/f1を対象とします。
誤passwordと未対応方式を区別し、サイズ・KDF回数・paddingを検査します。
Agileは存在するHMAC、ODFはchecksumを検証します。Standardには全体HMACがなく、Keynote stream末尾20bytesは未解釈です。
確認済みの範囲は`Decryption.capabilities(for:)`から取得します。

復号snapshotをPPTXとして通常保存すると平文になります。ReadResultはこの境界を診断として返します。
再暗号化、IRM/証明書、RC4/Blowfish、ODP/Keynoteへの保存は提供しません。
使用例と原本の取得方法は[SwiftSlidesの使用例](https://github.com/nanbu/SwiftSlides/blob/main/docs/cookbook.md)を参照してください。
