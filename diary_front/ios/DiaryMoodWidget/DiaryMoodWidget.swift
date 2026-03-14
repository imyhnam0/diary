import WidgetKit
import SwiftUI
import UIKit

private let widgetBackgroundColor = Color.white
private let widgetPrimaryTextColor = Color.black
private let widgetSecondaryTextColor = Color(red: 0.18, green: 0.18, blue: 0.18)

private extension View {
    @ViewBuilder
    func diaryWidgetBackground() -> some View {
        if #available(iOSApplicationExtension 17.0, *) {
            containerBackground(for: .widget) {
                widgetBackgroundColor
            }
        } else {
            background(widgetBackgroundColor)
        }
    }
}

private func widgetLocalized(_ key: String) -> String {
    NSLocalizedString(key, comment: "")
}

private enum WidgetConstants {
    static let appGroupId = "group.com.imyhnam.diary"
    static let keyToday = "widget_today_emoji"
    static let keyTodayImage = "widget_today_image_base64"
    static let keyRecent = "widget_recent_emojis"
    static let keyRecentImages = "widget_recent_images"
    static let keyMonth = "widget_month_key"
    static let keyMonthMap = "widget_month_map"
    static let keyMonthMapImages = "widget_month_map_images"
    static let keyLanguage = "widget_language"
}

enum WidgetLanguage: String {
    case ko
    case en

    init(code: String) {
        self = code == "en" ? .en : .ko
    }

    var todayTitle: String { self == .en ? "TODAY" : "오늘" }
    var monthTitle: String { self == .en ? "MONTH" : "이번 달" }
    var recentTitle: String { self == .en ? "RECENT" : "최근" }
    var emptyText: String { self == .en ? "None" : "없음" }
    var weekdays: [String] {
        self == .en
            ? ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
            : ["일", "월", "화", "수", "목", "금", "토"]
    }

    func monthText(_ month: Int) -> String {
        self == .en ? "\(month)" : "\(month)월"
    }
}

struct DiaryMoodEntry: TimelineEntry {
    let date: Date
    let language: WidgetLanguage
    let todayEmoji: String
    let todayImageData: Data?
    let recentEmojis: [String]
    let recentImageData: [Data?]
    let monthKey: String
    let monthEmojiByDay: [Int: String]
    let monthImageByDay: [Int: Data]
}

struct DiaryMoodProvider: TimelineProvider {
    func placeholder(in context: Context) -> DiaryMoodEntry {
        DiaryMoodEntry(
            date: Date(),
            language: .ko,
            todayEmoji: "🙂",
            todayImageData: nil,
            recentEmojis: ["🙂", "😊", "🥰", "😴", "😰", "😢"],
            recentImageData: [nil, nil, nil, nil, nil, nil],
            monthKey: "2026-03",
            monthEmojiByDay: [1: "🙂", 2: "😮", 3: "😡", 4: "😢"],
            monthImageByDay: [:]
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (DiaryMoodEntry) -> Void) {
        completion(loadEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<DiaryMoodEntry>) -> Void) {
        let entry = loadEntry()
        let nextRefresh = Calendar.current.date(byAdding: .minute, value: 30, to: Date()) ?? Date().addingTimeInterval(1800)
        completion(Timeline(entries: [entry], policy: .after(nextRefresh)))
    }

    private func loadEntry() -> DiaryMoodEntry {
        let defaults = UserDefaults(suiteName: WidgetConstants.appGroupId)
        let language = WidgetLanguage(code: defaults?.string(forKey: WidgetConstants.keyLanguage) ?? "ko")
        let today = defaults?.string(forKey: WidgetConstants.keyToday) ?? ""
        let todayImage = Data(base64Encoded: defaults?.string(forKey: WidgetConstants.keyTodayImage) ?? "")
        let recent = (defaults?.stringArray(forKey: WidgetConstants.keyRecent) ?? []).prefix(6)
        let recentImageStrings = Array((defaults?.stringArray(forKey: WidgetConstants.keyRecentImages) ?? []).prefix(6))
        var recentImages: [Data?] = []
        for index in 0..<6 {
            let encoded = index < recentImageStrings.count ? recentImageStrings[index] : ""
            recentImages.append(Data(base64Encoded: encoded))
        }
        let month = defaults?.string(forKey: WidgetConstants.keyMonth) ?? ""
        let rawMonthMap = defaults?.dictionary(forKey: WidgetConstants.keyMonthMap) as? [String: String] ?? [:]
        let rawMonthImageMap = defaults?.dictionary(forKey: WidgetConstants.keyMonthMapImages) as? [String: String] ?? [:]
        var monthMap: [Int: String] = [:]
        var monthImageMap: [Int: Data] = [:]
        for (key, value) in rawMonthMap {
            if let day = Int(key), !value.isEmpty {
                monthMap[day] = value
            }
        }
        for (key, value) in rawMonthImageMap {
            if let day = Int(key), let imageData = Data(base64Encoded: value) {
                monthImageMap[day] = imageData
            }
        }
        let current = Date()
        let todayDay = Calendar.current.component(.day, from: current)
        let todayKey = "\(todayDay)"
        let currentMonthKey = Self.monthKey(from: current)
        let monthIsCurrent = month == currentMonthKey
        let dayEmoji = rawMonthMap[todayKey] ?? ""
        let dayImageData = Data(base64Encoded: rawMonthImageMap[todayKey] ?? "")
        let hasTodayRecord = monthIsCurrent && (!dayEmoji.isEmpty || dayImageData != nil)
        let resolvedTodayEmoji = hasTodayRecord ? (today.isEmpty ? dayEmoji : today) : ""
        let resolvedTodayImage = hasTodayRecord ? (todayImage ?? dayImageData) : nil
        return DiaryMoodEntry(
            date: Date(),
            language: language,
            todayEmoji: resolvedTodayEmoji,
            todayImageData: resolvedTodayImage,
            recentEmojis: Array(recent),
            recentImageData: recentImages,
            monthKey: month,
            monthEmojiByDay: monthMap,
            monthImageByDay: monthImageMap
        )
    }

    private static func monthKey(from date: Date) -> String {
        let comps = Calendar.current.dateComponents([.year, .month], from: date)
        let year = comps.year ?? 0
        let month = comps.month ?? 0
        return String(format: "%04d-%02d", year, month)
    }
}

struct MoodIconView: View {
    let imageData: Data?
    let emoji: String
    let size: CGFloat
    let emptyText: String

