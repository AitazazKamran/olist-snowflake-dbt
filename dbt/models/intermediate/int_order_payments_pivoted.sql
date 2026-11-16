-- Grain: one row per order (only orders that have a payment).
-- An order can be split across several payments and methods; this turns them
-- into one row with an amount per payment type.

{% set payment_types = ['credit_card', 'boleto', 'voucher', 'debit_card'] %}

with payments as (

    select * from {{ ref('stg_payments') }}

)

select
    order_id,
    sum(payment_value)                                   as payment_total,
    count(*)                                             as payment_count,
    count(distinct payment_type)                         as payment_type_count,
    count(distinct payment_type) > 1                     as is_split_payment,
    max(installments)                                    as max_installments,
    -- the method that paid the largest share of the order
    max_by(payment_type, payment_value)                  as primary_payment_type,
    {% for t in payment_types %}
    sum(iff(payment_type = '{{ t }}', payment_value, 0)) as {{ t }}_amount{{ "," if not loop.last }}
    {% endfor %}

from payments
group by order_id
