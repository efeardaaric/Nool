import 'package:flutter/widgets.dart';

import '../services/settings_service.dart';

/// Basit TR / EN sözlük. `context.s.key` ile erişim.
class AppStrings {
  AppStrings._(this._code);

  final String _code;

  static AppStrings of(BuildContext context) {
    final code = Localizations.localeOf(context).languageCode;
    return AppStrings._(code == 'en' ? 'en' : 'tr');
  }

  static AppStrings fromSettings() {
    return AppStrings._(
      SettingsService.instance.isEnglish ? 'en' : 'tr',
    );
  }

  bool get isEnglish => _code == 'en';

  String _t(String tr, String en) => _code == 'en' ? en : tr;

  // —— Genel / nav ——
  String get appName => 'Nool';
  String get navFeed => _t('Akış', 'Feed');
  String get navCamera => _t('Kamera', 'Camera');
  String get navTrend => _t('Trend', 'Trend');
  String get navMessages => _t('Mesaj', 'Chat');
  String get navProfile => _t('Profil', 'Profile');
  String get navAccount => _t('Hesap', 'Account');
  String get settings => _t('Ayarlar', 'Settings');
  String get support => _t('Destek / şikayet', 'Support / report');
  String get website => _t('Web sitesi', 'Website');
  String get privacyPolicy => _t('Gizlilik politikası', 'Privacy policy');
  String get save => _t('Kaydet', 'Save');
  String get cancel => _t('Vazgeç', 'Cancel');
  String get done => _t('Tamam', 'Done');
  String get understood => _t('Anladım', 'Got it');
  String get retry => _t('Yeniden dene', 'Try again');
  String get continueWithoutLocation =>
      _t('Konum olmadan devam et', 'Continue without location');
  String get loading => _t('Yükleniyor...', 'Loading...');
  String get signInOrSignUp => _t('Giriş Yap / Kayıt Ol', 'Sign in / Sign up');
  String get continueWithGoogle =>
      _t('Google ile devam et', 'Continue with Google');
  String get continueWithApple =>
      _t('Apple ile devam et', 'Continue with Apple');
  String get signInCta => _t('GİRİŞ YAP', 'SIGN IN');
  String get orEmailDivider => _t('veya e-posta', 'or email');
  String get emailLabel => _t('E-posta', 'Email');
  String get passwordConfirmLabel => _t('Şifre tekrar', 'Confirm password');
  String get searchPeopleTooltip => _t('İnsan ara', 'Search people');
  String get reportTooltip => _t('Şikayet et', 'Report');

  // —— Feed sekmeleri ——
  String get tabNearYou => _t('Yakınımda', 'Near You');
  String get tabVibing => _t('Vibing', 'Vibing');
  String get tabCampus => _t('Campus', 'Campus');

  // —— Kullanıcı hataları ——
  String get errorGeneric => _t(
        'Bir şey ters gitti. Biraz sonra tekrar dene.',
        'Something went wrong. Try again in a moment.',
      );
  String get errorNetwork => _t(
        'Bağlantı yok. Wi-Fi veya mobil veriyi kontrol et.',
        'No connection. Check Wi-Fi or mobile data.',
      );
  String get errorInvalidCredentials => _t(
        'E-posta veya şifre hatalı.',
        'Wrong email or password.',
      );
  String get errorEmailTaken => _t(
        'Bu e-posta zaten kayıtlı. Giriş yapmayı dene.',
        'That email is already registered. Try signing in.',
      );
  String get errorRateLimited => _t(
        'Çok denedin. Biraz bekleyip tekrar dene.',
        'Too many attempts. Wait a bit and try again.',
      );
  String get errorPermission => _t(
        'Bu işlem için yetkin yok veya oturumun düşmüş.',
        'You don’t have permission, or your session expired.',
      );
  String get errorServerConfig => _t(
        'Sunucu ayarı eksik. Biraz sonra tekrar dene.',
        'Server isn’t ready yet. Try again shortly.',
      );
  String get errorUpload => _t(
        'Yükleme başarısız. Bağlantını kontrol edip tekrar dene.',
        'Upload failed. Check your connection and retry.',
      );
  String get errorCancelled => _t('İptal edildi.', 'Cancelled.');
  String get errorGoogleNonce => _t(
        'Google girişi için Supabase’te “Skip nonce checks” açık olmalı.',
        'Enable “Skip nonce checks” for Google in Supabase Auth.',
      );
  String get emptyFeedHint => _t(
        'Yakında henüz drop yok. Kameradan bir tane bırak.',
        'No drops nearby yet. Leave one from the camera.',
      );
  String get hotspotEmpty => _t(
        'Bu noktada henüz drop yok.\nFiltreyi kaldırıp tüm akışa dön.',
        'No drops at this spot yet.\nClear the filter to see the full feed.',
      );
  String get reportHiddenRefresh => _t(
        'Şikayet ettiğin videolar gizlendi. Yenile, akış güncellenir.',
        'Reported videos are hidden. Refresh to update the feed.',
      );

