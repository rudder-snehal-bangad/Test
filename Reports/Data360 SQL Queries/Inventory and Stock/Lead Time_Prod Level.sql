let
    BillingProject = BillingProjectID,
    Dataset = DatasetName,

    BasePath = BillingProject & "." & Dataset,

    SQLQuery ="--lead time prod code level
WITH ss AS (
  SELECT
    mov.order_line_id,
    ss.effective_date,
    date(ss.create_date) as create_date
  FROM `" & BasePath & ".supplier_shipments` AS ss
  LEFT JOIN UNNEST(moves) AS mov
  WHERE ss.state NOT IN ('cancel')
),
po AS (
  SELECT
    po.purchase_date,
    po_lines.id AS po_line_id,
    po_lines.product_code,
  FROM `" & BasePath & ".purchase_orders` AS po
  LEFT JOIN UNNEST(po.lines) AS po_lines
  WHERE po.state NOT IN ('cancel')
),
joined_data AS (
  SELECT
    p.code,
    p.id as prod_id, 
    po.product_code,
    po.purchase_date,
    ss.effective_date,
    DATE_DIFF(ss.effective_date, po.purchase_date, DAY) AS lead_time_days,
    DATE_DIFF(ss.effective_date, po.purchase_date, DAY) AS lead_time_po_purchase,
    DATE_DIFF(ss.effective_date, ss.create_date, DAY) AS lead_time_ss_create,
  --  ps.sequence,
   -- p.active
  FROM po
  LEFT JOIN ss ON po.po_line_id = ss.order_line_id
  LEFT JOIN " & BasePath & ".products AS p ON p.code = po.product_code
where ss.effective_date IS NOT NULL
    and p.active is true
  --  AND ps.sequence = 10
)
SELECT
  prod_id,
  product_code,
--  sequence,
  ROUND(AVG(lead_time_days), 2) AS avg_lead_time,
  ROUND(AVG(lead_time_po_purchase), 2) AS lead_time_po_purchase,
  ROUND(AVG(lead_time_ss_create), 2) AS lead_time_ss_create,
FROM joined_data
--where product_code= 'AD_SIZER'
--where sequence is not null
GROUP BY product_code,prod_id
--ORDER BY prod_id"
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