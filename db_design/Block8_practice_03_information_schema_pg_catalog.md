# Практика: INFORMATION_SCHEMA и pg_catalog

Схема MovieLens ml-latest:
- `movies(movie_id, title, genres)`
- `ratings(user_id, movie_id, rating, ts)`
- `tags(user_id, movie_id, tag, ts)`
- `links(movie_id, imdb_id, tmdb_id)`

---

## Блок 1. INFORMATION_SCHEMA

---

### Задание 1.1
Получить список всех таблиц схемы `public`. Вывести только базовые таблицы — без вьюх и foreign tables.

<details>
<summary>Решение</summary>

```sql
SELECT table_name, table_type
FROM information_schema.tables
WHERE table_schema = 'public'
  AND table_type   = 'BASE TABLE'
ORDER BY table_name;
```

`table_type = 'BASE TABLE'` исключает `VIEW` и `FOREIGN TABLE`. Ожидаемый результат: `links`, `movies`, `ratings`, `tags`.

</details>

---

### Задание 1.2
Для таблицы `ratings` получить все колонки: имя, тип данных, допускает ли NULL, есть ли default. Порядок — по позиции в таблице.

<details>
<summary>Решение</summary>

```sql
SELECT
    column_name,
    data_type,
    is_nullable,
    column_default
FROM information_schema.columns
WHERE table_schema = 'public'
  AND table_name   = 'ratings'
ORDER BY ordinal_position;
```

`ordinal_position` — порядковый номер колонки в DDL. Без него порядок не гарантирован.

</details>

---

### Задание 1.3
Получить все ограничения типа `PRIMARY KEY` и `UNIQUE` во всех четырёх таблицах схемы `public`. Показать: таблица, имя ограничения, тип.

<details>
<summary>Решение</summary>

```sql
SELECT
    table_name,
    constraint_name,
    constraint_type
FROM information_schema.table_constraints
WHERE table_schema    = 'public'
  AND constraint_type IN ('PRIMARY KEY', 'UNIQUE')
ORDER BY table_name, constraint_type;
```

`constraint_type` принимает: `PRIMARY KEY`, `FOREIGN KEY`, `UNIQUE`, `CHECK`.

</details>

---

### Задание 1.4
Найти таблицы в схеме `public`, у которых **нет** колонки `movie_id`. Вернуть только имена таких таблиц.

<details>
<summary>Решение</summary>

```sql
SELECT t.table_name
FROM information_schema.tables t
WHERE t.table_schema = 'public'
  AND t.table_type   = 'BASE TABLE'
  AND NOT EXISTS (
      SELECT 1
      FROM information_schema.columns c
      WHERE c.table_schema = t.table_schema
        AND c.table_name   = t.table_name
        AND c.column_name  = 'movie_id'
  )
ORDER BY t.table_name;
```

Паттерн `NOT EXISTS` над `information_schema.columns` — стандартный способ проверки наличия колонки. Переносим на любую СУБД без изменений.

</details>

---

### Задание 1.5
Найти все таблицы схемы `public`, у которых одновременно **нет** колонок `audit_created_at` **и** `audit_updated_at`.

Упрощённый аудит конвенций: в реальном банковском проекте такую проверку запускают в CI при каждом migration.

<details>
<summary>Решение</summary>

```sql
SELECT
    t.table_name,
    bool_or(c.column_name = 'audit_created_at') AS has_created_at,
    bool_or(c.column_name = 'audit_updated_at') AS has_updated_at
FROM information_schema.tables t
LEFT JOIN information_schema.columns c
    ON  c.table_schema = t.table_schema
    AND c.table_name   = t.table_name
    AND c.column_name IN ('audit_created_at', 'audit_updated_at')
WHERE t.table_schema = 'public'
  AND t.table_type   = 'BASE TABLE'
GROUP BY t.table_name
HAVING NOT (
    bool_or(c.column_name = 'audit_created_at')
    AND bool_or(c.column_name = 'audit_updated_at')
)
ORDER BY t.table_name;
```

На схеме MovieLens вернёт все четыре таблицы — ни у одной нет этих колонок. `bool_or` в `HAVING` позволяет проверить наличие каждой колонки независимо в одном `GROUP BY`.

</details>

---

## Блок 2. pg_catalog — объекты и структура

---

### Задание 2.1
Получить все индексы таблицы `ratings` через `pg_catalog`: имя индекса, колонка, уникальный ли, метод доступа (btree/hash/gin/...).

<details>
<summary>Решение</summary>

