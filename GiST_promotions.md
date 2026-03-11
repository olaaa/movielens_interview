# GiST — Generalized Search Tree

```sql
DROP TABLE IF EXISTS promotion CASCADE;
```
```sql
CREATE TABLE promotion (
id          bigserial PRIMARY KEY,
movie_id    bigint REFERENCES movies(movie_id),
description text,
active_during daterange   -- временной диапазон акции
);
```

GiST индекс на диапазон
```sql
CREATE INDEX promotion_active_during_idx
    ON promotion USING GIST (active_during);
```
-- Какие акции активны прямо сейчас?
```sql
SELECT p.description, m.title
FROM promotion p
JOIN movies m ON m.movie_id = p.movie_id
WHERE active_during @> '2025-01-01'::date;
```
-- Какие акции пересекаются с праздничным периодом?
WHERE active_during && '[2024-12-20, 2025-01-10)'::tsrange;

```sql
INSERT INTO promotion (movie_id, description, active_during) VALUES
-- Новогодняя акция на Toy Story
(1,    'Новогодняя скидка',        '[2024-12-20, 2025-01-10)'),
-- Летняя акция на Jumanji
(2,    'Летний марафон',           '[2024-06-01, 2024-08-31)'),
-- Хэллоуин на GoodFellas
(4993, 'Хэллоуин: криминал',      '[2024-10-25, 2024-11-01)'),
-- Текущая акция на Matrix
(2571, 'Месяц sci-fi',            '[2025-01-01, 2025-03-31)'),
-- Будущая акция на Inception
(79132,'Премиум декабрь',         '[2025-12-01, 2025-12-31)');
```

Теперь демонстрируем запросы:

```sql
-- Какие акции пересекались с новогодним периодом?
SELECT p.description, m.title, p.active_during
FROM promotion p
JOIN movies m ON m.movie_id = p.movie_id
WHERE active_during && '[2024-12-01, 2025-01-31)'::daterange;

-- Результат:
-- Новогодняя скидка  | Toy Story  | [2024-12-20, 2025-01-10)
-- Месяц sci-fi       | Matrix     | [2025-01-01, 2025-03-31)
```

```sql
-- Какие акции будут активны в декабре 2025?
SELECT p.description, m.title, p.active_during
FROM promotion p
JOIN movies m ON m.movie_id = p.movie_id
WHERE active_during && '[2025-12-01, 2025-12-31)'::daterange;

-- Результат:
-- Премиум декабрь | Inception | [2025-12-01, 2025-12-31)
```

GiST индекс при `&&` и `@>` отсекает нерелевантные поддеревья по bbox — не читает все 5 строк, а спускается только по тем узлам чей диапазон пересекается с искомым.