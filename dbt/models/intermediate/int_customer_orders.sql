-- Grain: one row per order, with the PERSON who placed it.
-- customer_id is created per order; customer_unique_id is the person
-- (99,441 customer_ids vs 96,096 people). All customer metrics use the person.

with orders as (

    select * from {{ ref('stg_orders') }}

),

customers as (

    select * from {{ ref('stg_customers') }}

)

select
    o.order_id,
    o.customer_id,
    c.customer_unique_id,
    o.order_status,
    o.purchased_at,
    c.zip_code_prefix,
    c.city,
    c.state,

    -- 1 = this person's first order, 2 = second, ...
    row_number() over (
        partition by c.customer_unique_id
        order by o.purchased_at, o.order_id
    )                                                        as customer_order_number,

    min(o.purchased_at) over (partition by c.customer_unique_id)
                                                             as customer_first_purchased_at

from orders o
left join customers c
    on o.customer_id = c.customer_id