  // —— Ayarlar ——
  String get settingsTitle => _t('Ayarlar', 'Settings');
  String get settingsSubtitle =>
      _t('Dil, ses ve hesap tercihlerin.', 'Language, sound, and account.');
  String get sectionLanguage => _t('Dil', 'Language');
  String get languageTurkish => _t('Türkçe', 'Turkish');
  String get languageEnglish => _t('English', 'English');
  String get languageHint => _t(
        'Arayüz dili anında değişir.',
        'Interface language updates instantly.',
      );
  String get sectionPlayback => _t('Oynatma', 'Playback');
  String get feedSound =>
      _t('Akışta ses açık başlasın', 'Start feed with sound on');
  String get feedSoundHint => _t(
        'Kapalıysa videolar sessiz açılır; tek dokunuşla açabilirsin.',
        'When off, videos start muted; tap once to unmute.',
      );
  String get haptics => _t('Titreşim', 'Haptics');
  String get hapticsHint =>
      _t('Beğeni ve buton geri bildirimi.', 'Feedback on likes and buttons.');
  String get reduceMotion => _t('Hareketi azalt', 'Reduce motion');
  String get reduceMotionHint => _t(
        'Bazı animasyonları sadeleştirir.',
        'Softens some animations.',
      );
  String get sectionAlerts => _t('Bildirimler', 'Alerts');
  String get curiosityPush => _t('Merak bildirimleri', 'Curiosity alerts');
  String get curiosityPushHint => _t(
        'Ara sıra radar veya kampüs hatırlatması. Günde en fazla 1-2.',
        'Occasional radar or campus reminders. Max 1-2 per day.',
      );
  String get sectionLegal => _t('Yasal', 'Legal');
  String get termsAndPermissions =>
      _t('Kullanım şartları ve izinler', 'Terms and permissions');
  String get privacyNote => _t(
        'Konum, kamera, mikrofon ve galeri izinleri.',
        'Location, camera, mic, and photo library access.',
      );
  String get sectionAccount => _t('Hesap', 'Account');
  String get sectionPassword => _t('Şifre', 'Password');
  String get changePassword => _t('Şifreyi değiştir', 'Change password');
  String get changePasswordHint => _t(
        'Oturum açıkken yeni şifre belirle.',
        'Set a new password while signed in.',
      );
  String get changePasswordTitle => _t('Şifreyi değiştir', 'Change password');
  String get changePasswordSubtitle => _t(
        'Yeni şifreni yaz. Hesabın hemen güncellenir.',
        'Enter a new password. Your account updates right away.',
      );
  String get changePasswordCta => _t('ŞİFREYİ GÜNCELLE', 'UPDATE PASSWORD');
  String get changePasswordSuccess => _t(
        'Şifren güncellendi.',
        'Your password was updated.',
      );
  String get sendResetEmail => _t('Sıfırlama maili gönder', 'Send reset email');
  String get sendResetEmailHint => _t(
        'Hesap e-postana sıfırlama linki yollar.',
        'Sends a reset link to your account email.',
      );
  String get sendResetEmailDone => _t(
        'Sıfırlama linki mailinde. Linke dokununca yeni şifre ekranı açılır.',
        'Reset link sent. Tap it to open the new-password screen.',
      );
  String get sendResetEmailNoEmail => _t(
        'Bu hesapta e-posta yok; şifre sıfırlama maili gönderilemez.',
        'This account has no email; reset email can’t be sent.',
      );
  String get passwordSocialOnlyHint => _t(
        'Google veya Apple ile girdin. İstersen e-posta şifresi ekleyebilir veya sıfırlama maili isteyebilirsin.',
        'You signed in with Google or Apple. You can still add an email password or request a reset link.',
      );
  String get signOut => _t('Çıkış yap', 'Sign out');
  String get deleteAccount =>
      _t('Hesabı kalıcı olarak sil', 'Permanently delete account');
  String get deleteAccountWarnTitle => _t('DİKKAT', 'WARNING');
  String get deleteAccountWarnBody => _t(
        'Bu işlem geri alınamaz. Videoların ve kanka bağlantıların silinir.',
        'This cannot be undone. Your videos and buddy links will be removed.',
      );
  String get deleteConfirm => _t('SİL', 'DELETE');
  String get deleteAccountNoSession => _t(
        'Silinecek hesap yok. Önce giriş yap.',
        'No account to delete. Sign in first.',
      );
  String get versionLabel => _t('Sürüm', 'Version');
  String get openSettings => _t('Ayarlar', 'Settings');

