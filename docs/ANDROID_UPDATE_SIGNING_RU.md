# Marble Labyrinth — постоянная подпись Android APK

## Почему старые APK конфликтуют
Название и package ID сами по себе недостаточны. Android обновляет установленное
приложение только при одинаковом package ID, совместимой подписи и достаточно
высоком versionCode. Старый CI-процесс генерировал НОВЫЙ debug.keystore на каждом
временном сервере GitHub — поэтому APK из разных сборок не могли обновлять друг друга.

Текущий постоянный идентификатор: `com.kirilsjanssen.marblelabyrinth`.
Отображаемое название: **Marble Labyrinth**. НЕ менять их между выпусками.

## Настройка ОДИН раз (владелец проекта, ПК)

1. Установить JDK 17 (Godot/Android Studio). В PowerShell проверить `keytool -help`.
2. В папке вне публичного репозитория создать личный ключ:
   ```powershell
   keytool -genkeypair -v -storetype PKCS12 -keystore MarbleLabyrinth-stable.p12 -alias marblelabyrinth -keyalg RSA -keysize 3072 -validity 10000
   ```
   На запрос задать **сильный уникальный пароль**, сохранить его в менеджере
   паролей. Формат PKCS12 использует одинаковый пароль для хранилища и ключа.
   Создать несколько офлайн-резервных копий `MarbleLabyrinth-stable.p12`.
   **Никогда не коммитить этот файл и не присылать приватный ключ в чат.**

3. Получить Base64 в буфер обмена Windows PowerShell:
   ```powershell
   [Convert]::ToBase64String([IO.File]::ReadAllBytes((Resolve-Path .\MarbleLabyrinth-stable.p12))) | Set-Clipboard
   ```
4. Открыть https://github.com/kirilsjanssen/marble-labyrinth/settings/secrets/actions
   и создать три **Repository secrets**:
   - `MARBLE_STABLE_KEYSTORE_BASE64` — вставить длинный Base64 из буфера.
   - `MARBLE_STABLE_KEY_ALIAS` — `marblelabyrinth`.
   - `MARBLE_STABLE_KEY_PASSWORD` — пароль хранилища.
   GitHub показывает секреты только в момент ввода; НЕ добавлять в Variables.
5. После объединения ветки с новым workflow открыть
   https://github.com/kirilsjanssen/marble-labyrinth/actions/workflows/android-stable-apk.yml
   и нажать **Run workflow** → ветка `main` → **Run workflow**.
6. После зелёного результата скачать артефакт `MarbleLabyrinth-stable-apk` и
   установить `MarbleLabyrinth-stable.apk`. Публичный SHA-256 сертификата из
   артефакта должен оставаться тем же у всех последующих стабильных сборок.

## Обновления
- Только `Android Stable APK` выдаёт сборки для установки поверх прежних.
  Workflow не запускается без трёх секретов; НЕ подменяет их временной подписью.
- Каждый ручной запуск GitHub Actions повышает `version/code`:
  10000 + `GITHUB_RUN_NUMBER`. Номер `version/name` тоже растёт.
- Будущий локальный APK с тем же package ID должен подписываться ТЕМ ЖЕ ключом
  и иметь versionCode не ниже уже установленного.
- Старый APK, подписанный случайным временным ключом, с новым стабильным ключом
  несовместим. Придётся **один раз удалить старую тестовую версию** — после этого
  обновления должны устанавливаться поверх, пока ключ, ID и номер версии верны.
- Не удалять старую версию, если важны её локальные данные: удаление стирает данные.

## О предупреждениях Android
Разрешение `INSTALL_PACKAGES` или `REQUEST_INSTALL_PACKAGES` **не нужно игре**
и НЕ отменяет защиту Google Play Protect. Для установки APK извне магазина на
телефоне нужно разрешить *Установка неизвестных приложений* тому приложению,
через которое открывается APK (браузер/файловый менеджер).
Android/Play Protect всё ещё может показать предупреждение при боковой установке;
гарантированно выключить эту защиту через манифест или разрешения игры нельзя.
Нельзя обещать отсутствие всех предупреждений. Самый обычный путь доверенной
дистрибуции — внутреннее тестирование через Google Play после регистрации.

Не выкладывать пароль или ключ в исходники, коммиты, Issues, PR, видео и логи.
