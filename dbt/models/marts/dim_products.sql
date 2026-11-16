-- Grain: one row per product.
-- English category: official translation, then our seed fixes for the 2
-- untranslated categories, then the Portuguese name, then 'unknown'
-- (610 products have no category at all).

with products as (
    select * from {{ ref('stg_products') }}
),

translations as (
    select * from {{ ref('stg_category_translation') }}
),

fixes as (
    select * from {{ ref('category_translation_fixes') }}
)

select
    p.product_id,
    coalesce(p.category_name_pt, 'unknown') as category_name_pt,
    coalesce(
        t.category_name_en, f.category_name_en,
        p.category_name_pt, 'unknown'
    )                                       as category_name,
    p.product_name_length,
    p.product_description_length,
    p.photo_count,
    p.weight_g,
    p.length_cm,
    p.height_cm,
    p.width_cm,
    p.length_cm * p.height_cm * p.width_cm  as volume_cm3

from products p
left join translations t on p.category_name_pt = t.category_name_pt
left join fixes f on p.category_name_pt = f.category_name_pt
