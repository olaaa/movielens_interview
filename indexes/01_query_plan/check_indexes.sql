SELECT indexname, indexdef
FROM pg_indexes
WHERE tablename IN ('movies', 'ratings', 'tags', 'links')
ORDER BY tablename, indexname;

-- links_pkey,CREATE UNIQUE INDEX links_pkey ON public.links USING btree (movie_id)
-- movies_pkey,CREATE UNIQUE INDEX movies_pkey ON public.movies USING btree (movie_id)
-- ratings_pkey,"CREATE UNIQUE INDEX ratings_pkey ON public.ratings USING btree (user_id, movie_id)"
-- tags_pkey,"CREATE UNIQUE INDEX tags_pkey ON public.tags USING btree (user_id, movie_id, tag)"

EXPLAIN ANALYZE
SELECT m.title,
       COUNT(r.rating)  AS rating_count,
       AVG(r.rating)    AS avg_rating
FROM ratings r
         JOIN movies m ON m.movie_id = r.movie_id
WHERE r.rating >= 4.0
GROUP BY m.movie_id, m.title
HAVING COUNT(r.rating) >= 100
ORDER BY avg_rating DESC
LIMIT 10; -- 7 сек, после добавления индекса -- 2,5 сек

-- Для нашего запроса PostgreSQL может сделать Index Only Scan — взять movie_id и rating прямо из индекса,
-- не ходя в heap вообще.
-- JOIN по movie_id и фильтр rating >= 4.0 — всё есть в индексе. Heap не нужен.
CREATE INDEX ratings_movie_rating_idx ON ratings(movie_id, rating);

