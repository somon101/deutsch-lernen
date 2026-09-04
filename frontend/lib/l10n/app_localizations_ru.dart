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
  String get statisticsLanguage => 'Статистика курса';

  @override
  String get statisticsLanguageNotSet => 'Выбрать';

  @override
  String get courseContentLanguage => 'Язык курса';

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
  String get clearCache => 'Очистить кэш';

  @override
  String get clearCacheConfirmTitle => 'Очистить сохранённые данные?';

  @override
  String get clearCacheConfirmBody =>
      'Курсы и уроки при следующем открытии загрузятся заново с сервера.';

  @override
  String get clearCacheDone => 'Кэш очищен';

  @override
  String get logout => 'Выйти из аккаунта';

  @override
  String get logoutConfirmTitle => 'Выйти из аккаунта?';

  @override
  String get logoutConfirmBody => 'Вы сможете снова войти в любой момент.';

  @override
  String get cancel => 'Отмена';

  @override
  String get change => 'Изменить';

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
  String get securityPasswordTooShort =>
      'Пароль должен содержать не менее 6 символов';

  @override
  String get securityPasswordChanged => 'Пароль изменён';

  @override
  String get securityEmailLabel => 'Email';

  @override
  String get securityChangeEmail => 'Изменить email';

  @override
  String get securityNewEmail => 'Новый email';

  @override
  String get securityEmailInvalid => 'Некорректный формат email';

  @override
  String get securityVerificationCode => 'Код подтверждения';

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

  @override
  String get qrCardTitle => 'Моя карточка';

  @override
  String get qrCardLevel => 'Уровень';

  @override
  String qrCardGoal(String level, int percent) {
    return 'до $level — $percent%';
  }

  @override
  String get qrCardMaxLevel => 'Максимальный уровень';

  @override
  String get qrCardStreakLabel => 'дней подряд';

  @override
  String get qrCardRankLabel => 'в мире';

  @override
  String get qrCardFollowersLabel => 'подписчиков';

  @override
  String get qrCardSlogan => 'Your language · Your path · Your future';

  @override
  String get qrCardShare => 'Поделиться';

  @override
  String get qrCardCopyId => 'Скопировать ID';

  @override
  String get qrCardIdCopied => 'ID скопирован';

  @override
  String get qrCardGenerating => 'Создаём карточку…';

  @override
  String get qrCardShareFailed => 'Не удалось поделиться карточкой';

  @override
  String get errorServerTimeout =>
      'Сервер не отвечает (превышено время ожидания). Проверьте интернет-соединение.';

  @override
  String get errorConnectionFailed =>
      'Нет соединения с сервером. Проверьте интернет и адрес сервера.';

  @override
  String get errorSslCertificate =>
      'Ошибка проверки сертификата сервера (SSL).';

  @override
  String get errorRequestCancelled => 'Запрос отменён.';

  @override
  String get errorUnknownNetwork => 'Неизвестная ошибка сети';

  @override
  String get errorServerError => 'Ошибка сервера. Попробуйте позже.';

  @override
  String get errorNetworkGeneric => 'Ошибка сети';

  @override
  String get wordAudioTooltip => 'Прослушать произношение';

  @override
  String get lessonStatusCompleted => '✓ Урок завершён';

  @override
  String get lessonStatusContinue => 'Продолжить';

  @override
  String get lessonStatusStart => 'Начать урок';

  @override
  String get myWordsTitle => 'Мои слова';

  @override
  String myWordsLoadError(Object error) {
    return 'Не удалось загрузить слова: $error';
  }

  @override
  String get myWordsEmpty =>
      'Пока нет изученных слов — они появятся здесь после завершения уроков.';

  @override
  String get myWordsUncategorized => 'Без категории';

  @override
  String get leaderboardTitle => 'Рейтинг';

  @override
  String get leaderboardSearchHint => 'Найти по нику или ID';

  @override
  String leaderboardLoadError(Object error) {
    return 'Не удалось загрузить рейтинг: $error';
  }

  @override
  String get leaderboardEmpty => 'Пока нет участников рейтинга';

  @override
  String leaderboardSearchError(Object error) {
    return 'Не удалось выполнить поиск: $error';
  }

  @override
  String get leaderboardUserNotFound => 'Пользователь не найден';

  @override
  String get authTagline => 'Войдите, чтобы продолжить обучение';

  @override
  String get authLoginOrEmail => 'Логин или email';

  @override
  String get authLoginRequired => 'Введите логин';

  @override
  String get authPasswordLabel => 'Пароль';

  @override
  String get authPasswordRequired => 'Введите пароль';

  @override
  String get authSignIn => 'Войти';

  @override
  String authSignInFailedDebug(Object error) {
    return 'Не удалось войти: $error';
  }

  @override
  String get authSignInFailed => 'Не удалось войти в аккаунт';

  @override
  String get forbiddenTitle => 'Доступ запрещён';

  @override
  String get forbiddenBodyTeacher =>
      'Этот раздел доступен только администраторам.';

  @override
  String get forbiddenBodyDefault => 'У вас нет доступа к этой странице.';

  @override
  String get forbiddenGoHome => 'На главную';

  @override
  String get homeExitConfirmation => 'Нажмите ещё раз для выхода';

  @override
  String get homeLanguagePickerTitle => 'Язык';

  @override
  String get homeThemeLight => 'Светлая тема';

  @override
  String get homeThemeDark => 'Тёмная тема';

  @override
  String homeLanguagesLoadError(Object error) {
    return 'Не удалось загрузить языки: $error';
  }

  @override
  String get homeNoCourses => 'Курсы пока не опубликованы';

  @override
  String homeGreeting(String name) {
    return 'Привет, $name!';
  }

  @override
  String homeLessonsLoadError(Object error) {
    return 'Не удалось загрузить уроки: $error';
  }

  @override
  String get homeNoLessons => 'Уроков пока нет';

  @override
  String get lessonDownloadTitle => 'Загружаем фото слов';

  @override
  String get lessonDownloadSubtitle =>
      'Один раз — дальше урок открывается мгновенно и работает без интернета.';

  @override
  String lessonDownloadProgress(int done, int total) {
    return '$done из $total';
  }

  @override
  String get socialFollowers => 'Подписчики';

  @override
  String get socialFollowing => 'Подписки';

  @override
  String get socialMutual => 'Взаимные';

  @override
  String socialListLoadError(Object error) {
    return 'Не удалось загрузить список: $error';
  }

  @override
  String get socialListEmpty => 'Пока пусто';

  @override
  String get socialThisIsYourProfile => 'Это ваш профиль';

  @override
  String get socialProfileTitle => 'Профиль';

  @override
  String socialProfileLoadError(Object error) {
    return 'Не удалось загрузить профиль: $error';
  }

  @override
  String socialStatsLoadError(Object error) {
    return 'Не удалось загрузить статистику: $error';
  }

  @override
  String socialUnfollowError(Object error) {
    return 'Не удалось отписаться: $error';
  }

  @override
  String socialFollowError(Object error) {
    return 'Не удалось подписаться: $error';
  }

  @override
  String get socialUnfollowing => 'Отписываемся…';

  @override
  String get socialUnfollow => 'Отписаться';

  @override
  String get socialFollowingInProgress => 'Подписываемся…';

  @override
  String get socialFollow => 'Подписаться';

  @override
  String get gamificationLevelHint => 'Вы близки к следующему уровню!';

  @override
  String get gamificationAchievementFirstLessonTitle => 'Первый урок';

  @override
  String get gamificationAchievementDone => 'Пройден';

  @override
  String get gamificationAchievementWeekTitle => 'Неделя 7 дней';

  @override
  String get gamificationAchievementGoalTitle => 'Цель 10 уроков';

  @override
  String get gamificationAchievementActiveTitle => 'Активный ученик';

  @override
  String get gamificationAchievementLessons10 => '10 уроков';

  @override
  String get gamificationAchievementWordMasterTitle => 'Мастер слов';

  @override
  String get gamificationAchievementLocked => 'Заблокировано';

  @override
  String get gamificationRankPeriodWeek => 'По неделе';

  @override
  String get gamificationLearningLanguageEnglish => 'английский';

  @override
  String profileFollowStatsLoadError(Object error) {
    return 'Не удалось загрузить подписки: $error';
  }

  @override
  String profileProgressLoadError(Object error) {
    return 'Не удалось загрузить прогресс: $error';
  }

  @override
  String get profileAchievementsTitle => 'Достижения';

  @override
  String profileRankLoadError(Object error) {
    return 'Не удалось загрузить рейтинг: $error';
  }

  @override
  String profileActivityLoadError(Object error) {
    return 'Не удалось загрузить активность: $error';
  }

  @override
  String get profileShareTooltip => 'Поделиться профилем';

  @override
  String get profileSeeAll => 'Все';

  @override
  String get avatarOnline => 'в сети';

  @override
  String get avatarOffline => 'не в сети';

  @override
  String get levelCardTitle => 'Ваш уровень';

  @override
  String get metricsStreak => 'Серия';

  @override
  String get metricsProgress => 'Прогресс';

  @override
  String get metricsTime => 'Время';

  @override
  String get metricsPoints => 'Очки';

  @override
  String get rankCardTitle => 'Ваш рейтинг';

  @override
  String rankTop(int percent) {
    return 'Топ $percent%';
  }

  @override
  String get rankGlobal => 'Глобально';

  @override
  String rankOutOf(int total) {
    return 'из $total';
  }

  @override
  String get rankAmongAllStudents => 'Среди всех студентов';

  @override
  String get weekActivityDayMon => 'Пн';

  @override
  String get weekActivityDayTue => 'Вт';

  @override
  String get weekActivityDayWed => 'Ср';

  @override
  String get weekActivityDayThu => 'Чт';

  @override
  String get weekActivityDayFri => 'Пт';

  @override
  String get weekActivityDaySat => 'Сб';

  @override
  String get weekActivityDaySun => 'Вс';

  @override
  String get weekActivityTitle => 'Активность за неделю';

  @override
  String get weekActivityAverage => 'Средняя активность';

  @override
  String get gamificationLevelNameIntermediate => 'Средний';

  @override
  String metricsTimeFormat(int hours, int minutes) {
    return '$hoursч $minutesм';
  }

  @override
  String weekActivityAvgPerDay(int minutes) {
    return '$minutesм/день';
  }

  @override
  String get stageVocabulary => 'Слова';

  @override
  String get stageMaterial => 'Материал';

  @override
  String get stageVideo => 'Видео';

  @override
  String get stageMinitest => 'Мини-тест';

  @override
  String get stageAudio => 'Аудио';

  @override
  String get stagePractice => 'Практика';

  @override
  String get stageReview => 'Закрепление';

  @override
  String get stageComplete => 'Итог';

  @override
  String get lessonTitle => 'Урок';

  @override
  String lessonLoadError(Object error) {
    return 'Не удалось загрузить урок: $error';
  }

  @override
  String lessonUnknownBlockType(String type) {
    return 'Неизвестный тип блока: $type';
  }

  @override
  String get lessonFinish => 'Завершить урок';

  @override
  String lessonNext(String title) {
    return 'Далее: $title →';
  }

  @override
  String get lessonCompleteTitle => 'Отличная работа!';

  @override
  String lessonCompleteSubtitleGraph(String title) {
    return 'Вы прошли урок «$title». Вот ваши результаты:';
  }

  @override
  String lessonCompleteSubtitleLinear(String title) {
    return 'Вы прошли все этапы урока «$title». Вот ваши результаты:';
  }

  @override
  String get lessonCompleteWordsLearned => 'слов изучено';

  @override
  String get lessonCompleteRestarting => 'Начинаем…';

  @override
  String get lessonCompleteRestart => 'Пройти ещё раз';

  @override
  String get lessonCompleteMinitestLabel => 'мини-тест';

  @override
  String get lessonCompletePracticeLabel => 'практика';

  @override
  String get lessonCompleteReviewLabel => 'закрепление';

  @override
  String get vocabularyStageEmpty =>
      'В этом уроке нет новых слов — все они уже встречались раньше.';

  @override
  String get commonNext => 'Далее';

  @override
  String get lessonStageSkip => 'Пропустить и продолжить';

  @override
  String materialStageStepTitle(int number, String title) {
    return 'Шаг $number. $title';
  }

  @override
  String get materialStageMissing => 'Не хватает материала';

  @override
  String get materialStageNotFound => 'Текст урока не найден.';

  @override
  String materialStageSection(int page, int total) {
    return 'Раздел $page из $total';
  }

  @override
  String get materialStageDefaultNextVideo => 'Перейти к видео';

  @override
  String get materialStageNextArrow => 'Далее →';

  @override
  String get materialStageBack => '← Назад';

  @override
  String get videoStageNotFound => 'Видео не найдено';

  @override
  String get videoStageNotUploaded => 'Для этого урока не загружено видео.';

  @override
  String get videoStageWatch => 'Посмотрите видео';

  @override
  String get videoStageWatched => '✓ Видео просмотрено';

  @override
  String get videoStageWatchToContinue =>
      'Досмотрите видео до конца, чтобы продолжить';

  @override
  String get videoStageDefaultNextMinitest => 'Перейти к мини-тесту →';

  @override
  String get audioStageLoadError =>
      'Не удалось загрузить аудиофайл. Проверьте, что файл существует и доступен, и попробуйте ещё раз.';

  @override
  String get audioStagePlaybackError =>
      'Не удалось запустить воспроизведение аудио. Проверьте, не отключён звук, и попробуйте ещё раз.';

  @override
  String get audioStageNotFound => 'Аудио не найдено';

  @override
  String get audioStageNotUploaded =>
      'Для этого урока не загружена аудиозапись.';

  @override
  String get audioStageListen => 'Прослушайте аудио';

  @override
  String get audioStageListenHint =>
      'Послушайте запись и закрепите произношение фраз из урока.';

  @override
  String get audioStageFinished => '✓ Запись прослушана';

  @override
  String get audioStageListenToContinue =>
      'Прослушайте запись до конца, чтобы продолжить';

  @override
  String get audioStageDefaultNextPractice => 'Перейти к практике →';

  @override
  String get exerciseKindChoice => 'Выбор ответа';

  @override
  String get exerciseKindTrueFalse => 'Верно или неверно';

  @override
  String get exerciseKindMatch => 'Сопоставление';

  @override
  String get exerciseKindScramble => 'Собери фразу';

  @override
  String get exerciseKindCloze => 'Заполни пропуск';

  @override
  String get exerciseKindAutoBlank => 'Пропущенное слово';

  @override
  String get exerciseKindAutoTranslate => 'Переведи слово';

  @override
  String get exercisePromptMatch => 'Сопоставление слов и переводов';

  @override
  String exercisePromptScramble(String translation) {
    return 'Фраза по переводу «$translation»';
  }

  @override
  String exercisePromptCloze(String translation) {
    return 'Пропуск во фразе «$translation»';
  }

  @override
  String exerciseCorrectAnswer(String answer) {
    return 'Правильный ответ: «$answer»';
  }

  @override
  String get exerciseNotAllPairsMatched =>
      'Не все пары были сопоставлены с первой попытки';

  @override
  String exerciseCorrectScramble(String answer) {
    return 'Правильно: «$answer»';
  }

  @override
  String exerciseCorrectWord(String answer) {
    return 'Правильное слово: «$answer»';
  }

  @override
  String get exerciseDetailsInHistory => 'Подробности — в истории ответов';

  @override
  String get exerciseStageNotEnoughMaterial =>
      'Недостаточно материала для этого блока — переходим дальше.';

  @override
  String exerciseStageProgress(int index, int total) {
    return 'Задание $index из $total';
  }

  @override
  String exerciseStageCorrectCount(int count) {
    return '$count правильно';
  }

  @override
  String get exerciseStageNextEnter => 'Следующее (Enter)';

  @override
  String get exerciseStageFinishEnter => 'Завершить (Enter)';

  @override
  String get exerciseStageResultTitle => 'Результат';

  @override
  String get exerciseStageAllCorrect => 'Отлично, всё верно!';

  @override
  String get exerciseStageGoodResult =>
      'Хороший результат. Разберём ошибки ниже.';

  @override
  String get exerciseStageContinueEnter => 'Продолжить (Enter)';

  @override
  String homeMapWordCount(int count) {
    return '$count слов';
  }

  @override
  String get homeMapLockedSnack => 'Завершите предыдущий урок';

  @override
  String get leaderboardPeriodDay => 'День';

  @override
  String get leaderboardPeriodWeek => 'Неделя';

  @override
  String get leaderboardPeriodMonth => 'Месяц';

  @override
  String get leaderboardPeriodAllTime => 'Всё время';

  @override
  String get leaderboardColumnRank => 'Место';

  @override
  String get leaderboardColumnStudent => 'Ученик';

  @override
  String get leaderboardColumnPoints => 'Очки';

  @override
  String leaderboardGoalToPlace(int rank, int points) {
    return 'До $rank места — $points очков';
  }

  @override
  String leaderboardGoalBeatName(String name) {
    return 'Один урок, и ты обгонишь $name';
  }

  @override
  String get leaderboardGoalTop => 'Ты на вершине. Удержи позицию';

  @override
  String get leaderboardThisIsYou => 'Это ты';

  @override
  String get leaderboardSearchTooltip => 'Поиск';

  @override
  String get leaderboardInfoTooltip => 'Как начисляются очки';

  @override
  String get leaderboardInfoTitle => 'Как начисляются очки';

  @override
  String get leaderboardInfoBody =>
      '10 очков за каждый правильно отвеченный вопрос и 50 очков за завершённый урок.';

  @override
  String get leaderboardRetry => 'Повторить';
}
