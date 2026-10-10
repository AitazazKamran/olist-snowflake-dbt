with source as (

    select * from {{ source('olist', 'order_items') }}

),

renamed as (

    select
        {{ dbt_utils.generate_surrogate_key(['order_id', 'order_item_id']) }} as order_item_key,
        order_id,
        try_to_number(order_item_id)                     as order_item_number,
        product_id,
        seller_id,
        try_to_timestamp_ntz(shipping_limit_date)        as shipping_limit_at,
        try_to_number(price, 12, 2)                      as price,
        try_to_number(freight_value, 12, 2)              as freight_value,
        _loaded_at

    from source

)

select * from renamed
