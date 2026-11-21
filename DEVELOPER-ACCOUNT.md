# OXION: что включится после покупки аккаунта разработчика Apple ($99/год)

Всё ниже уже написано и собирается. После покупки аккаунта нужно только вставить ключи.

## 1. Купить аккаунт
1. developer.apple.com → Account → Enroll. Физлицо, оплата $99 в год.
2. После одобрения: Membership → скопировать **Team ID** (10 символов).

## 2. Ключи
| Ключ | Где взять | Куда вставить |
|---|---|---|
| Team ID | developer.apple.com → Membership | GitHub: секрет `APPLE_TEAM_ID`; Cloudflare: переменная `APPLE_TEAM_ID` и `APNS_TEAM_ID` |
| Ключ App Store Connect API (.p8, Key ID, Issuer ID) | appstoreconnect.apple.com → Users and Access → Integrations → App Store Connect API → «+», роль App Manager | GitHub: `ASC_KEY_P8` (содержимое файла), `ASC_KEY_ID`, `ASC_ISSUER_ID` |
| Ключ пушей APNs (.p8, Key ID) | developer.apple.com → Certificates, IDs & Profiles → Keys → «+» → Apple Push Notifications service | Cloudflare: `APNS_KEY_P8` (содержимое файла), `APNS_KEY_ID` |

GitHub: репозиторий → Settings → Secrets and variables → Actions → New repository secret.
Cloudflare: воркер → Settings → Variables and Secrets → Add (тип Secret).

## 3. Приложение в App Store Connect
appstoreconnect.apple.com → Apps → «+» → New App: платформа iOS, Bundle ID `ru.oxion.app`, название OXION.
(Bundle ID появится в списке после первого запуска выгрузки — подпись создаётся автоматически.)

## 4. Выгрузка в TestFlight
GitHub → Actions → «Выгрузка в TestFlight» → Run workflow. Через 10–30 минут сборка появится в TestFlight.
В неё входят: приложение, виджеты, приложение для Apple Watch и App Clip.

## 5. Что заработает
| Функция | Тестовая версия (Sideloadly) | С аккаунтом |
|---|---|---|
| Пуши с сервера (сообщения, комментарии, когда OXION закрыт) | нет | да — `APNS_*` в Cloudflare |
| Живые данные в виджетах (App Group) | демо | да |
| Apple Health (HealthKit) | через команду iPhone | напрямую |
| Apple Watch: тренировка, «Готово», отдых, пульс | превью | да |
| NFC-отметка в клубе | превью | да |
| SharePlay — совместная тренировка | превью | да |
| App Clip по QR/NFC в зале | нет | да — `APPLE_TEAM_ID` в Cloudflare + App Clip Experience в App Store Connect |
| Универсальные ссылки (…/clip/trainer/34 открывает приложение) | нет | да |
| Подписка PRO через App Store (StoreKit 2) | кнопка есть, покупка недоступна | да — товар `ru.oxion.app.pro.month` в App Store Connect |
| Вход через Apple | кнопка есть, Apple ответит ошибкой | да — включить Sign in with Apple у App ID |
| Game Center: рейтинг и достижения | ошибка входа | да — создать рейтинги и достижения (см. ниже) |
| Музыка Apple Music | нет | да — включить MusicKit у App ID; у человека подписка Apple Music |
| «Не отвлекаться» (Экранное время) | нет | только после отдельного разрешения Apple на Family Controls |

## 6. App Clip и ссылки
- Cloudflare: переменная `APPLE_TEAM_ID` → воркер начнёт отдавать `/.well-known/apple-app-site-association`.
- После выхода в App Store: переменная `APPSTORE_ID` (число из ссылки на приложение) — для баннера в Safari.
- App Store Connect → приложение → App Clip → Default Experience: адрес `https://ваш-домен/clip`.
- Метки NFC и QR-коды: адрес вида `https://ваш-домен/clip/tag/<id>` (панель владельца показывает его у каждой метки), `…/clip/trainer/<id>`, `…/clip/exercise/<id>`.
- Свой домен вместо workers.dev: переменная GitHub `APP_DOMAIN` (Variables) — подставится в права приложения.

## 6а. Покупки, вход через Apple, Game Center, музыка
1. **Подписка PRO.** App Store Connect → приложение → Подписки → группа «OXION PRO» → подписка с ID `ru.oxion.app.pro.month`, срок 1 месяц, цена. Там же → App Information → App Store Server Notifications → Production и Sandbox URL: `https://fit-app.brootai.workers.dev/iap/apple/notify`, версия 2. Сервер сам проверяет подпись Apple, ключи не нужны.
2. **Вход через Apple.** developer.apple.com → Identifiers → ru.oxion.app → галочка Sign in with Apple. В Cloudflare должна быть `APNS_BUNDLE_ID=ru.oxion.app` (по ней сервер сверяет токен).
3. **Game Center.** App Store Connect → приложение → Features → Game Center: рейтинги `oxion.workouts.total` (всего тренировок, «Most recent score» → лучше «Best score»), `oxion.sets.week` (подходов за тренировку); достижения `oxion.first`, `oxion.ten`, `oxion.fifty`, `oxion.hundred`.
4. **Apple Music.** developer.apple.com → Identifiers → ru.oxion.app → App Services → MusicKit.
5. **Экранное время.** Заявка: developer.apple.com/contact/request/family-controls-distribution. После одобрения добавить в `Oxion/Oxion.release.entitlements` ключ `com.apple.developer.family-controls` = true. Без одобрения ключ НЕ добавлять — сборка не подпишется.
6. **Wallet-карта клуба** не сделана: нужен сертификат Pass Type ID и подпись карт на сервере. Сделаю, когда будет аккаунт.

## 7. Перед отправкой на проверку Apple
- Цифровые подписки (PRO для тренера) внутри iOS-приложения Apple требует продавать через In-App Purchase.
- Нужна кнопка удаления аккаунта, «Пожаловаться» и «Заблокировать» в ленте и чатах, ссылка на политику конфиденциальности.
