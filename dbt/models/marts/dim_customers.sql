-- Grain: one row per person (customer_unique_id).
-- Location = where the person's most recent order was delivered.
-- Repeat customer = 2 or more DELIVERED orders.
-- Cohort month = month of the person's first order (any status).

with customer_orders as (
    select * from {{ ref('int_customer_orders') }}
),

aggregated as (

    select
        customer_unique_id,
        min(purchased_at)                    as first_order_at,
        max(purchased_at)                    as last_order_at,
        count(*)                             as total_orders,
        count_if(order_status = 'delivered') as delivered_orders

    from customer_orders
    group by customer_unique_id

),

latest_location as (

    select
        customer_unique_id,
        zip_code_prefix,
        city,
        state
    from customer_orders
    qualify row_number() over (
            partition by customer_unique_id
            order by purchased_at desc, order_id desc
        ) = 1

)

select
    a.customer_unique_id,
    l.zip_code_prefix,
    l.city,
    l.state,
    a.first_order_at,
    a.last_order_at,
    date_trunc('month', a.first_order_at)::date as cohort_month,
    a.total_orders,
    a.delivered_orders,
    a.delivered_orders >= 2                     as is_repeat_customer

from aggregated a
left join latest_location l
    on a.customer_unique_id = l.customer_unique_id
