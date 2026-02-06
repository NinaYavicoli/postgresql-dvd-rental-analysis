DROP TABLE IF EXISTS detailed_duration; 
DROP TABLE IF EXISTS summary_duration; 

-- function that changes the rental duration to a SMALLINT reflecting days instead of a timestamp -- 
CREATE OR REPLACE FUNCTION calc_actual_rental_days(
    p_rental_date TIMESTAMP,
    p_return_date TIMESTAMP
)
RETURNS SMALLINT
LANGUAGE plpgsql
AS $$
BEGIN
    IF p_return_date IS NULL THEN
        RETURN NULL;
    END IF;

    RETURN (p_return_date::date - p_rental_date::date)::SMALLINT;
END;
$$;

-- test duration function (should output 4) -- 
SELECT calc_actual_rental_days(
    '2024-01-01'::timestamp,
    '2024-01-05'::timestamp
);

-- function that formats rental month as YYYY-MM -- 
CREATE OR REPLACE FUNCTION rental_month(p_rental_date TIMESTAMP)
RETURNS TEXT 
LANGUAGE plpgsql
AS $$
BEGIN 
	RETURN TO_CHAR(p_rental_date, 'YYYY-MM'); 
END; 
$$;

--test rental month function (should return 2000-10) -- 
SELECT rental_month('2000-10-17'::timestamp);

-- detailed table creation --
CREATE TABLE detailed_duration( 
rental_id INT, 
rental_date TIMESTAMP NOT NULL, 
return_date TIMESTAMP NULL,
actual_rental_days SMALLINT, 
rental_month TEXT NOT NULL, 
film_id INT NOT NULL, 
film_title VARCHAR(50) NOT NULL
); 


-- summary table creation -- 
CREATE TABLE summary_duration( 
film_id INT, 
film_title VARCHAR(50), 
avg_rental_days NUMERIC(10,2), 
avg_rentals_per_month NUMERIC(10,2)
);

-- make sure all tables have been created -- 
SELECT * FROM detailed_duration; 
SELECT * FROM summary_duration; 

-- create trigger to update summary with detailed report -- 
CREATE OR REPLACE FUNCTION duration_trigger_function()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    DELETE FROM summary_duration;

    INSERT INTO summary_duration (
        film_id,
        film_title,
        avg_rental_days,
        avg_rentals_per_month
    )
    SELECT
        film_id,
        film_title,
        AVG(actual_rental_days)::numeric(10,2) AS avg_rental_days,
        (COUNT(*)::numeric / NULLIF(COUNT(DISTINCT rental_month), 0))::numeric(10,2)
            AS avg_rentals_per_month
    FROM detailed_duration
    WHERE actual_rental_days IS NOT NULL
    GROUP BY film_id, film_title
    ORDER BY avg_rentals_per_month DESC;

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS updated_summary_duration ON detailed_duration;

CREATE TRIGGER updated_summary_duration
AFTER INSERT
ON detailed_duration
FOR EACH STATEMENT
EXECUTE FUNCTION duration_trigger_function();

-- check to see if trigger was created successfully -- 
SELECT tgname
FROM pg_trigger
WHERE tgname = 'updated_summary_duration';

-- load raw data into detailed table -- 
INSERT INTO detailed_duration
SELECT
  r.rental_id,
  r.rental_date,
  r.return_date,
  calc_actual_rental_days(r.rental_date, r.return_date) AS actual_rental_days,
  rental_month(r.rental_date) AS rental_month,
  f.film_id,
  f.title AS film_title
FROM rental r
JOIN inventory i ON r.inventory_id = i.inventory_id
JOIN film f ON i.film_id = f.film_id;

-- verify data in summary table -- 
SELECT COUNT(*) FROM summary_duration


-- refresh tables procedure -- 
CREATE OR REPLACE PROCEDURE refresh_tables()
LANGUAGE plpgsql
AS $$
BEGIN 
	DELETE FROM detailed_duration; 
	DELETE FROM summary_duration; 

	INSERT INTO detailed_duration( 
	rental_id, 
	rental_date, 
	return_date, 
	actual_rental_days, 
	rental_month,
	film_id, 
	film_title
	)
	SELECT
	r.rental_id, 
	r.rental_date, 
	r.return_date, 
	calc_actual_rental_days(r.rental_date, r.return_date), 
	rental_month(r.rental_date),
	f.film_id, 
	f.title
FROM rental r
JOIN inventory i ON r.inventory_id = i.inventory_id
JOIN film f ON i.film_id = f.film_id; 

END; 
$$; 

CALL refresh_tables(); 

-- test refresh -- 
SELECT COUNT(*) FROM detailed_duration -- 16044 --
SELECT COUNT(*) FROM summary_duration  -- 958 --

-- insert test values into detailed table -- 
INSERT INTO detailed_duration (rental_id,rental_date,return_date,actual_rental_days,rental_month,film_id,film_title)
VALUES (999999,'2000-10-17','2000-10-27',10,'2000-10',999999,'TEST FILM');

-- row count goes up by 1 for each -- 
SELECT COUNT(*) FROM detailed_duration
SELECT COUNT(*) FROM summary_duration

CALL refresh_tables(); 


-- shows both summary and detailed table -- 
SELECT *
FROM detailed_duration
WHERE actual_rental_days IS NOT NULL
ORDER BY actual_rental_days DESC
LIMIT 20; 

SELECT *
FROM summary_duration
ORDER BY avg_rentals_per_month DESC
LIMIT 20; 



