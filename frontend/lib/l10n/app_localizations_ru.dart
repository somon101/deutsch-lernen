// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Russian (`ru`).
class AppLocalizationsRu extends AppLocalizations {
  AppLocalizationsRu([String locale = 'ru']) : super(locale);

  @override
  String get settingsTitle => 'Настройки';

  @override
  String get sectionAccount => 'Аккаунт';

  @override
  String get personalDetails => 'Персональные данные';

  @override
  String get securityPrivacy => 'Безопасность и конфиденциальность';

  @override
  String get sectionLearning => 'Обучение';

  @override
  String get dailyGoal => 'Цель в день';

  @override
  String dailyGoalMinutes(int minutes) {
    return '$minutes мин';
  }

  @override
  String get languageLevel => 'Уровень языка';

  @override
  String get lessonSounds => 'Звуки в уроках';

  @override
  String get wordPronunciation => 'Озвучка слов';

  @override
  String get sectionNotifications => 'Уведомления';

  @override
  String get pushNotifications => 'Push-уведомления';

  @override
  String get lessonReminder => 'Напоминание о занятии';

  @override
  String get reminderTime => 'Время напоминания';

  @override
  String get streakReminder => 'Напоминание о серии дней';

  @override
  String get sectionLanguageAppearance => 'Язык и внешний вид';

  @override
  String get appLanguage => 'Язык программы';

  @override
  String get courseLanguage => 'Язык курса';

  @override
  String get theme => 'Тема';

  @override
  String get themeDark => 'Тёмная';

  @override
  String get themeLight => 'Светлая';

  @override
  String get themeSystem => 'Как в системе';

  @override
  String get sectionSupport => 'Поддержка';

  @override
  String get helpFaq => 'Помощь и FAQ';

  @override
  String get contactUs => 'Связаться с нами';

  @override
  String get aboutApp => 'О приложении';

  @override
  String appVersion(String version) {
    return 'Версия $version';
  }

  @override
  String get logout => 'Выйти из аккаунта';

  @override
  String get logoutConfirmTitle => 'Выйти из аккаунта?';

  @override
  String get logoutConfirmBody => 'Вы сможете снова войти в любой момент.';

  @override
  String get cancel => 'Отмена';

  @override
  String get comingSoon => 'Скоро';

  @override
  String get chooseOption => 'Выберите вариант';

  @override
  String get back => 'Назад';

  @override
  String get save => 'Сохранить';

  @override
  String get saved => 'Профиль сохранён';

  @override
  String get copy => 'Скопировать';

  @override
  String get copied => 'Скопировано';

  @override
  String get profileEditDisabled =>
      'Редактирование профиля отключено администратором — данные доступны только для просмотра.';

  @override
  String get personalDetailsFirstName => 'Имя';

  @override
  String get personalDetailsLastName => 'Фамилия';

  @override
  String get personalDetailsUsername => 'Логин';

  @override
  String get personalDetailsUsernameHint => 'латиница, цифры, _';

  @override
  String get personalDetailsBirthDate => 'Дата рождения';

  @override
  String get personalDetailsSelectDate => 'Выбрать дату';

  @override
  String get personalDetailsBio => 'О себе';

  @override
  String get personalDetailsBioPlaceholder => 'Расскажите о себе';

  @override
  String personalDetailsBioCounter(int count) {
    return '$count/150';
  }

  @override
  String get personalDetailsFirstNameRequired => 'Введите имя';

  @override
  String get personalDetailsLastNameRequired => 'Введите фамилию';

  @override
  String get personalDetailsUsernameInvalid =>
      'Только латинские буквы, цифры и «_», от 3 до 32 символов';

  @override
  String get securityChangePassword => 'Изменить пароль';

  @override
  String get securityCurrentPassword => 'Текущий пароль';

  @override
  String get securityNewPassword => 'Новый пароль';

  @override
  String get securityRepeatPassword => 'Повторите пароль';

  @override
  String get securityPasswordsDontMatch => 'Пароли не совпадают';

  @override
  String get securityPasswordChanged => 'Пароль изменён';

  @override
  String get securityChangeEmail => 'Изменить email';

  @override
  String get securityNewEmail => 'Новый email';

  @override
  String get securityVerificationCode => 'Код подтверждения';

  @override
  String get securityChangePhone => 'Изменить номер телефона';

  @override
  String get securityNewPhone => 'Новый номер';

  @override
  String get securityLinkedAccounts => 'Привязанные аккаунты';

  @override
  String get securityLinked => 'Привязан';

  @override
  String get securityNotLinked => 'Не привязан';

  @override
  String get securityLink => 'Привязать';

  @override
  String get securityUnlink => 'Отвязать';

  @override
  String get securityDeleteAccount => 'Удалить аккаунт';

  @override
  String get securityDeleteAccountWarning =>
      'Это действие необратимо. Все ваши данные будут удалены безвозвратно.';

  @override
  String get securityDeleteAccountConfirmTitle => 'Вы уверены?';

  @override
  String get securityDeleteAccountConfirmBody =>
      'Введите «УДАЛИТЬ», чтобы подтвердить окончательное удаление аккаунта.';

  @override
  String get securityDeleteConfirmationWord => 'УДАЛИТЬ';

  @override
  String get securityDeleteAccountAction => 'Удалить окончательно';

  @override
  String get avatarTakePhoto => 'Сделать фото';

  @override
  String get avatarChooseFromGallery => 'Выбрать из галереи';

  @override
  String get avatarRemovePhoto => 'Удалить фото';
}
