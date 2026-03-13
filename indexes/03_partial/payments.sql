CREATE SCHEMA IF NOT EXISTS payments;
SET search_path TO payments;

-- ============================================================
-- DDL
-- ============================================================

CREATE TABLE payments (
    id          bigserial       PRIMARY KEY,
    account_id  bigint          NOT NULL,
    amount      numeric(18, 2)  NOT NULL,
    status      text            NOT NULL,   -- PENDING, PROCESSING, COMPLETED, FAILED
    created_at  timestamptz     NOT NULL DEFAULT now()
);

-- ============================================================
-- Partial индексы
-- Колонка в CREATE INDEX — это порядок сортировки внутри индекса. WHERE — это фильтр какие строки вообще попадают в индекс.
-- ============================================================
-- Только необработанные платежи — воркер забирает задачи по created_at
CREATE INDEX payments_pending_idx
    ON payments(created_at)
    WHERE status IN ('PENDING', 'PROCESSING');

-- ============================================================
-- Тестовые данные
-- ============================================================

INSERT INTO payments (account_id, amount, status, created_at) VALUES
-- PENDING — ждут обработки
(1001, 500.00,   'PENDING',    now() - interval '5 minutes'),
(1002, 1200.50,  'PENDING',    now() - interval '3 minutes'),
(1003, 75.00,    'PENDING',    now() - interval '1 minute'),
(1004, 9999.99,  'PENDING',    now()),

-- PROCESSING — уже взяты воркером
(1005, 300.00,   'PROCESSING', now() - interval '10 minutes'),
(1006, 450.75,   'PROCESSING', now() - interval '8 minutes'),

-- COMPLETED — завершённые (99% таблицы в продакшне)
(1001, 100.00,   'COMPLETED',  now() - interval '2 days'),
(1002, 250.00,   'COMPLETED',  now() - interval '2 days'),
(1003, 800.00,   'COMPLETED',  now() - interval '3 days'),
(1004, 1500.00,  'COMPLETED',  now() - interval '5 days'),
(1005, 60.00,    'COMPLETED',  now() - interval '7 days'),
(1006, 3200.00,  'COMPLETED',  now() - interval '10 days'),
(1007, 420.00,   'COMPLETED',  now() - interval '14 days'),
(1008, 990.00,   'COMPLETED',  now() - interval '20 days'),
(1009, 175.25,   'COMPLETED',  now() - interval '30 days'),
(1010, 50.00,    'COMPLETED',  now() - interval '45 days'),

-- FAILED — отклонённые
(1007, 200.00,   'FAILED',     now() - interval '1 day'),
(1008, 5000.00,  'FAILED',     now() - interval '3 days'),
(1009, 350.00,   'FAILED',     now() - interval '6 days');

-- ============================================================
-- Проверочные запросы
-- ============================================================

-- Воркер забирает следующие 100 задач — использует payments_pending_idx
SELECT * FROM payments
WHERE status IN ('PENDING', 'PROCESSING')
ORDER BY created_at
LIMIT 100;

-- Убедиться что индекс используется
EXPLAIN ANALYZE
SELECT * FROM payments
WHERE status IN ('PENDING', 'PROCESSING')
ORDER BY created_at
LIMIT 100;

-- На большом количестве записей: Никакой отдельной сортировки — строки из индекса уже идут в порядке created_at.