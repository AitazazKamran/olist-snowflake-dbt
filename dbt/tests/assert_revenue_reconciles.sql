-- Total revenue must be the same at order level and item level,
-- and must equal the raw item prices for revenue orders.
-- Catches fan-out (double counting) from a bad join.
with by_order as (
    select sum(revenue) as revenue from {{ ref('fct_orders') }}
),
by_item as (
    select sum(revenue) as revenue from {{ ref('fct_order_items') }}
),
from_source as (
    select sum(i.price) as revenue
    from {{ ref('stg_order_items') }} i
    join {{ ref('stg_orders') }} o on i.order_id = o.order_id
    where o.order_status not in ('canceled', 'unavailable')
)
select
    o.revenue as fct_orders_revenue,
    i.revenue as fct_order_items_revenue,
    s.revenue as source_revenue
from by_order o, by_item i, from_source s
where abs(o.revenue - i.revenue) > 0.01
   or abs(o.revenue - s.revenue) > 0.01
