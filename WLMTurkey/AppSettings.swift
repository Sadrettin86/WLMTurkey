import SwiftUI

// MARK: - App Settings
@Observable
class AppSettings {
    static let shared = AppSettings()

    var theme: String {
        didSet { UserDefaults.standard.set(theme, forKey: "appTheme") }
    }

    var language: String {
        didSet { UserDefaults.standard.set(language, forKey: "appLanguage") }
    }

    var defaultLicense: String {
        didSet { UserDefaults.standard.set(defaultLicense, forKey: "appDefaultLicense") }
    }

    init() {
        self.theme = UserDefaults.standard.string(forKey: "appTheme") ?? "system"
        self.defaultLicense = UserDefaults.standard.string(forKey: "appDefaultLicense") ?? "CC BY-SA 4.0"
        if let saved = UserDefaults.standard.string(forKey: "appLanguage") {
            self.language = saved
        } else {
            let deviceLang = Locale.current.language.languageCode?.identifier ?? "en"
            self.language = deviceLang == "tr" ? "tr" : "en"
        }
    }

    var colorScheme: ColorScheme? {
        switch theme {
        case "light": return .light
        case "dark": return .dark
        default: return nil
        }
    }

    var l: Strings { Strings(lang: language) }
}

// MARK: - Localized Strings
struct Strings {
    let lang: String
    var isTR: Bool { lang == "tr" }

    // MARK: Tabs
    var tabMap: String { isTR ? "Harita" : "Map" }
    var tabSearch: String { isTR ? "Ara" : "Search" }
    var tabPhotos: String { isTR ? "Fotoğraflar" : "Photos" }
    var tabProfile: String { isTR ? "Profil" : "Profile" }

    // MARK: Settings
    var settings: String { isTR ? "Ayarlar" : "Settings" }
    var appearance: String { isTR ? "Görünüm" : "Appearance" }
    var themeSystem: String { isTR ? "Sistem" : "System" }
    var themeLight: String { isTR ? "Aydınlık" : "Light" }
    var themeDark: String { isTR ? "Koyu" : "Dark" }
    var languageTitle: String { isTR ? "Dil" : "Language" }

    // MARK: Map
    var filterAll: String { isTR ? "Tümü" : "All" }
    var filterWithoutPhoto: String { isTR ? "Fotoğrafsız" : "No Photo" }
    var filterWithPhoto: String { isTR ? "Fotoğraflı" : "Has Photo" }
    var monumentsLoading: String { isTR ? "Anıtlar yükleniyor..." : "Loading monuments..." }
    var monumentsUpdating: String { isTR ? "Anıtlar güncelleniyor..." : "Updating monuments..." }
    func cachedMonuments(_ count: Int) -> String { isTR ? "Önbellekteki \(count) anıt gösteriliyor" : "Showing \(count) cached monuments" }
    var uploadPhoto: String { isTR ? "Fotoğraf Yükle" : "Upload Photo" }
    var noPhoto: String { isTR ? "Fotoğraf yok" : "No photo" }

