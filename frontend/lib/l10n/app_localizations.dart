import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_ru.dart';

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
    Locale('en'),
    Locale('ru'),
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

  /// No description provided for @courseLanguage.
  ///
  /// In ru, this message translates to:
  /// **'Язык курса'**
  String get courseLanguage;

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
      <String>['en', 'ru'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'ru':
      return AppLocalizationsRu();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
