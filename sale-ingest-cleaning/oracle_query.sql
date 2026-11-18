SELECT
    table_name AS ias_table,
    column_name AS ias_col,
    data_type,
    data_length
FROM all_tab_columns
WHERE TABLE_NAME IN ('CVTRAN', 'CVLEG')