```sql
SELECT
    i.relname        AS index_name,
    a.attname        AS column_name,
    ix.indisunique   AS is_unique,
    ix.indisprimary  AS is_primary,
    am.amname        AS index_type
FROM pg_index      ix
JOIN pg_class       t  ON t.oid  = ix.indrelid
JOIN pg_class       i  ON i.oid  = ix.indexrelid
JOIN pg_attribute   a
    ON  a.attrelid = t.oid
    AND a.attnum   = ANY(ix.indkey)
JOIN pg_am          am ON am.oid = i.relam
JOIN pg_namespace   n  ON n.oid  = t.relnamespace
WHERE t.relname  = 'ratings'
  AND n.nspname  = 'public'
ORDER BY index_name, column_name;
```

`ix.indkey` — массив `int2[]` с номерами атрибутов. `ANY(ix.indkey)` разворачивает его для JOIN с `pg_attribute`.

</details>

---

### Задание 2.2
Получить все ограничения таблицы `movies` напрямую через `pg_constraint`. Показать: имя, тип (`p`/`u`/`f`/`c`), читаемое определение через `pg_get_constraintdef()`.

<details>
<summary>Решение</summary>

```sql
SELECT
    con.conname                    AS constraint_name,
    con.contype                    AS contype,
    pg_get_constraintdef(con.oid)  AS definition
FROM pg_constraint con
JOIN pg_class       c ON c.oid = con.conrelid
JOIN pg_namespace   n ON n.oid = c.relnamespace
WHERE c.relname  = 'movies'
  AND n.nspname  = 'public'
ORDER BY con.contype;
```

`contype`: `p` = PRIMARY KEY, `f` = FOREIGN KEY, `u` = UNIQUE, `c` = CHECK, `x` = EXCLUSION. `pg_get_constraintdef()` возвращает читаемый DDL-фрагмент.

</details>

---

### Задание 2.3
Найти таблицы в схеме `public` **без первичного ключа**.

<details>
<summary>Решение</summary>

```sql
SELECT c.relname AS table_name
FROM pg_class      c
JOIN pg_namespace  n ON n.oid = c.relnamespace
WHERE n.nspname  = 'public'
  AND c.relkind  = 'r'
  AND NOT EXISTS (
      SELECT 1
      FROM pg_constraint con
      WHERE con.conrelid = c.oid
        AND con.contype  = 'p'
  )
ORDER BY c.relname;
```

`relkind = 'r'` — только обычные таблицы (исключает индексы `i`, вьюхи `v`, последовательности `S`). На MovieLens таблицы `ratings` и `tags` скорее всего попадут в результат — у них составной индекс по `(user_id, movie_id)`, но не PK.

</details>

---

### Задание 2.4
Получить все триггеры в схеме `public`. Показать: таблица, имя триггера, определение. Исключить системные триггеры.

<details>
<summary>Решение</summary>

```sql
SELECT
    c.relname                      AS table_name,
    tg.tgname                      AS trigger_name,
    pg_get_triggerdef(tg.oid)      AS definition
FROM pg_trigger    tg
JOIN pg_class       c ON c.oid = tg.tgrelid
JOIN pg_namespace   n ON n.oid = c.relnamespace
WHERE n.nspname       = 'public'
  AND NOT tg.tgisinternal
ORDER BY table_name, trigger_name;
```

`tgisinternal = true` — триггеры, которые Postgres создаёт сам (например, для FK constraints). При аудите пользовательской логики их исключают.

</details>

---

## Блок 3. pg_catalog — статистика и мониторинг

---

### Задание 3.1
Найти неиспользуемые индексы в схеме `public` (`idx_scan = 0`). Показать размер каждого. Отсортировать по убыванию размера.

<details>
<summary>Решение</summary>

```sql
SELECT
    relname                                               AS table_name,
    indexrelname                                          AS index_name,
    idx_scan,
    pg_size_pretty(pg_relation_size(indexrelid))          AS index_size
FROM pg_stat_user_indexes
WHERE idx_scan   = 0
  AND schemaname = 'public'
ORDER BY pg_relation_size(indexrelid) DESC;
```

⚠️ `idx_scan = 0` после рестарта Postgres или `SELECT pg_stat_reset()` — не повод сразу дропать. Смотреть динамику за несколько дней.

</details>

---

### Задание 3.2
Найти таблицы с высокой долей sequential scan. Показать: `seq_scan`, `idx_scan`, процент seq_scan от всех сканирований, количество живых строк. Фильтр: `seq_scan > 100`.

<details>
<summary>Решение</summary>

```sql
SELECT
    relname     AS table_name,
    seq_scan,
    idx_scan,
    n_live_tup  AS live_rows,
    ROUND(
        seq_scan::numeric
        / NULLIF(seq_scan + idx_scan, 0) * 100, 1
    )           AS seq_scan_pct
FROM pg_stat_user_tables
WHERE schemaname = 'public'
  AND seq_scan   > 100
ORDER BY seq_scan_pct DESC;
```

