-- Grain: one row per (review_id, order_id).
-- review_id is not unique in the source: the same review can be attached to
-- several orders, and a few (review_id, order_id) pairs appear more than once.
-- Confirm the counts with snowflake/02_profile_raw.sql (query 2) and record
-- them in docs/data_profile.md. We keep the most recently answered copy.

with source as (

    select * from {{ source('olist', 'order_reviews') }}

),

renamed as (

    select
        {{ dbt_utils.generate_surrogate_key(['review_id', 'order_id']) }} as review_key,
        review_id,
        order_id,
        try_to_number(review_score)                      as review_score,
        nullif(trim(review_comment_title), '')           as comment_title,
        nullif(trim(review_comment_message), '')         as comment_message,
        try_to_timestamp_ntz(review_creation_date)       as review_created_at,
        try_to_timestamp_ntz(review_answer_timestamp)    as review_answered_at,
        _loaded_at

    from source

),

deduplicated as (

    select *
    from renamed
    qualify row_number() over (
        partition by review_id, order_id
        order by review_answered_at desc nulls last
    ) = 1

)

select * from deduplicated
