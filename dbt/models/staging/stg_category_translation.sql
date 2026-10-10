with source as (

    select * from {{ source('olist', 'product_category_name_translation') }}

),

renamed as (

    select
        lower(trim(product_category_name))               as category_name_pt,
        lower(trim(product_category_name_english))       as category_name_en,
        _loaded_at

    from source

)

select * from renamed