`NULLIF(seq_scan + idx_scan, 0)` — защита от деления на ноль для таблиц, которые ещё не читались. На `ratings` (32M строк) высокий `seq_scan_pct` — сигнал для добавления индексов по часто используемым фильтрам.

</details>

---

### Задание 3.3
Получить размер всех таблиц схемы `public`: общий (таблица + индексы + TOAST), только таблица, только индексы. Отсортировать по убыванию общего размера.

<details>
<summary>Решение</summary>

```sql
SELECT
    c.relname                                             AS table_name,
    pg_size_pretty(pg_total_relation_size(c.oid))         AS total_size,
    pg_size_pretty(pg_relation_size(c.oid))               AS table_size,
    pg_size_pretty(
        pg_total_relation_size(c.oid)
        - pg_relation_size(c.oid)
    )                                                     AS indexes_size
FROM pg_class      c
JOIN pg_namespace  n ON n.oid = c.relnamespace
WHERE n.nspname = 'public'
  AND c.relkind = 'r'
ORDER BY pg_total_relation_size(c.oid) DESC;
```

На MovieLens ожидаемый порядок: `ratings` (~1.2 GB) → `tags` → `movies` → `links`. `pg_total_relation_size` включает TOAST-таблицу — важно для таблиц с `text`-колонками вроде `movies.genres`.

</details>

---

### Задание 3.4
Показать текущие заблокированные запросы: кто блокирует, кого блокирует, тексты обоих запросов.

<details>
<summary>Решение</summary>

```sql
SELECT
    blocking.pid               AS blocking_pid,
    blocking_act.query         AS blocking_query,
    blocked.pid                AS blocked_pid,
    blocked_act.query          AS blocked_query,
    blocked_act.wait_event     AS wait_event
FROM pg_locks          blocked
JOIN pg_stat_activity  blocked_act
    ON  blocked_act.pid  = blocked.pid
JOIN pg_locks          blocking
    ON  blocking.granted   = true
    AND blocking.relation  = blocked.relation
    AND blocking.pid      != blocked.pid
JOIN pg_stat_activity  blocking_act
    ON  blocking_act.pid = blocking.pid
WHERE NOT blocked.granted;
```

Self-join `pg_locks`: одна сторона — заблокированные (`granted = false`), другая — удерживающие замок на тот же `relation` (`granted = true`). `pg_stat_activity` подтягивает текст запроса по `pid`.

</details>

---

### Задание 3.5 — комбинированный
Для таблицы `ratings` вывести в **одном запросе**:
- количество индексов
- суммарный размер всех индексов
- `seq_scan` и `idx_scan` из статистики
- количество мёртвых строк (`n_dead_tup`)

<details>
<summary>Решение</summary>

```sql
SELECT
    st.relname                                            AS table_name,
    COUNT(ix.indexrelid)                                  AS index_count,
    pg_size_pretty(
        SUM(pg_relation_size(ix.indexrelid))
    )                                                     AS indexes_total_size,
    st.seq_scan,
    st.idx_scan,
    st.n_dead_tup
FROM pg_stat_user_tables   st
JOIN pg_class               c  ON  c.relname  = st.relname
JOIN pg_namespace            n  ON  n.oid      = c.relnamespace
                                AND n.nspname  = st.schemaname
LEFT JOIN pg_index           ix ON  ix.indrelid = c.oid
WHERE st.schemaname = 'public'
  AND st.relname    = 'ratings'
GROUP BY st.relname, st.seq_scan, st.idx_scan, st.n_dead_tup;
```

`LEFT JOIN pg_index` — чтобы не потерять таблицы без индексов. `n_dead_tup` — строки удалённые, но ещё не очищенные VACUUM; на `ratings` с активными `UPDATE`/`DELETE` может быть значительным.

</details>

---

## Шпаргалка: что где искать

| Нужно найти | Источник |
|---|---|
| Список таблиц | `information_schema.tables` |
| Колонки и типы | `information_schema.columns` |
| FK с правилами ON DELETE/UPDATE | `information_schema.referential_constraints` |
| Индексы таблицы | `pg_index` + `pg_class` + `pg_am` |
| Таблицы без PK | `pg_constraint WHERE contype = 'p'` |
| Триггеры | `pg_trigger` |
| Неиспользуемые индексы | `pg_stat_user_indexes WHERE idx_scan = 0` |
| Таблицы с избытком seq_scan | `pg_stat_user_tables` |
| Размер таблицы / индексов | `pg_total_relation_size`, `pg_relation_size` |
| Текущие блокировки | `pg_locks` + `pg_stat_activity` |
| Мёртвые строки / статус VACUUM | `pg_stat_user_tables.n_dead_tup`, `last_vacuum` |
| Установленные расширения | `pg_extension` |
