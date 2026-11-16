-- Fails if any order was delivered before it was purchased.
-- Profiling found 0 such orders; this guards against future bad data.
select order_id, purchased_at, delivered_to_customer_at
from {{ ref('fct_orders') }}
where delivered_to_customer_at < purchased_at