    // MARK: Map - Upload Sheet
    var wikidataLabel: String { isTR ? "Vikiveri" : "Wikidata" }
    var wlmTurkey: String { (isTR ? "Viki Anıtları Seviyor" : "Wiki Loves Monuments") + " – " + (isTR ? "Türkiye" : "Turkey") }
    var uploadDescription: String { isTR ? "Fotoğrafınızı yükleyerek bu kültürel mirasın belgelenmesine katkı sağlayabilirsiniz." : "You can contribute to documenting this cultural heritage by uploading your photo." }
    var photosLabel: String { isTR ? "Fotoğraflar" : "Photos" }
    var selectPhotosHint: String { isTR ? "Fotoğraf seçmek için tıklayın" : "Tap to select photos" }
    var photoFormats: String { isTR ? "JPG, PNG, TIFF · En fazla 20 fotoğraf" : "JPG, PNG, TIFF · Up to 20 photos" }
    func photosLoading(_ loaded: Int, _ total: Int) -> String { isTR ? "\(loaded)/\(total) fotoğraf yükleniyor..." : "Loading \(loaded)/\(total) photos..." }
    func photosAdded(_ count: Int) -> String { isTR ? "\(count) fotoğraf eklendi" : "\(count) photos added" }
    var noLocationInfo: String { isTR ? "Konum bilgisi yok" : "No location info" }
    var noDateTaken: String { isTR ? "Çekim tarihi yok" : "No date taken" }
    var uploaded: String { isTR ? "Yüklendi" : "Uploaded" }
    func uploadingProgress(_ pct: Int) -> String { isTR ? "Yükleniyor... %\(pct)" : "Uploading... \(pct)%" }
    var fileName: String { isTR ? "DOSYA ADI" : "FILE NAME" }
    var descriptionLabel: String { isTR ? "AÇIKLAMA" : "DESCRIPTION" }
    var categories: String { isTR ? "KATEGORİLER" : "CATEGORIES" }
    var license: String { isTR ? "LİSANS" : "LICENSE" }
    var commonsPreview: String { isTR ? "Commons Önizleme" : "Commons Preview" }
    var loginRequired: String { isTR ? "Yüklemek için Profil sayfasından Wikimedia hesabınızla giriş yapın." : "Log in with your Wikimedia account from the Profile page to upload." }
    var uploadLoginRequired: String { isTR ? "Yükle (giriş gerekli)" : "Upload (login required)" }
    var uploadOnCommons: String { isTR ? "Commons'ta yükle →" : "Upload on Commons →" }
    var ok: String { isTR ? "Tamam" : "OK" }
    var oauthNotReady: String { isTR ? "Fotoğraf yüklemek için Profil sayfasından Wikimedia hesabınızla giriş yapın." : "Log in with your Wikimedia account from the Profile page to upload photos." }
    var wikipedia: String { isTR ? "Vikipedi" : "Wikipedia" }
    var categoryPhotos: String { isTR ? "Kategorideki fotoğraflar" : "Category photos" }
    var infoLoading: String { isTR ? "Bilgiler yükleniyor..." : "Loading info..." }
    var wikiLoading: String { isTR ? "Vikipedi yükleniyor..." : "Loading Wikipedia..." }
    var openInWiki: String { isTR ? "Vikipedi'de Aç" : "Open in Wikipedia" }
    var wikiTitle: String { isTR ? "Vikipedi" : "Wikipedia" }
    var backToForm: String { isTR ? "Forma Dön" : "Back to Form" }
    func photoCount(_ count: Int) -> String { isTR ? "\(count) fotoğraf" : "\(count) photos" }
    var viewOnCommons: String { isTR ? "Commons'ta Görüntüle" : "View on Commons" }
    var categoryPhotosTitle: String { isTR ? "Kategori Fotoğrafları" : "Category Photos" }
    var photosLoadingShort: String { isTR ? "Fotoğraflar yükleniyor..." : "Loading photos..." }
    var noCategoryPhotos: String { isTR ? "Bu kategoride fotoğraf bulunamadı" : "No photos found in this category" }
    var couldNotLoad: String { isTR ? "Yüklenemedi" : "Could not load" }

