let
    // Dynamic Parameters
    BillingProject = BillingProjectID,
    Dataset = DatasetName,
    Period = Number.ToText(#"Analysis Period (Years)"),
    // Dynamic table path
    ShipmentsTable = "`" & BillingProject & "." & Dataset & ".shipments`",

    SQLQuery = "
WITH shipments AS (
    SELECT
        cs.id,
        cs.number,
        cs.shipper,
        cs.state,
        cs.tracking_url,
        cs.is_on_hold,
        DATE(cs.create_date) AS create_date,
        cs.shipped_date,
        cs.picked_at,
        cs.packed_at,
        cs.shipped_at,
        cs.delivered_at,
        cs.planned_date,
        cs.shipment_cost,
        cs.assigned_time,
        cs.customer_name,
        cs.carrier,
        cs.carrier_service,
        cs.shipment_region_name,
        cs.shipment_country_name,
        cs.shipment_address_city,
        cs.tracking_number,
        cs.packages_count,
        COALESCE(cs.override_weight_lbs,COALESCE(cs.product_weight_lbs, 0) + COALESCE(cs.box_weight_lbs, 0)) as final_weight_lbs
    FROM " & ShipmentsTable & " AS cs
    WHERE cs.state != 'cancel'
      AND DATE(cs.create_date) between DATE_ADD(current_date(), INTERVAL -" & Period & " YEAR) AND CURRENT_DATE()
),

move_data AS (
    SELECT
        cs.id AS shipment_id,
        m.order_id as sale_order_id,
        m.order_channel_name as sales_channel_name,
        SUM(m.quantity) AS total_quantity,
        MAX(m.order_channel_id) AS order_channel_id
    FROM " & ShipmentsTable & " AS cs
    LEFT JOIN UNNEST(cs.moves) AS m
    WHERE move_type = 'outgoing'
    GROUP BY cs.id,m.order_id,m.order_channel_name
)

SELECT
    s.*,
    m.order_channel_id,
    m.sale_order_id,m.sales_channel_name,
    COALESCE(m.total_quantity, 0) AS quantity,

    CASE
        WHEN s.delivered_at IS NULL THEN 'false'
        ELSE 'true'
    END AS delivery_date_tf,

    COALESCE(
        ABS(TIMESTAMP_DIFF(s.delivered_at, s.shipped_at, SECOND)),
        0
    ) AS delivery_time_seconds,

    ABS(
        TIMESTAMP_DIFF(s.delivered_at, s.shipped_at, HOUR)
    ) AS delivery_time_hours,

    COALESCE(
        ABS(TIMESTAMP_DIFF(s.delivered_at, s.shipped_at, MINUTE)),
        0
    ) AS delivery_time_minutes,

    CASE
        WHEN s.delivered_at IS NULL THEN NULL
        WHEN ABS(TIMESTAMP_DIFF(s.delivered_at, s.shipped_at, HOUR)) BETWEEN 0 AND 12
            THEN '0-12 Hours'
        WHEN ABS(TIMESTAMP_DIFF(s.delivered_at, s.shipped_at, HOUR)) BETWEEN 13 AND 24
            THEN '13-24 Hours'
        WHEN ABS(TIMESTAMP_DIFF(s.delivered_at, s.shipped_at, HOUR)) BETWEEN 25 AND 36
            THEN '25-36 Hours'
        WHEN ABS(TIMESTAMP_DIFF(s.delivered_at, s.shipped_at, HOUR)) BETWEEN 37 AND 48
            THEN '37-48 Hours'
        WHEN ABS(TIMESTAMP_DIFF(s.delivered_at, s.shipped_at, HOUR)) BETWEEN 49 AND 60
            THEN '49-60 Hours'
        ELSE 'Above 60 Hours'
    END AS delivery_time_bins,

    COALESCE(
        DATE_DIFF(CURRENT_DATE(), DATE(s.shipped_at), DAY),
        0
    ) AS TransitDay

FROM shipments AS s
LEFT JOIN move_data AS m
    ON s.id = m.shipment_id
",

    Source = Value.NativeQuery(
        GoogleBigQuery.Database(
            [BillingProject = BillingProject, UseStorageApi = false]
        ){[Name = BillingProject]}[Data],
        SQLQuery,
        null,
        [EnableFolding = true]
    ),

    #"Renamed Columns" = Table.RenameColumns(Source,{
        {"delivery_date_tf", "Delivery Date T/F"},
        {"delivery_time_bins", "Delivery Time (Bins)"},
        {"delivery_time_hours", "Delivery Time Hours"},
        {"delivery_time_minutes", "Delivery Time Minutes"},
        {"delivery_time_seconds", "Delivery Time"},
        {"TransitDay", "TransitDays"}
    }),
    #"Capitalized Each Word" = Table.TransformColumns(#"Renamed Columns",{{"state", Text.Proper, type text}})

in
    #"Capitalized Each Word"