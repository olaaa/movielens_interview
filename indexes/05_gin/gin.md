**GIN — Generalized Inverted Index**

---

**Что это такое**

GIN — инвертированный индекс. Название "инвертированный" пришло из информационного поиска: вместо того чтобы хранить "документ → список слов", GIN хранит "слово → список документов где оно встречается".

Аналогия: оглавление книги ведёт тебя от главы к странице. Предметный указатель в конце книги — инвертированный: от термина к списку страниц где он встречается. GIN — это предметный указатель.

---

**Где используется**
```
+----------+---------------------------+----------+-----------+----------------+
| Оператор | Что проверяет             | Ключ     | Значение  | jsonb_path_ops |
+----------+---------------------------+----------+-----------+----------------+
| @>       | содержит подструктуру     | ✅ + знач | ✅ + ключ | ✅             |
| ?        | ключ существует           | ✅        | ❌        | ❌             |
| ?&       | все ключи существуют      | ✅        | ❌        | ❌             |
| ?|       | хотя бы один ключ есть    | ✅        | ❌        | ❌             |
+----------+---------------------------+----------+-----------+----------------+
```
---

**Структура**

GIN хранит словарь: каждый элемент (слово, ключ JSON, элемент массива) → список TID строк где он встречается.

```
Термин        →  Posting list (список строк)
-----------      --------------------------------
"фильм"      →  [TID:1, TID:3, TID:7, TID:12]
"триллер"    →  [TID:2, TID:7, TID:9]
"комедия"    →  [TID:1, TID:4, TID:5]
"action"     →  [TID:3, TID:6, TID:8]
```

При поиске `WHERE tags @@ 'триллер'` GIN находит "триллер" в словаре и возвращает [TID:2, TID:7, TID:9] — без перебора всей таблицы.

---

**Пример на MovieLens — полнотекстовый поиск по названиям**

В MovieLens есть `title` и `genres` в таблице `movies`. Сделаем полнотекстовый поиск.

```sql
-- Добавляем колонку tsvector (денормализованная форма для поиска)
ALTER TABLE movies ADD COLUMN search_vector tsvector;

-- Заполняем — title с весом A (важнее), genres с весом B
UPDATE movies
SET search_vector =
    setweight(to_tsvector('english', coalesce(title, '')), 'A') ||
    setweight(to_tsvector('english', coalesce(genres, '')), 'B');

-- GIN индекс на tsvector
CREATE INDEX movies_search_vector_idx
    ON movies USING GIN (search_vector);
```

**Разбор каждой строки UPDATE:**

`coalesce(title, '')` — если `title` равен NULL, подставляем пустую строку. Защита от NULL.  
`to_tsvector('english', 'Toy Story (1995)')` — преобразует строку в tsvector с учётом английской морфологии. Результат: `'1995':3 'stori':2 'toy':1`. Числа — позиции слов. Слова нормализованы: "Story" → "stori".  
`setweight(..., 'A')` и `setweight(..., 'B')` — присваивают вес. Вес A важнее чем B. При ранжировании результатов (`ts_rank`) совпадение в названии (A) даст больший вес чем совпадение в жанре (B).  
`||` — конкатенация двух tsvector. Объединяем вектор из title и вектор из genres в один.
setweight(to_tsvector('english', coalesce(title,  '')), 'A') ||
setweight(to_tsvector('english', coalesce(genres, '')), 'B')
```
Для строки `Toy Story (1995) | Adventure|Animation|Children|Comedy|Fantasy`:
```
title вектор:   `'1995':3A 'stori':2A 'toy':1A`
genres вектор:  `'adventur':1B 'anim':2B 'children':3B 'comedi':4B 'fantasi':5B`
после ||:       `'1995':3A 'adventur':4B 'anim':5B 'children':6B 'comedi':7B 'fantasi':8B 'stori':2A 'toy':1A`

Буква после позиции — это вес (A или B). Позиции второго вектора сдвигаются чтобы не пересекаться с первым.  
Для каждой из 87 585 строк: берём title и genres, преобразуем в tsvector с весами, объединяем, сохраняем в колонку `search_vector`. Это делается один раз. После этого GIN индекс строится уже на готовых векторах, и при запросах to_tsvector больше не вычисляется.
```sql
-- Найти все фильмы про toy
SELECT title, genres
FROM movies
WHERE search_vector @@ to_tsquery('english', 'toy');
```
-- Результат:
-- Toy Story (1995)           | Adventure|Animation|Children|Comedy|Fantasy
-- Toy Story 2 (1999)         | Adventure|Animation|Children|Comedy|Fantasy
-- Toy Story 3 (2010)         | Adventure|Animation|Children|Comedy|Fantasy

