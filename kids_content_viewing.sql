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

/*
Need to see how much viewing of kids content there was on those adult accounts before they created a child account,
and now after they have a child.

Look at clicks/starts/completes to the CBBC/Cbeebies content by day for those users and see how it changes.
Could try and use the date they created the kids account but that would be different for everyone.
*/
-- journey table goes back to 2020-06-01
SELECT *--min(dt)
FROM central_insights_sandbox.dataforce_journey_start_watch_complete
LIMIT 10;

DROP TABLE if exists dataforce_sandbox.vb_vmb_temp;
CREATE TABLE dataforce_sandbox.vb_vmb_temp as
SELECT distinct master_brand_name, brand_title, brand_id, series_title, series_id, episode_title, episode_id
FROM prez.scv_vmb
WHERE master_brand_name in ('CBBC', 'CBeebies');

SELECT distinct master_brand_name, --brand_title, brand_id, series_title, series_id, episode_title, episode_id,
                split_part(pips_genre_level_1_names, ';', 1) as simple_genre
FROM prez.scv_vmb
WHERE simple_genre ILIKE 'Children%' or simple_genre ILIKE 'Learning%'
LIMIT 100;--childrens or learning

SELECT distinct master_brand_name FROM dataforce_sandbox.vb_vmb_temp LIMIT 10;

--- Adult viewing over time
DROP TABLE IF EXISTS dataforce_sandbox.vb_parent_viewing;
CREATE TABLE dataforce_sandbox.vb_parent_viewing AS
SELECT dt,
       hashed_id,
       visit_id,
       app_type,
       click_placement,
       content_id,
       c.master_brand_name,
       c.brand_title,
       CASE WHEN start_flag = 'iplxp-ep-started' then 1 ELSE 0 END   as start_flag,
       CASE WHEN watched_flag = 'iplxp-ep-watched' THEN 1 ELSE 0 END as complete_flag
FROM central_insights_sandbox.dataforce_journey_start_watch_complete a
JOIN (select distinct parent from dataforce_sandbox.vb_kids_hids) b on a.hashed_id = b.parent
JOIN (select distinct master_brand_name, brand_title,episode_id from dataforce_sandbox.vb_vmb_temp) c on a.content_id = c.episode_id
;
SELECT * FROM  dataforce_sandbox.vb_parent_viewing LIMIT 100;

DROP TABLE IF EXISTS dataforce_sandbox.vb_parent_viewing_summary;
CREATE TABLE dataforce_sandbox.vb_parent_viewing_summary AS
SELECT dt,
       master_brand_name,
       app_type,
       count(distinct hashed_id) as parents,
       count(distinct dt||visit_id) as parent_visits,
       count(*) as parent_clicks,
       sum(start_flag) as parent_starts,
       sum(complete_flag) as parent_completes
FROM dataforce_sandbox.vb_parent_viewing
GROUP BY 1,2,3
ORDER BY 1,2;

--- Child viewing over time
DROP TABLE IF EXISTS dataforce_sandbox.vb_child_viewing;
CREATE TABLE dataforce_sandbox.vb_child_viewing AS
SELECT dt,
       hashed_id,
       visit_id,
       app_type,
       click_placement,
       content_id,
       c.master_brand_name,
       c.brand_title,
       b.age,
       CASE WHEN start_flag = 'iplxp-ep-started' then 1 ELSE 0 END   as start_flag,
       CASE WHEN watched_flag = 'iplxp-ep-watched' THEN 1 ELSE 0 END as complete_flag
FROM central_insights_sandbox.dataforce_journey_start_watch_complete a
JOIN (select distinct child,age from dataforce_sandbox.vb_kids_hids) b on a.hashed_id = b.child
JOIN (select distinct master_brand_name, brand_title,episode_id from dataforce_sandbox.vb_vmb_temp) c on a.content_id = c.episode_id
;


DROP TABLE IF eXISTS dataforce_sandbox.vb_child_viewing_summary;
CREATE TABLE dataforce_sandbox.vb_child_viewing_summary as
SELECT dt,
       master_brand_name,
       app_type,
       age,
       count(distinct hashed_id) as children,
       count(distinct dt||visit_id) as child_visits,
       count(*) as child_clicks,
       sum(start_flag) as child_starts,
       sum(complete_flag) as child_completes
FROM dataforce_sandbox.vb_child_viewing
GROUP BY 1,2,3,4
ORDER BY 1,2;


SELECT * FROM dataforce_sandbox.vb_parent_viewing_summary limit 10;

CREATE TABLE dataforce_sandbox.vb_parent_child_viewing as
SELECT a.*, b.children, b.child_visits, b.child_clicks, b.child_starts, b.child_completes
FROM dataforce_sandbox.vb_parent_viewing_summary a
         join dataforce_sandbox.vb_child_viewing_summary b
              on a.dt = b.dt and a.app_type = b.app_type and a.master_brand_name = b.master_brand_name
;
SELECT * FROM dataforce_sandbox.vb_parent_child_viewing LIMIT 10;


-- What is the split of kids viewing on different platforms
DROP TABLE dataforce_sandbox.vb_kids_content_per_platform;
CREATE TABLE dataforce_sandbox.vb_kids_content_per_platform AS
with kids_viewing AS (
    SELECT dt,
           hashed_id,
           visit_id,
           app_type,
           age_range,
           click_placement,
           content_id,
           c.master_brand_name,
           c.brand_title,
           start_flag,
           complete_flag
    FROM central_insights_sandbox.vb_journey_start_watch_complete a
             JOIN (select distinct master_brand_name, brand_title, episode_id from dataforce_sandbox.vb_vmb_temp) c
                  on a.content_id = c.episode_id

)
SELECT dt,
       age_range,
       app_type,
       master_brand_name,
       count(distinct dt||visit_id) as child_visits,
       count(*)           as child_clicks,
       sum(start_flag)    as child_starts,
       sum(complete_flag) as child_completes
