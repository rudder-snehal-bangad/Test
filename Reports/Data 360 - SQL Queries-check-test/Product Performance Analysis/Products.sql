let
    BillingProject = BillingProjectID,
    Dataset = DatasetName,

    SQLQuery = "
with products as(SELECT 
distinct product.id,
product.code as product_code,
variant_name,
product.template_name,
product.template_code,
product.category_name,
product.brand_name,
product.product_type,
product.active,
product.sellable,
product.manufacturable,
--product.is_gift_card,
product.purchasable,
product.hs_code,
product.create_date,
product.fulfil_strategy,
product.consumable,
product.length,
co.cost as cost_price,
lp.list_price as list_price,
a.attribute_name,
a.value
FROM " & BillingProject & "." & Dataset & ".products product 
left join unnest(costs) as co 
left join unnest(list_prices) as lp
left join unnest(attributes) as a
where category_root_name not in ('SERVICE','To be Classified','PACKAGING','OPTIONS_HIDDEN_PRODUCT')
),
latest_invoices AS (
  SELECT
    ai_lines.product_code,
    ai_lines.unit_price AS last_received_invoice_price,
    ai.invoice_date AS last_received_invoice_date
  FROM " & BillingProject & "." & Dataset & ".account_invoices AS ai,
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
  FROM " & BillingProject & "." & Dataset & ".purchase_orders AS po
    LEFT JOIN UNNEST(po.lines) AS po_lines
    LEFT JOIN (
      SELECT ss_mov.effective_date, ss_mov.order_line_id, ss_mov.unit_price
      FROM " & BillingProject & "." & Dataset & ".supplier_shipments AS ss
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
)
select p.*,
 po.last_received_po_price as lr_po_price,
  li.last_received_invoice_price as lr_invoice_price, 
from products p
 LEFT JOIN latest_invoices li ON p.product_code = li.product_code
 LEFT JOIN latest_po po ON p.product_code = po.product_code
",

    Source =
        Value.NativeQuery(
            GoogleBigQuery.Database(
                [BillingProject = BillingProject, UseStorageApi = false]
            ){[Name = BillingProject]}[Data],
            SQLQuery,
            null,
            [EnableFolding = true]
        )
in
    Source