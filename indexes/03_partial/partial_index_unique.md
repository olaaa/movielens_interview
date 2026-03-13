# Partial индекс + уникальность

## Бизнес-задача

У пользователя может быть только один активный черновик заявки на кредит,
но завершённых заявок — сколько угодно.

## DDL

```sql
CREATE SCHEMA IF NOT EXISTS loan_application;
SET search_path TO loan_application;
CREATE TABLE loan_applications (
    id          bigserial       PRIMARY KEY,
    user_id     bigint          NOT NULL,
    amount      numeric(18, 2)  NOT NULL,
    status      text            NOT NULL,   -- DRAFT, SUBMITTED, COMPLETED, REJECTED
    created_at  timestamptz     NOT NULL DEFAULT now()
);

-- Только одна заявка в статусе DRAFT на пользователя
-- COMPLETED и REJECTED под ограничение не попадают
CREATE UNIQUE INDEX loan_application_draft_unique
    ON loan_applications(user_id)
    WHERE status = 'DRAFT';
```

## Данные

```sql
INSERT INTO loan_applications (user_id, amount, status, created_at) VALUES
-- Завершённые заявки пользователя 1001 — несколько, это разрешено
(1001, 50000.00,  'COMPLETED', now() - interval '6 months'),
(1001, 30000.00,  'COMPLETED', now() - interval '1 year'),
(1001, 75000.00,  'REJECTED',  now() - interval '3 months'),

-- Завершённые заявки пользователя 1002
(1002, 20000.00,  'COMPLETED', now() - interval '8 months'),
(1002, 45000.00,  'REJECTED',  now() - interval '2 months'),

-- Черновики — по одному на пользователя
(1001, 100000.00, 'DRAFT',     now() - interval '1 day'),
(1002,  60000.00, 'DRAFT',     now() - interval '2 hours'),

-- Поданная заявка — тоже только одна активная
(1003, 35000.00,  'SUBMITTED', now() - interval '3 days');
```

## Демонстрация — constraint срабатывает

Попытка создать второй черновик для user_id = 1001:

```sql
INSERT INTO loan_applications (user_id, amount, status)
VALUES (1001, 200000.00, 'DRAFT');
```

Ожидаемая ошибка:

```
ERROR: duplicate key value violates unique constraint "loan_application_draft_unique"
DETAIL: Key (user_id)=(1001) already exists.
```

## Демонстрация — завершённые заявки не мешают

Ещё одна COMPLETED заявка для user_id = 1001 — проходит без ошибки:

```sql
INSERT INTO loan_applications (user_id, amount, status)
VALUES (1001, 15000.00, 'COMPLETED');
```

Constraint не срабатывает — COMPLETED строки в индекс не попадают.

## Демонстрация — после закрытия черновика можно создать новый

```sql
-- Закрываем текущий черновик пользователя 1001
UPDATE loan_applications
SET status = 'SUBMITTED'
WHERE user_id = 1001 AND status = 'DRAFT';

-- Теперь можно создать новый черновик
INSERT INTO loan_applications (user_id, amount, status)
VALUES (1001, 200000.00, 'DRAFT');
-- INSERT 0 1 — успешно
```

## Проверочные SELECT-ы

```sql
-- Все заявки пользователя 1001
SELECT id, user_id, amount, status, created_at
FROM loan_applications
WHERE user_id = 1001
ORDER BY created_at;

-- Текущие черновики всех пользователей
SELECT id, user_id, amount, created_at
FROM loan_applications
WHERE status = 'DRAFT'
ORDER BY created_at;

-- Количество заявок по статусам
SELECT status, count(*) AS cnt
FROM loan_applications
GROUP BY status
ORDER BY cnt DESC;
```

## Сравнение с обычным UNIQUE

```sql
-- Обычный UNIQUE — запретил бы больше одной заявки вообще
CREATE UNIQUE INDEX loan_application_user_unique
    ON loan_applications(user_id);
-- Нельзя было бы иметь историю заявок

-- Partial UNIQUE — только одна заявка в статусе DRAFT
CREATE UNIQUE INDEX loan_application_draft_unique
    ON loan_applications(user_id)
    WHERE status = 'DRAFT';
-- История COMPLETED и REJECTED не ограничена
```
