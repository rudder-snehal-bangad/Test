let
    BillingProject = BillingProjectID,
    Dataset = DatasetName,

    BasePath = BillingProject & "." & Dataset,
  Period = Number.ToText(#"Analysis Period (Years)"),
    SQLQuery =
	"SELECT
  invoice_date,
  invoice_number,
  state,
  invoice_address_phone_number,
  invoice_address_city,
  invoice_region_name,
  invoice_country_name,
  lines.product_code,
  lines.quantity,
  lines.amount,
  purchases.*
  EXCEPT (purchase_line_id),
  payment_term_name
FROM      `" & BasePath & ".account_invoices` inv
LEFT JOIN unnest(lines) AS lines
LEFT JOIN
(
  SELECT lines_s.id AS purchase_line_id,
        purchase_date,
        po.requested_delivery_date,
        po.requested_shipping_date,
        supplier_name
  FROM  `" & BasePath & ".purchase_orders` po,
        unnest(lines) AS lines_s
  WHERE  purchase_date between DATE_ADD(current_date(), INTERVAL -" & Period & " YEAR) AND CURRENT_DATE() ) purchases
ON lines.purchase_line_id = purchases.purchase_line_id
WHERE invoice_type = 'in'
  AND invoice_date between DATE_ADD(current_date(), INTERVAL -" & Period & " YEAR) AND CURRENT_DATE()",
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
