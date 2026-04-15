let
    // Dynamic Parameters
    BillingProject = BillingProjectID,
    Dataset = DatasetName,
    Period = Number.ToText(#"Analysis Period (Years)"),
    // Dynamic table path
    ShipmentsTable = "`" & BillingProject & "." & Dataset & ".shipments`",

    SQLQuery = "
SELECT
    cs.id,
    cs.number,
    cs.state AS shipment_state,
    DATE(cs.create_date) as create_date,
    cs.shipped_at,
    cs.delivered_at,
    cs.shipper,
    cs.planned_date,
    cs.customer_name,
    cs.customer_id,
    cs.shipment_country_name,
    cs.shipment_region_name,
    cs.state,
    reference,
    cs_mo.order_id AS order_id,
    cs_mo.order_number AS order_number,
    cs_mo.quantity,
    cs_mo.product_code,
    cs_mo.order_line_id as sale_line_id
FROM " & ShipmentsTable & " cs
LEFT JOIN UNNEST(moves) cs_mo
WHERE DATE(cs.create_date) between DATE_ADD(current_date(), INTERVAL -" & Period & " YEAR) AND CURRENT_DATE()
  AND cs_mo.move_type = 'outgoing'
",

    Source = Value.NativeQuery(
        GoogleBigQuery.Database(
            [BillingProject = BillingProject, UseStorageApi = false]
        ){[Name = BillingProject]}[Data],
        SQLQuery,
        null,
        [EnableFolding = true]
    )

in
    Source