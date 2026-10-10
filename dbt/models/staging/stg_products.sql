-- Fixes the source typo "lenght" -> "length" and casts numbers.
-- English category names are joined later (dim_products), not here:
-- staging stays one model per source table.

with source as (

    select * from {{ source('olist', 'products') }}

),

renamed as (

    select
        product_id,
        nullif(lower(trim(product_category_name)), '')   as category_name_pt,
        try_to_number(product_name_lenght)               as product_name_length,
        try_to_number(product_description_lenght)        as product_description_length,
        try_to_number(product_photos_qty)                as photo_count,
        try_to_number(product_weight_g)                  as weight_g,
        try_to_number(product_length_cm)                 as length_cm,
        try_to_number(product_height_cm)                 as height_cm,
        try_to_number(product_width_cm)                  as width_cm,
        _loaded_at

    from source

)

select * from renamed
