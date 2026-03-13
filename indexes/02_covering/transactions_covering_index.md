# Covering индекс (INCLUDE) — таблица transactions
## Планы запроса не будут использовать индексы, а будут читать табличку целиком, потому что она маленькая. 
### Принудительная проверка Index Only Scan

Если таблица маленькая — оптимизатор может выбрать Bitmap Heap Scan.
Принудительно проверяем что индекс покрывающий:

```sql
SET enable_bitmapscan = off;
SET enable_seqscan    = off;

EXPLAIN ANALYZE
SELECT avg(rating)
FROM ratings
WHERE movie_id = 1;

SET enable_bitmapscan = on;
SET enable_seqscan    = on;
```

## Бизнес-задача

Самый горячий запрос в банке — выписка по счёту. Выполняется миллионы раз в день —
каждый раз когда клиент открывает мобильное приложение.

## DDL

```sql
CREATE SCHEMA IF NOT EXISTS bank_transactions;
SET search_path TO bank_transactions;
CREATE TABLE transactions (
    id              bigserial       PRIMARY KEY,
    account_id      bigint          NOT NULL,
    amount          numeric(18, 2)  NOT NULL,
    currency        char(3)         NOT NULL,   -- 'RUB', 'USD', 'EUR'
    direction       char(1)         NOT NULL,   -- 'D' debit, 'C' credit
    created_at      timestamptz     NOT NULL DEFAULT now(),
    status          text            NOT NULL,   -- меняется: PENDING -> COMPLETED
    description     text,                       -- меняется: иногда редактируют
    counterparty_id bigint          NOT NULL    -- никогда не меняется
);
```

### Covering индекс

`amount`, `currency`, `direction` — устанавливаются при создании транзакции,
никогда не меняются. Банк не может изменить сумму проведённой транзакции.

`status` и `description` — в INCLUDE не добавляем: они меняются,
каждое изменение будет обновлять индекс (write amplification, HOT отключается).

```sql
CREATE INDEX transactions_account_covering_idx
    ON transactions(account_id, created_at DESC)
    INCLUDE (amount, currency, direction);
```

## Данные

```sql
INSERT INTO transactions (account_id, amount, currency, direction, status, description, counterparty_id) VALUES
-- Счёт 1001 — рублёвые операции
(1001,  50000.00, 'RUB', 'C', 'COMPLETED', 'Зарплата за январь',         2001),
(1001,   3200.00, 'RUB', 'D', 'COMPLETED', 'Оплата ЖКХ',                 2002),
(1001,   1500.00, 'RUB', 'D', 'COMPLETED', 'Кофейня на Арбате',          2003),
(1001,  12000.00, 'RUB', 'D', 'COMPLETED', 'Супермаркет',                2004),
(1001,   5000.00, 'RUB', 'D', 'COMPLETED', 'Перевод другу',              2005),
(1001,  50000.00, 'RUB', 'C', 'COMPLETED', 'Зарплата за февраль',        2001),
(1001,   3200.00, 'RUB', 'D', 'COMPLETED', 'Оплата ЖКХ',                 2002),
(1001,    800.00, 'RUB', 'D', 'COMPLETED', 'Такси',                      2006),
(1001,  15000.00, 'RUB', 'D', 'PENDING',   'Перевод на вклад',           2007),
(1001,   2300.00, 'RUB', 'D', 'PENDING',   'Интернет и телефон',         2008),

-- Счёт 1002 — валютные операции
(1002,   1000.00, 'USD', 'C', 'COMPLETED', 'Фриланс оплата',             3001),
(1002,    250.00, 'USD', 'D', 'COMPLETED', 'Adobe подписка',             3002),
(1002,    500.00, 'EUR', 'C', 'COMPLETED', 'Возврат от партнёра',        3003),
(1002,    120.00, 'EUR', 'D', 'COMPLETED', 'Отель Берлин',               3004),
(1002,   1000.00, 'USD', 'C', 'COMPLETED', 'Фриланс оплата февраль',     3001),

-- Счёт 1003
(1003,  30000.00, 'RUB', 'C', 'COMPLETED', 'Аванс',                     4001),
(1003,   4500.00, 'RUB', 'D', 'COMPLETED', 'Аренда',                    4002),
(1003,   2100.00, 'RUB', 'D', 'COMPLETED', 'Продукты',                  4003),
(1003,  30000.00, 'RUB', 'C', 'COMPLETED', 'Зарплата',                  4001),
(1003,    500.00, 'RUB', 'D', 'PROCESSING','Штраф ГИБДД',               4004);
```

## Запросы

### Выписка по счёту — Index Only Scan

Запрос использует covering индекс — heap не читается: `Index Only Scan` и `Heap Fetches: 0`.

```sql
EXPLAIN ANALYZE
SELECT amount, currency, direction, created_at
FROM transactions
WHERE account_id = 1001
ORDER BY created_at DESC
LIMIT 50;
```

### Проверить что Heap Fetches = 0

```sql
EXPLAIN (ANALYZE, BUFFERS)
SELECT amount, currency, direction, created_at
FROM transactions
WHERE account_id = 1001
ORDER BY created_at DESC
LIMIT 10;
```

### Выписка только по дебетовым операциям

```sql
SELECT amount, currency, created_at
FROM transactions
WHERE account_id = 1001
  AND direction = 'D'
ORDER BY created_at DESC;
```

### Сумма поступлений и списаний по счёту

```sql
SELECT
    direction,
    currency,
    sum(amount)   AS total,
    count(*)      AS cnt
FROM transactions
WHERE account_id = 1001
GROUP BY direction, currency
ORDER BY currency, direction;
```

### Незавершённые транзакции по счёту

```sql
SELECT amount, currency, direction, status, description, created_at
FROM transactions
WHERE account_id = 1001
  AND status IN ('PENDING', 'PROCESSING')
ORDER BY created_at DESC;
```

### Все транзакции с контрагентом

```sql
SELECT t.account_id, t.amount, t.currency, t.direction, t.created_at
FROM transactions t
WHERE t.counterparty_id = 2001
ORDER BY t.created_at DESC;
```

## Что подходит для INCLUDE и что нет

| Колонка        | В INCLUDE? | Причина                                          |
|----------------|-----------|--------------------------------------------------|
| amount         | да        | устанавливается при создании, никогда не меняется |
| currency       | да        | устанавливается при создании, никогда не меняется |
| direction      | да        | D или C, никогда не меняется                     |
| status         | нет       | меняется: PENDING -> PROCESSING -> COMPLETED     |
| description    | нет       | пользователь может редактировать                 |
| counterparty_id| нет       | не меняется, но text — весит много               |