  // —— Profil ——
  String get editProfile => _t('Profili düzenle', 'Edit profile');
  String get editProfileNeedSignIn => _t(
        'Profil düzenlemek için giriş yap.',
        'Sign in to edit your profile.',
      );
  String get usernameLabel => _t('Kullanıcı adı', 'Username');
  String get bioLabel => _t('Bio (max 150)', 'Bio (max 150)');
  String get dismissTooltip => _t('Kapat', 'Close');
  String get myDrops => 'MY DROPS';
  String get hours24 => _t('· 24 saat', '· 24h');
  String get anonymousUser => _t('kullanıcı', 'user');
  String get anonymousHandle => _t('@kullanıcı', '@user');
  String get anonymousNoLinkedProfile => _t(
        'Bu kullanıcı henüz kayıtlı bir profil bağlamamış.',
        'This user has not linked a registered profile yet.',
      );
  String get anonymousNoDropsToday => _t(
        'Bu kullanıcı bugün henüz drop atmamış.',
        'This user has not dropped anything today.',
      );
  String get noBio => _t(
        'Bio yok. Kim olduğunu kısaca yaz.',
        'No bio yet. Say who you are in a line.',
      );
  String get noBioOther => _t(
        'Bio yok.',
        'No bio.',
      );
  String get profileUpdated => _t('Profil güncellendi.', 'Profile updated.');
  String get tapPhotoHint => _t(
        'Fotoğrafa dokun: galeri, kamera veya kaldır',
        'Tap photo: gallery, camera, or remove',
      );
  String get noDropsYet => _t(
        'Henüz drop yok.\nKameradan bir tane bırak.',
        'No drops yet.\nLeave one from the camera.',
      );
  String get dropManageTitle => _t('Drop yönetimi', 'Manage drop');
  String get dropEditCaption => _t('Açıklamayı düzenle', 'Edit caption');
  String get dropDelete => _t('Drop’u sil', 'Delete drop');
  String get dropDeleteConfirmTitle => _t('Silinsin mi?', 'Delete this?');
  String get dropDeleteConfirmBody => _t(
        'Bu drop akışından kalkacak.',
        'This drop will be removed from the feed.',
      );
  String get dropDeletedToast => _t('Drop silindi.', 'Drop deleted.');
  String get dropDeleteFailed => _t('Silinemedi', 'Couldn’t delete');
  String get dropCaptionTitle => _t('Açıklama', 'Caption');
  String get dropCaptionUpdated =>
      _t('Açıklama güncellendi.', 'Caption updated.');
  String get dropCaptionFailed => _t('Güncellenemedi', 'Couldn’t update');
  String get forgingIdentity => _t(
        'hazırlanıyor...',
        'getting ready...',
      );
  String helloUser(String name) => _t('merhaba $name', 'hey $name');

  // —— Campus ——
  String get campusTabEmpty => _t(
        'Kampüste henüz drop yok.\nAynı okul mailiyle biri bırakınca burada görünür.',
        'No campus drops yet.\nWhen someone with your school email drops, it shows here.',
      );
  String get campusNeedEmailTitle => _t(
        'Kampüs feed’i kilitli',
        'Campus feed locked',
      );
  String get campusNeedEmailBody => _t(
        'Öğrenci e-postanı bağla. Aynı domain’deki (@okul.edu.tr) insanlar birbirinin drop’larını konumdan bağımsız görür. Dışarıdan kimse göremez.',
        'Link your student email. People on the same domain (@school.edu) see each other’s drops anywhere. Outsiders stay out.',
      );
  String get campusClaimCta => _t(
        'Öğrenci mailini bağla',
        'Link student email',
      );
  String get campusClaimTitle => _t(
        'Öğrenci mailin',
        'Your student email',
      );
  String get campusClaimBody => _t(
        'Okul mailini yaz. Domain, kampüs feed’in olur. Sadece aynı mail türü görür.',
        'Enter your school email. That domain becomes your campus feed. Only matching emails can see it.',
      );
  String get campusEmailHint => 'ad@stu.istinye.edu.tr';
  String get campusEmailInvalid => _t(
        'Geçerli bir e-posta gir (ad@okul.edu.tr).',
        'Enter a valid email (name@school.edu).',
      );
  String get campusEmailSignInRequired => _t(
        'Kampüs için önce giriş yap.',
        'Sign in first for campus.',
      );
  String get campusUnlockSignIn => _t(
        'Açmak için giriş yap',
        'Sign in to unlock',
      );
  String get campusEmailClaimFailed => _t(
        'Bağlanamadı. Maili kontrol edip tekrar dene.',
        'Couldn’t link. Check the email and try again.',
      );
  String get campusEmailVerifyNote => _t(
        'Şimdilik profiline yazılır. Tam doğrulama (OTP / magic link) için Supabase Auth e-posta ayarı gerekir.',
        'Saved on your profile for now. Full OTP / magic-link verification needs Supabase Auth email setup.',
      );
  String get campusEmailLinkedToast => _t(
        'Kampüs bağlandı. Feed senin domain’in.',
        'Campus linked. Feed is your domain.',
      );
  String get campusAudienceNear => _t('Yakında', 'Nearby');
  String get campusAudienceCampus => _t('Kampüs', 'Campus');
  String get campusAudienceHint => _t(
        'Kampüs: yalnızca aynı okul maili görür.',
        'Campus: only your school email domain can see it.',
      );
  String get campusDropNeedsEmail => _t(
        'Campus drop için önce öğrenci e-postanı bağla.',
        'Link your student email before a campus drop.',
      );
  String get campusDropLabel => _t(
        'Kampüse bırak',
        'Drop to campus',
      );
  String get nearDropLabel => _t(
        'Yakına bırak',
        'Drop nearby',
      );
  String campusDropDone(String domain) => _t(
        'Kampüse bırakıldı. Sadece @$domain görür.',
        'Dropped to campus. Only @$domain can see it.',
      );
  String get dropDone => _t(
        'Drop yayınlandı.',
        'Drop published.',
      );

