-- Grain: one row per calendar day, 2016-01-01 to 2018-12-31.
-- Orders run from 2016-09-04 to 2018-10-17; full years keep every month complete.

with spine as (

    {{ dbt_utils.date_spine(
        datepart="day",
        start_date="cast('2016-01-01' as date)",
        end_date="cast('2019-01-01' as date)"
    ) }}

)

select
    date_day::date                               as date_day,
    year(date_day)                               as year,
    quarter(date_day)                            as quarter,
    month(date_day)                              as month,
    monthname(date_day)                          as month_name,
    date_trunc('month', date_day)::date          as month_start,
    date_trunc('week', date_day)::date           as week_start,
    dayofweekiso(date_day)                       as day_of_week,
    dayname(date_day)                            as day_name,
    dayofweekiso(date_day) in (6, 7)             as is_weekend

from spine