Найти фильмы про войну `И` будущее
```sql
SELECT title, genres
FROM movies
WHERE search_vector @@ to_tsquery('english', 'war & future');
```
```
+-------------------------------+---------------------------------+
|title                          |genres                           |
+-------------------------------+---------------------------------+
|Future War (1997)              |Action|Sci-Fi                    |
|We Are from the Future 2 (2010)|Action|Drama|Fantasy|War         |
|Future War 198X (1982)         |Action|Animation|Drama|Sci-Fi|War|
+-------------------------------+---------------------------------+
```
-- Найти фильмы про войну ИЛИ космос
```sql
SELECT title, genres
FROM movies
WHERE search_vector @@ to_tsquery('english', 'war | space') 
LIMIT 3;

```
```
+----------------------+----------------+
|title                 |genres          |
+----------------------+----------------+
|Richard III (1995)    |Drama|War       |
|Misérables, Les (1995)|Drama|War       |
|Braveheart (1995)     |Action|Drama|War|
+----------------------+----------------+

```
`to_tsquery('english', 'toy')` — преобразует строку поиска в tsquery: `'toy'`. Оператор `@@` — "совпадает ли tsvector с tsquery". `&` означает И — оба слова должны присутствовать. `|` означает ИЛИ — хотя бы одно слово.

**Как GIN обрабатывает запрос `@@ to_tsquery('toy')`:**


1. to_tsquery('toy') → лексема 'toy'
2. GIN находит 'toy' в словаре → [TID:1, TID:2, TID:3, ...]
3. Возвращает строки по TID
4. Таблица не сканируется целиком — только нужные TID

---

# Пример — поиск по JSONB

Допустим добавляем таблицу с метаданными фильмов в JSONB:

```sql
CREATE TABLE movie_meta (
    movie_id bigint REFERENCES movies(movie_id),
    meta     jsonb
);

INSERT INTO movie_meta VALUES
(1,     '{"director": "John Lasseter", "tags": ["animation", "family"]}'),
(2,     '{"director": "Joe Johnston",  "tags": ["adventure", "family"]}'),
(2571,  '{"director": "Wachowski",     "tags": ["action", "sci-fi"]}');

-- GIN индекс на jsonb
CREATE INDEX movie_meta_gin_idx
    ON movie_meta USING GIN (meta);

-- Найти фильмы с тегом "family"
SELECT movie_id FROM movie_meta
WHERE meta @> '{"tags": ["family"]}';
```
Найти фильмы где director = "Wachowski" И в tags есть "action"
```sql
SELECT movie_id FROM movie_meta
WHERE meta @> '{"director": "Wachowski", "tags": ["action"]}';
-- вернёт movie_id: 2571
```

-- Найти фильмы у которых есть ключ "director"
```sql
SELECT movie_id FROM movie_meta
WHERE meta ? 'director';
```
-- Найти фильмы у которых есть ОБА ключа
```sql
SELECT movie_id FROM movie_meta
WHERE meta ?& array['director', 'tags'];
```
Есть ли все три ключа: director, tags, year? (year ни у кого нет)
```sql
SELECT movie_id FROM movie_meta
WHERE meta ?& array['director', 'tags', 'year'];
-- вернёт пусто
```

---

**GIN vs GiST — когда что**

| | GIN | GiST |
|---|---|---|
| Скорость поиска | Быстрее | Медленнее |
| Размер индекса | Больше | Меньше |
| Скорость вставки | Медленнее | Быстрее |
| Подходит для | много элементов на строку (текст, JSONB) | геометрия, диапазоны |

GIN быстрее при поиске потому что posting list уже готов — не нужно спускаться по дереву предикатов. Но он дороже при вставке: нужно обновить posting list для каждого нового элемента.

---

**`fastupdate` — буферизация вставок**

Чтобы смягчить медленную вставку PostgreSQL буферизует изменения GIN индекса:

```sql
CREATE INDEX movies_search_vector_idx
    ON movies USING GIN (search_vector)
    WITH (fastupdate = on);  -- включено по умолчанию
```

Новые элементы сначала попадают в отдельный список pending, который сбрасывается в основной индекс при VACUUM или когда список достигает `gin_pending_list_limit` (по умолчанию 4MB). Это ускоряет вставку, но немного замедляет первый запрос который триггерит сброс.