    // MARK: Search
    var searchTitle: String { isTR ? "Ara" : "Search" }
    var searchPrompt: String { isTR ? "Anıt veya yapı adı yazın..." : "Type monument or building name..." }
    var searchHint: String { isTR ? "Kültürel miras öğesi arayın" : "Search for cultural heritage" }
    var searchSubhint: String { isTR ? "Türkiye'deki tescilli anıtlar arasında arama yapabilirsiniz" : "You can search among registered monuments in Turkey" }
    var recentSearches: String { isTR ? "Son Aramalar" : "Recent Searches" }
    var clearSearchHistory: String { isTR ? "Arama geçmişini sil" : "Clear search history" }
    var retryButton: String { isTR ? "Tekrar dene" : "Try again" }
    var searching: String { isTR ? "Aranıyor..." : "Searching..." }
    func searchingFor(_ q: String) -> String { isTR ? "\"\(q)\" için sonuçlar getiriliyor" : "Fetching results for \"\(q)\"" }
    var noResults: String { isTR ? "Sonuç bulunamadı" : "No results found" }
    func noResultsFor(_ q: String) -> String { isTR ? "\"\(q)\" için eşleşen anıt bulunamadı" : "No matching monument found for \"\(q)\"" }
    var keepTyping: String { isTR ? "Aramak için yazmaya devam edin" : "Keep typing to search" }
    var updating: String { isTR ? "Güncelleniyor..." : "Updating..." }
    var hasPhoto: String { isTR ? "Fotoğraflı" : "Has Photo" }
    var noPhotoLabel: String { isTR ? "Fotoğraf yok" : "No photo" }
    var unnamed: String { isTR ? "Adsız" : "Unnamed" }
    var errorPrefix: String { isTR ? "Hata" : "Error" }
    var dataUnavailable: String { isTR ? "Veri alınamadı" : "Data unavailable" }

    // MARK: Photos
    var photosTitle: String { isTR ? "Fotoğraflar" : "Photos" }
    var needingPhotos: String { isTR ? "Fotoğraf Bekleyenler" : "Needs Photo" }
    var recentUploads: String { isTR ? "Son Yüklenenler" : "Recent Uploads" }
    var myUploads: String { isTR ? "Yüklediklerim" : "My Uploads" }
    var myUploadsEmpty: String { isTR ? "Henüz yüklediğiniz fotoğraf yok" : "You haven't uploaded any photos yet" }
    var myUploadsHint: String { isTR ? "Anıtlara fotoğraf yükleyerek katkıda bulunun" : "Contribute by uploading photos of monuments" }
    var myUploadsLoginRequired: String { isTR ? "Yüklemelerinizi görmek için giriş yapın" : "Log in to see your uploads" }
    var searchingNeedingPhotos: String { isTR ? "Fotoğraf bekleyen anıtlar aranıyor..." : "Searching for monuments needing photos..." }
    var allHavePhotos: String { isTR ? "Yakınlardaki tüm anıtların fotoğrafı var!" : "All nearby monuments have photos!" }
    var discoverNew: String { isTR ? "Farklı bir konuma giderek yeni anıtlar keşfedebilirsiniz" : "You can discover new monuments by going to a different location" }
    func needingPhotoCount(_ count: Int) -> String { isTR ? "Yakınında **\(count)** anıt fotoğraf bekliyor" : "**\(count)** monuments nearby need photos" }
    var locationUnavailable: String { isTR ? "Konum bilgisi alınamıyor. Konum izni verildiğinden emin olun." : "Cannot get location. Make sure location permission is granted." }
    func wlmStats(_ count: Int) -> String {
        let formatted = NumberFormatter.localizedString(from: NSNumber(value: count), number: .decimal)
        return isTR ? "Viki Anıtları Seviyor Türkiye'den toplam **\(formatted)** fotoğraf yüklendi" : "**\(formatted)** photos uploaded from WLM Turkey"
    }

    // MARK: Monument Details
    var instanceOf: String { isTR ? "Türü" : "Type" }
    var adminEntity: String { isTR ? "İdari birim" : "Administrative Entity" }
    var heritageDesig: String { isTR ? "Korunmuşluk durumu" : "Heritage Status" }
    var architect: String { isTR ? "Mimar" : "Architect" }
    var archStyle: String { isTR ? "Mimari Tarz" : "Architectural Style" }

