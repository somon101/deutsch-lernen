// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Tajik (`tg`).
class AppLocalizationsTg extends AppLocalizations {
  AppLocalizationsTg([String locale = 'tg']) : super(locale);

  @override
  String get settingsTitle => 'Танзимот';

  @override
  String get sectionAccount => 'Ҳисоб';

  @override
  String get personalDetails => 'Маълумоти шахсӣ';

  @override
  String get securityPrivacy => 'Амният ва махфият';

  @override
  String get sectionLearning => 'Таълим';

  @override
  String get dailyGoal => 'Ҳадафи рӯзона';

  @override
  String dailyGoalMinutes(int minutes) {
    return '$minutes дақ';
  }

  @override
  String get languageLevel => 'Сатҳи забон';

  @override
  String get lessonSounds => 'Садоҳо дар дарсҳо';

  @override
  String get wordPronunciation => 'Талаффузи калимаҳо';

  @override
  String get sectionNotifications => 'Огоҳиномаҳо';

  @override
  String get pushNotifications => 'Огоҳиномаҳои push';

  @override
  String get lessonReminder => 'Ёдоварӣ дар бораи дарс';

  @override
  String get reminderTime => 'Вақти ёдоварӣ';

  @override
  String get streakReminder => 'Ёдоварии силсилаи рӯзҳо';

  @override
  String get sectionLanguageAppearance => 'Забон ва намуди зоҳирӣ';

  @override
  String get appLanguage => 'Забони барнома';

  @override
  String get statisticsLanguage => 'Омори курс';

  @override
  String get statisticsLanguageNotSet => 'Интихоб кунед';

  @override
  String get courseContentLanguage => 'Забони курс';

  @override
  String get theme => 'Мавзӯъ';

  @override
  String get themeDark => 'Торик';

  @override
  String get themeLight => 'Равшан';

  @override
  String get themeSystem => 'Мисли система';

  @override
  String get sectionSupport => 'Дастгирӣ';

  @override
  String get helpFaq => 'Кӯмак ва саволҳои маъмул';

  @override
  String get contactUs => 'Бо мо тамос гиред';

  @override
  String get aboutApp => 'Дар бораи барнома';

  @override
  String appVersion(String version) {
    return 'Версияи $version';
  }

  @override
  String get clearCache => 'Тоза кардани кэш';

  @override
  String get clearCacheConfirmTitle => 'Маълумоти захирашударо тоза кунем?';

  @override
  String get clearCacheConfirmBody =>
      'Курсҳо ва дарсҳо ҳангоми кушодани навбатӣ аз сервер аз нав бор мешаванд.';

  @override
  String get clearCacheDone => 'Кэш тоза шуд';

  @override
  String get logout => 'Аз ҳисоб баромадан';

  @override
  String get logoutConfirmTitle => 'Аз ҳисоб мебароед?';

  @override
  String get logoutConfirmBody =>
      'Шумо метавонед дар ҳар лаҳза бозгашта ворид шавед.';

  @override
  String get cancel => 'Бекор кардан';

  @override
  String get change => 'Тағйир додан';

  @override
  String get comingSoon => 'Ба зудӣ';

  @override
  String get chooseOption => 'Вариантро интихоб кунед';

  @override
  String get back => 'Бозгашт';

  @override
  String get save => 'Захира кардан';

  @override
  String get saved => 'Профил захира шуд';

  @override
  String get copy => 'Нусхабардорӣ';

  @override
  String get copied => 'Нусхабардорӣ шуд';

  @override
  String get profileEditDisabled =>
      'Таҳрири профил аз ҷониби маъмур ғайрифаъол карда шудааст — маълумот танҳо барои дидан дастрас аст.';

  @override
  String get personalDetailsFirstName => 'Ном';

  @override
  String get personalDetailsLastName => 'Насаб';

  @override
  String get personalDetailsUsername => 'Номи корбарӣ';

  @override
  String get personalDetailsUsernameHint => 'ҳарфҳои лотинӣ, рақамҳо, _';

  @override
  String get personalDetailsBirthDate => 'Санаи таваллуд';

  @override
  String get personalDetailsSelectDate => 'Санаро интихоб кунед';

  @override
  String get personalDetailsBio => 'Дар бораи худ';

  @override
  String get personalDetailsBioPlaceholder => 'Дар бораи худ нависед';

  @override
  String personalDetailsBioCounter(int count) {
    return '$count/150';
  }

