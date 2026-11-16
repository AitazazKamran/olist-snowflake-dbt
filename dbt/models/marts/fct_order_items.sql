-- Grain: one row per item in an order.
--
-- Incremental: the first run builds the whole table; later runs only process
-- orders purchased in the last 3 days of what is already loaded, and MERGE them
-- on order_item_key (update if it exists, insert if new). The 3-day lookback
-- catches items that arrive late. Rebuild everything with --full-refresh.
--
-- Order-level attributes (is_late, review_score) are repeated on each item so
-- seller performance can be analysed. When averaging them per seller, count
-- DISTINCT orders, not items.

{{
    config(
        materialized='incremental',
        unique_key='order_item_key',
        incremental_strategy='merge',
        on_schema_change='append_new_columns'
    )
}}

with items as (
    select * from {{ ref('stg_order_items') }}
),

orders as (
    select * from {{ ref('fct_orders') }}
)

select
    i.order_item_key,
    i.order_id,
    i.order_item_number,
    i.product_id,
    i.seller_id,
    o.customer_unique_id,
    o.order_date,
    o.purchased_at,
    o.order_status,
    o.is_revenue_order,
    i.price,
    i.freight_value,
    iff(o.is_revenue_order, i.price, 0) as revenue,
    i.shipping_limit_at,
    o.is_late,
    o.delivery_days,
    o.review_score

from items i
inner join orders o
    on i.order_id = o.order_id

{% if is_incremental() %}
    where o.purchased_at >= (
            select dateadd('day', -3, max(existing.purchased_at))
            from {{ this }} as existing
        )
{% endif %}
