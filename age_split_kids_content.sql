------- Ages of kids for different content
--Identify kids accounts and their linked parent
DROP TABLE IF EXISTS vb_kids_hids;
CREATE TABLE dataforce_sandbox.vb_kids_hids AS
SELECT distinct bbc_hid3 as child, age::integer as age, isparent, ischild, profile_admin_bbc_hid3 as parent
FROM prez.id_profile
WHERE status != 'deleted'
and profile_admin_bbc_hid3 is not null
;

SELECt * FROM dataforce_sandbox.vb_kids_hids LIMIT 10;
--How many are there?
SELECT count(*) as rows,                    --1,234,018
       count(distinct child) as children,   --1,234,018
       count(distinct parent) as parents    --  964,017
FROM dataforce_sandbox.vb_kids_hids
;
-- Simple vmb
DROP TABLE IF EXISTS vb_vmb;
CREATE TEMP TABLE vb_vmb as
SELECT distinct master_brand_name,
                brand_title,
                brand_id,
                series_title,
                series_id,
                episode_title,
                episode_id,
                CASE
                    WHEN brand_title != 'null' and brand_title IS NOT NULL then brand_title
                    WHEN (brand_title = 'null' or brand_title ISNULL) AND series_title != 'null' and
                         series_title IS NOT NULL THEN series_title
                    WHEN (brand_title = 'null' or brand_title ISNULL) AND
                         (series_title = 'null' or series_title IS NULL) AND episode_title != 'null' AND
                         episode_title IS NOT NULL THEN episode_title
                    END as prog_title
FROM prez.scv_vmb;

SELECT * from vb_vmb LIMIT 20;

-- from the journey table just those kids profiles
DROP TABLE dataforce_sandbox.vb_kids_journey;
CREATE TABLE dataforce_sandbox.vb_kids_journey AS
SELECT *,
              CASE
           WHEN content_id in (select distinct brand_id from vb_vmb) then 'brand'
           WHEN content_id in (select distinct series_id from vb_vmb) then 'series'
           WHEN content_id in (select distinct episode_id from vb_vmb) then 'episode'
           ELSE 'unknown' end as id_type
FROM central_insights_sandbox.vb_journey_start_watch_complete a
         JOIN dataforce_sandbox.vb_kids_hids b on a.hashed_id = b.child
WHERE a.dt between 20210120 and 20210220
;

--how many clicks are each type? --97% are episode
SELECT id_type, count(*)
from dataforce_sandbox.vb_kids_journey
group by 1;

--Create TABLE of content
DROP TABLE IF eXISTS dataforce_sandbox.vb_kids_viewing;
CREATE TABLE dataforce_sandbox.vb_kids_viewing as
SELECT dt,
       hashed_id,
       age,
       app_type,
       content_id,
       id_type,
       b.master_brand_name,
       prog_title,
       brand_title,
       start_flag,
       complete_flag
FROM dataforce_sandbox.vb_kids_journey a
         LEFT JOIN vb_vmb b ON a.content_id = b.episode_id
WHERE id_type = 'episode'
;
GRANT ALL on dataforce_sandbox.vb_top_kids_brands to jana_eggink;

DROP TABLE IF EXISTS dataforce_sandbox.vb_top_kids_brands;
CREATE TABLE dataforce_sandbox.vb_top_kids_brands as
with grouped AS (
    SELECT
           app_type,
           age,
           master_brand_name,
           prog_title,
           count(*)           as clicks,
           sum(start_flag)    as starts,
           sum(complete_flag) as completes

    FROM dataforce_sandbox.vb_kids_viewing
    GROUP BY 1, 2, 3, 4),
     ranked as (
         SELECT *,
                row_number()
                over ( partition by app_type, age, master_brand_name order by clicks desc ) as rank_by_click
         from grouped
     )
SELECT *
FROM ranked
WHERE rank_by_click <= 20
AND master_brand_name in('CBeebies', 'CBBC', 'BBC Bitesize', 'BBC One');

SELECT * FROM dataforce_sandbox.vb_top_kids_brands;
SELECT count(distinct hashed_id) FROM dataforce_sandbox.vb_kids_viewing;