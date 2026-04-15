let
    BillingProject = BillingProjectID,
    Dataset = DatasetName,

    BasePath = BillingProject & "." & Dataset,

    SQLQuery ="-- --item_master_data

WITH products AS (
  SELECT 
    prod.active,
    prod.id AS product_id,
    prod.code AS product_code,
    prod.variant_name AS variant_name,
    category_name, 
    purchasable, sellable,	
    product_type,
    hs_code, country_of_origin_code,
    lp.list_price,
    cp.cost as cost_price,
  FROM `" & BasePath & ".products` AS prod
      LEFT JOIN UNNEST(prod.list_prices) as lp
      LEFT JOIN UNNEST(prod.costs) as cp
),

latest_invoices AS (
  SELECT
    ai_lines.product_code,
    ai_lines.unit_price AS last_received_invoice_price,
    ai.invoice_date AS last_received_invoice_date
  FROM `" & BasePath & ".account_invoices` AS ai,
       UNNEST(ai.lines) AS ai_lines
  WHERE ai.state NOT IN ('cancel') AND ai.invoice_type = 'in' AND ai_lines.unit_price IS NOT NULL
  QUALIFY ROW_NUMBER() OVER (PARTITION BY ai_lines.product_code ORDER BY ai.invoice_date DESC) = 1
),

latest_po AS (
  SELECT
    po_lines.product_code,
    max(ss.effective_date) as last_received_po_date,
    ARRAY_AGG(ss.unit_price ORDER BY po.purchase_date DESC LIMIT 1)[OFFSET(0)] AS last_received_po_price,
    -- ARRAY_AGG(po.purchase_date ORDER BY po.purchase_date DESC LIMIT 1)[OFFSET(0)] AS last_po_purchase_date
  FROM " & BasePath & ".purchase_orders AS po
    LEFT JOIN UNNEST(po.lines) AS po_lines
    LEFT JOIN (
      SELECT ss_mov.effective_date, ss_mov.order_line_id, ss_mov.unit_price
      FROM " & BasePath & ".supplier_shipments AS ss
        LEFT JOIN UNNEST(ss.moves) AS ss_mov
      WHERE ss_mov.from_location_type = 'supplier' AND ss_mov.to_location_type = 'storage' AND ss_mov.state='done'
    ) AS ss ON ss.order_line_id = po_lines.id
  WHERE
    po_lines.product_code IS NOT NULL
    AND po_lines.unit_price IS NOT NULL
    AND po.purchase_date IS NOT NULL
    AND po.state IN ('done', 'processing')
    AND ss.effective_date IS NOT NULL
  GROUP BY 1
),

suppliers AS (
  SELECT product_code, primary_supplier_name
  FROM (
    SELECT
      ps.product_code, ps.supplier_name AS primary_supplier_name, ps.sequence,
      ROW_NUMBER() OVER (
        PARTITION BY ps.product_code
        ORDER BY CASE WHEN ps.sequence = 10 THEN 0 ELSE 1 END, ps.sequence
      ) AS rn
    FROM `" & BasePath & ".product_suppliers` ps
  )
  WHERE rn = 1
)

SELECT
  CASE WHEN pa.active THEN 'True' ELSE 'False' END AS active,
  pa.product_id,
  pa.product_code,
  pa.variant_name,
  pa.category_name,
  pa.purchasable,
  pa.sellable,
  pa.product_type,
  pa.hs_code,
  -- pt.primary_supplier,
  -- pt.primary_supplier_country,
  pa.list_price,
  pa.cost_price,
  po.last_received_po_price as lr_po_price,
  li.last_received_invoice_price as lr_invoice_price, 
  li.last_received_invoice_date as lr_invoice_date,
  po.last_received_po_date as lr_po_date
FROM `" & BasePath & ".products` AS pr
  LEFT JOIN products pa ON pr.code = pa.product_code
  LEFT JOIN suppliers s ON pr.code = s.product_code
  LEFT JOIN latest_invoices li ON pr.code = li.product_code
  -- LEFT JOIN bom_data bd ON pr.code = bd.product_code
  LEFT JOIN latest_po po ON pr.code = po.product_code
  -- LEFT JOIN `mbm-etl.gruntstyle.products_and_tariff` pt on pr.code = pt.product_code
ORDER BY pa.product_id"
	,
	Source = Value.NativeQuery(
        GoogleBigQuery.Database(
            [BillingProject = BillingProject, UseStorageApi = false]
        ){[Name = BillingProject]}[Data],
        SQLQuery,
        null,
        [EnableFolding = true]
    ),
    #"Sorted Rows" = Table.Sort(Source,{{"product_id", Order.Ascending}}),
    #"Removed Duplicates" = Table.Distinct(#"Sorted Rows", {"product_id"})
in
    #"Removed Duplicates"