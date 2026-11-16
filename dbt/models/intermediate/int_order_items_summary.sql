-- Grain: one row per order (only orders that have at least one item).
-- Rolls item lines up to order level BEFORE joining to orders, so the join
-- in fct_orders is one-to-one and cannot multiply rows.

with items as (

    select * from {{ ref('stg_order_items') }}

)

select
    order_id,
    count(*)                   as item_count,
    count(distinct product_id) as distinct_product_count,
    count(distinct seller_id)  as distinct_seller_count,
    sum(price)                 as items_value,
    sum(freight_value)         as freight_value

from items
group by order_id
