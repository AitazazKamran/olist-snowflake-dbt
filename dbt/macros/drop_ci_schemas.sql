{#-
    Drops every schema created by one CI run, e.g. CI_PR_12_STAGING,
    CI_PR_12_INTERMEDIATE, CI_PR_12_MARTS, CI_PR_12_SNAPSHOTS.
    Only runs on the ci target so it can never touch dev or prod.

        dbt run-operation drop_ci_schemas --target ci
-#}
{% macro drop_ci_schemas() %}
    {% if target.name != 'ci' %}
        {{ exceptions.raise_compiler_error("drop_ci_schemas only runs on the ci target") }}
    {% endif %}

    {% set prefix = target.schema | upper %}
    {% set find_schemas %}
        select schema_name
        from {{ target.database }}.information_schema.schemata
        where schema_name = '{{ prefix }}'
           or startswith(schema_name, '{{ prefix }}_')
    {% endset %}

    {% for row in run_query(find_schemas) %}
        {% do run_query("drop schema if exists " ~ target.database ~ "." ~ row[0] ~ " cascade") %}
        {{ log("Dropped schema " ~ row[0], info=true) }}
    {% endfor %}
{% endmacro %}