  // —— Feed / paylaş ——
  String get share => _t('Paylaş', 'Share');
  String get copyLink => _t('Linki kopyala', 'Copy link');
  String get notInterested => _t('İlgimi çekmiyor', 'Not interested');
  String get notInterestedToast => _t(
        'Tamam, bunu göstermeyeceğiz.',
        'Got it. We won’t show this.',
      );
  String get report => _t('Şikayet et', 'Report');
  String get reportWhy =>
      _t('Neden şikayet ediyorsun?', 'Why are you reporting?');
  String get reportHelp => _t(
        'Seçimin kampüsü temiz tutmamıza yardım eder.',
        'Your choice helps keep campus clean.',
      );
  String get options => _t('Seçenekler', 'Options');
  String get more => _t('Daha', 'More');
  String get seeMore => _t('...devamı', '...more');
  String get seeLess => _t('küçült', 'less');
  String get linkCopied => _t('Link panoya kopyalandı.', 'Link copied.');
  String get muted => _t('SESSİZ', 'MUTED');
  String get soundOn => _t('SES AÇIK', 'SOUND ON');
  String get reportReceived => _t('Şikayet alındı', 'Report received');
  String get videoHidden => _t('video gizlendi.', 'video hidden.');
  String get reportCampusCleaning => _t(
        'Şikayet alındı. İçerik incelenecek.',
        'Report received. We’ll review it.',
      );
  String get moderationTitle => _t('Moderasyon', 'Moderation');
  String get reportThisVideo =>
      _t('Bu videoyu şikayet et', 'Report this video');
  String get blockThisUser => _t(
        'Bu kullanıcıyı kalıcı olarak engelle',
        'Block this user permanently',
      );
  String get blockConfirmTitle =>
      _t('Kullanıcıyı engelle?', 'Block this user?');
  String get blockConfirmBody => _t(
        'Bu kişinin drop’ları bir daha akışında görünmez.',
        'Their drops will no longer appear in your feed.',
      );
  String get blockConfirmCta => _t('ENGELLE', 'BLOCK');
  String get userBlockedCampusClean => _t(
        'Kullanıcı engellendi.',
        'User blocked.',
      );
  String get signInToModerate => _t(
        'Şikayet ve engel için giriş yapmalısın.',
        'Sign in to report or block.',
      );
  String get profileBlockedTitle =>
      _t('Bu kullanıcı engellendi', 'This user is blocked');
  String get profileBlockedBody => _t(
        'Engellediğin kişinin profilini ve drop’larını göremezsin.',
        'You can’t see profiles or drops from people you’ve blocked.',
      );
  String get goBack => _t('Geri dön', 'Go back');
  String get shareDefaultCaption => _t('Nool drop', 'Nool drop');

  String get reportSpam => _t('Spam / reklam', 'Spam / ads');
  String get reportHarassment =>
      _t('Taciz / zorbalık', 'Harassment / bullying');
  String get reportSexual =>
      _t('Cinsel / uygunsuz içerik', 'Sexual / inappropriate');
  String get reportViolence => _t('Şiddet / nefret', 'Violence / hate');
  String get reportMisinfo => _t('Yanıltıcı bilgi', 'Misinformation');
  String get reportOther => _t('Diğer', 'Other');

  // —— Yorumlar ——
  String get commentsEmpty => _t(
        'Henüz yorum yok. İlkini sen yaz.',
        'No comments yet. Be the first.',
      );
  String get commentHint => _t('Yorum yaz...', 'Write a comment...');

  // —— Arama ——
  String get peopleSearchHint =>
      _t('@kullanıcı veya isim...', '@user or name...');
  String get friendNeedAccountDm => _t(
        'Mesaj için hesabını oluştur.',
        'Create an account to message.',
      );
  String get friendNeedAccountAdd => _t(
        'Kanka olmak için hesabını oluştur.',
        'Create an account to add buddies.',
      );

  // —— Mesajlar ——
  String get messagesTitle => _t('MESAJLAR', 'MESSAGES');
  String get messagesSubtitle => _t(
        'Direkt sohbetler, kadrolar ve kankalar.',
        'Direct chats, circles, and buddies.',
      );
  String get noSquadYet => _t('Henüz konuşma yok.', 'No conversations yet.');
  String get noSquadHint => _t(
        'Profilinden Mesaj’a bas veya kadro kur.',
        'Tap Message on a profile or start a circle.',
      );
  String get loginRequired => _t('Giriş gerekli', 'Sign-in required');
  String get messagesNeedAccount => _t(
        'Mesajlar için hesabını oluştur.',
        'Create an account to use messages.',
      );
  String get secureAccount => _t('Hesabı oluştur', 'Create account');
  String get secureAccountTitle => _t(
        'Hâlâ anon’sun.',
        'You’re still anonymous.',
      );
  String get secureAccountBody => _t(
        'Drop’ların ve kankaların kalsın diye hesabını oluştur. Bir dakika sürer.',
        'Create an account so your drops and buddies stick around. Takes a minute.',
      );
  String get secureAccountCta => _t('HESABIMI OLUŞTUR', 'CREATE ACCOUNT');
  String get secureAccountBannerTitle =>
      _t('Hesabımı oluştur', 'Create account');
  String get secureAccountBannerHint => _t(
        'Anonim kalma. Drop’ların kaybolmasın.',
        'Don’t stay anonymous. Keep your drops.',
      );

  String get dmSection => _t('DİREKT', 'DIRECT');
  String get dmOpenChat => _t('Direkt mesaj', 'Direct message');
  String get dmChatHint => _t('Mesaj yaz...', 'Write a message...');
  String get dmChatEmpty => _t(
        'Henüz mesaj yok.\nİlk mesajı sen at.',
        'No messages yet.\nSend the first one.',
      );
  String get dmMessageCta => _t('Mesaj', 'Message');
  String get dmOpenFailed => _t(
        'Mesaj açılamadı. Biraz sonra tekrar dene.',
        'Couldn’t open chat. Try again shortly.',
      );
  String get dmNoPreview => _t('Sohbete başla', 'Start chatting');

