# Partial индекс — ratings (MovieLens)

## DDL — добавляем колонку featured в таблицу ratings
rating -- это оценки. то, что ставят пользователи.  
featured в данном контексте переводится как "рекомендуемый" или "выделенный".
В контексте кино/стриминга — это фильмы которые редакция или алгоритм пометил как рекомендованные к показу. 
Например на главной странице Netflix есть блок "Featured" — это не просто популярные фильмы, а специально отобранные для продвижения.

```sql
ALTER TABLE ratings ADD COLUMN IF NOT EXISTS featured boolean DEFAULT false;
```
### До использования частичного индекса:
```sql
EXPLAIN ANALYZE
SELECT movie_id, count(*) AS cnt
FROM ratings
WHERE featured = true
GROUP BY movie_id
ORDER BY cnt DESC;
```
->  Parallel Seq Scan on ratings  (cost=0.00..339568.96 rows=6714398 width=4) (actual time=7.100..15776.438 rows=73579 loops=3)  
7.100     — время до первой отданной строки: 7 мс  
15776.438 — время до последней строки: 15 776 мс = ~15.7 секунд

## Partial индекс — только рекомендуемые оценки
movie_id в индексе — потому что запросу нужна группировка по movie_id. Данные в индексе уже лежат в нужном порядке 
    — группировка "бесплатная".
```sql
CREATE INDEX ratings_featured_idx
    ON ratings(movie_id)
    WHERE featured = true;
```

## Помечаем фильмы как рекомендуемые

Toy Story (1995) — movie_id = 1:

```sql
UPDATE ratings SET featured = true WHERE movie_id = 1;
```

The Matrix (1999) — movie_id = 2571:

```sql
UPDATE ratings SET featured = true WHERE movie_id = 2571;
```

Inception (2010) — movie_id = 79132:

```sql
UPDATE ratings SET featured = true WHERE movie_id = 79132;
```

## Проверочные запросы

Сколько строк помечено как featured?

```sql
SELECT movie_id, count(*) AS cnt
FROM ratings
WHERE featured = true
GROUP BY movie_id
ORDER BY cnt DESC;
```

## Убедиться что индекс используется:

```sql
EXPLAIN ANALYZE
SELECT movie_id, count(*) AS cnt
FROM ratings
WHERE featured = true
GROUP BY movie_id
ORDER BY cnt DESC;
```
В 30 раз быстрее. Индекс нашёл 220 736 TID, но после обращения к heap осталось 73 579 строк. Это Recheck Cond: 
featured — при Bitmap Heap Scan PostgreSQL перепроверяет условие на уровне heap потому что Bitmap работает с гранулярностью страниц, 
а не строк. Некоторые страницы содержат как featured = true так и featured = false — лишние отсеиваются при Recheck.