    // MARK: Welcome Card
    func welcomeTitle(_ count: Int) -> String { isTR ? "Yakınında **\(count)** anıt keşfedilmeyi bekliyor" : "**\(count)** monuments nearby waiting to be discovered" }
    var welcomeSubtitle: String { isTR ? "Fotoğraf çekerek kültürel mirasa katkıda bulun" : "Contribute to cultural heritage by taking photos" }
    var welcomeNoPhoto: String { isTR ? "fotoğraf bekliyor" : "need photos" }
    var welcomeDismiss: String { isTR ? "Anladım" : "Got it" }

    // MARK: Dashboard
    var dashboardTitle: String { isTR ? "Genel Bakış" : "Overview" }
    var totalMonuments: String { isTR ? "Toplam Anıt" : "Total Monuments" }
    var withPhotoCount: String { isTR ? "Fotoğraflı" : "With Photo" }
    var withoutPhotoCount: String { isTR ? "Fotoğrafsız" : "Without Photo" }
    var coverageRate: String { isTR ? "Kapsama Oranı" : "Coverage Rate" }
    var monumentStats: String { isTR ? "Anıt İstatistikleri" : "Monument Statistics" }

    // MARK: Profile
    var profileTitle: String { isTR ? "Profil" : "Profile" }
    var notLoggedIn: String { isTR ? "Giriş yapılmadı" : "Not logged in" }
    var loginHint: String { isTR ? "Fotoğraf yüklemek için Wikimedia hesabınızla giriş yapın" : "Log in with your Wikimedia account to upload photos" }
    var loginWithWikimedia: String { isTR ? "Wikimedia ile Giriş Yap" : "Log in with Wikimedia" }
    var comingSoon: String { isTR ? "Yakında" : "Soon" }
    var about: String { isTR ? "Hakkında" : "About" }
    var whatIsWLM: String { isTR ? "Viki Anıtları Seviyor Nedir?" : "What is Wiki Loves Monuments?" }
    var internationalContest: String { isTR ? "Uluslararası Yarışma" : "International Contest" }
    var internationalContestDesc: String { isTR ? "Viki Anıtları Seviyor, her yıl Eylül ayında düzenlenen dünyanın en büyük fotoğraf yarışmasıdır. 2010'dan bu yana 60'tan fazla ülkede düzenlenmektedir." : "Wiki Loves Monuments is the world's largest photo contest, held every September. It has been organized in over 60 countries since 2010." }
    var wlmInTurkey: String { isTR ? "Türkiye'de Viki Anıtları Seviyor" : "WLM in Turkey" }
    var wlmInTurkeyDesc: String { isTR ? "Türkiye'deki tescilli taşınmaz kültür varlıklarını fotoğraflayarak bu yarışmaya katılabilirsiniz. Fotoğraflarınız Wikimedia Commons'a yüklenir." : "You can participate by photographing registered cultural heritage sites in Turkey. Your photos are uploaded to Wikimedia Commons." }
    var valueForWikipedia: String { isTR ? "Vikipedi İçin Değer" : "Value for Wikipedia" }
    var valueForWikipediaDesc: String { isTR ? "Yüklediğiniz fotoğraflar Vikipedi makalelerinde, Vikiveri öğelerinde ve diğer Vikimedia projelerinde özgürce kullanılır." : "Your uploaded photos are freely used in Wikipedia articles, Wikidata items, and other Wikimedia projects." }
    var awards: String { isTR ? "Ödüller" : "Awards" }
    var awardsDesc: String { isTR ? "Her ülkede ulusal jüri en iyi fotoğrafları seçer. Ulusal kazananlar uluslararası finalde yarışır." : "In each country, a national jury selects the best photos. National winners compete in the international finale." }
    var moreInfo: String { isTR ? "Daha fazla bilgi" : "More info" }
    var photoTipsTitle: String { isTR ? "Fotoğraf Çekme İpuçları" : "Photography Tips" }
    var tipsAndSuggestions: String { isTR ? "İpuçları ve Öneriler" : "Tips and Suggestions" }
    var tipRightLight: String { isTR ? "Doğru Işık" : "Right Light" }
    var tipRightLightDesc: String { isTR ? "Gün ışığında çekim yapın. Sabah erken veya ikindi saatleri en iyi ışığı verir. Öğle güneşi sert gölgeler oluşturur." : "Shoot in daylight. Early morning or late afternoon gives the best light. Midday sun creates harsh shadows." }
    var tipFullFrame: String { isTR ? "Tam Kadraj" : "Full Frame" }
    var tipFullFrameDesc: String { isTR ? "Yapının tamamını kadraja alın. Mümkünse farklı açılardan (ön cephe, yan, arka) birden fazla fotoğraf çekin." : "Capture the entire structure. If possible, take multiple photos from different angles (front, side, back)." }
    var tipCleanFrame: String { isTR ? "Temiz Kadraj" : "Clean Frame" }
    var tipCleanFrameDesc: String { isTR ? "Araçları, insanları ve geçici nesneleri (çöp kutusu, tabela vb.) kadraja almamaya çalışın." : "Try to keep vehicles, people, and temporary objects (trash cans, signs, etc.) out of the frame." }
    var tipDetails: String { isTR ? "Detay Çekimleri" : "Detail Shots" }
    var tipDetailsDesc: String { isTR ? "Kitabeler, süslemeler, kapı tokmakları, pencere detayları gibi yakın çekimler de çok değerlidir." : "Close-up shots of inscriptions, ornaments, door knockers, and window details are also very valuable." }
    var tipLandscape: String { isTR ? "Yatay Çekim" : "Landscape Shot" }
    var tipLandscapeDesc: String { isTR ? "Binalar için yatay (landscape) çekim genellikle daha iyi sonuç verir. Uzun yapılar için dikey de uygundur." : "Landscape orientation usually works better for buildings. Portrait is also fine for tall structures." }
    var tipLocation: String { isTR ? "Konum Bilgisi" : "Location Info" }
    var tipLocationDesc: String { isTR ? "Telefonunuzda konum servislerinin açık olduğundan emin olun. GPS bilgisi fotoğrafa otomatik eklenir." : "Make sure location services are enabled on your phone. GPS data is automatically added to the photo." }
    var tipResolution: String { isTR ? "Yüksek Çözünürlük" : "High Resolution" }
    var tipResolutionDesc: String { isTR ? "Telefonunuzun en yüksek çözünürlük ayarını kullanın. HDR modunu açabilirsiniz, ancak filtre kullanmayın." : "Use your phone's highest resolution setting. You can enable HDR mode, but don't use filters." }
    var tipStraight: String { isTR ? "Düz Çekim" : "Straight Shot" }
    var tipStraightDesc: String { isTR ? "Telefonu düz tutun, ufuk çizgisinin eğik olmamasına dikkat edin. Izgarayı (grid) açabilirsiniz." : "Hold the phone level, make sure the horizon isn't tilted. You can enable the grid." }
    var tipAspectRatio: String { isTR ? "4:3 En Boy Oranı" : "4:3 Aspect Ratio" }
    var tipAspectRatioDesc: String { isTR ? "Kamera ayarlarından en boy oranını 4:3 olarak seçin. 16:9 veya 1:1 gibi oranlar fotoğrafı kırparak çözünürlüğü düşürür. 4:3, sensörün tam alanını kullanır ve Vikimedia Commons için en uygun formattır." : "Set the aspect ratio to 4:3 in your camera settings. Ratios like 16:9 or 1:1 crop the image and reduce resolution. 4:3 uses the full sensor area and is the best format for Wikimedia Commons." }
    var showOnboardingAgain: String { isTR ? "Tanıtımı Tekrar Göster" : "Show Onboarding Again" }
    var links: String { isTR ? "Bağlantılar" : "Links" }
    var version: String { isTR ? "Sürüm" : "Version" }