  String get kadrolarSection => _t('KADROLAR', 'CIRCLES');
  String get squadsSection => _t('KANKALAR', 'BUDDIES');

  // —— Kankalar / bildirimler ——
  String get friendAddCta => _t('Kanka ol', 'Add buddy');
  String get friendAccept => _t('Kabul', 'Accept');
  String get friendReject => _t('Reddet', 'Reject');
  String get friendCancel => _t('İptal', 'Cancel');
  String get friendPendingSent => _t('İstek gönderildi', 'Request sent');
  String get friendPendingReceived => _t('İsteği kabul et', 'Accept request');
  String get friendAlready => _t('Kankadasınız', 'Buddies');
  String get friendUnfriend => _t('Kankalıktan çıkar', 'Remove buddy');
  String get friendAcceptedToast =>
      _t('Artık kankadasınız.', 'You are now buddies.');
  String get friendRejectedToast =>
      _t('İstek reddedildi.', 'Request rejected.');
  String get friendCancelledToast =>
      _t('İstek iptal edildi.', 'Request cancelled.');
  String get friendRemovedToast => _t('Kankalık kaldırıldı.', 'Buddy removed.');
  String get friendRequestsTitle => _t('KANKA İSTEKLERİ', 'BUDDY REQUESTS');
  String get friendIncomingSection => _t('GELEN İSTEKLER', 'INCOMING');
  String get friendOutgoingSection => _t('GİDEN İSTEKLER', 'OUTGOING');
  String get friendIncomingEmpty => _t(
        'Gelen istek yok.',
        'No incoming requests.',
      );
  String get friendOutgoingEmpty => _t(
        'Giden istek yok.',
        'No outgoing requests.',
      );
  String get friendRequestsEntry => _t('İstekler', 'Requests');
  String get friendsListEntry => _t('Kankalar', 'Buddies');

  String get notificationsTitle => _t('BİLDİRİMLER', 'NOTIFICATIONS');
  String get notificationsSubtitle => _t(
        'İstekler, mesajlar ve hatırlatmalar.',
        'Requests, messages, and reminders.',
      );
  String get notificationsEmpty =>
      _t('Henüz bildirim yok.', 'No notifications yet.');
  String get notificationsEmptyHint => _t(
        'Kanka isteği veya mesaj gelince burada görünür.',
        'Buddy requests and messages show up here.',
      );
  String get notificationsMarkAll => _t('Tümünü oku', 'Mark all read');
  String get notificationsBellTooltip => _t('Bildirimler', 'Notifications');
  String get pushPermissionTitle => _t(
        'Bildirimler açılsın mı?',
        'Turn on notifications?',
      );
  String get pushPermissionBody => _t(
        'Kanka isteği veya mesaj gelince haberin olsun. İstediğin zaman kapatabilirsin.',
        'Get notified for buddy requests and messages. You can turn this off anytime.',
      );
  String get pushPermissionLater => _t('ŞİMDİLİK YOK', 'NOT NOW');
  String get pushPermissionAllow => _t('AÇ', 'ALLOW');
  String get createCircleTitle => _t('Yeni Kadro', 'New Circle');
  String get createCircleNameHint => _t('Kadro adı', 'Circle name');
  String get createCirclePickMembers => _t(
        'Kankalarından üye seç',
        'Pick members from your buddies',
      );
  String get createCircleCta => _t('Kadro kur', 'Create circle');
  String get createCircleShort => _t('+ Kadro', '+ Circle');
  String kadrolarTileSub({required int streak}) => _t(
        'Kadro · 🔥 $streak',
        'Circle · 🔥 $streak',
      );
  String get deleteKadroTitle => _t('Kadroyu sil?', 'Delete circle?');
  String get deleteKadroBody => _t(
        'Bu kadro, mesajları, drop’ları ve ateş sayısı kalıcı olarak silinir. Geri alınamaz.',
        'This circle, its messages, drops, and fire count will be permanently deleted. This cannot be undone.',
      );
  String get deleteKadroConfirm => _t('Kadroyu sil', 'Delete circle');
  String get deleteKadroMenu => _t('Kadroyu sil', 'Delete circle');
  String get deleteKadroDone => _t('Kadro silindi.', 'Circle deleted.');
  String get deleteKadroOwnerOnly => _t(
        'Yalnızca kadro kurucusu silebilir.',
        'Only the circle creator can delete it.',
      );