  @override
  String get personalDetailsFirstNameRequired => 'Номро ворид кунед';

  @override
  String get personalDetailsLastNameRequired => 'Насабро ворид кунед';

  @override
  String get personalDetailsUsernameInvalid =>
      'Танҳо ҳарфҳои лотинӣ, рақамҳо ва «_», аз 3 то 32 аломат';

  @override
  String get securityChangePassword => 'Тағйир додани парол';

  @override
  String get securityCurrentPassword => 'Пароли ҷорӣ';

  @override
  String get securityNewPassword => 'Пароли нав';

  @override
  String get securityRepeatPassword => 'Паролро такрор кунед';

  @override
  String get securityPasswordsDontMatch => 'Паролҳо мувофиқат намекунанд';

  @override
  String get securityPasswordTooShort =>
      'Парол бояд на кам аз 6 аломат дошта бошад';

  @override
  String get securityPasswordChanged => 'Парол тағйир ёфт';

  @override
  String get securityEmailLabel => 'Email';

  @override
  String get securityChangeEmail => 'Тағйир додани email';

  @override
  String get securityNewEmail => 'Email-и нав';

  @override
  String get securityEmailInvalid => 'Формати email нодуруст аст';

  @override
  String get securityVerificationCode => 'Рамзи тасдиқ';

  @override
  String get securityLinkedAccounts => 'Ҳисобҳои пайвастшуда';

  @override
  String get securityLinked => 'Пайваст шудааст';

  @override
  String get securityNotLinked => 'Пайваст нашудааст';

  @override
  String get securityLink => 'Пайваст кардан';

  @override
  String get securityUnlink => 'Ҷудо кардан';

  @override
  String get securityDeleteAccount => 'Ҳисобро ҳазф кардан';

  @override
  String get securityDeleteAccountWarning =>
      'Ин амал баргарданашаванда аст. Ҳамаи маълумоти шумо барои ҳамеша ҳазф карда мешавад.';

  @override
  String get securityDeleteAccountConfirmTitle => 'Мутмаин ҳастед?';

  @override
  String get securityDeleteAccountConfirmBody =>
      'Барои тасдиқи ҳазфи ниҳоии ҳисобатон калимаи «ҲАЗФ»-ро ворид кунед.';

  @override
  String get securityDeleteConfirmationWord => 'ҲАЗФ';

  @override
  String get securityDeleteAccountAction => 'Ба таври ниҳоӣ ҳазф кардан';

  @override
  String get avatarTakePhoto => 'Расм гирифтан';

  @override
  String get avatarChooseFromGallery => 'Аз галерея интихоб кардан';

  @override
  String get avatarRemovePhoto => 'Расмро ҳазф кардан';

  @override
  String get qrCardTitle => 'Корти ман';

  @override
  String get qrCardLevel => 'Дараҷа';

  @override
  String qrCardGoal(String level, int percent) {
    return 'то $level — $percent%';
  }

  @override
  String get qrCardMaxLevel => 'Дараҷаи максималӣ';

  @override
  String get qrCardStreakLabel => 'рӯз пай дар пай';

  @override
  String get qrCardRankLabel => 'дар ҷаҳон';

  @override
  String get qrCardFollowersLabel => 'пайрав';

  @override
  String get qrCardSlogan => 'Your language · Your path · Your future';

  @override
  String get qrCardShare => 'Мубодила кардан';

  @override
  String get qrCardCopyId => 'ID-ро нусха бардоштан';

  @override
  String get qrCardIdCopied => 'ID нусха бардошта шуд';

  @override
  String get qrCardGenerating => 'Корт эҷод карда истодааст…';

  @override
  String get qrCardShareFailed => 'Мубодилаи корт ноком шуд';

  @override
  String get errorServerTimeout =>
      'Сервер ҷавоб намедиҳад (вақти интизорӣ гузашт). Пайвасти интернетро санҷед.';

  @override
  String get errorConnectionFailed =>
      'Пайваст бо сервер вуҷуд надорад. Интернет ва нишонии серверро санҷед.';

  @override
  String get errorSslCertificate => 'Хатои санҷиши сертификати сервер (SSL).';

  @override
  String get errorRequestCancelled => 'Дархост бекор карда шуд.';

  @override
  String get errorUnknownNetwork => 'Хатои номаълуми шабака';

  @override
  String get errorServerError => 'Хатои сервер. Баъдтар кӯшиш кунед.';

