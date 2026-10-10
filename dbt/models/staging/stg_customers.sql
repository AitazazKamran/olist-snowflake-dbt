-- customer_id is created per order. customer_unique_id is the real person:
-- use it for repeat-customer and cohort metrics.

with source as (

    select * from {{ source('olist', 'customers') }}

),

renamed as (

    select
        customer_id,
        customer_unique_id,
        lpad(trim(customer_zip_code_prefix), 5, '0')     as zip_code_prefix,
        lower(trim(customer_city))                       as city,
        upper(trim(customer_state))                      as state,
        _loaded_at

    from source

)

select * from renamed