  String get watchGroupFeedCta => _t('KADRO AKIŞINI İZLE', 'WATCH CIRCLE FEED');
  String get dropToGroupCta => _t('Gruba drop et', 'Drop to group');
  String get groupChatHint => _t('Kadrona yaz...', 'Message your circle...');
  String get groupChatEmpty => _t(
        'Henüz mesaj yok.\nYaz veya gruba video bırak.',
        'No messages yet.\nType or drop a video to the circle.',
      );
  String get groupFeedEmpty => _t(
        'Son 24 saatte drop yok.\nKameradan kadroya bir tane bırak.',
        'No drops in the last 24h.\nLeave one for the circle from the camera.',
      );
  String get squadOnlyChip => _t('• Sadece kadro', '• Circle only');
  String get kaosFireTitle => _t('Kadro ateşi yanıyor', 'Circle fire is live');
  String kaosFireBody({
    required int hours,
    required int minutes,
    required int streak,
  }) =>
      _t(
        'Sönmesine $hours saat $minutes dk\nMevcut ateş: $streak',
        '$hours h $minutes min left\nCurrent fire: $streak',
      );
  String dropToGroupToast(String name) => _t(
        '$name kadrosuna bırakıldı.',
        'Dropped to $name.',
      );
  String dropToGroupOnly(String name) => _t(
        'Sadece $name kadrosuna bırak',
        'Drop only to $name',
      );
  String get cameraPreview => _t('Önizleme', 'Preview');
  String get captionRequired => _t(
        'Bir açıklama yaz.',
        'Add a caption.',
      );
  String get captionRequiredGroup => _t(
        'Bir açıklama yaz. Kadro ne olduğunu bilsin.',
        'Add a caption so your circle knows what’s up.',
      );
  String get cameraFlashRearOnly => _t(
        'Flaş yalnızca arka kamerada.',
        'Flash works on the rear camera only.',
      );
  String get cameraFlashUnsupported => _t(
        'Flaş bu cihazda desteklenmiyor.',
        'Flash isn’t supported on this device.',
      );
  String get cameraRecordFailed => _t(
        'Kayıt başlatılamadı.',
        'Couldn’t start recording.',
      );
  String get cameraStopFailed => _t(
        'Kayıt durdurulamadı.',
        'Couldn’t stop recording.',
      );
  String get supabaseNotConfigured => _t(
        'Sunucu bağlı değil. Yapılandırmayı kontrol et.',
        'Server isn’t connected. Check configuration.',
      );

  // —— Welcome / ilk açılış ——
  String get welcomeSkip => _t('Atla', 'Skip');
  String get welcomeContinue => _t('Devam', 'Continue');
  String get welcomeStartCta => _t('KEŞFET', 'EXPLORE');
  String get welcomePage1Headline => _t(
        'Yakındaki vibe’lar',
        'Nearby vibes',
      );
  String get welcomePage1Body => _t(
        'Kampüs ve semtinde paylaşılan kısa videolar.',
        'Short videos shared on campus and around you.',
      );
  String get welcomePage2Headline => _t(
        'İzle, bırak',
        'Watch, drop',
      );
  String get welcomePage2Body => _t(
        'Yakındakileri gör. İstersen kameradan kendi anını paylaş.',
        'See what’s near you. Share a moment from the camera when you want.',
      );
  String get welcomePage3Headline => _t(
        'Akışa gir',
        'Jump in',
      );
  String get welcomePage3Body => _t(
        'Konum yakındakileri açar. Hesap şart değil.',
        'Location unlocks nearby. An account isn’t required.',
      );

  // —— Splash / izin ——
  String get splashTagline => _t(
        'kampüs, canlı',
        'campus, live',
      );
  String get locationRequiredTitle => _t(
        'Konum gerekli',
        'Location needed',
      );
  String get locationRequiredBody => _t(
        'Yakındaki drop’ları göstermek için konuma ihtiyacımız var.',
        'We need your location to show nearby drops.',
      );
  String locationRequiredBodyNamed(String name) => _t(
        '$name, yakındaki drop’ları göstermek için konum lazım.',
        '$name, we need location to show nearby drops.',
      );
  String get locationGpsOff => _t(
        'GPS kapalı görünüyor. Konumu aç, yakındakiler gelsin.',
        'GPS looks off. Turn on location to see what’s nearby.',
      );
  String get locationServiceOff => _t(
        'Konum servisi kapalı. Ayarlardan GPS’i aç, sonra tekrar dene.',
        'Location services are off. Turn on GPS in Settings, then try again.',
      );
  String get locationDenied => _t(
        'Yakındakileri görmek için konuma ihtiyacımız var. İzni ayarlardan açabilirsin.',
        'We need location to show what’s nearby. You can enable it in Settings.',
      );
  String get enableLocationCta => _t(
        'KONUMU AÇ',
        'ENABLE LOCATION',
      );
  String get permissionDeniedHeadline => _t(
        'Yakındakileri görmek için konuma ihtiyacımız var',
        'We need location to show what’s nearby',
      );
  String get permissionDeniedBody => _t(
        'İzin yoksa harita ve yakındaki drop’lar görünmez. Ayarlardan konumu açıp geri dön.',
        'Without permission the map and nearby drops stay hidden. Enable location in Settings, then come back.',
      );
  String get retryPermission => _t('İzni yeniden dene', 'Retry permission');
  String get backToStart => _t('Başa dön', 'Back to start');

  // —— Radar ——
  String get radarScanning => _t(
        'Nool Radar taranıyor...',
        'Scanning Nool Radar...',
      );
  String get radarFallback => _t(
        'Çevrende drop yok. Halka sonuna gelindi.',
        'No drops around you. Reached the outer ring.',
      );
  String radarAtMeters(int meters) {
    switch (meters) {
      case 500:
        return _t('500m. Yakın halka taranıyor...', '500m. Scanning nearby...');
      case 1000:
        return _t('1 km. Halka genişliyor...', '1 km. Widening the ring...');
      case 2000:
        return _t('2 km. Semt yoklanıyor...', '2 km. Checking the area...');
      case 3000:
        return _t('3 km. Çevre genişliyor...', '3 km. Expanding further...');
      case 5000:
        return _t('5 km. Kampüs halkası...', '5 km. Campus ring...');
      case 10000:
        return _t('10 km. Şehir çeperi...', '10 km. City edge...');
      case 20000:
        return _t('20 km. Son halka...', '20 km. Outer ring...');
      default:
        return radarScanning;
    }
  }

