{#-
    Where each model's schema ends up.

    dbt's default glues the target schema and the custom schema together
    (DBT_DEV + staging = DBT_DEV_STAGING) in every environment. That is what we
    want in dev and CI, so people and pull requests never overwrite each other.
    In prod we want the clean names STAGING / INTERMEDIATE / MARTS / SNAPSHOTS
    that Power BI and the REPORTER grants point at.

      target   custom schema   result
      prod     marts           MARTS
      dev      marts           DBT_DEV_MARTS
      ci       marts           CI_PR_12_MARTS
-#}
{% macro generate_schema_name(custom_schema_name, node) -%}
    {%- set default_schema = target.schema -%}
    {%- if custom_schema_name is none -%}
        {{ default_schema }}
    {%- elif target.name == 'prod' -%}
        {{ custom_schema_name | trim | upper }}
    {%- else -%}
        {{ default_schema }}_{{ custom_schema_name | trim | upper }}
    {%- endif -%}
{%- endmacro %}