  @override
  String get errorNetworkGeneric => 'Хатои шабака';

  @override
  String get wordAudioTooltip => 'Талаффузро гӯш кунед';

  @override
  String get lessonStatusCompleted => '✓ Дарс анҷом ёфт';

  @override
  String get lessonStatusContinue => 'Идома додан';

  @override
  String get lessonStatusStart => 'Дарсро оғоз кардан';

  @override
  String get myWordsTitle => 'Калимаҳои ман';

  @override
  String myWordsLoadError(Object error) {
    return 'Боркунии калимаҳо ноком шуд: $error';
  }

  @override
  String get myWordsEmpty =>
      'Ҳанӯз калимаи омӯхташуда нест — онҳо пас аз анҷоми дарсҳо дар ин ҷо пайдо мешаванд.';

  @override
  String get myWordsUncategorized => 'Бе категория';

  @override
  String get leaderboardTitle => 'Рейтинг';

  @override
  String get leaderboardSearchHint => 'Аз рӯи ник ё ID ҷустуҷӯ кунед';

  @override
  String leaderboardLoadError(Object error) {
    return 'Боркунии рейтинг ноком шуд: $error';
  }

  @override
  String get leaderboardEmpty => 'Ҳанӯз иштирокчии рейтинг нест';

  @override
  String leaderboardSearchError(Object error) {
    return 'Ҷустуҷӯ иҷро нашуд: $error';
  }

  @override
  String get leaderboardUserNotFound => 'Корбар ёфт нашуд';

  @override
  String get authTagline => 'Барои идомаи таълим ворид шавед';

  @override
  String get authLoginOrEmail => 'Номи корбарӣ ё email';

  @override
  String get authLoginRequired => 'Номи корбариро ворид кунед';

  @override
  String get authPasswordLabel => 'Парол';

  @override
  String get authPasswordRequired => 'Паролро ворид кунед';

  @override
  String get authSignIn => 'Ворид шудан';

  @override
  String authSignInFailedDebug(Object error) {
    return 'Ворид шудан ноком шуд: $error';
  }

  @override
  String get authSignInFailed => 'Ворид шудан ба ҳисоб ноком шуд';

  @override
  String get forbiddenTitle => 'Дастрасӣ манъ аст';

  @override
  String get forbiddenBodyTeacher =>
      'Ин бахш танҳо барои маъмурон дастрас аст.';

  @override
  String get forbiddenBodyDefault => 'Шумо ба ин саҳифа дастрасӣ надоред.';

  @override
  String get forbiddenGoHome => 'Ба саҳифаи асосӣ';

  @override
  String get homeExitConfirmation => 'Барои баромадан бори дигар пахш кунед';

  @override
  String get homeLanguagePickerTitle => 'Забон';

  @override
  String get homeThemeLight => 'Мавзӯи равшан';

  @override
  String get homeThemeDark => 'Мавзӯи торик';

  @override
  String homeLanguagesLoadError(Object error) {
    return 'Боркунии забонҳо ноком шуд: $error';
  }

  @override
  String get homeNoCourses => 'Курсҳо ҳанӯз нашр нашудаанд';

  @override
  String homeGreeting(String name) {
    return 'Салом, $name!';
  }

  @override
  String homeLessonsLoadError(Object error) {
    return 'Боркунии дарсҳо ноком шуд: $error';
  }

  @override
  String get homeNoLessons => 'Ҳанӯз дарсе нест';

  @override
  String get lessonDownloadTitle => 'Расмҳои калимаҳо бор карда истодаанд';

  @override
  String get lessonDownloadSubtitle =>
      'Як маротиба — минбаъд дарс фавран кушода мешавад ва бидуни интернет кор мекунад.';

  @override
  String lessonDownloadProgress(int done, int total) {
    return '$done аз $total';
  }

  @override
  String get socialFollowers => 'Пайравон';

  @override
  String get socialFollowing => 'Обунаҳо';

  @override
  String get socialMutual => 'Мутақобила';

  @override
  String socialListLoadError(Object error) {
    return 'Боркунии рӯйхат ноком шуд: $error';
  }

  @override
  String get socialListEmpty => 'Ҳанӯз холӣ аст';

  @override
  String get socialThisIsYourProfile => 'Ин профили шумост';

  @override
  String get socialProfileTitle => 'Профил';

  @override
  String socialProfileLoadError(Object error) {
    return 'Боркунии профил ноком шуд: $error';
  }

