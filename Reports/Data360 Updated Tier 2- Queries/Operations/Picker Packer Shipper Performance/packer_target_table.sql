let
    // Dynamic Parameters
    BillingProject = BillingProjectID,
    Dataset = DatasetName,

    // Dynamic table paths
    ShipmentsTable = "`" & BillingProject & "." & Dataset & ".shipments`",
    SalesOrdersTable = "`" & BillingProject & "." & Dataset & ".sales_orders`",

    SQLQuery = "
-- Packer Target Query with Days Worked and Total Complexity Score

WITH base_data AS (
  SELECT
    s.packer,
    DATE(DATETIME(TIMESTAMP(s.packed_at), 'America/Chicago')) AS pack_date,
    DATETIME(TIMESTAMP(s.packed_at), 'America/Chicago') AS packed_dt,
    m.quantity,
    m.order_id,
    m.order_channel_name
  FROM " & ShipmentsTable & " AS s
  LEFT JOIN UNNEST(s.moves) AS m
  WHERE
    s.state != 'cancel'
    AND m.order_id IS NOT NULL
    AND s.packed_at IS NOT NULL
    AND s.packer IS NOT NULL
    AND m.order_channel_name NOT LIKE '%Wholesale%'
    AND m.order_channel_name NOT IN ('EDI', 'Shopify GS Retailer', 'SPS Commerce')
    AND s.packer != 'Cron Trigger'
    AND DATE(DATETIME(TIMESTAMP(s.packed_at), 'America/Chicago'))
        BETWEEN DATE_SUB(CURRENT_DATE(), INTERVAL 3 MONTH) AND CURRENT_DATE()
),

daily_hours AS (
  SELECT
    packer,
    pack_date,
    TIMESTAMP_DIFF(MAX(packed_dt), MIN(packed_dt), SECOND) / 3600.0 AS daily_hours_worked
  FROM base_data
  GROUP BY packer, pack_date
),

hours_and_days AS (
  SELECT
    packer,
    ROUND(SUM(daily_hours_worked), 2) AS total_hours_worked,
    COUNT(DISTINCT pack_date) AS days_worked
  FROM daily_hours
  GROUP BY packer
),

quantity_metrics AS (
  SELECT
    b.packer,
    SUM(b.quantity) AS total_quantity
  FROM base_data AS b
  INNER JOIN " & SalesOrdersTable & " AS so
    ON so.id = b.order_id
  GROUP BY b.packer
)

SELECT
  q.packer,
  h.total_hours_worked,
  h.days_worked,
  q.total_quantity
FROM quantity_metrics AS q
LEFT JOIN hours_and_days AS h
  ON q.packer = h.packer
",

    Source = Value.NativeQuery(
        GoogleBigQuery.Database(
            [BillingProject = BillingProject, UseStorageApi = false]
        ){[Name = BillingProject]}[Data],
        SQLQuery,
        null,
        [EnableFolding = true]
    ),

    #"Changed Type" = Table.TransformColumnTypes(
        Source,
        {{"total_quantity", Int64.Type}}
    )

in
    #"Changed Type"