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
    static let keyYesterday = "widget_yesterday_emoji"
    static let keyYesterdayImage = "widget_yesterday_image_base64"
    static let keyRecent = "widget_recent_emojis"
    static let keyRecentImages = "widget_recent_images"
    static let keyMonth = "widget_month_key"
    static let keyMonthMap = "widget_month_map"
    static let keyMonthMapPhotos = "widget_month_map_photos"
    static let keyMonthMapTitles = "widget_month_map_titles"
    static let keyLanguage = "widget_language"
}

enum WidgetLanguage: String {
    case ko
    case en

    init(code: String) {
        self = code == "en" ? .en : .ko
    }

    var todayTitle: String { self == .en ? "YESTERDAY" : "어제" }
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
    let yesterdayEmoji: String
    let yesterdayImageData: Data?
    let recentEmojis: [String]
    let recentImageData: [Data?]
    let monthKey: String
    let monthEmojiByDay: [Int: String]
    let monthPhotoByDay: [Int: Data]
    let monthTitleByDay: [Int: String]
}

struct DiaryMoodProvider: TimelineProvider {
    func placeholder(in context: Context) -> DiaryMoodEntry {
        DiaryMoodEntry(
            date: Date(),
            language: .ko,
            yesterdayEmoji: "🙂",
            yesterdayImageData: nil,
            recentEmojis: ["🙂", "😊", "🥰", "😴", "😰", "😢"],
            recentImageData: [nil, nil, nil, nil, nil, nil],
            monthKey: "2026-03",
            monthEmojiByDay: [1: "🙂", 2: "😮", 3: "😡", 4: "😢"],
            monthPhotoByDay: [:],
            monthTitleByDay: [1: "행복한 하루", 2: "산책", 3: "집밥", 4: "기록"]
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
        let yesterday = defaults?.string(forKey: WidgetConstants.keyYesterday) ?? ""
        let yesterdayImage = Data(base64Encoded: defaults?.string(forKey: WidgetConstants.keyYesterdayImage) ?? "")
        let recent = (defaults?.stringArray(forKey: WidgetConstants.keyRecent) ?? []).prefix(6)
        let recentImageStrings = Array((defaults?.stringArray(forKey: WidgetConstants.keyRecentImages) ?? []).prefix(6))
        var recentImages: [Data?] = []
        for index in 0..<6 {
            let encoded = index < recentImageStrings.count ? recentImageStrings[index] : ""
            recentImages.append(Data(base64Encoded: encoded))
        }
        let month = defaults?.string(forKey: WidgetConstants.keyMonth) ?? ""
        let rawMonthMap = defaults?.dictionary(forKey: WidgetConstants.keyMonthMap) as? [String: String] ?? [:]
        let rawMonthPhotoMap = defaults?.dictionary(forKey: WidgetConstants.keyMonthMapPhotos) as? [String: String] ?? [:]
        let rawMonthTitleMap = defaults?.dictionary(forKey: WidgetConstants.keyMonthMapTitles) as? [String: String] ?? [:]
        var monthMap: [Int: String] = [:]
        var monthPhotoMap: [Int: Data] = [:]
        var monthTitleMap: [Int: String] = [:]
        for (key, value) in rawMonthMap {
            if let day = Int(key), !value.isEmpty {
                monthMap[day] = value
            }
        }
        for (key, value) in rawMonthPhotoMap {
            if let day = Int(key), let imageData = Data(base64Encoded: value) {
                monthPhotoMap[day] = imageData
            }
        }
        for (key, value) in rawMonthTitleMap {
            if let day = Int(key), !value.isEmpty {
                monthTitleMap[day] = value
            }
        }
        return DiaryMoodEntry(
            date: Date(),
            language: language,
            yesterdayEmoji: yesterday,
            yesterdayImageData: yesterdayImage,
            recentEmojis: Array(recent),
            recentImageData: recentImages,
            monthKey: month,
            monthEmojiByDay: monthMap,
            monthPhotoByDay: monthPhotoMap,
            monthTitleByDay: monthTitleMap
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
    let cornerRadius: CGFloat

    var body: some View {
        if let imageData, let uiImage = UIImage(data: imageData) {
            Image(uiImage: uiImage)
                .resizable()
                .scaledToFit()
                .frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
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
                if entry.yesterdayImageData == nil && entry.yesterdayEmoji.isEmpty {
                    Text(entry.language.emptyText)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(widgetSecondaryTextColor)
                } else {
                    MoodIconView(
                        imageData: entry.yesterdayImageData,
                        emoji: entry.yesterdayEmoji,
                        size: 64,
                        emptyText: entry.language.emptyText,
                        cornerRadius: 10
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
                            emptyText: "",
                            cornerRadius: 6
                        )
                            .frame(maxWidth: .infinity)
                    }
                }
            }
            .padding(14)
        }
        .diaryWidgetBackground()
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
                                Group {
                                    if day > 0 {
                                        calendarCell(day: day)
                                    } else {
                                        Color.clear
                                    }
                                }
                                .frame(maxWidth: .infinity, minHeight: 44, maxHeight: 44)
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

    @ViewBuilder
    private func calendarCell(day: Int) -> some View {
        let title = entry.monthTitleByDay[day] ?? ""
        if let imageData = entry.monthPhotoByDay[day], let uiImage = UIImage(data: imageData) {
            VStack(alignment: .leading, spacing: 2) {
                if !title.isEmpty {
                    calendarTitleBadge(title)
                }
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 32, height: 32)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        } else if let emoji = entry.monthEmojiByDay[day] {
            VStack(alignment: .leading, spacing: 2) {
                if !title.isEmpty {
                    calendarTitleBadge(title)
                }
                VStack(spacing: 1) {
                    Text("\(day)")
                        .font(.system(size: 8, weight: .regular))
                        .foregroundStyle(widgetSecondaryTextColor)
                    MoodIconView(imageData: nil, emoji: emoji, size: 16, emptyText: "", cornerRadius: 0)
                }
                .frame(maxWidth: .infinity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        } else {
            Text("\(day)")
                .font(.system(size: 11, weight: .regular))
                .foregroundStyle(widgetSecondaryTextColor)
        }
    }

    private func calendarTitleBadge(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 7, weight: .semibold))
            .foregroundStyle(widgetPrimaryTextColor)
            .lineLimit(1)
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .frame(maxWidth: 38, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(Color.white)
            )
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