  @override
  String socialStatsLoadError(Object error) {
    return 'Боркунии омор ноком шуд: $error';
  }

  @override
  String socialUnfollowError(Object error) {
    return 'Бекор кардани обуна ноком шуд: $error';
  }

  @override
  String socialFollowError(Object error) {
    return 'Обуна шудан ноком шуд: $error';
  }

  @override
  String get socialUnfollowing => 'Обуна бекор карда истодааст…';

  @override
  String get socialUnfollow => 'Бекор кардани обуна';

  @override
  String get socialFollowingInProgress => 'Обуна шуда истодааст…';

  @override
  String get socialFollow => 'Обуна шудан';

  @override
  String get gamificationLevelHint => 'Шумо ба дараҷаи навбатӣ наздик ҳастед!';

  @override
  String get gamificationAchievementFirstLessonTitle => 'Дарси аввал';

  @override
  String get gamificationAchievementDone => 'Гузашта шуд';

  @override
  String get gamificationAchievementWeekTitle => 'Ҳафтаи 7-рӯза';

  @override
  String get gamificationAchievementGoalTitle => 'Ҳадафи 10 дарс';

  @override
  String get gamificationAchievementActiveTitle => 'Хонандаи фаъол';

  @override
  String get gamificationAchievementLessons10 => '10 дарс';

  @override
  String get gamificationAchievementWordMasterTitle => 'Устоди калимаҳо';

  @override
  String get gamificationAchievementLocked => 'Баста аст';

  @override
  String get gamificationRankPeriodWeek => 'Аз рӯи ҳафта';

  @override
  String get gamificationLearningLanguageEnglish => 'англисӣ';

  @override
  String profileFollowStatsLoadError(Object error) {
    return 'Боркунии обунаҳо ноком шуд: $error';
  }

  @override
  String profileProgressLoadError(Object error) {
    return 'Боркунии пешравӣ ноком шуд: $error';
  }

  @override
  String get profileAchievementsTitle => 'Дастовардҳо';

  @override
  String profileRankLoadError(Object error) {
    return 'Боркунии рейтинг ноком шуд: $error';
  }

  @override
  String profileActivityLoadError(Object error) {
    return 'Боркунии фаъолият ноком шуд: $error';
  }

  @override
  String get profileShareTooltip => 'Мубодилаи профил';

  @override
  String get profileSeeAll => 'Ҳама';

  @override
  String get avatarOnline => 'онлайн';

  @override
  String get avatarOffline => 'офлайн';

  @override
  String get levelCardTitle => 'Дараҷаи шумо';

  @override
  String get metricsStreak => 'Силсила';

  @override
  String get metricsProgress => 'Пешравӣ';

  @override
  String get metricsTime => 'Вақт';

  @override
  String get metricsPoints => 'Холҳо';

  @override
  String get rankCardTitle => 'Рейтинги шумо';

  @override
  String rankTop(int percent) {
    return 'Топ $percent%';
  }

  @override
  String get rankGlobal => 'Ҷаҳонӣ';

  @override
  String rankOutOf(int total) {
    return 'аз $total';
  }

  @override
  String get rankAmongAllStudents => 'Дар байни ҳамаи хонандагон';

  @override
  String get weekActivityDayMon => 'Дш';

  @override
  String get weekActivityDayTue => 'Се';

  @override
  String get weekActivityDayWed => 'Чш';

  @override
  String get weekActivityDayThu => 'Пш';

  @override
  String get weekActivityDayFri => 'Ҷм';

  @override
  String get weekActivityDaySat => 'Шб';

  @override
  String get weekActivityDaySun => 'Як';

  @override
  String get weekActivityTitle => 'Фаъолият дар як ҳафта';

  @override
  String get weekActivityAverage => 'Фаъолияти миёна';

  @override
  String get gamificationLevelNameIntermediate => 'Миёна';

  @override
  String metricsTimeFormat(int hours, int minutes) {
    return '$hoursс $minutesд';
  }

  @override
  String weekActivityAvgPerDay(int minutes) {
    return '$minutesд/рӯз';
  }

  @override
  String get activityHistoryTitle => 'Таърихи фаъолият';

  @override
  String activityHistoryLoadError(Object error) {
    return 'Боркунии таърих ноком шуд: $error';
  }

  @override
  String activityHistoryMinutesActive(int minutes) {
    return '$minutes дақ фаъолият';
  }

