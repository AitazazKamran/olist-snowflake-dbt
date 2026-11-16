-- Grain: one row per zip code prefix.
--
-- Includes EVERY zip used by a customer or seller, not only the zips in the
-- geolocation file (157 customer zips have no geolocation match). Those rows
-- get city/state from the customer/seller data and null coordinates, so
-- relationships from dim_customers and dim_sellers never break.

with geo as (
    select * from {{ ref('stg_geolocation') }}
),

used_zips as (

    select zip_code_prefix, city, state from {{ ref('stg_customers') }}
    union all
    select zip_code_prefix, city, state from {{ ref('stg_sellers') }}

),

used_zip_names as (

    select
        zip_code_prefix,
        mode(city)  as city,
        mode(state) as state
    from used_zips
    group by zip_code_prefix

),

all_zips as (

    select zip_code_prefix from geo
    union
    select zip_code_prefix from used_zip_names

)

select
    z.zip_code_prefix,
    coalesce(g.city, u.city)          as city,
    coalesce(g.state, u.state)        as state,
    g.latitude,
    g.longitude,
    g.latitude is not null            as has_coordinates

from all_zips z
left join geo            g on z.zip_code_prefix = g.zip_code_prefix
left join used_zip_names u on z.zip_code_prefix = u.zip_code_prefix
