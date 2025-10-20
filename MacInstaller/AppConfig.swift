import Foundation

// MARK: - Глобальная конфигурация инсталлера
struct AppConfig {
    //  Укажите имя приложения обязательно с заглавной буквы
//    static let appName = "Proxer"
//    static let appName = "Spacedrive"
    static let appName = "Cap"

    //  Путь установленного приложения
    static let installedAppPath = "/Applications/\(appName).app"

    //  Путь к точке монтирования приложения
    static let mountPoint = "/Volumes/\(appName)Installer"
    
    // Закреплять окно установщика поверх остальных окон
    static let isWindowFloating = true

    //  Тип скачивания (direct/json)
    static let downloadType = "direct"

    //  URL для получения метаданных последнего релиза. Использовать downloadType = "json"
    static let latestReleaseURL = URL(
        string:
            "https://api.github.com/repos/doroved/proxer-releases/releases/latest"
    )!
//    static let latestReleaseURL = URL(
//        string:
//            "https://api.github.com/repos/spacedriveapp/spacedrive/releases/latest"
//    )!
//    static let latestReleaseURL = URL(
//        string:
//            "https://api.github.com/repos/lzdyes/douyin-downloader/releases/latest"
//    )!

    //  Прямые ссылки на .dmg файлы приложения. Использовать downloadType = "direct"
    //    https://hf.ru/linkd56f7 // Proxer aarch64
    //    https://hf.ru/linkdd75e // Proxer x86_64
//    static let arm64URL = URL(
//        string:
//            "https://hf.ru/linkd56f7"
//    )!
//        static let arm64URL = URL(
//            string:
//                "https://www.spacedrive.com/api/releases/desktop/stable/darwin/aarch64"
//        )!
    //    static let arm64URL = URL(
    //        string:
    //            "https://app.gitbutler.com/downloads/release/darwin/aarch64/dmg"
    //    )!
        static let arm64URL = URL(
            string:
                "https://cap.so/download/apple-silicon"
        )!
    static let x86_64URL = URL(
        string:
            "https://app.gitbutler.com/downloads/release/darwin/x86_64/dmg"
    )!

    //    let downloadURL = URL(string: "https://download.scdn.co/SpotifyARM64.dmg")!
}