  @override
  String get activityHistoryNoActivity => 'Фаъолият нест';

  @override
  String get stageVocabulary => 'Калимаҳо';

  @override
  String get stageMaterial => 'Мавод';

  @override
  String get stageVideo => 'Видео';

  @override
  String get stageMinitest => 'Тести хурд';

  @override
  String get stageAudio => 'Аудио';

  @override
  String get stagePractice => 'Машқ';

  @override
  String get stageReview => 'Мустаҳкамкунӣ';

  @override
  String get stageComplete => 'Натиҷа';

  @override
  String get lessonTitle => 'Дарс';

  @override
  String lessonLoadError(Object error) {
    return 'Боркунии дарс ноком шуд: $error';
  }

  @override
  String lessonUnknownBlockType(String type) {
    return 'Навъи номаълуми блок: $type';
  }

  @override
  String get lessonFinish => 'Дарсро анҷом додан';

  @override
  String lessonNext(String title) {
    return 'Баъдӣ: $title →';
  }

  @override
  String get lessonCompleteTitle => 'Кори аъло!';

  @override
  String lessonCompleteSubtitleGraph(String title) {
    return 'Шумо дарси «$title»-ро гузаштед. Инак натиҷаҳои шумо:';
  }

  @override
  String lessonCompleteSubtitleLinear(String title) {
    return 'Шумо ҳамаи марҳилаҳои дарси «$title»-ро гузаштед. Инак натиҷаҳои шумо:';
  }

  @override
  String get lessonCompleteWordsLearned => 'калима омӯхта шуд';

  @override
  String get lessonCompleteRestarting => 'Оғоз мекунем…';

  @override
  String get lessonCompleteRestart => 'Боз як бор гузаштан';

  @override
  String get lessonCompleteMinitestLabel => 'тести хурд';

  @override
  String get lessonCompletePracticeLabel => 'машқ';

  @override
  String get lessonCompleteReviewLabel => 'мустаҳкамкунӣ';

  @override
  String get vocabularyStageEmpty =>
      'Дар ин дарс калимаи нав нест — ҳамаашон қаблан вохӯрда буданд.';

  @override
  String get commonNext => 'Баъдӣ';

  @override
  String get lessonStageSkip => 'Гузарондан ва идома додан';

  @override
  String materialStageStepTitle(int number, String title) {
    return 'Қадами $number. $title';
  }

  @override
  String get materialStageMissing => 'Мавод намерасад';

  @override
  String get materialStageNotFound => 'Матни дарс ёфт нашуд.';

  @override
  String materialStageSection(int page, int total) {
    return 'Бахши $page аз $total';
  }

  @override
  String get materialStageDefaultNextVideo => 'Гузаштан ба видео';

  @override
  String get materialStageNextArrow => 'Баъдӣ →';

  @override
  String get materialStageBack => '← Бозгашт';

  @override
  String get videoStageNotFound => 'Видео ёфт нашуд';

  @override
  String get videoStageNotUploaded =>
      'Барои ин дарс видео бор карда нашудааст.';

  @override
  String get videoStageWatch => 'Видеоро тамошо кунед';

  @override
  String get videoStageWatched => '✓ Видео тамошо шуд';

  @override
  String get videoStageWatchToContinue =>
      'Барои идома додан видеоро то охир тамошо кунед';

  @override
  String get videoStageDefaultNextMinitest => 'Гузаштан ба тести хурд →';

  @override
  String get audioStageLoadError =>
      'Боркунии файли аудио ноком шуд. Санҷед, ки файл мавҷуд ва дастрас аст, ва бори дигар кӯшиш кунед.';

  @override
  String get audioStagePlaybackError =>
      'Пахши аудио оғоз нашуд. Санҷед, ки садо хомӯш нашудааст, ва бори дигар кӯшиш кунед.';

  @override
  String get audioStageNotFound => 'Аудио ёфт нашуд';

  @override
  String get audioStageNotUploaded =>
      'Барои ин дарс сабти аудио бор карда нашудааст.';

  @override
  String get audioStageListen => 'Аудиоро гӯш кунед';

  @override
  String get audioStageListenHint =>
      'Сабтро гӯш кунед ва талаффузи ибораҳои дарсро мустаҳкам кунед.';

  @override
  String get audioStageFinished => '✓ Сабт гӯш карда шуд';

  @override
  String get audioStageListenToContinue =>
      'Барои идома додан сабтро то охир гӯш кунед';

