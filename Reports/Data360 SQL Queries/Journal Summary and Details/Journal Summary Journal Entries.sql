let
    Period = Number.ToText(#"Analysis Period (Years)"),
    // Build full table reference dynamically

    FullTableName = 

        "`" & BillingProjectID & "." & DatasetName & ".journal_entries`",
 
    // Build dynamic SQL

    SQLStatement = 

		" WITH base AS (
  SELECT
    je.number,
    je.date,
    l.id AS line_id,
    l.account_core_type,
    l.account_type_name,
    l.account_code,
    l.account_name,
    l.product_variant_name AS product,
    l.product_code,
    l.invoice_line_id AS invoice_line_id,
    ROUND(SUM(l.debit), 2) AS debit,
    ROUND(SUM(l.credit), 2) AS credit,
    ROUND(SUM(l.credit) - SUM(l.debit), 2) AS net
  FROM " & FullTableName & " je
  LEFT JOIN UNNEST(je.lines) AS l
  WHERE je.date between DATE_ADD(current_date(), INTERVAL -" & Period & " YEAR) AND CURRENT_DATE()
  AND  je.state != 'draft'
  GROUP BY
    je.number,
    l.id,
    l.account_name,
    l.account_code,
    l.account_type_name,
    l.account_core_type,
    je.date,
    l.product_variant_name,
    l.product_code,
    l.invoice_line_id
),
cc_names AS (
  SELECT
    l.id AS line_id,
    STRING_AGG(DISTINCT cc.cost_center_name, ', ' ORDER BY cc.cost_center_name) AS cost_center_names
  FROM " & FullTableName & " je
  
  LEFT JOIN UNNEST(je.lines) AS l
  LEFT JOIN UNNEST(l.cost_center_lines) AS cc
  WHERE je.date between DATE_ADD(current_date(), INTERVAL -" & Period & " YEAR) AND CURRENT_DATE() AND  je.state != 'draft'
  GROUP BY l.id
)
SELECT
  b.*,
  c.cost_center_names
FROM base b
LEFT JOIN cc_names c
  ON b.line_id = c.line_id

		",

    // Connect to BigQuery using parameter

    Source =

        Value.NativeQuery(

            GoogleBigQuery.Database(

                [BillingProject = BillingProjectID, UseStorageApi = false]

            ){[Name = BillingProjectID]}[Data],

            SQLStatement,

            null,

            [EnableFolding = true]

        ),
    #"Capitalized Each Word" = Table.TransformColumns(Source,{{"account_core_type", Text.Proper, type text}}),
    #"Added Custom" = Table.AddColumn(#"Capitalized Each Word", "sort_by_account_core", each if [account_core_type] = "income" or [account_core_type] = "Income" then 1
        else if [account_core_type] = "expense" or [account_core_type] = "Expense" then 2
        else if [account_core_type] = "asset" or [account_core_type] = "Asset" then 3
        else if [account_core_type] = "liability" or [account_core_type] = "Liability" then 4
        else if [account_core_type] = "equity" or [account_core_type] = "Equity" then 5
        else 6)

in

    #"Added Custom"