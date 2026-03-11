Да, это был `EXCLUDE USING GIST` — constraint который не даёт вставить пересекающиеся диапазоны для одного продукта. Вот полный пример с демонстрацией нарушения:
```sql
CREATE SCHEMA product_tariff;
```
```sql
-- Сначала устанавливаем расширение
set search_path = "product_tariff";
CREATE EXTENSION IF NOT EXISTS btree_gist;
```
```sql
CREATE TABLE product_tariff (
    product_id  bigint,
    valid_range daterange,
    rate        numeric,
    EXCLUDE USING GIST (
        product_id WITH =,
        valid_range WITH &&
    )
);
```

Вставляем корректные данные — диапазоны не пересекаются:

```sql
INSERT INTO product_tariff VALUES (1, '[2024-01-01, 2024-06-01)', 5.0);
INSERT INTO product_tariff VALUES (1, '[2024-06-01, 2024-12-31)', 7.5);
INSERT INTO product_tariff VALUES (2, '[2024-01-01, 2024-12-31)', 3.0);
```

Пытаемся вставить тариф для product_id=1 который пересекается с уже существующим:

```sql
INSERT INTO product_tariff VALUES (1, '[2024-05-01, 2024-07-01)', 6.0);
```

ERROR:  conflicting key value violates exclusion constraint "product_tariff_product_id_valid_range_excl"
DETAIL:  Key (product_id, valid_range)=(1, [2024-05-01,2024-07-01))
         conflicts with existing key (product_id, valid_range)=(1, [2024-01-01,2024-06-01)).

Диапазон `[2024-05-01, 2024-07-01)` пересекается (`&&`) с `[2024-01-01, 2024-06-01)` у того же `product_id=1` — PostgreSQL блокирует вставку.

# SELECT
```sql
-- Все записи — смотрим что есть
SELECT product_id, valid_range, rate
FROM product_tariff
ORDER BY product_id, valid_range;
```

```
 product_id |       valid_range        | rate
------------+--------------------------+------
          1 | [2024-01-01,2024-06-01)  |  5.0
          1 | [2024-06-01,2024-12-31)  |  7.5
          2 | [2024-01-01,2024-12-31)  |  3.0
```

---
`@>` — оператор "содержит".
Для диапазонов читается как "диапазон слева содержит значение справа". То есть проверяет что значение находится внутри диапазона.
```sql
-- Какой тариф действует для product_id=1 на конкретную дату?
SELECT product_id, valid_range, rate
FROM product_tariff
WHERE product_id = 1
  AND valid_range @> '2024-03-15'::date;
```

```
 product_id |       valid_range        | rate
------------+--------------------------+------
          1 | [2024-01-01,2024-06-01)  |  5.0
```
@> '2024-03-15'  →  true   -- 2024-03-15 внутри диапазона
@> '2024-07-01'  →  false  -- 2024-07-01 за пределами
```sql
-- Какие тарифы содержатся в периоде за квартал?
SELECT product_id, valid_range, rate
FROM product_tariff
WHERE '[2024-04-01, 2024-08-01)'::daterange @> valid_range;
```
Результат: пустая строка

---
Отличие: `&&` проверяет пересечение (хоть один общий день), `@>` проверяет полное вхождение (один диапазон полностью внутри другого).
```sql
-- Какие тарифы пересекаются с периодом [2024-05-01, 2024-07-01)?
SELECT product_id, valid_range, rate
FROM product_tariff
WHERE valid_range && '[2024-05-01, 2024-07-01)'::daterange;
```

```
 product_id |       valid_range        | rate
------------+--------------------------+------
          1 | [2024-01-01,2024-06-01)  |  5.0
          1 | [2024-06-01,2024-12-31)  |  7.5
          2 | [2024-01-01,2024-12-31)  |  3.0
```

---

```