  @override
  String get audioStageDefaultNextPractice => 'Гузаштан ба машқ →';

  @override
  String get exerciseKindChoice => 'Интихоби ҷавоб';

  @override
  String get exerciseKindTrueFalse => 'Дуруст ё нодуруст';

  @override
  String get exerciseKindMatch => 'Мутобиқат';

  @override
  String get exerciseKindScramble => 'Ибораро ҷамъ кунед';

  @override
  String get exerciseKindCloze => 'Ҷои холиро пур кунед';

  @override
  String get exerciseKindAutoBlank => 'Калимаи ғайб';

  @override
  String get exerciseKindAutoTranslate => 'Калимаро тарҷума кунед';

  @override
  String get exercisePromptMatch => 'Мутобиқати калимаҳо ва тарҷумаҳо';

  @override
  String exercisePromptScramble(String translation) {
    return 'Ибора аз рӯи тарҷумаи «$translation»';
  }

  @override
  String exercisePromptCloze(String translation) {
    return 'Ҷои холӣ дар ибораи «$translation»';
  }

  @override
  String exerciseCorrectAnswer(String answer) {
    return 'Ҷавоби дуруст: «$answer»';
  }

  @override
  String get exerciseNotAllPairsMatched =>
      'На ҳамаи ҷуфтҳо аз кӯшиши аввал мутобиқат карда шуданд';

  @override
  String exerciseCorrectScramble(String answer) {
    return 'Дуруст: «$answer»';
  }

  @override
  String exerciseCorrectWord(String answer) {
    return 'Калимаи дуруст: «$answer»';
  }

  @override
  String get exerciseDetailsInHistory => 'Тафсилот — дар таърихи ҷавобҳо';

  @override
  String get exerciseStageNotEnoughMaterial =>
      'Барои ин блок мавод кофӣ нест — идома медиҳем.';

  @override
  String exerciseStageProgress(int index, int total) {
    return 'Супориши $index аз $total';
  }

  @override
  String exerciseStageCorrectCount(int count) {
    return '$count дуруст';
  }

  @override
  String get exerciseStageNextEnter => 'Навбатӣ (Enter)';

  @override
  String get exerciseStageFinishEnter => 'Анҷом додан (Enter)';

  @override
  String get exerciseStageResultTitle => 'Натиҷа';

  @override
  String get exerciseStageAllCorrect => 'Аъло, ҳама дуруст!';

  @override
  String get exerciseStageGoodResult =>
      'Натиҷаи хуб. Хатоҳоро дар поён баррасӣ мекунем.';

  @override
  String get exerciseStageContinueEnter => 'Идома додан (Enter)';

  @override
  String homeMapWordCount(int count) {
    return '$count калима';
  }

  @override
  String get homeMapLockedSnack => 'Дарси қаблиро анҷом диҳед';

  @override
  String get leaderboardPeriodDay => 'Рӯз';

  @override
  String get leaderboardPeriodWeek => 'Ҳафта';

  @override
  String get leaderboardPeriodMonth => 'Моҳ';

  @override
  String get leaderboardPeriodAllTime => 'Тамоми вақт';

  @override
  String get leaderboardColumnRank => 'Ҷой';

  @override
  String get leaderboardColumnStudent => 'Донишҷӯ';

  @override
  String get leaderboardColumnPoints => 'Хол';

  @override
  String leaderboardGoalToPlace(int rank, int points) {
    return 'То ҷои $rank — $points хол';
  }

  @override
  String leaderboardGoalBeatName(String name) {
    return 'Як дарс, ва ту аз $name пеш мегузарӣ';
  }

  @override
  String get leaderboardGoalTop => 'Ту дар қулла ҳастӣ. Ҷойгаҳатро нигоҳ дор';

  @override
  String get leaderboardThisIsYou => 'Ин туӣ';

  @override
  String get leaderboardSearchTooltip => 'Ҷустуҷӯ';

  @override
  String get leaderboardInfoTooltip => 'Холҳо чӣ тавр ҳисоб мешаванд';

  @override
  String get leaderboardInfoTitle => 'Холҳо чӣ тавр ҳисоб мешаванд';

  @override
  String get leaderboardInfoBody =>
      'Барои ҳар як саволи дуруст ҷавобдодашуда 10 хол ва барои ҳар дарси анҷомёфта 50 хол.';

  @override
  String get leaderboardRetry => 'Такрор кардан';
}
