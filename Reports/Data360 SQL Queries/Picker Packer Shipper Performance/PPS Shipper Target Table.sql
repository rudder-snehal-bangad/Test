let
    // Dynamic Parameters
    BillingProject = BillingProjectID,
    Dataset = DatasetName,

    // Dynamic table path
    ShipmentsTable = "`" & BillingProject & "." & Dataset & ".shipments`",

    SQLQuery = "
-- Shipper Target Query with Days Worked and Total Shipment Count

WITH base_shipments AS (
  SELECT
    s.id,
    s.shipper,
    s.shipped_at,
    mo.order_id,
    mo.quantity,
    mo.order_channel_name
  FROM " & ShipmentsTable & " s
  LEFT JOIN UNNEST(s.moves) mo
  WHERE
    s.state = 'done'
    AND s.shipper IS NOT NULL
    AND s.shipper NOT IN ('Cron Trigger')
    AND mo.order_id IS NOT NULL
    AND mo.order_channel_name NOT LIKE '%Wholesale%'
    AND mo.order_channel_name NOT IN ('EDI', 'Shopify GS Retailer', 'SPS Commerce')
    AND DATE(DATETIME(TIMESTAMP(s.shipped_at), 'America/Chicago'))
        BETWEEN DATE_SUB(CURRENT_DATE(), INTERVAL 3 MONTH) AND CURRENT_DATE()
),

daily_shipper_hours AS (
  SELECT
    shipper,
    DATE(DATETIME(TIMESTAMP(shipped_at), 'America/Chicago')) AS ship_date,
    TIMESTAMP_DIFF(
      MAX(DATETIME(TIMESTAMP(shipped_at), 'America/Chicago')),
      MIN(DATETIME(TIMESTAMP(shipped_at), 'America/Chicago')),
      SECOND
    ) / 3600.0 AS daily_hours_worked
  FROM base_shipments
  GROUP BY shipper, ship_date
),

hrs_worked AS (
  SELECT
    shipper,
    ROUND(SUM(daily_hours_worked), 2) AS total_hours_worked
  FROM daily_shipper_hours
  GROUP BY shipper
),

days_worked AS (
  SELECT
    shipper,
    COUNT(DISTINCT ship_date) AS days_worked
  FROM daily_shipper_hours
  GROUP BY shipper
),

ship_qty AS (
  SELECT
    shipper,
    SUM(quantity) AS total_quantity
  FROM base_shipments
  GROUP BY shipper
),

shipment_counts AS (
  SELECT
    shipper,
    COUNT(DISTINCT id) AS total_shipment_count
  FROM base_shipments
  GROUP BY shipper
)

SELECT
  ship_qty.shipper,
  hrs_worked.total_hours_worked,
  days_worked.days_worked,
  ship_qty.total_quantity,
  shipment_counts.total_shipment_count
FROM ship_qty
LEFT JOIN hrs_worked ON ship_qty.shipper = hrs_worked.shipper
LEFT JOIN days_worked ON ship_qty.shipper = days_worked.shipper
LEFT JOIN shipment_counts ON ship_qty.shipper = shipment_counts.shipper
",

    Source = Value.NativeQuery(
        GoogleBigQuery.Database(
            [BillingProject = BillingProject, UseStorageApi = false]
        ){[Name = BillingProject]}[Data],
        SQLQuery,
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