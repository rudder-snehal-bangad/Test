let
    // Dynamic Parameters
    BillingProject = BillingProjectID,
    Dataset = DatasetName,
    Period = Number.ToText(#"Analysis Period (Years)"),
    // Dynamic table path
    AccountInvoicesTable = "`" & BillingProject & "." & Dataset & ".journal_entries`",

    // Build SQL dynamically
    SQLQuery = "
WITH cm_metrics AS (
    SELECT
      je.date as date,
      -- Revenue Metrics
      ROUND(SUM(CASE WHEN l.account_code = '40010' THEN l.credit - l.debit ELSE 0 END), 2) as sales,
      ROUND(SUM(CASE WHEN l.account_code = '40090' THEN l.credit - l.debit ELSE 0 END), 2) as preorder_sales,
      ROUND(SUM(CASE WHEN l.account_code = '40050' THEN l.credit - l.debit ELSE 0 END), 2) as preorder_revenue,
      ROUND(SUM(CASE WHEN l.account_code = '40020' THEN l.credit - l.debit ELSE 0 END), 2) as sales_discounts,
      ROUND(SUM(CASE WHEN l.account_code = '40030' THEN l.credit - l.debit ELSE 0 END), 2) as refunds,
      ROUND(SUM(CASE WHEN l.account_code = '40110' THEN l.credit - l.debit ELSE 0 END), 2) as sales_allowances,
      ROUND(SUM(CASE WHEN l.account_code = '40100' THEN l.credit - l.debit ELSE 0 END), 2) as chargebacks,
 
      -- Product & Variance
      ROUND(SUM(CASE WHEN l.account_code = '50010' THEN l.credit - l.debit ELSE 0 END), 2) as direct_product_cost,
      ROUND(SUM(CASE WHEN l.account_code = '50020' THEN l.credit - l.debit ELSE 0 END), 2) as purchase_price_variance,
      ROUND(SUM(CASE WHEN l.account_code = '50040' THEN l.credit - l.debit ELSE 0 END), 2) as production_outsourcing,
      ROUND(SUM(CASE WHEN l.account_code = '502' THEN l.credit - l.debit ELSE 0 END), 2) as freight_inward,
      ROUND(SUM(CASE WHEN l.account_code = '50050' THEN l.credit - l.debit ELSE 0 END), 2) as demo_spoilage,
 
      -- Fulfillment and Payment Cost
      ROUND(SUM(CASE WHEN l.account_code = '50030' THEN l.credit - l.debit ELSE 0 END), 2) as outbound_freight_shipping,
      ROUND(SUM(CASE WHEN l.account_code = '61080' THEN l.credit - l.debit ELSE 0 END), 2) as shipping_supplies,
      ROUND(SUM(CASE WHEN l.account_code = '68150' THEN l.credit - l.debit ELSE 0 END), 2) as postage,
      ROUND(SUM(CASE WHEN l.account_code = '61100' THEN l.credit - l.debit ELSE 0 END), 2) as cc_processing_fees,
      ROUND(SUM(CASE WHEN l.account_code = '61060' THEN l.credit - l.debit ELSE 0 END), 2) as royalty_expense,
 
      -- Marketing Expense
      ROUND(SUM(CASE WHEN l.account_code = '61010' THEN l.credit - l.debit ELSE 0 END), 2) as performance_marketing,
      ROUND(SUM(CASE WHEN l.account_code = '61020' THEN l.credit - l.debit ELSE 0 END), 2) as advertising,
      ROUND(SUM(CASE WHEN l.account_code = '62070' THEN l.credit - l.debit ELSE 0 END), 2) as commissions,
      ROUND(SUM(CASE WHEN l.account_code = '61070' THEN l.credit - l.debit ELSE 0 END), 2) as external_commission_expense,
      ROUND(SUM(CASE WHEN l.account_code = '61110' THEN l.credit - l.debit ELSE 0 END), 2) as promotional_giveaways,
      -- ROUND(SUM(CASE WHEN l.account_code = '61110' THEN l.credit - l.debit ELSE 0 END), 2) as promotional_printing,
      ROUND(SUM(CASE WHEN l.account_code = '15050' THEN l.credit - l.debit ELSE 0 END), 2) as prepaid_advertising,
    FROM " & AccountInvoicesTable & " je
    --FROM `fulfil-data-warehouse-227710.gruntstyle.journal_entries` AS je
      LEFT JOIN UNNEST(je.lines) AS l
    WHERE je.date BETWEEN DATE_ADD(current_date(), INTERVAL -" & Period & " YEAR) AND CURRENT_DATE() 
    AND je.state != 'draft'
    GROUP BY je.date
  )
 
  SELECT
    c.*,
    c.sales + c.preorder_sales + c.preorder_revenue - abs(c.sales_discounts + c.refunds + c.sales_allowances + c.chargebacks) as net_sales
  FROM cm_metrics c
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