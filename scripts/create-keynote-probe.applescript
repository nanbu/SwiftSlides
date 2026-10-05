-- 架空2枚の資料。型抽出・再署名は行わない。既定themeは実行環境に依存する。
on run argv
    if (count of argv) is not 1 then error "出力する.keyの絶対パスを一つ指定してください"
    tell application "Keynote Creator Studio"
        set d to make new document with properties {width:960, height:540}
        tell d
            tell slide 1
                set object text of default title item to "Synthetic title A"
                set object text of default body item to "Fictional body"
                set presenter notes to "Synthetic notes"
            end tell
            set s to make new slide
            set object text of default title item of s to "Second slide"
            save in POSIX file (item 1 of argv)
            close saving no
        end tell
        return version
    end tell
end run
