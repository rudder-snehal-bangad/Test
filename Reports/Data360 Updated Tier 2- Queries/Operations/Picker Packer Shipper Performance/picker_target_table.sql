let
    // Dynamic Parameters
    BillingProject = BillingProjectID,
    Dataset = DatasetName,

    // Dynamic table paths
    ShipmentsTable = "`" & BillingProject & "." & Dataset & ".shipments`",
    SalesOrdersTable = "`" & BillingProject & "." & Dataset & ".sales_orders`",

    SQL =
"
WITH base_data AS (
  SELECT
    s.picker,
    DATE(DATETIME(TIMESTAMP(s.picked_at), 'America/Denver')) AS pick_date,
    DATETIME(TIMESTAMP(s.picked_at), 'America/Denver') AS picked_dt,
    m.quantity,
    m.order_id,
    m.order_channel_name
  FROM " & ShipmentsTable & " AS s
  LEFT JOIN UNNEST(s.moves) AS m
  WHERE
    s.state != 'cancel'
    AND m.order_id IS NOT NULL
    AND s.picking_status = 'done'
    AND s.picker IS NOT NULL
    AND s.picker != 'Cron Trigger'
    AND m.order_channel_name NOT LIKE '%Wholesale%'
    AND m.order_channel_name NOT IN ('EDI', 'Shopify GS Retailer', 'SPS Commerce')
    AND DATE(DATETIME(TIMESTAMP(s.picked_at), 'America/Denver'))
        BETWEEN DATE_SUB(CURRENT_DATE(), INTERVAL 3 MONTH)
        AND CURRENT_DATE()
),

daily_hours AS (
  SELECT
    picker,
    pick_date,
    TIMESTAMP_DIFF(MAX(picked_dt), MIN(picked_dt), SECOND) / 3600.0
        AS daily_hours_worked
  FROM base_data
  GROUP BY picker, pick_date
),

hours_and_days AS (
  SELECT
    picker,
    ROUND(SUM(daily_hours_worked), 2) AS total_hours_worked,
    COUNT(DISTINCT pick_date) AS days_worked
  FROM daily_hours
  GROUP BY picker
),

quantity_metrics AS (
  SELECT
    b.picker,
    SUM(b.quantity) AS total_quantity
  FROM base_data AS b
  INNER JOIN " & SalesOrdersTable & " AS so
      ON so.id = b.order_id
  GROUP BY b.picker
)

SELECT
  q.picker,
  h.total_hours_worked,
  h.days_worked,
  q.total_quantity
FROM quantity_metrics AS q
LEFT JOIN hours_and_days AS h
  ON q.picker = h.picker
",

    Source =
        Value.NativeQuery(
            GoogleBigQuery.Database(
                [BillingProject = BillingProject, UseStorageApi = false]
            ){[Name = BillingProject]}[Data],
            SQL,
            null,
            [EnableFolding = true]
        ),

    #"Changed Type" =
        Table.TransformColumnTypes(
            Source,
            {{"total_quantity", Int64.Type}}
        )

in
    #"Changed Type"