    var body: some View {
        if let imageData, let uiImage = UIImage(data: imageData) {
            Image(uiImage: uiImage)
                .resizable()
                .scaledToFit()
                .frame(width: size, height: size)
        } else {
            Text(emoji.isEmpty ? emptyText : emoji)
                .font(.system(size: size * 0.75))
                .foregroundStyle(widgetPrimaryTextColor)
                .frame(width: size, height: size)
        }
    }
}

struct DiaryTodayWidgetEntryView: View {
    var entry: DiaryMoodProvider.Entry

    var body: some View {
        ZStack {
            widgetBackgroundColor
            VStack(alignment: .leading, spacing: 12) {
                Text(entry.language.todayTitle)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(widgetPrimaryTextColor)
                if entry.todayImageData == nil && entry.todayEmoji.isEmpty {
                    Text(entry.language.emptyText)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(widgetSecondaryTextColor)
                } else {
                    MoodIconView(
                        imageData: entry.todayImageData,
                        emoji: entry.todayEmoji,
                        size: 64,
                        emptyText: entry.language.emptyText
                    )
                }
            }
            .padding(14)
        }
        .diaryWidgetBackground()
    }
}

struct DiaryMonthSummaryWidgetEntryView: View {
    var entry: DiaryMoodProvider.Entry

    var body: some View {
        ZStack {
            widgetBackgroundColor
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(entry.language.monthTitle)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(widgetPrimaryTextColor)
                    Spacer()
                    Text(monthTitle(from: entry.monthKey))
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(widgetPrimaryTextColor)
                }
                HStack(spacing: 8) {
                    ForEach(0..<3, id: \.self) { index in
                        let emoji = index < entry.recentEmojis.count ? entry.recentEmojis[index] : ""
                        let imageData = index < entry.recentImageData.count ? entry.recentImageData[index] : nil
                        MoodIconView(
                            imageData: imageData,
                            emoji: emoji,
                            size: 32,
                            emptyText: ""
                        )
                            .frame(maxWidth: .infinity)
                    }
                }
                Text(entry.language.recentTitle)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(widgetPrimaryTextColor)
                HStack(spacing: 4) {
                    ForEach(0..<6, id: \.self) { index in
                        let emoji = index < entry.recentEmojis.count ? entry.recentEmojis[index] : ""
                        let imageData = index < entry.recentImageData.count ? entry.recentImageData[index] : nil
                        MoodIconView(
                            imageData: imageData,
                            emoji: emoji,
                            size: 24,
                            emptyText: ""
                        )
                            .frame(maxWidth: .infinity)
                    }
                }
            }
            .padding(14)
        }
        .diaryWidgetBackground()
    }

    private func monthTitle(from key: String) -> String {
        let chunks = key.split(separator: "-")
        if chunks.count == 2 {
            return entry.language.monthText(Int(chunks[1]) ?? Calendar.current.component(.month, from: Date()))
        }
        return entry.language.monthText(Calendar.current.component(.month, from: Date()))
    }
}

