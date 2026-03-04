CREATE TABLE movies (
                        movie_id   INTEGER PRIMARY KEY,
                        title      TEXT    NOT NULL,
                        genres     TEXT    NOT NULL
);

CREATE TABLE ratings (
                         user_id    INTEGER        NOT NULL,
                         movie_id   INTEGER        NOT NULL REFERENCES movies(movie_id),
                         rating     NUMERIC(2,1)   NOT NULL CHECK (rating BETWEEN 0.5 AND 5.0),
                         ts         BIGINT         NOT NULL,
                         PRIMARY KEY (user_id, movie_id)
);

CREATE TABLE tags (
                      user_id    INTEGER NOT NULL,
                      movie_id   INTEGER NOT NULL REFERENCES movies(movie_id),
                      tag        TEXT    NOT NULL,
                      ts         BIGINT  NOT NULL,
                      PRIMARY KEY (user_id, movie_id, tag)
);

CREATE TABLE links (
                       movie_id   INTEGER PRIMARY KEY REFERENCES movies(movie_id),
                       imdb_id    TEXT,
                       tmdb_id    TEXT
);

-- Загрузка данных (\copy работает на стороне клиента — не нужны права суперпользователя)
-- \copy movies(movie_id, title, genres)        FROM '/Users/olga/DataGripProjects/ml-32m/movies.csv'  CSV HEADER ENCODING 'UTF8'
-- \copy ratings(user_id, movie_id, rating, ts) FROM '/Users/olga/DataGripProjects/ml-32m/ratings.csv' CSV HEADER ENCODING 'UTF8'
-- \copy tags(user_id, movie_id, tag, ts)       FROM '/Users/olga/DataGripProjects/ml-32m/tags.csv'    CSV HEADER ENCODING 'UTF8'
-- \copy links(movie_id, imdb_id, tmdb_id)      FROM '/Users/olga/DataGripProjects/ml-32m/links.csv'   CSV HEADER ENCODING 'UTF8'
SELECT 'movies'  AS таблица, COUNT(*) AS строк FROM movies
UNION ALL
SELECT 'ratings',            COUNT(*)           FROM ratings
UNION ALL
SELECT 'tags',               COUNT(*)           FROM tags
UNION ALL
SELECT 'links',              COUNT(*)           FROM links;

-- Ожидаемый результат:
--   таблица  |  строк
---------+----------
--  movies    |    87585
--  ratings   | 32000204
--  tags      |  2000072
--  links     |    87585