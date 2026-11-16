-- Grain: one row per order (only orders that have a review).
-- Profiling found 551 extra review rows: some orders have 2 or 3 reviews.
-- We keep the most recently answered review so fct_orders stays one row per order.

with reviews as (

    select * from {{ ref('stg_reviews') }}

),

ranked as (

    select
        order_id,
        review_id,
        review_score,
        comment_message is not null                      as has_comment,
        review_created_at,
        review_answered_at,
        count(*) over (partition by order_id)            as review_count

    from reviews
    qualify row_number() over (
        partition by order_id
        order by review_answered_at desc nulls last,
                 review_created_at desc nulls last,
                 review_id
    ) = 1

)

select * from ranked