    // MARK: Onboarding
    var onboardingTitle1: String { isTR ? "Viki Anıtları Seviyor" : "Wiki Loves Monuments" }
    var onboardingSubtitle1: String { isTR ? "Dünyanın en büyük fotoğraf yarışmasına hoş geldiniz" : "Welcome to the world's largest photo contest" }
    var onboarding1Bullet1: String { isTR ? "Her yıl düzenlenen uluslararası bir kültürel miras fotoğraf yarışması" : "An annual international cultural heritage photo contest" }
    var onboarding1Bullet2: String { isTR ? "Türkiye'deki tescilli anıt ve yapıları fotoğraflayarak katkıda bulunun" : "Contribute by photographing registered monuments in Turkey" }
    var onboarding1Bullet3: String { isTR ? "Fotoğraflarınız Wikimedia Commons'a yüklenir ve Wikipedia'da kullanılır" : "Your photos are uploaded to Wikimedia Commons and used on Wikipedia" }
    var onboarding1Bullet4: String { isTR ? "Kültürel mirasın dijital olarak korunmasına katkı sağlayın" : "Help preserve cultural heritage digitally" }
    var onboardingTitle2: String { isTR ? "Nasıl Çalışır?" : "How It Works?" }
    var onboardingSubtitle2: String { isTR ? "Üç adımda katkıda bulunun" : "Contribute in three steps" }
    var onboarding2Bullet1: String { isTR ? "Haritada yakınınızdaki tescilli anıtları keşfedin" : "Discover registered monuments near you on the map" }
    var onboarding2Bullet2: String { isTR ? "Arama ile Türkiye genelindeki anıtları bulun" : "Find monuments across Turkey with search" }
    var onboarding2Bullet3: String { isTR ? "Fotoğraf çekip doğrudan Commons'a yükleyin" : "Take photos and upload directly to Commons" }
    var onboarding2Bullet4: String { isTR ? "Yüklenen fotoğraflar otomatik olarak yarışmaya katılır" : "Uploaded photos automatically enter the contest" }
    var onboardingTitle3: String { isTR ? "Fotoğraf İpuçları" : "Photo Tips" }
    var onboardingSubtitle3: String { isTR ? "Daha iyi fotoğraflar için öneriler" : "Tips for better photos" }
    var onboarding3Bullet1: String { isTR ? "Gün ışığında, tercihen sabah veya ikindi saatlerinde çekim yapın" : "Shoot in daylight, preferably in the morning or late afternoon" }
    var onboarding3Bullet2: String { isTR ? "Yapının tamamını kadraj içine alın, farklı açılardan da çekin" : "Capture the whole structure, shoot from different angles" }
    var onboarding3Bullet3: String { isTR ? "Yakınındaki insanları, araçları veya geçici nesneleri kadraja almamaya özen gösterin" : "Avoid including people, vehicles, or temporary objects in the frame" }
    var onboarding3Bullet4: String { isTR ? "Konum bilgisinin açık olduğundan emin olun — EXIF verisi otomatik okunur" : "Make sure location is enabled — EXIF data is read automatically" }
    var onboarding3Bullet5: String { isTR ? "Detay çekimleri de değerlidir: kitabeler, süslemeler, kapı tokmakları" : "Detail shots are also valuable: inscriptions, ornaments, door knockers" }
    var onboarding3Bullet6: String { isTR ? "Yatay çekim genellikle daha iyi sonuç verir" : "Landscape orientation usually gives better results" }
    var onboarding3Bullet7: String { isTR ? "Kamera oranını 4:3 olarak ayarlayın — 16:9 sensörü kırpar ve çözünürlük düşer" : "Set camera ratio to 4:3 — 16:9 crops the sensor and reduces resolution" }
    var onboarding3Bullet8: String { isTR ? "Aydınlatması iyi olan gece fotoğrafları da çok değerlidir" : "Night photos with good lighting are also very valuable" }
    var continueButton: String { isTR ? "Devam" : "Continue" }
    var startButton: String { isTR ? "Başla" : "Start" }
    var skipButton: String { isTR ? "Atla" : "Skip" }
}
