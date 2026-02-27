# Тестовое задание ERPNext (Task auto dates)

## Оглавление

1. [Что сделано и бонус](#что-сделано-и-бонус)
2. [Ответы на вопросы](#ответы-на-вопросы)
3. [Как запустить](#как-запустить)

## Что сделано и бонус

- Реализован `Client Script` для `Task`: расчет `exp_end_date = exp_start_date + (duration - 1)` (календарные дни).
- Реализована клиентская валидация: если `exp_end_date < exp_start_date`, показывается `frappe.msgprint`, поле `exp_end_date` очищается.
- Добавлено требование поля `duration`, если заполнено `exp_start_date`.
- Реализован `Server Script` (`DocType Event`, `Before Save`) с тем же расчетом `exp_end_date`.
- Добавлено серверное бизнес-правило: если дата завершения уже в прошлом и статус не `Completed`/`Cancelled`, сохранение блокируется через `frappe.throw("Дата завершения задачи уже прошла! Измените дату или статус задачи.")`.
- Бонус: опциональная двунаправленная синхронизация (`exp_end_date -> duration`) через флаг `TASK_ENABLE_BIDIRECTIONAL_SYNC` в клиентском скрипте.

## Ответы на вопросы

- Почему логика на клиенте и сервере: клиент дает мгновенный UX в форме, сервер гарантирует корректность данных при API/импорте/отключенном JS.
- Какое событие выбрано на сервере: `Before Save`, чтобы пересчет и валидации выполнялись до записи в БД.
- Какой DocType использован: стандартный `Task` (новый DocType не создавался).
- Про имена полей: в `Task` используются реальные поля `exp_start_date`, `duration`, `exp_end_date` (эквивалент `expected_*` из формулировки задания).
- Про имена скриптов: используется префикс `rsalagaev`, чтобы исключить конфликты с другими решениями.

## Как запустить

1. Склонировать репозиторий со скриптами:

```bash
git clone https://github.com/russsik1/frappe_test_project.git
cd frappe_test_project
```

2. Убедиться, что ERPNext уже развернут и доступен (по умолчанию `http://localhost:8080`).

3. Один раз включить Server Script в окружении ERPNext.  
   Команды ниже выполняются в директории `frappe_docker` (там, где лежит `pwd.yml`):

```bash
docker compose -f pwd.yml exec backend bench --site frontend set-config server_script_enabled true
docker compose -f pwd.yml exec backend bench set-config -g server_script_enabled 1
```

4. Из директории этого репозитория загрузить скрипты в ERPNext:

PowerShell:

```powershell
.\customizations\task-auto-dates\apply-task-auto-dates.ps1 -BaseUrl "http://localhost:8080" -Username "Administrator" -Password "admin" -NamePrefix "rsalagaev"
```

Bash:

```bash
bash ./customizations/task-auto-dates/apply-task-auto-dates.sh --base-url "http://localhost:8080" --username "Administrator" --password "admin" --name-prefix "rsalagaev"
```

5. Проверить, что созданы документы:

- `rsalagaev Task Auto Dates Client`
- `rsalagaev Task Auto Dates Server`

Страницы проверки:
- `http://localhost:8080/app/client-script`
- `http://localhost:8080/app/server-script`
