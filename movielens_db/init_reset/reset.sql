-- ============================================================
-- reset.sql — удаляет все кастомные индексы на таблицах MovieLens
-- Оставляет только PRIMARY KEY индексы (*_pkey)
-- Запускать перед каждой новой демонстрацией
-- ============================================================

-- Посмотреть что сейчас висит (перед удалением)
SELECT tablename, indexname, indexdef
FROM pg_indexes
WHERE tablename IN ('movies', 'ratings', 'tags', 'links')
  AND indexname NOT LIKE '%_pkey'
ORDER BY tablename, indexname;

-- Удалить все кастомные индексы
DO $$
DECLARE
    r RECORD;
BEGIN
    FOR r IN
        SELECT indexname
        FROM pg_indexes
        WHERE tablename IN ('movies', 'ratings', 'tags', 'links')
          AND indexname NOT LIKE '%_pkey'
    LOOP
        EXECUTE 'DROP INDEX IF EXISTS ' || r.indexname;
        RAISE NOTICE 'Dropped: %', r.indexname;
    END LOOP;
END;
$$;

-- Проверить что осталось — должны быть только *_pkey
SELECT tablename, indexname
FROM pg_indexes
WHERE tablename IN ('movies', 'ratings', 'tags', 'links')
ORDER BY tablename, indexname;

-- ============================================================
-- Также удаляем тестовые таблицы если они были созданы
-- ============================================================

DROP TABLE IF EXISTS promotion;
DROP TABLE IF EXISTS product_tariff;
DROP TABLE IF EXISTS movie_meta;
DROP TABLE IF EXISTS payments;
DROP TABLE IF EXISTS loan_applications;
DROP TABLE IF EXISTS transactions;

-- ============================================================
-- Также сбрасываем колонку featured если была добавлена
-- ============================================================

ALTER TABLE ratings DROP COLUMN IF EXISTS featured;
ALTER TABLE movies  DROP COLUMN IF EXISTS search_vector;
