-- Grain: one row per order (all 99,441 orders, including those with no items).
--
-- Starts from orders and LEFT JOINs every other input, so no order is lost.
-- Each input is already one row per order, so no join can multiply rows.
--
-- Revenue = sum of item price for orders that are not canceled or unavailable.
-- Freight and payments are reported separately and are not revenue.

with orders as (
    select * from {{ ref('stg_orders') }}
),

customer_orders as (
    select * from {{ ref('int_customer_orders') }}
),

items as (
    select * from {{ ref('int_order_items_summary') }}
),

payments as (
    select * from {{ ref('int_order_payments_pivoted') }}
),

reviews as (
    select * from {{ ref('int_order_reviews') }}
),

delivery as (
    select * from {{ ref('int_order_delivery_metrics') }}
),

joined as (

    select
        -- keys
        o.order_id,
        co.customer_unique_id,
        o.customer_id,
        o.purchased_at::date                                    as order_date,

        -- status
        o.order_status,
        o.order_status not in ('canceled', 'unavailable')      as is_revenue_order,
        coalesce(i.item_count, 0) > 0                           as has_items,
        co.customer_order_number,
        co.customer_order_number = 1                            as is_first_order,

        -- lifecycle timestamps
        o.purchased_at,
        o.approved_at,
        o.delivered_to_carrier_at,
        o.delivered_to_customer_at,
        o.estimated_delivery_at,

        -- items
        coalesce(i.item_count, 0)                               as item_count,
        coalesce(i.distinct_seller_count, 0)                    as seller_count,
        coalesce(i.items_value, 0)                              as items_value,
        coalesce(i.freight_value, 0)                            as freight_value,
        iff(o.order_status not in ('canceled', 'unavailable'),
            coalesce(i.items_value, 0), 0)                      as revenue,

        -- payments
        p.payment_total,
        p.payment_count,
        p.primary_payment_type,
        coalesce(p.is_split_payment, false)                     as is_split_payment,
        p.max_installments,
        p.credit_card_amount,
        p.boleto_amount,
        p.voucher_amount,
        p.debit_card_amount,

        -- delivery
        d.delivery_days,
        d.days_to_carrier,
        d.estimated_delivery_days,
        d.is_late,
        d.days_late,

        -- review
        r.review_score,
        r.review_count,
        r.has_comment                                           as review_has_comment

    from orders o
    left join customer_orders co on o.order_id = co.order_id
    left join items           i  on o.order_id = i.order_id
    left join payments        p  on o.order_id = p.order_id
    left join reviews         r  on o.order_id = r.order_id
    left join delivery        d  on o.order_id = d.order_id

)

select * from joined
