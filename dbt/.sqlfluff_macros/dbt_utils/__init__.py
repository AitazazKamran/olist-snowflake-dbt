# Stand-ins for dbt_utils macros so SQLFluff can render models without a
# warehouse connection. They only need to produce valid SQL, not real logic.
def generate_surrogate_key(cols):
    return "md5('stub')"


def date_spine(datepart, start_date, end_date):
    return "select current_date as date_day"
