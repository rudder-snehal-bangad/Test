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
      FORMAT_DATETIME('%Y-%m-%d %H:%M:%S', cal_time.cal_time_pst) AS cal_time_pst,
      packer.id,
      packer.number,
      packer.state,
      packer.is_on_hold,
      packer.picker,
      packer.packer,
      packer.shipper,
      packer.create_date,
      packer.picking_status,
      packer.picked_at,
      packer.packed_at,
      FORMAT_DATETIME('%Y-%m-%d %H:%M:%S', packer.packed_at) AS packed_at_formatted,
      packer.shipped_at,
      packer.planned_date,
      packer.quantity,
      packer.sales_order_id,
      packer.order_channel_id,
      packer.order_channel_name,
      packer.assigned_time,
      packer.sales_order_number,
      packer.sales_state,
      packer.customer_name,
      packer.product_id
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
          cs_mo.quantity AS quantity,
          so.id AS sales_order_id,
          cs_mo.order_channel_id,
          cs_mo.order_channel_name,
          cs.assigned_time,
          so.order_number AS sales_order_number,
          so.state AS sales_state,
          cs.customer_name,
          so.id AS product_id,
          cs_mo.to_location_name,
          cs_mo.from_location_name,
          cs_mo.move_type
       FROM " & ShipmentsTable & " AS cs
       LEFT JOIN UNNEST(moves) AS cs_mo
       INNER JOIN " & SalesOrdersTable & " AS so 
            ON so.id = cs_mo.order_id
       LEFT JOIN UNNEST(lines) AS so_lines
       WHERE cs.state != 'cancel' 
         AND so_lines.line_type = 'sale'
         AND cs_mo.order_channel_name NOT IN ('EDI', 'Shopify GS Retailer', 'SPS Commerce')
         AND cs_mo.order_channel_name NOT LIKE '%Wholesale%'
      ) packer
ON EXTRACT(HOUR from cal_time.cal_time_pst) = EXTRACT(HOUR from packer.packed_at)
WHERE DATE(packed_at) BETWEEN DATE_SUB(CURRENT_DATE(), INTERVAL 6 MONTH) AND CURRENT_DATE()
  AND packer.product_id IS NOT NULL
  AND packer.picking_status = 'done'
  AND packer.from_location_name LIKE '%Output%'
  AND packer.to_location_name = 'Customer'
  AND packer.move_type = 'outgoing'
",

    Source = Value.NativeQuery(
        GoogleBigQuery.Database(
            [BillingProject = BillingProject, UseStorageApi = false]
        ){[Name = BillingProject]}[Data],
        SQLQuery,
        null,
        [EnableFolding = true]
    ),

    #"Filtered Rows" = Table.SelectRows(Source, each ([packer] <> "Cron Trigger")),

    #"Changed Type" = Table.TransformColumnTypes(#"Filtered Rows",{
        {"create_date", type date},
        {"picked_at", type date},
        {"packed_at", type date},
        {"quantity", Int64.Type},
        {"assigned_time", type date},
        {"current_time_UTC", type datetime},
        {"cal_time_pst", type datetime}
    }),

    #"Changed Type1" = Table.TransformColumnTypes(#"Changed Type",{
        {"current_time_UTC", type date},
        {"cal_time_pst", type datetime},
        {"shipped_at", type date}
    })

in
    #"Changed Type1"