FROM kids_viewing
GROUP BY 1, 2, 3, 4;


--- how many starts per day?
SELECT dt, hashed_id, app_type, master_brand_name, sum(start_flag) as starts
FROM dataforce_sandbox.vb_child_viewing
GROUP BY 1, 2, 3, 4
LIMIT 10;


SELECT * FROM s3_audience.publisher WHERE dt = 20190906 AND destination = 'PS_IPLAYER' LIMIT 20;

-------- How much kids viewing was there?
--CREATE TABLE dataforce_sandbox.vb_kids_starts AS
INSERT INTO dataforce_sandbox.vb_kids_starts
with daily_starts as (
    SELECT a.dt,
           CASE WHEN a.attribute = 'iplxp-ep-started' THEN 1 ELSE 0 END starts,
           a.result               as                                    content_id,
           b.master_brand_name,
           CASE
               wHEN metadata ILIKE '%bigscreen%' then 'tv'
               WHEN metadata ILIKE '%responsive%' then 'web'
               WHEN metadata ILIKE '%mobile%' then 'mobile'
               else 'unknown' END as                                    platform
    FROM s3_audience.publisher a
             JOIN dataforce_sandbox.vb_vmb_temp b on a.result = b.episode_id
    WHERE attribute = 'iplxp-ep-started'
      AND dt = 20190908
      AND destination = 'PS_IPLAYER'
)
SELECT dt, master_brand_name, platform, sum(starts) as starts
FROM daily_starts
GROUP BY 1, 2,3;
GRANT ALL ON dataforce_sandbox.vb_kids_starts to GROUP central_insights_server;

SELECT distinct dt, count(*) FROM dataforce_sandbox.vb_kids_starts group by 1 order by dt ;


GRANT ALL on dataforce_sandbox.vb_child_viewing TO GROUP central_insights_server;
GRANT ALL on dataforce_sandbox.vb_vmb_temp TO GROUP central_insights_server;

SELECT min(dt) FROM central_insights_sandbox.vb_journey_start_watch_complete;
SELECT * FROM central_insights_sandbox.dataforce_journey_start_watch_complete limit 10;

---Average monthly values
with data as (
    SELECT split_part(dt::date, '-', 1) as year,
           split_part(dt::date, '-', 2) as month,
           split_part(dt::date, '-', 3) as day,
           sum(parents)                 as parents,
           sum(parent_visits)           as parent_visits,
           sum(parent_clicks)           as parent_clicks,
           sum(parent_starts)           as parent_starts,
           sum(parent_completes)           as parent_completes,
           sum(children)                as children,
           sum(child_visits)            as child_visits,
           sum(child_clicks)            as child_clicks,
           sum(child_starts)            as child_starts,
           sum(child_completes)           as child_completes
    FROM dataforce_sandbox.vb_parent_child_viewing
    WHERE app_type = 'bigscreen-html'
    GROUP BY 1, 2, 3
)
SELECT year,
       month,
       round(avg(parents), -3)       as parents,
       round(avg(parent_visits), -3) as parent_visits,
       round(avg(parent_clicks), -3) as parent_clicks,
       round(avg(parent_starts), -3) as parent_starts,
       round(avg(parent_completes), -3) as parent_completes,
       round(avg(children), -3)      as children,
       round(avg(child_visits), -3)  as child_visits,
       round(avg(child_clicks), -3)  as child_clicks,
       round(avg(child_starts), -3)  as child_starts,
       round(avg(child_completes), -3) as child_completes
FROM data
GROUP BY 1, 2
ORDEr BY 1, 2
LIMIT 10;

SELECT min(dt) FROM dataforce_sandbox.vb_parent_child_viewing
WHERE app_type = 'bigscreen-html'
LIMIT 10;



---- Do parents with kids accounts still watch kids things?
SELECT * FROM dataforce_sandbox.vb_parent_viewing LIMIT 10;
SELECT * FROM dataforce_sandbox.vb_child_viewing LIMIT 10;
SELECT * FROM dataforce_sandbox.vb_kids_hids LIMIT 10;

--CREATE TABLE dataforce_sandbox.vb_adults_daily as

with adult_daily_totals AS (
    SELECT dt, hashed_id, sum(start_flag) as starts
    FROM dataforce_sandbox.vb_parent_viewing
    WHERE app_type = 'bigscreen-html'
    GROUP BY 1, 2
)
SELECT dt, hashed_id, case when starts > 0 then 1 else 0 end as viewing
from adult_daily_totals;


GRANT ALL on dataforce_sandbox.vb_parent_viewing to group central_insights_server;
GRANT ALL on dataforce_sandbox.vb_child_viewing to group central_insights_server;
GRANT ALL on dataforce_sandbox.vb_kids_hids to group central_insights_server;


with adult_daily_totals AS (
    SELECT dt, hashed_id, sum(start_flag) as starts
    FROM dataforce_sandbox.vb_parent_viewing
    WHERE app_type = 'bigscreen-html'
      and dt = '20210307'
    GROUP BY 1, 2
)
SELECT dt, hashed_id, case when starts > 0 then 1 else 0 end as viewing
from adult_daily_totals;

SELECT distinct  parent, child, age FROM dataforce_sandbox.vb_kids_hids LIMIT 10;
SELECT min(dt) from dataforce_sandbox.vb_child_viewing;


------- In R we took all the adults and for every day gave them a 1 if they viewed anything from CBBC or Cbeeies
SELECt * FROM central_insights_sandbox.vb_adult_viewing_daily LIMIT 10;