struct DiaryCalendarWidgetEntryView: View {
    var entry: DiaryMoodProvider.Entry

    var body: some View {
        let calendar = Calendar.current
        let date = dateFromMonthKey(entry.monthKey) ?? Date()
        let year = calendar.component(.year, from: date)
        let month = calendar.component(.month, from: date)
        let monthDates = calendarGridDates(for: year, month: month)

        return ZStack {
            widgetBackgroundColor
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(entry.language.monthText(month))
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(widgetPrimaryTextColor)
                    Spacer()
                }
                HStack(spacing: 0) {
                    ForEach(entry.language.weekdays, id: \.self) { day in
                        Text(day)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(widgetPrimaryTextColor)
                            .frame(maxWidth: .infinity)
                    }
                }
                VStack(spacing: 4) {
                    ForEach(0..<6, id: \.self) { row in
                        HStack(spacing: 0) {
                            ForEach(0..<7, id: \.self) { col in
                                let idx = row * 7 + col
                                let day = monthDates[idx]
                                VStack(spacing: 1) {
                                    if day > 0 {
                                        if let imageData = entry.monthImageByDay[day] {
                                            MoodIconView(
                                                imageData: imageData,
                                                emoji: entry.monthEmojiByDay[day] ?? "🙂",
                                                size: 18,
                                                emptyText: ""
                                            )
                                        } else if let emoji = entry.monthEmojiByDay[day] {
                                            MoodIconView(imageData: nil, emoji: emoji, size: 18, emptyText: "")
                                        } else {
                                            Text("\(day)")
                                                .font(.system(size: 11, weight: .regular))
                                                .foregroundStyle(widgetSecondaryTextColor)
                                        }
                                    } else {
                                        Text(" ").font(.system(size: 11))
                                    }
                                }
                                .frame(maxWidth: .infinity, minHeight: 22, maxHeight: 22)
                            }
                        }
                    }
                }
            }
            .padding(12)
        }
        .diaryWidgetBackground()
    }

    private func dateFromMonthKey(_ key: String) -> Date? {
        let parts = key.split(separator: "-")
        guard parts.count == 2,
              let year = Int(parts[0]),
              let month = Int(parts[1]) else {
            return nil
        }
        return Calendar.current.date(from: DateComponents(year: year, month: month, day: 1))
    }

    private func calendarGridDates(for year: Int, month: Int) -> [Int] {
        let calendar = Calendar.current
        guard let first = calendar.date(from: DateComponents(year: year, month: month, day: 1)),
              let range = calendar.range(of: .day, in: .month, for: first) else {
            return Array(repeating: 0, count: 42)
        }
        let firstWeekday = calendar.component(.weekday, from: first) // 1=Sun
        var cells = Array(repeating: 0, count: 42)
        var index = firstWeekday - 1
        for day in range {
            if index >= cells.count { break }
            cells[index] = day
            index += 1
        }
        return cells
    }
}

struct DiaryTodayWidget: Widget {
    let kind: String = "DiaryTodayWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: DiaryMoodProvider()) { entry in
            DiaryTodayWidgetEntryView(entry: entry)
        }
        .configurationDisplayName(widgetLocalized("WIDGET_TODAY_NAME"))
        .description(widgetLocalized("WIDGET_TODAY_DESCRIPTION"))
        .supportedFamilies([.systemSmall])
    }
}

struct DiaryMonthSummaryWidget: Widget {
    let kind: String = "DiaryMonthSummaryWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: DiaryMoodProvider()) { entry in
            DiaryMonthSummaryWidgetEntryView(entry: entry)
        }
        .configurationDisplayName(widgetLocalized("WIDGET_MONTH_NAME"))
        .description(widgetLocalized("WIDGET_MONTH_DESCRIPTION"))
        .supportedFamilies([.systemMedium])
    }
}

struct DiaryCalendarWidget: Widget {
    let kind: String = "DiaryCalendarWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: DiaryMoodProvider()) { entry in
            DiaryCalendarWidgetEntryView(entry: entry)
        }
        .configurationDisplayName(widgetLocalized("WIDGET_CALENDAR_NAME"))
        .description(widgetLocalized("WIDGET_CALENDAR_DESCRIPTION"))
        .supportedFamilies([.systemLarge])
    }
}

@main
struct DiaryMoodWidgetBundle: WidgetBundle {
    var body: some Widget {
        DiaryTodayWidget()
        DiaryMonthSummaryWidget()
        DiaryCalendarWidget()
    }
}
