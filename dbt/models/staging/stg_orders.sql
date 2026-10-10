with source as (

    select * from {{ source('olist', 'orders') }}

),

renamed as (

    select
        order_id,
        customer_id,
        lower(trim(order_status))                                as order_status,
        try_to_timestamp_ntz(order_purchase_timestamp)           as purchased_at,
        try_to_timestamp_ntz(order_approved_at)                  as approved_at,
        try_to_timestamp_ntz(order_delivered_carrier_date)       as delivered_to_carrier_at,
        try_to_timestamp_ntz(order_delivered_customer_date)      as delivered_to_customer_at,
        try_to_timestamp_ntz(order_estimated_delivery_date)      as estimated_delivery_at,
        _loaded_at

    from source

)

select * from renamed
