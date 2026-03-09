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
      picker.id,
      picker.number,
      picker.state,
      picker.is_on_hold,
      picker.picker,
      picker.packer,
      picker.shipper,
      picker.create_date,
      picker.picking_status,
      picker.picked_at,
      picker.packed_at,
      FORMAT_DATETIME('%Y-%m-%d %H:%M:%S', picker.picked_at) as picked_at_formatted,
      picker.shipped_at,
      picker.planned_date,
      picker.quantity,
      picker.sales_order_id,
      picker.order_channel_id,
      picker.order_channel_name,
      picker.assigned_time,
      picker.sales_order_number,
      picker.sales_state,
      picker.customer_name,
      picker.product_id
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
          so.id as product_id,
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
      ) picker
ON EXTRACT(HOUR from cal_time.cal_time_pst) = EXTRACT(HOUR from picker.picked_at)
WHERE DATE(picked_at) BETWEEN DATE_SUB(CURRENT_DATE(), INTERVAL 6 MONTH) AND CURRENT_DATE()
  AND picker.product_id IS NOT NULL
  AND picker.picking_status = 'done'
",

    Source = Value.NativeQuery(
        GoogleBigQuery.Database(
            [BillingProject = BillingProject, UseStorageApi = false]
        ){[Name = BillingProject]}[Data],
        SQLQuery,
        null,
        [EnableFolding = true]
    ),

    #"Filtered Rows" = Table.SelectRows(Source, each ([picker] <> "Cron Trigger")),
    #"Changed Type" = Table.TransformColumnTypes(#"Filtered Rows",{
        {"picked_at", type date}, 
        {"packed_at", type date}, 
        {"create_date", type date}, 
        {"shipped_at", type date}, 
        {"quantity", Int64.Type}, 
        {"assigned_time", type date}, 
        {"current_time_UTC", type text}
    }),
    #"Changed Type1" = Table.TransformColumnTypes(#"Changed Type",{
        {"current_time_UTC", type datetime}, 
        {"cal_time_pst", type datetime}, 
        {"picked_at_formatted", type datetime}
    }),
    #"Changed Type2" = Table.TransformColumnTypes(#"Changed Type1",{
        {"current_time_UTC", type date}
    })

in
    #"Changed Type2"