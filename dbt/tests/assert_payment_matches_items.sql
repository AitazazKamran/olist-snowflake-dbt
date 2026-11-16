-- Orders whose total payment differs from items + freight by more than 1%.
-- Profiling found 254 (0.26%), mostly credit-card instalment interest, so a few
-- are normal: WARN when any exist, ERROR only if the count jumps above 1,000
-- (which would point to a broken join, not real customer behaviour).
{{ config(severity='error', warn_if='>0', error_if='>1000') }}

select
    order_id,
    payment_total,
    items_value + freight_value as items_plus_freight
from {{ ref('fct_orders') }}
where has_items
  and payment_total is not null
  and abs(payment_total - (items_value + freight_value)) > 0.01 * (items_value + freight_value)
