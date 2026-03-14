# Синтаксис и практика: CLUSTER

## Почему ratings не подходит для демонстрации

В таблице `ratings` PRIMARY KEY — `(user_id, movie_id)`, и данные при загрузке через `\copy` легли в том же порядке, что
в CSV-файле, а CSV отсортирован по `user_id, movie_id`. Heap уже физически упорядочен по пользователю — CLUSTER здесь
ничего не изменит.

## Честный демо-сценарий: таблица tags

Таблица `tags` имеет PRIMARY KEY `(user_id, movie_id, tag)`, но типичный запрос — «все теги пользователя,
отсортированные по времени» — требует порядка по `(user_id, ts)`. Этого порядка в heap нет, и индекса по `ts` тоже нет.
Именно здесь CLUSTER даст измеримый эффект.

## Замер ДО кластеризации

Индекса по `ts` ещё нет, поэтому планировщик вынужден использовать PK или seq scan, читая строки `user_id = ` в
произвольном физическом порядке:
```sql
SELECT COUNT(*) FROM tags;
```
2000072

```sql
SELECT user_id, COUNT(*) AS cnt
FROM tags
GROUP BY user_id
ORDER BY cnt DESC
LIMIT 3;
```

```sql
EXPLAIN (ANALYZE, BUFFERS, FORMAT TEXT)
SELECT t.movie_id, m.title, t.tag, t.ts
FROM tags t
         JOIN movies m ON t.movie_id = m.movie_id
WHERE t.user_id = 119227
ORDER BY t.ts DESC;
```
Ключевая строка на узле  
`Parallel Seq Scan on tags: Rows Removed by Filter: 425533`  
— PostgreSQL прочитал все 2 миллиона строк таблицы tags (по 241158 + 425533 = 666691 на каждый из трёх воркеров), 
чтобы отфильтровать 723к строк пользователя 119227.  
`Buffers: shared hit=64 read=14543` — 14 543 страниц с диска. Это и есть random I/O по всему heap.

## Создание индекса и кластеризация

Создаём индекс по `(user_id, ts)` — без него `CLUSTER` не запустить:

```sql
CREATE INDEX idx_tags_user_ts ON tags (user_id, ts);
```

Физически переупорядочиваем heap по этому индексу. Команда берёт `ACCESS EXCLUSIVE` блокировку на всё время выполнения —
таблица недоступна ни для чтения, ни для записи:

```sql
CLUSTER tags USING idx_tags_user_ts;
```

Обновляем статистику — без этого планировщик будет работать с устаревшими оценками селективности:

```sql
ANALYZE tags;
```

## Замер ПОСЛЕ кластеризации

Тот же запрос — смотрим на `Buffers: shared hit` у узла сканирования `tags`. Все строки `user_id = 119227` теперь лежат
физически рядом, поэтому количество затронутых страниц должно упасть в разы:  
**Heap Blocks: exact=44** у узла **Bitmap Heap Scan on tags** — это и показывает, что все строки пользователя уместились на 44 соседних страницах heap. До кластеризации это число было бы в сотни раз больше. movies и индексные страницы к CLUSTER отношения не имеют.  
`Heap Blocks: exact=44` появляется только когда работает `Bitmap Heap Scan`
```sql
EXPLAIN (ANALYZE, BUFFERS, FORMAT TEXT)
SELECT t.movie_id, m.title, t.tag, t.ts
FROM tags t
         JOIN movies m ON t.movie_id = m.movie_id
WHERE t.user_id = 119227
ORDER BY t.ts DESC;
```

## Повторная кластеризация

PostgreSQL запоминает индекс кластеризации в `pg_class`. Повторный запуск — например, по ночному расписанию — можно
делать без `USING`:

```sql
CLUSTER tags;
```

## Проверка текущего индекса кластеризации

```sql
SELECT relname,
       (SELECT indexrelid::regclass
        FROM pg_index
        WHERE indrelid = pg_class.oid
          AND indisclustered) AS cluster_index
FROM pg_class
WHERE relname = 'tags';
```

Если `cluster_index` вернёт `NULL` — таблица либо никогда не кластеризовалась, либо индекс был удалён после
кластеризации.

```sql
DROP INDEX idx_tags_user_ts;
```