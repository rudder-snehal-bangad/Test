let
    // Dynamic Parameters
    BillingProject = BillingProjectID,
    Dataset = DatasetName,

    // Dynamic table paths
    ShipmentsTable = "`" & BillingProject & "." & Dataset & ".shipments`",
    SalesOrdersTable = "`" & BillingProject & "." & Dataset & ".sales_orders`",

    SQLQuery = "
SELECT
      FORMAT_TIMESTAMP('%Y-%m-%d %H:%M:%S', CURRENT_TIMESTAMP()) AS current_time_UTC,
      FORMAT_DATETIME('%Y-%m-%d %H:%M:%S', cal_time.cal_time_pst) as cal_time_pst,
      shipper.id,
      shipper.number,
      shipper.state,
      shipper.is_on_hold,
      shipper.picker,
      shipper.packer,
      shipper.shipper,
      shipper.create_date,
      shipper.picking_status,
      shipper.picked_at,
      shipper.packed_at,
      FORMAT_DATETIME('%Y-%m-%d %H:%M:%S', shipper.shipped_at) as shipped_at_formatted,
      shipper.shipped_at,
      shipper.planned_date,
      shipper.quantity,
      shipper.sales_order_id,
      shipper.order_channel_id,
      shipper.order_channel_name,
      shipper.assigned_time,
      shipper.sales_order_number,
      shipper.sales_state,
      shipper.customer_name,
      shipper.product_id
FROM
      (SELECT TIMESTAMP_ADD(TIMESTAMP(DATE(CURRENT_DATE())), INTERVAL hour HOUR) AS cal_time_pst
       FROM UNNEST(GENERATE_ARRAY(0, 23)) AS hour) cal_time
LEFT JOIN
      (SELECT DISTINCT
          cs.id,
          cs.number,
          cs.state,
          cs.is_on_hold,
          cs.picker,
          cs.packer,
          cs.shipper,
          cs.create_date,
          cs.picking_status,
          cs.picked_at,
          cs.packed_at,
          cs.shipped_at,
          cs.planned_date,
          cs_mo.quantity as quantity,
          so.id as sales_order_id,
          cs_mo.order_channel_id,
          cs_mo.order_channel_name,
          cs.assigned_time,
          so.order_number as sales_order_number,
          so.state as sales_state,
          cs.customer_name,
          so.id AS product_id,
          cs_mo.to_location_name,
          cs_mo.from_location_name,
          cs_mo.move_type
       FROM " & ShipmentsTable & " as cs
       LEFT JOIN UNNEST(moves) as cs_mo
       INNER JOIN " & SalesOrdersTable & " as so 
            ON so.id = cs_mo.order_id
       LEFT JOIN UNNEST(lines) AS so_lines
       WHERE cs.state != 'cancel'  
         AND so_lines.line_type = 'sale'
         AND cs_mo.order_channel_name NOT IN ('EDI', 'Shopify GS Retailer', 'SPS Commerce')
         AND cs_mo.order_channel_name NOT LIKE '%Wholesale%'
      ) shipper
ON EXTRACT(HOUR from cal_time.cal_time_pst) = EXTRACT(HOUR from shipper.shipped_at)
WHERE DATE(shipped_at) BETWEEN DATE_SUB(CURRENT_DATE(), INTERVAL 6 MONTH) AND CURRENT_DATE()
  AND shipper.product_id IS NOT NULL
  AND shipper.picking_status = 'done'
  AND shipper.from_location_name LIKE '%Output%'
  AND shipper.to_location_name = 'Customer'
  AND shipper.move_type = 'outgoing'
",

    Source = Value.NativeQuery(
        GoogleBigQuery.Database(
            [BillingProject = BillingProject, UseStorageApi = false]
        ){[Name = BillingProject]}[Data],
        SQLQuery,
        null,
        [EnableFolding = true]
    ),

    #"Filtered Rows" = Table.SelectRows(Source, each ([shipper] <> "Cron Trigger")),

    #"Changed Type" = Table.TransformColumnTypes(#"Filtered Rows",{
        {"create_date", type date},
        {"picked_at", type date},
        {"packed_at", type date},
        {"shipped_at", type date},
        {"quantity", Int64.Type},
        {"assigned_time", type date},
        {"current_time_UTC", type datetime},
        {"cal_time_pst", type datetime},
        {"shipped_at_formatted", type datetime}
    }),

    #"Changed Type1" = Table.TransformColumnTypes(#"Changed Type",{
        {"current_time_UTC", type date},
        {"cal_time_pst", type datetime},
        {"shipped_at_formatted", type datetime}
    })

in
    #"Changed Type1"