  // —— Trend ——
  String get trendHeadline =>
      _t('ÇEVRENDE KAÇ VİDEO?', 'HOW MANY VIDEOS NEAR YOU?');
  String get trendSub => _t(
        'Yoğunluk halkası. Konum başına video sayısı.',
        'Density ring. Video count per spot.',
      );
  String trendSubWithRadius(String radiusLabel) => _t(
        '$radiusLabel yoğunluk. Pinler video sayısını gösterir.',
        '$radiusLabel density. Pins show video counts.',
      );
  String get heat => _t('ISI', 'HEAT');
  String get cold => _t('soğuk', 'cold');
  String get hot => _t('sıcak', 'hot');
  String get dropsHere => _t('Buradaki videolar', 'Videos here');
  String get trendNoHeat => _t(
        'Bu halkada henüz video yok. Drop bırak veya halkayı genişlet.',
        'No videos in this ring yet. Drop one or widen the ring.',
      );
  String get trendGpsError => _t(
        'GPS çekmiyor. Konumu açıp yenile.',
        'GPS unavailable. Turn on location and refresh.',
      );
  String get trendConnError => _t(
        'Bağlantı koptu. Wi-Fi’yi kontrol edip tekrar dene.',
        'Connection lost. Check Wi-Fi and try again.',
      );
  String get trendRetry => _t('Yeniden dene', 'Try again');
  String get trendStop => _t('DUR.', 'STOP.');
  String get densityRing => _t('HALKA', 'RING');
  String get densityAuto => _t('Oto', 'Auto');
  String get trendIntroSkip => _t('dokun, geç', 'tap to skip');
  String trendVideoCount(int n) =>
      n == 1 ? _t('1 video', '1 video') : _t('$n video', '$n videos');
  String trendAway(String distance) => _t('$distance uzakta', '$distance away');
  String densityRadiusLabel(double meters) {
    if (meters < 1000) return '${meters.round()}m';
    final km = meters / 1000;
    if (km == km.roundToDouble()) return '${km.round()}km';
    return '${km.toStringAsFixed(1)}km';
  }

  // —— Giriş / şifre sıfırlama ——
  String get signInTitle => _t('Giriş Yap', 'Sign in');
  String get signInSubtitle => _t(
        'Google veya e-posta ile kampüse bağlan.',
        'Join campus with Google or email.',
      );
  String get signUpSubtitle => _t(
        'Hesabını oluştur, drop’ların kalsın.',
        'Create an account so your drops stick around.',
      );
  String get verifyEmailHint => _t(
        'Mailini doğrula, sonra Giriş Yap ile devam et. (E-posta onayı açıksa)',
        'Verify your email, then continue with Sign in. (If email confirmation is on)',
      );
  String get forgotPassword => _t('Şifremi unuttum', 'Forgot password');
  String get forgotPasswordTitle => _t('Şifremi unuttum', 'Forgot password');
  String get forgotPasswordSubtitle => _t(
        'E-postanı yaz. Sıfırlama linkini göndeririz.',
        'Enter your email. We’ll send a reset link.',
      );
  String get forgotPasswordEmailHint => _t('E-posta', 'Email');
  String get forgotPasswordCta =>
      _t('SIFIRLAMA LİNKİ GÖNDER', 'SEND RESET LINK');
  String get forgotPasswordNeedEmail => _t(
        'Şifre sıfırlamak için önce e-postanı yaz.',
        'Enter your email first to reset your password.',
      );
  String get forgotPasswordInvalidEmail =>
      _t('Geçerli bir e-posta yaz', 'Enter a valid email');
  String get forgotPasswordSuccessTitle => _t('Mail yolda', 'Check your inbox');
  String get forgotPasswordSuccessBody => _t(
        'Sıfırlama linki gönderildi. Mailini kontrol et, linke dokun, yeni şifreni Nool’da belirle.',
        'Reset link sent. Check your email, tap the link, then set a new password in Nool.',
      );
  String get forgotPasswordBackToSignIn => _t('Girişe dön', 'Back to sign in');
  String get resetPasswordTitle => _t('Yeni şifre', 'New password');
  String get resetPasswordSubtitle => _t(
        'Yeni bir şifre belirle, hesabına dön.',
        'Pick a new password and get back in.',
      );
  String get resetPasswordLabel => _t('Yeni şifre', 'New password');
  String get resetPasswordConfirmLabel =>
      _t('Şifre tekrar', 'Confirm password');
  String get resetPasswordCta => _t('ŞİFREYİ KAYDET', 'SAVE PASSWORD');
  String get resetPasswordSuccessTitle => _t('Şifre hazır', 'Password set');
  String get resetPasswordSuccess => _t(
        'Şifren güncellendi. Girişe hazırsın.',
        'Password updated. You’re ready to sign in.',
      );
  String get resetPasswordDoneCta => _t('Tamam', 'Done');
  String get resetPasswordMismatch =>
      _t('Şifreler uyuşmuyor', 'Passwords don’t match');
  String get resetPasswordTooShort =>
      _t('En az 6 karakter', 'At least 6 characters');
  String get passwordLabel => _t('Şifre', 'Password');

