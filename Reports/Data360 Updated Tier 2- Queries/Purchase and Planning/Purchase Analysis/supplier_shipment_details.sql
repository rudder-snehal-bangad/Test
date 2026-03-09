let
    BillingProject = BillingProjectID,
    Dataset = DatasetName,

    BasePath = BillingProject & "." & Dataset,
    Period = Number.ToText(#"Analysis Period (Years)"),
    SQLQuery =
	"
    SELECT
    ss.id as ss_id,
    DATE(create_date)as create_date,
    number as ss_number,
    ss.state,
    ss.planned_date,
    ss.effective_date,
    warehouse_name,
    supplier_name,
    quantity,
    unit_price,
    move.planned_date as move_planned_date,
    move.effective_date as move_effective_date,
    move.state as move_state,
    product_code,
    order_line_id as purchase_line_id,
    order_number as po_number
FROM `" & BasePath & ".supplier_shipments` ss
LEFT JOIN UNNEST(moves) move
WHERE from_location_type = 'supplier'
  AND (DATE(ss.create_date) IS NULL OR DATE(ss.create_date) between DATE_ADD(current_date(), INTERVAL -" & Period & " YEAR) AND CURRENT_DATE())",
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