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


// let
//     Source = Value.NativeQuery(GoogleBigQuery.Database([BillingProject="rudder-data360-etl", UseStorageApi=false]){[Name="rudder-data360-etl"]}[Data], "SELECT#(lf)  invoice_date,#(lf)  invoice_number,#(lf)  state,#(lf)  invoice_address_phone_number,#(lf)  invoice_address_city,#(lf)  invoice_region_name,#(lf)  invoice_country_name,#(lf)  lines.product_code,#(lf)  lines.quantity,#(lf)  lines.amount,#(lf)  purchases.*#(lf)  EXCEPT (purchase_line_id),#(lf)  payment_term_name#(lf)FROM      `rudder-data360-etl.fulfil_gruntstyle_bqdwh.account_invoices` inv#(lf)LEFT JOIN unnest(lines) AS lines#(lf)LEFT JOIN#(lf)(#(lf)  SELECT lines_s.id AS purchase_line_id,#(lf)        purchase_date,#(lf)        po.requested_delivery_date,#(lf)        po.requested_shipping_date,#(lf)        supplier_name#(lf)  FROM  `rudder-data360-etl.fulfil_gruntstyle_bqdwh.purchase_orders` po,#(lf)        unnest(lines) AS lines_s#(lf)  WHERE  purchase_date BETWEEN date_trunc(date_add(CURRENT_DATE(), interval -2 year), year) AND    CURRENT_DATE() ) purchases#(lf)ON lines.purchase_line_id = purchases.purchase_line_id#(lf)WHERE invoice_type = 'in'#(lf)  AND invoice_date BETWEEN date_add(CURRENT_DATE(), interval -2 year) AND       CURRENT_DATE()", null, [EnableFolding=true])
// in
//     Source