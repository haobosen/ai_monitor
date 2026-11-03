import Foundation

/// 判断用户输入是不是“继续 / 好的 / ok”这类没有实际信息量的推进语
enum PromptText {

    /// 组成 filler 的词元，按长度从长到短匹配，避免 "go" 抢先匹配 "goon"
    private static let fillerTokens: [String] = [
        "continueplease", "keepgoing", "carryon", "goahead",
        "继续努力", "继续完成", "继续执行", "继续处理", "继续做", "继续干", "继续吧", "继续",
        "接着做", "接着来", "接着", "往下做", "往下走", "往下",
        "下一步", "然后呢", "开始吧", "来吧", "走起", "搞起",
        "好的", "好滴", "好呀", "好吧", "好", "行的", "行", "可以的", "可以",
        "嗯嗯", "嗯", "哦", "噢", "吧", "啊", "呀", "呢", "啦",
        "收到", "了解", "明白", "知道了", "谢谢", "thanks", "thankyou", "辛苦了",
        "请", "帮我", "帮忙", "麻烦", "please", "okay", "ok", "yes", "yeah", "sure", "proceed", "resume",
        "again", "more", "next", "goon", "go", "continue",
    ].sorted { $0.count > $1.count }

    static func isFiller(_ text: String) -> Bool {
        let compact = compacted(text)
        guard !compact.isEmpty else { return true }
        if fillerTokens.contains(compact) { return true }

        // “好的继续”“ok 继续”“继续吧谢谢”这类组合
        var rest = compact
        while let token = fillerTokens.first(where: { rest.hasPrefix($0) }) {
            rest.removeFirst(token.count)
        }
        return rest.isEmpty
    }

    /// 去掉空格、标点、表情，只留下文字和数字，方便比较
    private static func compacted(_ text: String) -> String {
        let allowed = CharacterSet.letters.union(.decimalDigits)
        var result = ""
        for scalar in text.lowercased().unicodeScalars where allowed.contains(scalar) {
            result.unicodeScalars.append(scalar)
        }
        return result
    }
}
