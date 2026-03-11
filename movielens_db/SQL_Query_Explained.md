# Разбор SQL запроса — MovieLens

```sql
SELECT m.title,
       COUNT(r.rating)  AS rating_count,
       AVG(r.rating)    AS avg_rating
FROM movies m
JOIN ratings r ON r.movie_id = m.movie_id
WHERE r.rating >= 4.0
GROUP BY m.movie_id, m.title
HAVING COUNT(r.rating) >= 100
ORDER BY avg_rating DESC
LIMIT 10;
```

---

## FROM + JOIN

```sql
FROM movies m
JOIN ratings r ON r.movie_id = m.movie_id
```

Берём две таблицы и соединяем их по `movie_id`. `JOIN` (он же `INNER JOIN`) возвращает только те строки где `movie_id` есть в обеих таблицах. Фильм без ни одной оценки в результат не попадёт. `m` и `r` — псевдонимы, чтобы не писать полное имя таблицы каждый раз.

---

## WHERE

```sql
WHERE r.rating >= 4.0
```

Фильтрует строки до группировки. Из ~25 млн оценок оставляем только те где оценка >= 4.0 — это примерно 40% строк, около 10 млн.

---

## GROUP BY

```sql
GROUP BY m.movie_id, m.title
```

Группируем все оставшиеся строки по фильму. Представь промежуточную таблицу после JOIN + WHERE:

```
movie_id | title      | rating
---------+------------+-------
1        | Toy Story  | 4.0
1        | Toy Story  | 4.5
1        | Toy Story  | 5.0
2        | Jumanji    | 4.0
2        | Jumanji    | 4.5
```
```sql
`GROUP BY movie_id` собирает строки с одинаковым `movie_id` в одну группу:
```
Группа 1 (movie_id=1): три строки Toy Story
Группа 2 (movie_id=2): две строки Jumanji

Почему `movie_id` и `title` вместе — потому что `title` не агрегируется, и PostgreSQL требует либо включить его в `GROUP BY`, либо обернуть в агрегатную функцию.

---

## SELECT с агрегатными функциями

```sql
COUNT(r.rating) AS rating_count,
AVG(r.rating)   AS avg_rating
```

Агрегат — это вычисление над набором строк которое возвращает одно значение. `COUNT` и `AVG` работают внутри каждой группы отдельно:

```
Группа 1 (Toy Story)  → COUNT=3, AVG=4.5
Группа 2 (Jumanji)    → COUNT=2, AVG=4.25
```

Результат — одна строка на группу:

```
title      | rating_count | avg_rating
-----------+--------------+-----------
Toy Story  | 3            | 4.5
Jumanji    | 2            | 4.25
```

### Стандартные агрегатные функции в PostgreSQL

| Функция | Что делает |
|---|---|
| `COUNT(*)` | считает количество строк |
| `SUM(rating)` | сумма всех значений |
| `AVG(rating)` | среднее значение |
| `MAX(rating)` | максимальное значение |
| `MIN(rating)` | минимальное значение |

---

## HAVING

```sql
HAVING COUNT(r.rating) >= 100
```

Фильтрует после группировки — в отличие от `WHERE` которая фильтрует до. `WHERE` не знает про агрегаты, `HAVING` знает. Поэтому `WHERE rating >= 4.0` можно, а `WHERE COUNT(rating) >= 100` — ошибка компиляции. Убираем фильмы с малым числом оценок — иначе фильм с одной оценкой 5.0 был бы на первом месте. Из ~55 000 групп остаётся ~7 800.

---

## Порядок выполнения

```
1. FROM + JOIN  — соединяем таблицы
2. WHERE        — фильтруем строки (до группировки)
3. GROUP BY     — группируем
4. HAVING       — фильтруем группы (после группировки)
5. SELECT       — вычисляем COUNT и AVG
6. ORDER BY     — сортируем
7. LIMIT        — берём первые 10
```

---

## ORDER BY + LIMIT

```sql
ORDER BY avg_rating DESC
LIMIT 10
```

Сортируем по среднему рейтингу от большего к меньшему и берём топ-10. В плане PostgreSQL использовал `top-N heapsort` — умную сортировку которая держит в памяти только 10 строк, а не сортирует все 7 800.
