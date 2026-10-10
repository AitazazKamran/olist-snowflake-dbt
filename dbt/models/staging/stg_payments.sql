with source as (

    select * from {{ source('olist', 'order_payments') }}

),

renamed as (

    select
        {{ dbt_utils.generate_surrogate_key(['order_id', 'payment_sequential']) }} as payment_key,
        order_id,
        try_to_number(payment_sequential)                as payment_sequence,
        lower(trim(payment_type))                        as payment_type,
        try_to_number(payment_installments)              as installments,
        try_to_number(payment_value, 12, 2)              as payment_value,
        _loaded_at

    from source

)

select * from renamed
