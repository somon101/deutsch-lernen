import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_ru.dart';
import 'app_localizations_tg.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('ru'),
    Locale('tg'),
  ];

  /// Settings screen app bar title
  ///
  /// In ru, this message translates to:
  /// **'Настройки'**
  String get settingsTitle;

  /// No description provided for @sectionAccount.
  ///
  /// In ru, this message translates to:
  /// **'Аккаунт'**
  String get sectionAccount;

  /// No description provided for @personalDetails.
  ///
  /// In ru, this message translates to:
  /// **'Персональные данные'**
  String get personalDetails;

  /// No description provided for @securityPrivacy.
  ///
  /// In ru, this message translates to:
  /// **'Безопасность и конфиденциальность'**
  String get securityPrivacy;

  /// No description provided for @sectionLearning.
  ///
  /// In ru, this message translates to:
  /// **'Обучение'**
  String get sectionLearning;

  /// No description provided for @dailyGoal.
  ///
  /// In ru, this message translates to:
  /// **'Цель в день'**
  String get dailyGoal;

  /// No description provided for @dailyGoalMinutes.
  ///
  /// In ru, this message translates to:
  /// **'{minutes} мин'**
  String dailyGoalMinutes(int minutes);

  /// No description provided for @languageLevel.
  ///
  /// In ru, this message translates to:
  /// **'Уровень языка'**
  String get languageLevel;

  /// No description provided for @lessonSounds.
  ///
  /// In ru, this message translates to:
  /// **'Звуки в уроках'**
  String get lessonSounds;

  /// No description provided for @wordPronunciation.
  ///
  /// In ru, this message translates to:
  /// **'Озвучка слов'**
  String get wordPronunciation;

  /// No description provided for @sectionNotifications.
  ///
  /// In ru, this message translates to:
  /// **'Уведомления'**
  String get sectionNotifications;

  /// No description provided for @pushNotifications.
  ///
  /// In ru, this message translates to:
  /// **'Push-уведомления'**
  String get pushNotifications;

  /// No description provided for @lessonReminder.
  ///
  /// In ru, this message translates to:
  /// **'Напоминание о занятии'**
  String get lessonReminder;

  /// No description provided for @reminderTime.
  ///
  /// In ru, this message translates to:
  /// **'Время напоминания'**
  String get reminderTime;

  /// No description provided for @streakReminder.
  ///
  /// In ru, this message translates to:
  /// **'Напоминание о серии дней'**
  String get streakReminder;

  /// No description provided for @sectionLanguageAppearance.
  ///
  /// In ru, this message translates to:
  /// **'Язык и внешний вид'**
  String get sectionLanguageAppearance;

  /// No description provided for @appLanguage.
  ///
  /// In ru, this message translates to:
  /// **'Язык программы'**
  String get appLanguage;

  /// No description provided for @statisticsLanguage.
  ///
  /// In ru, this message translates to:
  /// **'Статистика курса'**
  String get statisticsLanguage;

  /// No description provided for @statisticsLanguageNotSet.
  ///
  /// In ru, this message translates to:
  /// **'Выбрать'**
  String get statisticsLanguageNotSet;

  /// No description provided for @courseContentLanguage.
  ///
  /// In ru, this message translates to:
  /// **'Язык курса'**
  String get courseContentLanguage;

  /// No description provided for @theme.
  ///
  /// In ru, this message translates to:
  /// **'Тема'**
  String get theme;

  /// No description provided for @themeDark.
  ///
  /// In ru, this message translates to:
  /// **'Тёмная'**
  String get themeDark;

  /// No description provided for @themeLight.
  ///
  /// In ru, this message translates to:
  /// **'Светлая'**
  String get themeLight;

  /// No description provided for @themeSystem.
  ///
  /// In ru, this message translates to:
  /// **'Как в системе'**
  String get themeSystem;

  /// No description provided for @sectionSupport.
  ///
  /// In ru, this message translates to:
  /// **'Поддержка'**
  String get sectionSupport;

  /// No description provided for @helpFaq.
  ///
  /// In ru, this message translates to:
  /// **'Помощь и FAQ'**
  String get helpFaq;

  /// No description provided for @contactUs.
  ///
  /// In ru, this message translates to:
  /// **'Связаться с нами'**
  String get contactUs;

  /// No description provided for @aboutApp.
  ///
  /// In ru, this message translates to:
  /// **'О приложении'**
  String get aboutApp;

  /// No description provided for @appVersion.
  ///
  /// In ru, this message translates to:
  /// **'Версия {version}'**
  String appVersion(String version);

  /// No description provided for @clearCache.
  ///
  /// In ru, this message translates to:
  /// **'Очистить кэш'**
  String get clearCache;

  /// No description provided for @clearCacheConfirmTitle.
  ///
  /// In ru, this message translates to:
  /// **'Очистить сохранённые данные?'**
  String get clearCacheConfirmTitle;

  /// No description provided for @clearCacheConfirmBody.
  ///
  /// In ru, this message translates to:
  /// **'Курсы и уроки при следующем открытии загрузятся заново с сервера.'**
  String get clearCacheConfirmBody;

  /// No description provided for @clearCacheDone.
  ///
  /// In ru, this message translates to:
  /// **'Кэш очищен'**
  String get clearCacheDone;

  /// No description provided for @logout.
  ///
  /// In ru, this message translates to:
  /// **'Выйти из аккаунта'**
  String get logout;

  /// No description provided for @logoutConfirmTitle.
  ///
  /// In ru, this message translates to:
  /// **'Выйти из аккаунта?'**
  String get logoutConfirmTitle;

  /// No description provided for @logoutConfirmBody.
  ///
  /// In ru, this message translates to:
  /// **'Вы сможете снова войти в любой момент.'**
  String get logoutConfirmBody;

  /// No description provided for @cancel.
  ///
  /// In ru, this message translates to:
  /// **'Отмена'**
  String get cancel;

  /// No description provided for @change.
  ///
  /// In ru, this message translates to:
  /// **'Изменить'**
  String get change;

  /// No description provided for @comingSoon.
  ///
  /// In ru, this message translates to:
  /// **'Скоро'**
  String get comingSoon;

  /// No description provided for @chooseOption.
  ///
  /// In ru, this message translates to:
  /// **'Выберите вариант'**
  String get chooseOption;

  /// No description provided for @back.
  ///
  /// In ru, this message translates to:
  /// **'Назад'**
  String get back;

  /// No description provided for @save.
  ///
  /// In ru, this message translates to:
  /// **'Сохранить'**
  String get save;

  /// No description provided for @saved.
  ///
  /// In ru, this message translates to:
  /// **'Профиль сохранён'**
  String get saved;

  /// No description provided for @copy.
  ///
  /// In ru, this message translates to:
  /// **'Скопировать'**
  String get copy;

  /// No description provided for @copied.
  ///
  /// In ru, this message translates to:
  /// **'Скопировано'**
  String get copied;

  /// No description provided for @profileEditDisabled.
  ///
  /// In ru, this message translates to:
  /// **'Редактирование профиля отключено администратором — данные доступны только для просмотра.'**
  String get profileEditDisabled;

  /// No description provided for @personalDetailsFirstName.
  ///
  /// In ru, this message translates to:
  /// **'Имя'**
  String get personalDetailsFirstName;

  /// No description provided for @personalDetailsLastName.
  ///
  /// In ru, this message translates to:
  /// **'Фамилия'**
  String get personalDetailsLastName;

  /// No description provided for @personalDetailsUsername.
  ///
  /// In ru, this message translates to:
  /// **'Логин'**
  String get personalDetailsUsername;

  /// No description provided for @personalDetailsUsernameHint.
  ///
  /// In ru, this message translates to:
  /// **'латиница, цифры, _'**
  String get personalDetailsUsernameHint;

  /// No description provided for @personalDetailsBirthDate.
  ///
  /// In ru, this message translates to:
  /// **'Дата рождения'**
  String get personalDetailsBirthDate;

  /// No description provided for @personalDetailsSelectDate.
  ///
  /// In ru, this message translates to:
  /// **'Выбрать дату'**
  String get personalDetailsSelectDate;

  /// No description provided for @personalDetailsBio.
  ///
  /// In ru, this message translates to:
  /// **'О себе'**
  String get personalDetailsBio;

  /// No description provided for @personalDetailsBioPlaceholder.
  ///
  /// In ru, this message translates to:
  /// **'Расскажите о себе'**
  String get personalDetailsBioPlaceholder;

  /// No description provided for @personalDetailsBioCounter.
  ///
  /// In ru, this message translates to:
  /// **'{count}/150'**
  String personalDetailsBioCounter(int count);

  /// No description provided for @personalDetailsFirstNameRequired.
  ///
  /// In ru, this message translates to:
  /// **'Введите имя'**
  String get personalDetailsFirstNameRequired;

  /// No description provided for @personalDetailsLastNameRequired.
  ///
  /// In ru, this message translates to:
  /// **'Введите фамилию'**
  String get personalDetailsLastNameRequired;

  /// No description provided for @personalDetailsUsernameInvalid.
  ///
  /// In ru, this message translates to:
  /// **'Только латинские буквы, цифры и «_», от 3 до 32 символов'**
  String get personalDetailsUsernameInvalid;

  /// No description provided for @securityChangePassword.
  ///
  /// In ru, this message translates to:
  /// **'Изменить пароль'**
  String get securityChangePassword;

  /// No description provided for @securityCurrentPassword.
  ///
  /// In ru, this message translates to:
  /// **'Текущий пароль'**
  String get securityCurrentPassword;

  /// No description provided for @securityNewPassword.
  ///
  /// In ru, this message translates to:
  /// **'Новый пароль'**
  String get securityNewPassword;

  /// No description provided for @securityRepeatPassword.
  ///
  /// In ru, this message translates to:
  /// **'Повторите пароль'**
  String get securityRepeatPassword;

  /// No description provided for @securityPasswordsDontMatch.
  ///
  /// In ru, this message translates to:
  /// **'Пароли не совпадают'**
  String get securityPasswordsDontMatch;

  /// No description provided for @securityPasswordTooShort.
  ///
  /// In ru, this message translates to:
  /// **'Пароль должен содержать не менее 6 символов'**
  String get securityPasswordTooShort;

  /// No description provided for @securityPasswordChanged.
  ///
  /// In ru, this message translates to:
  /// **'Пароль изменён'**
  String get securityPasswordChanged;

  /// No description provided for @securityEmailLabel.
  ///
  /// In ru, this message translates to:
  /// **'Email'**
  String get securityEmailLabel;

  /// No description provided for @securityChangeEmail.
  ///
  /// In ru, this message translates to:
  /// **'Изменить email'**
  String get securityChangeEmail;

  /// No description provided for @securityNewEmail.
  ///
  /// In ru, this message translates to:
  /// **'Новый email'**
  String get securityNewEmail;

  /// No description provided for @securityEmailInvalid.
  ///
  /// In ru, this message translates to:
  /// **'Некорректный формат email'**
  String get securityEmailInvalid;

  /// No description provided for @securityVerificationCode.
  ///
  /// In ru, this message translates to:
  /// **'Код подтверждения'**
  String get securityVerificationCode;

  /// No description provided for @securityLinkedAccounts.
  ///
  /// In ru, this message translates to:
  /// **'Привязанные аккаунты'**
  String get securityLinkedAccounts;

  /// No description provided for @securityLinked.
  ///
  /// In ru, this message translates to:
  /// **'Привязан'**
  String get securityLinked;

  /// No description provided for @securityNotLinked.
  ///
  /// In ru, this message translates to:
  /// **'Не привязан'**
  String get securityNotLinked;

  /// No description provided for @securityLink.
  ///
  /// In ru, this message translates to:
  /// **'Привязать'**
  String get securityLink;

  /// No description provided for @securityUnlink.
  ///
  /// In ru, this message translates to:
  /// **'Отвязать'**
  String get securityUnlink;

  /// No description provided for @securityDeleteAccount.
  ///
  /// In ru, this message translates to:
  /// **'Удалить аккаунт'**
  String get securityDeleteAccount;

  /// No description provided for @securityDeleteAccountWarning.
  ///
  /// In ru, this message translates to:
  /// **'Это действие необратимо. Все ваши данные будут удалены безвозвратно.'**
  String get securityDeleteAccountWarning;

  /// No description provided for @securityDeleteAccountConfirmTitle.
  ///
  /// In ru, this message translates to:
  /// **'Вы уверены?'**
  String get securityDeleteAccountConfirmTitle;

  /// No description provided for @securityDeleteAccountConfirmBody.
  ///
  /// In ru, this message translates to:
  /// **'Введите «УДАЛИТЬ», чтобы подтвердить окончательное удаление аккаунта.'**
  String get securityDeleteAccountConfirmBody;

  /// No description provided for @securityDeleteConfirmationWord.
  ///
  /// In ru, this message translates to:
  /// **'УДАЛИТЬ'**
  String get securityDeleteConfirmationWord;

  /// No description provided for @securityDeleteAccountAction.
  ///
  /// In ru, this message translates to:
  /// **'Удалить окончательно'**
  String get securityDeleteAccountAction;

  /// No description provided for @avatarTakePhoto.
  ///
  /// In ru, this message translates to:
  /// **'Сделать фото'**
  String get avatarTakePhoto;

  /// No description provided for @avatarChooseFromGallery.
  ///
  /// In ru, this message translates to:
  /// **'Выбрать из галереи'**
  String get avatarChooseFromGallery;

  /// No description provided for @avatarRemovePhoto.
  ///
  /// In ru, this message translates to:
  /// **'Удалить фото'**
  String get avatarRemovePhoto;

  /// No description provided for @qrCardTitle.
  ///
  /// In ru, this message translates to:
  /// **'Моя карточка'**
  String get qrCardTitle;

  /// No description provided for @qrCardLevel.
  ///
  /// In ru, this message translates to:
  /// **'Уровень'**
  String get qrCardLevel;

  /// No description provided for @qrCardGoal.
  ///
  /// In ru, this message translates to:
  /// **'до {level} — {percent}%'**
  String qrCardGoal(String level, int percent);

  /// No description provided for @qrCardMaxLevel.
  ///
  /// In ru, this message translates to:
  /// **'Максимальный уровень'**
  String get qrCardMaxLevel;

  /// No description provided for @qrCardStreakLabel.
  ///
  /// In ru, this message translates to:
  /// **'дней подряд'**
  String get qrCardStreakLabel;

  /// No description provided for @qrCardRankLabel.
  ///
  /// In ru, this message translates to:
  /// **'в мире'**
  String get qrCardRankLabel;

  /// No description provided for @qrCardFollowersLabel.
  ///
  /// In ru, this message translates to:
  /// **'подписчиков'**
  String get qrCardFollowersLabel;

  /// No description provided for @qrCardSlogan.
  ///
  /// In ru, this message translates to:
  /// **'Your language · Your path · Your future'**
  String get qrCardSlogan;

  /// No description provided for @qrCardShare.
  ///
  /// In ru, this message translates to:
  /// **'Поделиться'**
  String get qrCardShare;

  /// No description provided for @qrCardCopyId.
  ///
  /// In ru, this message translates to:
  /// **'Скопировать ID'**
  String get qrCardCopyId;

  /// No description provided for @qrCardIdCopied.
  ///
  /// In ru, this message translates to:
  /// **'ID скопирован'**
  String get qrCardIdCopied;

  /// No description provided for @qrCardGenerating.
  ///
  /// In ru, this message translates to:
  /// **'Создаём карточку…'**
  String get qrCardGenerating;

  /// No description provided for @qrCardShareFailed.
  ///
  /// In ru, this message translates to:
  /// **'Не удалось поделиться карточкой'**
  String get qrCardShareFailed;

  /// No description provided for @errorServerTimeout.
  ///
  /// In ru, this message translates to:
  /// **'Сервер не отвечает (превышено время ожидания). Проверьте интернет-соединение.'**
  String get errorServerTimeout;

  /// No description provided for @errorConnectionFailed.
  ///
  /// In ru, this message translates to:
  /// **'Нет соединения с сервером. Проверьте интернет и адрес сервера.'**
  String get errorConnectionFailed;

  /// No description provided for @errorSslCertificate.
  ///
  /// In ru, this message translates to:
  /// **'Ошибка проверки сертификата сервера (SSL).'**
  String get errorSslCertificate;

  /// No description provided for @errorRequestCancelled.
  ///
  /// In ru, this message translates to:
  /// **'Запрос отменён.'**
  String get errorRequestCancelled;

  /// No description provided for @errorUnknownNetwork.
  ///
  /// In ru, this message translates to:
  /// **'Неизвестная ошибка сети'**
  String get errorUnknownNetwork;

  /// No description provided for @errorServerError.
  ///
  /// In ru, this message translates to:
  /// **'Ошибка сервера. Попробуйте позже.'**
  String get errorServerError;

  /// No description provided for @errorNetworkGeneric.
  ///
  /// In ru, this message translates to:
  /// **'Ошибка сети'**
  String get errorNetworkGeneric;

  /// No description provided for @wordAudioTooltip.
  ///
  /// In ru, this message translates to:
  /// **'Прослушать произношение'**
  String get wordAudioTooltip;

  /// No description provided for @lessonStatusCompleted.
  ///
  /// In ru, this message translates to:
  /// **'✓ Урок завершён'**
  String get lessonStatusCompleted;

  /// No description provided for @lessonStatusContinue.
  ///
  /// In ru, this message translates to:
  /// **'Продолжить'**
  String get lessonStatusContinue;

  /// No description provided for @lessonStatusStart.
  ///
  /// In ru, this message translates to:
  /// **'Начать урок'**
  String get lessonStatusStart;

  /// No description provided for @myWordsTitle.
  ///
  /// In ru, this message translates to:
  /// **'Мои слова'**
  String get myWordsTitle;

  /// No description provided for @myWordsLoadError.
  ///
  /// In ru, this message translates to:
  /// **'Не удалось загрузить слова: {error}'**
  String myWordsLoadError(Object error);

  /// No description provided for @myWordsEmpty.
  ///
  /// In ru, this message translates to:
  /// **'Пока нет изученных слов — они появятся здесь после завершения уроков.'**
  String get myWordsEmpty;

  /// No description provided for @myWordsUncategorized.
  ///
  /// In ru, this message translates to:
  /// **'Без категории'**
  String get myWordsUncategorized;

  /// No description provided for @leaderboardTitle.
  ///
  /// In ru, this message translates to:
  /// **'Рейтинг'**
  String get leaderboardTitle;

  /// No description provided for @leaderboardSearchHint.
  ///
  /// In ru, this message translates to:
  /// **'Найти по нику или ID'**
  String get leaderboardSearchHint;

  /// No description provided for @leaderboardLoadError.
  ///
  /// In ru, this message translates to:
  /// **'Не удалось загрузить рейтинг: {error}'**
  String leaderboardLoadError(Object error);

  /// No description provided for @leaderboardEmpty.
  ///
  /// In ru, this message translates to:
  /// **'Пока нет участников рейтинга'**
  String get leaderboardEmpty;

  /// No description provided for @leaderboardSearchError.
  ///
  /// In ru, this message translates to:
  /// **'Не удалось выполнить поиск: {error}'**
  String leaderboardSearchError(Object error);

  /// No description provided for @leaderboardUserNotFound.
  ///
  /// In ru, this message translates to:
  /// **'Пользователь не найден'**
  String get leaderboardUserNotFound;

  /// No description provided for @authTagline.
  ///
  /// In ru, this message translates to:
  /// **'Войдите, чтобы продолжить обучение'**
  String get authTagline;

  /// No description provided for @authLoginOrEmail.
  ///
  /// In ru, this message translates to:
  /// **'Логин или email'**
  String get authLoginOrEmail;

  /// No description provided for @authLoginRequired.
  ///
  /// In ru, this message translates to:
  /// **'Введите логин'**
  String get authLoginRequired;

  /// No description provided for @authPasswordLabel.
  ///
  /// In ru, this message translates to:
  /// **'Пароль'**
  String get authPasswordLabel;

  /// No description provided for @authPasswordRequired.
  ///
  /// In ru, this message translates to:
  /// **'Введите пароль'**
  String get authPasswordRequired;

  /// No description provided for @authSignIn.
  ///
  /// In ru, this message translates to:
  /// **'Войти'**
  String get authSignIn;

  /// No description provided for @authSignInFailedDebug.
  ///
  /// In ru, this message translates to:
  /// **'Не удалось войти: {error}'**
  String authSignInFailedDebug(Object error);

  /// No description provided for @authSignInFailed.
  ///
  /// In ru, this message translates to:
  /// **'Не удалось войти в аккаунт'**
  String get authSignInFailed;

  /// No description provided for @forbiddenTitle.
  ///
  /// In ru, this message translates to:
  /// **'Доступ запрещён'**
  String get forbiddenTitle;

  /// No description provided for @forbiddenBodyTeacher.
  ///
  /// In ru, this message translates to:
  /// **'Этот раздел доступен только администраторам.'**
  String get forbiddenBodyTeacher;

  /// No description provided for @forbiddenBodyDefault.
  ///
  /// In ru, this message translates to:
  /// **'У вас нет доступа к этой странице.'**
  String get forbiddenBodyDefault;

  /// No description provided for @forbiddenGoHome.
  ///
  /// In ru, this message translates to:
  /// **'На главную'**
  String get forbiddenGoHome;

  /// No description provided for @homeExitConfirmation.
  ///
  /// In ru, this message translates to:
  /// **'Нажмите ещё раз для выхода'**
  String get homeExitConfirmation;

  /// No description provided for @homeLanguagePickerTitle.
  ///
  /// In ru, this message translates to:
  /// **'Язык'**
  String get homeLanguagePickerTitle;

  /// No description provided for @homeThemeLight.
  ///
  /// In ru, this message translates to:
  /// **'Светлая тема'**
  String get homeThemeLight;

  /// No description provided for @homeThemeDark.
  ///
  /// In ru, this message translates to:
  /// **'Тёмная тема'**
  String get homeThemeDark;

  /// No description provided for @homeLanguagesLoadError.
  ///
  /// In ru, this message translates to:
  /// **'Не удалось загрузить языки: {error}'**
  String homeLanguagesLoadError(Object error);

  /// No description provided for @homeNoCourses.
  ///
  /// In ru, this message translates to:
  /// **'Курсы пока не опубликованы'**
  String get homeNoCourses;

  /// No description provided for @homeGreeting.
  ///
  /// In ru, this message translates to:
  /// **'Привет, {name}!'**
  String homeGreeting(String name);

  /// No description provided for @homeLessonsLoadError.
  ///
  /// In ru, this message translates to:
  /// **'Не удалось загрузить уроки: {error}'**
  String homeLessonsLoadError(Object error);

  /// No description provided for @homeNoLessons.
  ///
  /// In ru, this message translates to:
  /// **'Уроков пока нет'**
  String get homeNoLessons;

  /// No description provided for @lessonDownloadTitle.
  ///
  /// In ru, this message translates to:
  /// **'Загружаем фото слов'**
  String get lessonDownloadTitle;

  /// No description provided for @lessonDownloadSubtitle.
  ///
  /// In ru, this message translates to:
  /// **'Один раз — дальше урок открывается мгновенно и работает без интернета.'**
  String get lessonDownloadSubtitle;

  /// No description provided for @lessonDownloadProgress.
  ///
  /// In ru, this message translates to:
  /// **'{done} из {total}'**
  String lessonDownloadProgress(int done, int total);

  /// No description provided for @socialFollowers.
  ///
  /// In ru, this message translates to:
  /// **'Подписчики'**
  String get socialFollowers;

  /// No description provided for @socialFollowing.
  ///
  /// In ru, this message translates to:
  /// **'Подписки'**
  String get socialFollowing;

  /// No description provided for @socialMutual.
  ///
  /// In ru, this message translates to:
  /// **'Взаимные'**
  String get socialMutual;

  /// No description provided for @socialListLoadError.
  ///
  /// In ru, this message translates to:
  /// **'Не удалось загрузить список: {error}'**
  String socialListLoadError(Object error);

  /// No description provided for @socialListEmpty.
  ///
  /// In ru, this message translates to:
  /// **'Пока пусто'**
  String get socialListEmpty;

  /// No description provided for @socialThisIsYourProfile.
  ///
  /// In ru, this message translates to:
  /// **'Это ваш профиль'**
  String get socialThisIsYourProfile;

  /// No description provided for @socialProfileTitle.
  ///
  /// In ru, this message translates to:
  /// **'Профиль'**
  String get socialProfileTitle;

  /// No description provided for @socialProfileLoadError.
  ///
  /// In ru, this message translates to:
  /// **'Не удалось загрузить профиль: {error}'**
  String socialProfileLoadError(Object error);

  /// No description provided for @socialStatsLoadError.
  ///
  /// In ru, this message translates to:
  /// **'Не удалось загрузить статистику: {error}'**
  String socialStatsLoadError(Object error);

  /// No description provided for @socialUnfollowError.
  ///
  /// In ru, this message translates to:
  /// **'Не удалось отписаться: {error}'**
  String socialUnfollowError(Object error);

  /// No description provided for @socialFollowError.
  ///
  /// In ru, this message translates to:
  /// **'Не удалось подписаться: {error}'**
  String socialFollowError(Object error);

  /// No description provided for @socialUnfollowing.
  ///
  /// In ru, this message translates to:
  /// **'Отписываемся…'**
  String get socialUnfollowing;

  /// No description provided for @socialUnfollow.
  ///
  /// In ru, this message translates to:
  /// **'Отписаться'**
  String get socialUnfollow;

  /// No description provided for @socialFollowingInProgress.
  ///
  /// In ru, this message translates to:
  /// **'Подписываемся…'**
  String get socialFollowingInProgress;

  /// No description provided for @socialFollow.
  ///
  /// In ru, this message translates to:
  /// **'Подписаться'**
  String get socialFollow;

  /// No description provided for @gamificationLevelHint.
  ///
  /// In ru, this message translates to:
  /// **'Вы близки к следующему уровню!'**
  String get gamificationLevelHint;

  /// No description provided for @gamificationAchievementFirstLessonTitle.
  ///
  /// In ru, this message translates to:
  /// **'Первый урок'**
  String get gamificationAchievementFirstLessonTitle;

  /// No description provided for @gamificationAchievementDone.
  ///
  /// In ru, this message translates to:
  /// **'Пройден'**
  String get gamificationAchievementDone;

  /// No description provided for @gamificationAchievementWeekTitle.
  ///
  /// In ru, this message translates to:
  /// **'Неделя 7 дней'**
  String get gamificationAchievementWeekTitle;

  /// No description provided for @gamificationAchievementGoalTitle.
  ///
  /// In ru, this message translates to:
  /// **'Цель 10 уроков'**
  String get gamificationAchievementGoalTitle;

  /// No description provided for @gamificationAchievementActiveTitle.
  ///
  /// In ru, this message translates to:
  /// **'Активный ученик'**
  String get gamificationAchievementActiveTitle;

  /// No description provided for @gamificationAchievementLessons10.
  ///
  /// In ru, this message translates to:
  /// **'10 уроков'**
  String get gamificationAchievementLessons10;

  /// No description provided for @gamificationAchievementWordMasterTitle.
  ///
  /// In ru, this message translates to:
  /// **'Мастер слов'**
  String get gamificationAchievementWordMasterTitle;

  /// No description provided for @gamificationAchievementLocked.
  ///
  /// In ru, this message translates to:
  /// **'Заблокировано'**
  String get gamificationAchievementLocked;

  /// No description provided for @gamificationRankPeriodWeek.
  ///
  /// In ru, this message translates to:
  /// **'По неделе'**
  String get gamificationRankPeriodWeek;

  /// No description provided for @gamificationLearningLanguageEnglish.
  ///
  /// In ru, this message translates to:
  /// **'английский'**
  String get gamificationLearningLanguageEnglish;

  /// No description provided for @profileFollowStatsLoadError.
  ///
  /// In ru, this message translates to:
  /// **'Не удалось загрузить подписки: {error}'**
  String profileFollowStatsLoadError(Object error);

  /// No description provided for @profileProgressLoadError.
  ///
  /// In ru, this message translates to:
  /// **'Не удалось загрузить прогресс: {error}'**
  String profileProgressLoadError(Object error);

  /// No description provided for @profileAchievementsTitle.
  ///
  /// In ru, this message translates to:
  /// **'Достижения'**
  String get profileAchievementsTitle;

  /// No description provided for @profileRankLoadError.
  ///
  /// In ru, this message translates to:
  /// **'Не удалось загрузить рейтинг: {error}'**
  String profileRankLoadError(Object error);

  /// No description provided for @profileActivityLoadError.
  ///
  /// In ru, this message translates to:
  /// **'Не удалось загрузить активность: {error}'**
  String profileActivityLoadError(Object error);

  /// No description provided for @profileShareTooltip.
  ///
  /// In ru, this message translates to:
  /// **'Поделиться профилем'**
  String get profileShareTooltip;

  /// No description provided for @profileSeeAll.
  ///
  /// In ru, this message translates to:
  /// **'Все'**
  String get profileSeeAll;

  /// No description provided for @avatarOnline.
  ///
  /// In ru, this message translates to:
  /// **'в сети'**
  String get avatarOnline;

  /// No description provided for @avatarOffline.
  ///
  /// In ru, this message translates to:
  /// **'не в сети'**
  String get avatarOffline;

  /// No description provided for @levelCardTitle.
  ///
  /// In ru, this message translates to:
  /// **'Ваш уровень'**
  String get levelCardTitle;

  /// No description provided for @metricsStreak.
  ///
  /// In ru, this message translates to:
  /// **'Серия'**
  String get metricsStreak;

  /// No description provided for @metricsProgress.
  ///
  /// In ru, this message translates to:
  /// **'Прогресс'**
  String get metricsProgress;

  /// No description provided for @metricsTime.
  ///
  /// In ru, this message translates to:
  /// **'Время'**
  String get metricsTime;

  /// No description provided for @metricsPoints.
  ///
  /// In ru, this message translates to:
  /// **'Очки'**
  String get metricsPoints;

  /// No description provided for @rankCardTitle.
  ///
  /// In ru, this message translates to:
  /// **'Ваш рейтинг'**
  String get rankCardTitle;

  /// No description provided for @rankTop.
  ///
  /// In ru, this message translates to:
  /// **'Топ {percent}%'**
  String rankTop(int percent);

  /// No description provided for @rankGlobal.
  ///
  /// In ru, this message translates to:
  /// **'Глобально'**
  String get rankGlobal;

  /// No description provided for @rankOutOf.
  ///
  /// In ru, this message translates to:
  /// **'из {total}'**
  String rankOutOf(int total);

  /// No description provided for @rankAmongAllStudents.
  ///
  /// In ru, this message translates to:
  /// **'Среди всех студентов'**
  String get rankAmongAllStudents;

  /// No description provided for @weekActivityDayMon.
  ///
  /// In ru, this message translates to:
  /// **'Пн'**
  String get weekActivityDayMon;

  /// No description provided for @weekActivityDayTue.
  ///
  /// In ru, this message translates to:
  /// **'Вт'**
  String get weekActivityDayTue;

  /// No description provided for @weekActivityDayWed.
  ///
  /// In ru, this message translates to:
  /// **'Ср'**
  String get weekActivityDayWed;

  /// No description provided for @weekActivityDayThu.
  ///
  /// In ru, this message translates to:
  /// **'Чт'**
  String get weekActivityDayThu;

  /// No description provided for @weekActivityDayFri.
  ///
  /// In ru, this message translates to:
  /// **'Пт'**
  String get weekActivityDayFri;

  /// No description provided for @weekActivityDaySat.
  ///
  /// In ru, this message translates to:
  /// **'Сб'**
  String get weekActivityDaySat;

  /// No description provided for @weekActivityDaySun.
  ///
  /// In ru, this message translates to:
  /// **'Вс'**
  String get weekActivityDaySun;

  /// No description provided for @weekActivityTitle.
  ///
  /// In ru, this message translates to:
  /// **'Активность за неделю'**
  String get weekActivityTitle;

  /// No description provided for @weekActivityAverage.
  ///
  /// In ru, this message translates to:
  /// **'Средняя активность'**
  String get weekActivityAverage;

  /// No description provided for @gamificationLevelNameIntermediate.
  ///
  /// In ru, this message translates to:
  /// **'Средний'**
  String get gamificationLevelNameIntermediate;

  /// No description provided for @metricsTimeFormat.
  ///
  /// In ru, this message translates to:
  /// **'{hours}ч {minutes}м'**
  String metricsTimeFormat(int hours, int minutes);

  /// No description provided for @weekActivityAvgPerDay.
  ///
  /// In ru, this message translates to:
  /// **'{minutes}м/день'**
  String weekActivityAvgPerDay(int minutes);

  /// No description provided for @stageVocabulary.
  ///
  /// In ru, this message translates to:
  /// **'Слова'**
  String get stageVocabulary;

  /// No description provided for @stageMaterial.
  ///
  /// In ru, this message translates to:
  /// **'Материал'**
  String get stageMaterial;

  /// No description provided for @stageVideo.
  ///
  /// In ru, this message translates to:
  /// **'Видео'**
  String get stageVideo;

  /// No description provided for @stageMinitest.
  ///
  /// In ru, this message translates to:
  /// **'Мини-тест'**
  String get stageMinitest;

  /// No description provided for @stageAudio.
  ///
  /// In ru, this message translates to:
  /// **'Аудио'**
  String get stageAudio;

  /// No description provided for @stagePractice.
  ///
  /// In ru, this message translates to:
  /// **'Практика'**
  String get stagePractice;

  /// No description provided for @stageReview.
  ///
  /// In ru, this message translates to:
  /// **'Закрепление'**
  String get stageReview;

  /// No description provided for @stageComplete.
  ///
  /// In ru, this message translates to:
  /// **'Итог'**
  String get stageComplete;

  /// No description provided for @lessonTitle.
  ///
  /// In ru, this message translates to:
  /// **'Урок'**
  String get lessonTitle;

  /// No description provided for @lessonLoadError.
  ///
  /// In ru, this message translates to:
  /// **'Не удалось загрузить урок: {error}'**
  String lessonLoadError(Object error);

  /// No description provided for @lessonUnknownBlockType.
  ///
  /// In ru, this message translates to:
  /// **'Неизвестный тип блока: {type}'**
  String lessonUnknownBlockType(String type);

  /// No description provided for @lessonFinish.
  ///
  /// In ru, this message translates to:
  /// **'Завершить урок'**
  String get lessonFinish;

  /// No description provided for @lessonNext.
  ///
  /// In ru, this message translates to:
  /// **'Далее: {title} →'**
  String lessonNext(String title);

  /// No description provided for @lessonCompleteTitle.
  ///
  /// In ru, this message translates to:
  /// **'Отличная работа!'**
  String get lessonCompleteTitle;

  /// No description provided for @lessonCompleteSubtitleGraph.
  ///
  /// In ru, this message translates to:
  /// **'Вы прошли урок «{title}». Вот ваши результаты:'**
  String lessonCompleteSubtitleGraph(String title);

  /// No description provided for @lessonCompleteSubtitleLinear.
  ///
  /// In ru, this message translates to:
  /// **'Вы прошли все этапы урока «{title}». Вот ваши результаты:'**
  String lessonCompleteSubtitleLinear(String title);

  /// No description provided for @lessonCompleteWordsLearned.
  ///
  /// In ru, this message translates to:
  /// **'слов изучено'**
  String get lessonCompleteWordsLearned;

  /// No description provided for @lessonCompleteRestarting.
  ///
  /// In ru, this message translates to:
  /// **'Начинаем…'**
  String get lessonCompleteRestarting;

  /// No description provided for @lessonCompleteRestart.
  ///
  /// In ru, this message translates to:
  /// **'Пройти ещё раз'**
  String get lessonCompleteRestart;

  /// No description provided for @lessonCompleteMinitestLabel.
  ///
  /// In ru, this message translates to:
  /// **'мини-тест'**
  String get lessonCompleteMinitestLabel;

  /// No description provided for @lessonCompletePracticeLabel.
  ///
  /// In ru, this message translates to:
  /// **'практика'**
  String get lessonCompletePracticeLabel;

  /// No description provided for @lessonCompleteReviewLabel.
  ///
  /// In ru, this message translates to:
  /// **'закрепление'**
  String get lessonCompleteReviewLabel;

  /// No description provided for @vocabularyStageEmpty.
  ///
  /// In ru, this message translates to:
  /// **'В этом уроке нет новых слов — все они уже встречались раньше.'**
  String get vocabularyStageEmpty;

  /// No description provided for @commonNext.
  ///
  /// In ru, this message translates to:
  /// **'Далее'**
  String get commonNext;

  /// No description provided for @lessonStageSkip.
  ///
  /// In ru, this message translates to:
  /// **'Пропустить и продолжить'**
  String get lessonStageSkip;

  /// No description provided for @materialStageStepTitle.
  ///
  /// In ru, this message translates to:
  /// **'Шаг {number}. {title}'**
  String materialStageStepTitle(int number, String title);

  /// No description provided for @materialStageMissing.
  ///
  /// In ru, this message translates to:
  /// **'Не хватает материала'**
  String get materialStageMissing;

  /// No description provided for @materialStageNotFound.
  ///
  /// In ru, this message translates to:
  /// **'Текст урока не найден.'**
  String get materialStageNotFound;

  /// No description provided for @materialStageSection.
  ///
  /// In ru, this message translates to:
  /// **'Раздел {page} из {total}'**
  String materialStageSection(int page, int total);

  /// No description provided for @materialStageDefaultNextVideo.
  ///
  /// In ru, this message translates to:
  /// **'Перейти к видео'**
  String get materialStageDefaultNextVideo;

  /// No description provided for @materialStageNextArrow.
  ///
  /// In ru, this message translates to:
  /// **'Далее →'**
  String get materialStageNextArrow;

  /// No description provided for @materialStageBack.
  ///
  /// In ru, this message translates to:
  /// **'← Назад'**
  String get materialStageBack;

  /// No description provided for @videoStageNotFound.
  ///
  /// In ru, this message translates to:
  /// **'Видео не найдено'**
  String get videoStageNotFound;

  /// No description provided for @videoStageNotUploaded.
  ///
  /// In ru, this message translates to:
  /// **'Для этого урока не загружено видео.'**
  String get videoStageNotUploaded;

  /// No description provided for @videoStageWatch.
  ///
  /// In ru, this message translates to:
  /// **'Посмотрите видео'**
  String get videoStageWatch;

  /// No description provided for @videoStageWatched.
  ///
  /// In ru, this message translates to:
  /// **'✓ Видео просмотрено'**
  String get videoStageWatched;

  /// No description provided for @videoStageWatchToContinue.
  ///
  /// In ru, this message translates to:
  /// **'Досмотрите видео до конца, чтобы продолжить'**
  String get videoStageWatchToContinue;

  /// No description provided for @videoStageDefaultNextMinitest.
  ///
  /// In ru, this message translates to:
  /// **'Перейти к мини-тесту →'**
  String get videoStageDefaultNextMinitest;

  /// No description provided for @audioStageLoadError.
  ///
  /// In ru, this message translates to:
  /// **'Не удалось загрузить аудиофайл. Проверьте, что файл существует и доступен, и попробуйте ещё раз.'**
  String get audioStageLoadError;

  /// No description provided for @audioStagePlaybackError.
  ///
  /// In ru, this message translates to:
  /// **'Не удалось запустить воспроизведение аудио. Проверьте, не отключён звук, и попробуйте ещё раз.'**
  String get audioStagePlaybackError;

  /// No description provided for @audioStageNotFound.
  ///
  /// In ru, this message translates to:
  /// **'Аудио не найдено'**
  String get audioStageNotFound;

  /// No description provided for @audioStageNotUploaded.
  ///
  /// In ru, this message translates to:
  /// **'Для этого урока не загружена аудиозапись.'**
  String get audioStageNotUploaded;

  /// No description provided for @audioStageListen.
  ///
  /// In ru, this message translates to:
  /// **'Прослушайте аудио'**
  String get audioStageListen;

  /// No description provided for @audioStageListenHint.
  ///
  /// In ru, this message translates to:
  /// **'Послушайте запись и закрепите произношение фраз из урока.'**
  String get audioStageListenHint;

  /// No description provided for @audioStageFinished.
  ///
  /// In ru, this message translates to:
  /// **'✓ Запись прослушана'**
  String get audioStageFinished;

  /// No description provided for @audioStageListenToContinue.
  ///
  /// In ru, this message translates to:
  /// **'Прослушайте запись до конца, чтобы продолжить'**
  String get audioStageListenToContinue;

  /// No description provided for @audioStageDefaultNextPractice.
  ///
  /// In ru, this message translates to:
  /// **'Перейти к практике →'**
  String get audioStageDefaultNextPractice;

  /// No description provided for @exerciseKindChoice.
  ///
  /// In ru, this message translates to:
  /// **'Выбор ответа'**
  String get exerciseKindChoice;

  /// No description provided for @exerciseKindTrueFalse.
  ///
  /// In ru, this message translates to:
  /// **'Верно или неверно'**
  String get exerciseKindTrueFalse;

  /// No description provided for @exerciseKindMatch.
  ///
  /// In ru, this message translates to:
  /// **'Сопоставление'**
  String get exerciseKindMatch;

  /// No description provided for @exerciseKindScramble.
  ///
  /// In ru, this message translates to:
  /// **'Собери фразу'**
  String get exerciseKindScramble;

  /// No description provided for @exerciseKindCloze.
  ///
  /// In ru, this message translates to:
  /// **'Заполни пропуск'**
  String get exerciseKindCloze;

  /// No description provided for @exerciseKindAutoBlank.
  ///
  /// In ru, this message translates to:
  /// **'Пропущенное слово'**
  String get exerciseKindAutoBlank;

  /// No description provided for @exerciseKindAutoTranslate.
  ///
  /// In ru, this message translates to:
  /// **'Переведи слово'**
  String get exerciseKindAutoTranslate;

  /// No description provided for @exercisePromptMatch.
  ///
  /// In ru, this message translates to:
  /// **'Сопоставление слов и переводов'**
  String get exercisePromptMatch;

  /// No description provided for @exercisePromptScramble.
  ///
  /// In ru, this message translates to:
  /// **'Фраза по переводу «{translation}»'**
  String exercisePromptScramble(String translation);

  /// No description provided for @exercisePromptCloze.
  ///
  /// In ru, this message translates to:
  /// **'Пропуск во фразе «{translation}»'**
  String exercisePromptCloze(String translation);

  /// No description provided for @exerciseCorrectAnswer.
  ///
  /// In ru, this message translates to:
  /// **'Правильный ответ: «{answer}»'**
  String exerciseCorrectAnswer(String answer);

  /// No description provided for @exerciseNotAllPairsMatched.
  ///
  /// In ru, this message translates to:
  /// **'Не все пары были сопоставлены с первой попытки'**
  String get exerciseNotAllPairsMatched;

  /// No description provided for @exerciseCorrectScramble.
  ///
  /// In ru, this message translates to:
  /// **'Правильно: «{answer}»'**
  String exerciseCorrectScramble(String answer);

  /// No description provided for @exerciseCorrectWord.
  ///
  /// In ru, this message translates to:
  /// **'Правильное слово: «{answer}»'**
  String exerciseCorrectWord(String answer);

  /// No description provided for @exerciseDetailsInHistory.
  ///
  /// In ru, this message translates to:
  /// **'Подробности — в истории ответов'**
  String get exerciseDetailsInHistory;

  /// No description provided for @exerciseStageNotEnoughMaterial.
  ///
  /// In ru, this message translates to:
  /// **'Недостаточно материала для этого блока — переходим дальше.'**
  String get exerciseStageNotEnoughMaterial;

  /// No description provided for @exerciseStageProgress.
  ///
  /// In ru, this message translates to:
  /// **'Задание {index} из {total}'**
  String exerciseStageProgress(int index, int total);

  /// No description provided for @exerciseStageCorrectCount.
  ///
  /// In ru, this message translates to:
  /// **'{count} правильно'**
  String exerciseStageCorrectCount(int count);

  /// No description provided for @exerciseStageNextEnter.
  ///
  /// In ru, this message translates to:
  /// **'Следующее (Enter)'**
  String get exerciseStageNextEnter;

  /// No description provided for @exerciseStageFinishEnter.
  ///
  /// In ru, this message translates to:
  /// **'Завершить (Enter)'**
  String get exerciseStageFinishEnter;

  /// No description provided for @exerciseStageResultTitle.
  ///
  /// In ru, this message translates to:
  /// **'Результат'**
  String get exerciseStageResultTitle;

  /// No description provided for @exerciseStageAllCorrect.
  ///
  /// In ru, this message translates to:
  /// **'Отлично, всё верно!'**
  String get exerciseStageAllCorrect;

  /// No description provided for @exerciseStageGoodResult.
  ///
  /// In ru, this message translates to:
  /// **'Хороший результат. Разберём ошибки ниже.'**
  String get exerciseStageGoodResult;

  /// No description provided for @exerciseStageContinueEnter.
  ///
  /// In ru, this message translates to:
  /// **'Продолжить (Enter)'**
  String get exerciseStageContinueEnter;

  /// No description provided for @homeMapWordCount.
  ///
  /// In ru, this message translates to:
  /// **'{count} слов'**
  String homeMapWordCount(int count);

  /// No description provided for @homeMapLockedSnack.
  ///
  /// In ru, this message translates to:
  /// **'Завершите предыдущий урок'**
  String get homeMapLockedSnack;

  /// No description provided for @leaderboardPeriodDay.
  ///
  /// In ru, this message translates to:
  /// **'День'**
  String get leaderboardPeriodDay;

  /// No description provided for @leaderboardPeriodWeek.
  ///
  /// In ru, this message translates to:
  /// **'Неделя'**
  String get leaderboardPeriodWeek;

  /// No description provided for @leaderboardPeriodMonth.
  ///
  /// In ru, this message translates to:
  /// **'Месяц'**
  String get leaderboardPeriodMonth;

  /// No description provided for @leaderboardPeriodAllTime.
  ///
  /// In ru, this message translates to:
  /// **'Всё время'**
  String get leaderboardPeriodAllTime;

  /// No description provided for @leaderboardColumnRank.
  ///
  /// In ru, this message translates to:
  /// **'Место'**
  String get leaderboardColumnRank;

  /// No description provided for @leaderboardColumnStudent.
  ///
  /// In ru, this message translates to:
  /// **'Ученик'**
  String get leaderboardColumnStudent;

  /// No description provided for @leaderboardColumnPoints.
  ///
  /// In ru, this message translates to:
  /// **'Очки'**
  String get leaderboardColumnPoints;

  /// No description provided for @leaderboardGoalToPlace.
  ///
  /// In ru, this message translates to:
  /// **'До {rank} места — {points} очков'**
  String leaderboardGoalToPlace(int rank, int points);

  /// No description provided for @leaderboardGoalBeatName.
  ///
  /// In ru, this message translates to:
  /// **'Один урок, и ты обгонишь {name}'**
  String leaderboardGoalBeatName(String name);

  /// No description provided for @leaderboardGoalTop.
  ///
  /// In ru, this message translates to:
  /// **'Ты на вершине. Удержи позицию'**
  String get leaderboardGoalTop;

  /// No description provided for @leaderboardThisIsYou.
  ///
  /// In ru, this message translates to:
  /// **'Это ты'**
  String get leaderboardThisIsYou;

  /// No description provided for @leaderboardSearchTooltip.
  ///
  /// In ru, this message translates to:
  /// **'Поиск'**
  String get leaderboardSearchTooltip;

  /// No description provided for @leaderboardInfoTooltip.
  ///
  /// In ru, this message translates to:
  /// **'Как начисляются очки'**
  String get leaderboardInfoTooltip;

  /// No description provided for @leaderboardInfoTitle.
  ///
  /// In ru, this message translates to:
  /// **'Как начисляются очки'**
  String get leaderboardInfoTitle;

  /// No description provided for @leaderboardInfoBody.
  ///
  /// In ru, this message translates to:
  /// **'10 очков за каждый правильно отвеченный вопрос и 50 очков за завершённый урок.'**
  String get leaderboardInfoBody;

  /// No description provided for @leaderboardRetry.
  ///
  /// In ru, this message translates to:
  /// **'Повторить'**
  String get leaderboardRetry;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['ru', 'tg'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'ru':
      return AppLocalizationsRu();
    case 'tg':
      return AppLocalizationsTg();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
