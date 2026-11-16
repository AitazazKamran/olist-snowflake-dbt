-- Grain: one row per order.
-- Delivery durations and the late flag.
--
-- Rules (from docs/data_profile.md):
--   * is_late only applies to orders with status 'delivered' AND a delivery date
--     and an estimated date; otherwise it is null (unknown), never false.
--   * Late = delivered DATE is after the estimated DATE (same day = on time).
--   * 166 orders have a carrier date before the purchase date: negative
--     durations are impossible, so they become null.

with orders as (

    select * from {{ ref('stg_orders') }}

),

metrics as (

    select
        order_id,
        order_status,
        purchased_at,
        delivered_to_carrier_at,
        delivered_to_customer_at,
        estimated_delivery_at,

        -- hours / 24 gives fractional days (datediff('day') only counts midnights)
        round(datediff('hour', purchased_at, delivered_to_customer_at) / 24.0, 1)
                                                            as delivery_days,

        case
            when delivered_to_carrier_at >= purchased_at
                then round(datediff('hour', purchased_at, delivered_to_carrier_at) / 24.0, 1)
        end                                                 as days_to_carrier,

        round(datediff('hour', purchased_at, estimated_delivery_at) / 24.0, 1)
                                                            as estimated_delivery_days,

        case
            when order_status = 'delivered'
             and delivered_to_customer_at is not null
             and estimated_delivery_at is not null
                then delivered_to_customer_at::date > estimated_delivery_at::date
        end                                                 as is_late,

        case
            when order_status = 'delivered'
             and delivered_to_customer_at::date > estimated_delivery_at::date
                then datediff('day', estimated_delivery_at::date, delivered_to_customer_at::date)
        end                                                 as days_late

    from orders

)

select * from metrics
