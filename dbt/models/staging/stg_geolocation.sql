-- Raw geolocation has ~1M rows for ~19K zip prefixes: exact duplicates,
-- slightly different coordinates for the same prefix, accent/case variants of
-- city names, and some points outside Brazil.
--
-- Output grain: one row per zip_code_prefix.
--   latitude / longitude  average of the points inside Brazil's bounding box
--   city / state          most common spelling for that prefix
--   raw_row_count         how many raw rows were collapsed (useful for docs)

with source as (

    select * from {{ source('olist', 'geolocation') }}

),

cleaned as (

    select
        lpad(trim(geolocation_zip_code_prefix), 5, '0')  as zip_code_prefix,
        try_to_double(geolocation_lat)                   as latitude,
        try_to_double(geolocation_lng)                   as longitude,
        lower(trim(geolocation_city))                    as city,
        upper(trim(geolocation_state))                   as state

    from source

),

inside_brazil as (

    -- Rough bounding box of Brazil; drops obviously wrong coordinates.
    select *
    from cleaned
    where latitude  between -34 and 6
      and longitude between -74 and -34

),

aggregated as (

    select
        zip_code_prefix,
        avg(latitude)            as latitude,
        avg(longitude)           as longitude,
        mode(city)               as city,
        mode(state)              as state,
        count(*)                 as raw_row_count

    from inside_brazil
    group by zip_code_prefix

)

select * from aggregated
