**Функциональный индекс — что это**

Обычный индекс хранит значения колонки как есть. Функциональный индекс хранит результат функции или выражения применённого к колонке. PostgreSQL использует такой индекс только когда запрос содержит то же самое выражение.

---

**Проблема которую он решает**

В MovieLens есть `title` — строки вида `"Toy Story (1995)"`. Пользователи ищут без учёта регистра. Обычный индекс не поможет:

```sql
-- Обычный B-Tree индекс на title
CREATE INDEX movies_title_idx ON movies(title);
```

```sql
-- Этот запрос НЕ использует индекс — lower() вычисляется на лету
EXPLAIN ANALYZE
SELECT * FROM movies
WHERE lower(title) = 'toy story (1995)';
```

PostgreSQL не может использовать индекс на `title` для поиска по `lower(title)` — это разные значения. Без индекса — Seq Scan по 87 тысячам строк.

---

**Решение — функциональный индекс**

-- Индекс хранит lower(title) для каждой строки
```sql
CREATE INDEX movies_title_lower_idx ON movies(lower(title));
```

-- Теперь этот запрос использует индекс
Bitmap Index Scan on movies_title_lower_idx
```sql
EXPLAIN ANALYZE
SELECT * FROM movies
WHERE lower(title) = 'toy story (1995)';
```
# Префиксный поиск (prefix search) или поиск по префиксу.
Должен отработать movd_title_lower_idx, но не отработал: sequential scan
```sql
EXPLAIN ANALYZE
SELECT * FROM movies
WHERE lower(title) LIKE 'toy story%';
```
```sql
SHOW lc_collate;
```
Результат: en_US.UTF-8  

-- Пересоздаём индекс с указанием операторного класса
```sql
DROP INDEX movies_title_lower_idx;

CREATE INDEX movies_title_lower_idx
    ON movies(lower(title) text_pattern_ops);
```
`text_pattern_ops` — операторный класс который говорит PostgreSQL: "этот индекс будет использоваться для LIKE и ~". Без него B-Tree при не-C локали не знает как делать prefix matching для текста.

PostgreSQL видит `lower(title)` в запросе, находит индекс на `lower(title)` — использует его.  
Еще раз: Bitmap Index Scan on movies_title_lower_idx. В 430 раз быстрее. 
```sql
EXPLAIN ANALYZE
SELECT * FROM movies
WHERE lower(title) LIKE 'toy story%';
```

---

**Когда индекс movies_title_lower_idx НЕ будет использоваться в LIKE**

**1. Аргумент начинается с wildcard:**

```sql
-- НЕ использует индекс — wildcard в начале строки
EXPLAIN ANALYZE
SELECT * FROM movies
WHERE lower(title) LIKE '%story%';
SELECT * FROM movies
WHERE lower(title) LIKE '%toy%';
SELECT * FROM movies
WHERE lower(title) LIKE '%story';
```

B-Tree индекс работает для `LIKE` только когда паттерн начинается с фиксированного префикса — `'toy%'`. Если строка начинается с `%` — PostgreSQL не знает с какого места в индексе начинать поиск, приходится делать Seq Scan.

**2. Выражение в запросе не совпадает с выражением в индексе:**

```sql
-- НЕ использует индекс — выражение другое
WHERE lower(trim(title)) = 'toy story (1995)';
WHERE upper(title) = 'TOY STORY (1995)';
WHERE title ILIKE 'toy story%';  -- ILIKE != lower() + LIKE
```

PostgreSQL ищет индекс точно по выражению. `lower(trim(title))` — это другое выражение, не `lower(title)`. `ILIKE` — тоже другое выражение, хотя семантически похоже.

```
+-------------------------------------------+-------------------+
| Запрос                                    | Использует индекс |
+-------------------------------------------+-------------------+
| WHERE lower(title) = 'toy story (1995)'   | да                |
| WHERE lower(title) LIKE 'toy%'            | да                |
| WHERE lower(title) LIKE '%story%'         | нет — % в начале  |
| WHERE lower(title) LIKE '%story'          | нет — % в начале  |
| WHERE lower(trim(title)) = 'toy story'    | нет — другое выр. |
| WHERE title ILIKE 'toy%'                  | нет — другое выр. |
+-------------------------------------------+-------------------+
```

---

**Важное правило**

Выражение в запросе должно совпадать с выражением в индексе дословно. Если в индексе `lower(title)`, а в запросе `LOWER(title)` — PostgreSQL всё равно найдёт (регистр функции не важен). Но если в индексе `lower(title)`, а в запросе `lower(trim(title))` — индекс не используется.

---

**Ещё примеры на MovieLens**

```sql
-- Индекс на год из названия фильма
-- title имеет вид "Toy Story (1995)" — год всегда в конце в скобках
CREATE INDEX movies_year_idx
    ON movies (CAST(
                       SUBSTRING(title FROM '\((\d{4})\)$') AS INT
               ));;
```

Bitmap Index Scan on movies_year_idx
-- Найти все фильмы 1994 года
```sql
EXPLAIN ANALYZE
SELECT title FROM movies
WHERE (substring(title FROM '\((\d{4})\)$'))::int = 1994;
```

```sql
-- Индекс на первый жанр из списка
-- genres имеет вид "Adventure|Animation|Children"
CREATE INDEX movies_first_genre_idx
    ON movies(split_part(genres, '|', 1));
```
Bitmap Index Scan on movies_first_genre_idx
```sql
-- Найти все фильмы где первый жанр — Action
EXPLAIN ANALYZE
SELECT title FROM movies
WHERE split_part(genres, '|', 1) = 'Action';
```

--

**Функциональный индекс + уникальность**

Классический банковский пример — уникальность без учёта регистра:

```sql
-- Нельзя создать двух пользователей с одинаковым email
-- независимо от регистра: "User@Bank.com" и "user@bank.com" — один и тот же
CREATE UNIQUE INDEX users_email_unique_idx
    ON users(lower(email));
```

Обычный `UNIQUE` на `email` пропустит оба варианта — он сравнивает побайтово. Функциональный `UNIQUE` на `lower(email)` — нет.

---

**Когда использовать**

Локатор: в запросах есть функция или выражение над колонкой в `WHERE`. Частые кандидаты: `lower()`, `upper()`, `date_trunc()`, `extract()`, `substring()`, `coalesce()`, арифметика.