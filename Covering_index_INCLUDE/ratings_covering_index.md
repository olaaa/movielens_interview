# Covering индекс (INCLUDE) — таблица ratings, MovieLens

## Бизнес-задача

Самый частый запрос на странице фильма — средняя оценка и количество голосов.
Выполняется при каждом открытии карточки фильма.

## DDL

Таблица ratings уже существует в MovieLens:

```sql
-- user_id   bigint
-- movie_id  bigint
-- rating    numeric (0.5 — 5.0 с шагом 0.5)
-- timestamp bigint
```
### План запроса до создания индекса
Execution Time: 4603.555 ms, Parallel Seq Scan on ratings
```sql
EXPLAIN ANALYZE
SELECT avg(rating)
FROM ratings
WHERE movie_id = 1;
```

### Обычный индекс — без покрытия

```sql
CREATE INDEX ratings_movie_id_idx ON ratings(movie_id);
-- DROP INDEX ratings_movie_id_idx;
```

При запросе `avg(rating)` PostgreSQL находит строки через индекс,
но `rating` в индексе не хранится — для каждого TID идёт в heap.
На 300 оценках фильма — 300 обращений к heap.

### Covering индекс

`rating` устанавливается один раз при вставке — пользователь может
переоценить фильм, но это редкая операция. Хороший кандидат для INCLUDE.

```sql
CREATE INDEX ratings_movie_id_covering_idx
    ON ratings(movie_id)
    INCLUDE (rating);
```

## Запросы для демонстрации

### 1. Средняя оценка фильма — базовый запрос

```sql
EXPLAIN ANALYZE
SELECT avg(rating)
FROM ratings
WHERE movie_id = 1;
```
```
Bitmap Heap Scan on ratings
  Recheck Cond:
     Bitmap Index Scan on ratings_movie_id_covering_idx
```
Оценок много -- 68_997, разбросаны по 509 страницам.  
Поэтому выполняем:
```sql
VACUUM ratings;
```
Еще раз строим план. Ожидаемый план с covering индексом:

```
Index Only Scan using ratings_movie_id_covering_idx on ratings
  Index Cond: (movie_id = 1)
  Heap Fetches: 0
```

`Heap Fetches: 0` — ни одного обращения к heap. Все данные взяты из индекса.

### 2. Средняя оценка и количество голосов

```sql
EXPLAIN ANALYZE
SELECT
    movie_id,
    round(avg(rating), 2)  AS avg_rating,
    count(*)               AS votes
FROM ratings
WHERE movie_id = 1
GROUP BY movie_id;
```

### 3. ⚠️ Топ-10 фильмов по средней оценке (минимум 100 голосов)
⚠️⚠️⚠️ Этот запрос индекс не использует — нет WHERE по конкретному movie_id.  
Нужно прочитать все 32 миллиона строк. PostgreSQL выбирает Parallel Seq Scan. Covering индекс здесь не помогает.
```sql
EXPLAIN ANALYZE
SELECT
    movie_id,
    round(avg(rating), 2)  AS avg_rating,
    count(*)               AS votes
FROM ratings
GROUP BY movie_id
HAVING count(*) >= 100
ORDER BY avg_rating DESC
LIMIT 10;
```

### 4. Распределение оценок для фильма

```sql
EXPLAIN ANALYZE
SELECT
    rating,
    count(*) AS cnt
FROM ratings
WHERE movie_id = 1
GROUP BY rating
ORDER BY rating;
```
Index Only Scan 

### 6. Проверка структуры индекса через pg_indexes

```sql
SELECT indexname, indexdef
FROM pg_indexes
WHERE tablename = 'ratings'
  AND indexname = 'ratings_movie_id_covering_idx';
```

Ожидаемый результат:

```
ratings_movie_id_covering_idx |
CREATE INDEX ratings_movie_id_covering_idx
ON ratings USING btree (movie_id) INCLUDE (rating)
```

## Что подходит для INCLUDE и что нет

| Колонка   | В INCLUDE? | Причина                                              |
|-----------|------------|------------------------------------------------------|
| rating    | да         | меняется редко — только при переоценке фильма        |
| timestamp | нет        | не нужен в SELECT для этого запроса                  |
| user_id   | нет        | не нужен в SELECT для этого запроса                  |

## Сравнение планов

### До covering индекса (обычный индекс на movie_id)

```
Bitmap Heap Scan on ratings
  Recheck Cond: (movie_id = 1)
  Heap Blocks: exact=N       <- N обращений к heap
```

### После covering индекса (INCLUDE rating)

```
Index Only Scan using ratings_movie_id_covering_idx on ratings
  Index Cond: (movie_id = 1)
  Heap Fetches: 0            <- heap не читается вообще
```
