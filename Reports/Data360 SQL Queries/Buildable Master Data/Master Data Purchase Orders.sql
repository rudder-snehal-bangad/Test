let
    BillingProject = BillingProjectID,
    Dataset = DatasetName,
    Period = Number.ToText(#"Analysis Period (Years)"),
    BasePath = BillingProject & "." & Dataset,

    SQLQuery ="
    with ss as (SELECT DISTINCT
    ss.id,
    ss.number,
    ss.state,
    ss.effective_date AS ss_effective_date,
    DATE(ss.create_date) AS ss_create_date,
    ss.planned_date AS ss_planned_date,
    mov.order_line_id,
    mov.product_code,
    mov.state as mov_state,
    SUM(mov.quantity) AS ss_quantity,
    ss.supplier_name
  FROM " & BasePath & ".supplier_shipments ss
  -- from fulfil-data-warehouse-227710.gruntstyle.supplier_shipments ss
  LEFT JOIN UNNEST(moves) AS mov
  WHERE mov.order_id IS NOT NULL
  AND DATE(ss.create_date) between DATE_ADD(current_date(), INTERVAL -" & Period & " YEAR) AND CURRENT_DATE()
  GROUP BY 
    ss.id, 
    ss.number, 
    ss.state, 
    ss.effective_date, 
    ss.create_date, 
    ss.planned_date, 
    mov.product_code, 
    mov.state,
    mov.order_line_id,
    ss.supplier_name),

po AS (
  SELECT
    po.purchase_date as po_purchase_date,po.id as po_id,
    po_lines.id AS po_line_id,
    po_lines.product_code
  FROM `" & BasePath & ".purchase_orders` AS po
  -- from fulfil-data-warehouse-227710.gruntstyle.purchase_orders po
  LEFT JOIN UNNEST(po.lines) AS po_lines
  WHERE po.state NOT IN ('cancel')
  and po.purchase_date between DATE_ADD(current_date(), INTERVAL -" & Period & " YEAR) AND CURRENT_DATE()
)

SELECT 
--DISTINCT
    ss.id,
    ss.number,
    ss.state,
    ss_effective_date,
    ss_create_date,
    po_purchase_date,
     ss_planned_date,
    ss.product_code,
     mov_state,
    ss_quantity,
    ss.supplier_name,
    po.po_id
  FROM ss
  LEFT JOIN po ON po.po_line_id = ss.order_line_id
  
    "
	,
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