  // —— Kayıt / yasal ——
  String get signUp => _t('Kayıt Ol', 'Sign up');
  String get legalCheckboxPrefix => _t(
        'Konum, kamera, mikrofon, galeri ve veri işleme izinleri dahil Nool kullanım şartlarını ve gizlilik politikasını ',
        'I have read Nool’s terms and privacy policy (location, camera, mic, gallery, data) and I ',
      );
  String get legalRead => _t('okudum', 'accept');
  String get legalAnd => _t(' ve ', ' ');
  String get legalApproved => _t('onayladım.', 'them.');
  String get readFullTerms => _t('Tam metni oku', 'Read full terms');
  String get legalMustAccept => _t(
        'Devam etmek için kullanım şartlarını ve izinleri okuyup onayla.',
        'Accept the terms and permissions to continue.',
      );
  String get signUpCta => _t('KAYIT OL', 'SIGN UP');
  String get signUpCtaNeedConsent => _t('ÖNCE ONAYLA', 'ACCEPT FIRST');
  String get termsTitle =>
      _t('Kullanım şartları ve izinler', 'Terms and permissions');
  String get termsIntro => _t(
        'Nool’a kayıt olarak aşağıdaki izinleri ve hukuki koşulları okuduğunu ve kabul ettiğini onaylarsın.',
        'By signing up for Nool you confirm you have read and accept the following permissions and legal terms.',
      );

  List<({String title, String body})> get legalSections => [
        (
          title: _t('1. Konum izni', '1. Location'),
          body: _t(
            'Yakınındaki drop’ları, trend ısı haritasını ve kampüs mesafesini hesaplamak için konumuna erişiriz. Konum, feed sıralaması ve yakındaki içerik için kullanılır; izni istediğin zaman cihaz ayarlarından kapatabilirsin.',
            'We use your location for nearby drops, the trend heat map, and campus distance. Location powers feed ranking and nearby content; you can turn it off in device settings anytime.',
          ),
        ),
        (
          title: _t('2. Kamera ve mikrofon', '2. Camera and microphone'),
          body: _t(
            'Video drop bırakmak için kamera ve mikrofon erişimi gerekir. Kayıt yalnızca sen başlattığında alınır; izinsiz arka planda kayıt yapılmaz.',
            'Camera and mic access are required to drop videos. Recording starts only when you start it; we never record in the background without you.',
          ),
        ),
        (
          title: _t('3. Galeri / fotoğraf', '3. Photos / gallery'),
          body: _t(
            'Profil fotoğrafı seçmek veya galeriden medya eklemek için fotoğraf kitaplığına erişebiliriz. Seçtiğin dosya dışında galerini taramayız.',
            'We may access your photo library to set a profile photo or add media. We do not scan your gallery beyond the file you pick.',
          ),
        ),
        (
          title: _t('4. Hesap ve kimlik verileri', '4. Account and identity'),
          body: _t(
            'E-posta, Google veya Apple ile kayıt olduğunda kimlik doğrulama bilgilerin güvenli şekilde işlenir. Kullanıcı adı, bio ve avatar profilinde görünür olabilir.',
            'When you sign up with email, Google, or Apple, your auth data is handled securely. Username, bio, and avatar may appear on your profile.',
          ),
        ),
        (
          title: _t('5. İçerik ve paylaşım', '5. Content and sharing'),
          body: _t(
            'Yüklediğin videolar, yorumlar ve tepkiler kampüste görünebilir. Yasadışı, nefret içeren, cinsel istismar veya şiddet içeren içerik yasaktır. Şikayet edilen içerikler incelenir ve kaldırılabilir.',
            'Videos, comments, and reactions you post may appear on campus. Illegal, hateful, sexual abuse, or violent content is banned. Reported content may be reviewed and removed.',
          ),
        ),
        (
          title: _t('6. Veri saklama', '6. Data retention'),
          body: _t(
            'Drop’ların akışta gösterimi 24 saatle sınırlıdır; bu, dosyaların aynı anda fiziksel olarak silindiği anlamına gelmez. Hesabını Ayarlar’dan silebilirsin. Silme hata verirse tekrar dene veya destek ekibine yaz.',
            'Drops appear in the feed for 24 hours; this does not guarantee simultaneous physical file deletion. You can delete your account in Settings. If deletion fails, retry or contact support.',
          ),
        ),
        (
          title: _t('7. Yaş ve sorumluluk', '7. Age and responsibility'),
          body: _t(
            'Nool’u kullanarak ilgili yasalara uygun yaşta olduğunu ve paylaştığın içerikten sorumlu olduğunu kabul edersin. Uygulama izinlerini ve bu metni okuyup onayladığını beyan edersin.',
            'By using Nool you confirm you meet the legal age and are responsible for what you share. You also confirm you have read and accept these permissions and terms.',
          ),
        ),
        (
          title: _t('8. Destek ve şikayet', '8. Support and reports'),
          body: _t(
            'Destek, veri talepleri ve uygunsuz içerik şikayetleri için aricefearda@gmail.com adresine yazabilirsin. Web sitesi: https://drective.io. Videonun menüsünden şikayet edebilir ve kullanıcıları engelleyebilirsin.',
            'For support, data requests and inappropriate content reports, email aricefearda@gmail.com. Website: https://drective.io. You can report videos and block users from the video menu.',
          ),
        ),
      ];
}

extension AppStringsX on BuildContext {
  AppStrings get s => AppStrings.of(this);
}
