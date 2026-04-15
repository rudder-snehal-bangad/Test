let
    BillingProject = BillingProjectID,
    Dataset = DatasetName,

    BasePath = BillingProject & "." & Dataset,
    Period = Number.ToText(#"Analysis Period (Years)"),
    SQLQuery ="
    WITH all_receipts_unioned AS (
    -- Unify all incoming inventory from suppliers, manufacturing, and internal transfers.
    SELECT
        'supplier_shipment' AS source_document,
        ss.id,
        ss.number,
        DATE(ss.effective_date) AS receipt_date,
        m.product_code,
        m.cost_price,
        m.quantity,
        ss.warehouse_code,ss.warehouse_id
    FROM
        `" & BasePath & ".supplier_shipments` AS ss
    LEFT JOIN
        UNNEST(moves) AS m
    WHERE
        m.from_location_type = 'supplier' AND m.to_location_type = 'storage' AND m.order_id IS NOT NULL AND ss.state = 'done'
        AND DATE(ss.create_date) between DATE_ADD(current_date(), INTERVAL -" & Period & " YEAR) AND CURRENT_DATE()
    UNION ALL
    SELECT
        'manufacturing_order' AS source_document,
        mo.id,
        mo.number,
        DATE(mo.effective_date) AS receipt_date,
        m.product_code,
        m.cost_price,
        m.quantity,
        mo.warehouse_code,mo.warehouse_id
    FROM
        `" & BasePath & ".manufacturing_orders` AS mo
    LEFT JOIN
        UNNEST(moves) AS m
    WHERE
        mo.state = 'done' AND m.from_location_type = 'production' AND m.to_location_type = 'storage'
        AND DATE(mo.create_date) between DATE_ADD(current_date(), INTERVAL -" & Period & " YEAR) AND CURRENT_DATE()
    UNION ALL
    SELECT
        'internal_shipment' AS source_document,
        s.id,
        s.number,
        DATE(s.effective_date) AS receipt_date,
        l.product_code,
        NULL AS cost_price,
        l.quantity,
        s.to_warehouse_code AS warehouse_code,s.to_warehouse_id as warehouse_id
    FROM
        `" & BasePath & ".internal_shipments` AS s
    LEFT JOIN
        UNNEST(lines) AS l
    WHERE
        s.state = 'done'
),

base_with_inventory AS (
    -- Combine receipts with current inventory levels and product status.
    SELECT DISTINCT
        fr.source_document,
        fr.id,
        fr.number,
        fr.receipt_date,
        COALESCE(ic.product_code, fr.product_code) AS product_code,
        COALESCE(ic.warehouse_code, fr.warehouse_code) AS warehouse_code,
        COALESCE(ic.warehouse_id, fr.warehouse_id) AS warehouse_id,
        fr.cost_price,
        fr.quantity,
        ic.quantity_on_hand,
        ic.warehouse AS warehouse_name,
        p.active,
        (SELECT AVG(cost) FROM UNNEST(p.costs)) AS product_default_cost
    FROM
        all_receipts_unioned AS fr
    FULL OUTER JOIN
        `" & BasePath & ".inventory_current` AS ic
        ON fr.product_code = ic.product_code AND fr.warehouse_code = ic.warehouse_code
    LEFT JOIN
        `" & BasePath & ".products` p
        ON COALESCE(ic.product_code, fr.product_code) = p.code
),

calculations_step1 AS (
    -- Add a row index and calculate the age of each receipt.
    SELECT
        *,
        ROW_NUMBER() OVER (PARTITION BY product_code, warehouse_code ORDER BY receipt_date ASC, id ASC) as sequence,
        CASE
            WHEN receipt_date IS NULL THEN 10000000000
            ELSE DATE_DIFF(CURRENT_DATE(), receipt_date, DAY)
        END AS aging
    FROM
        base_with_inventory
),

calculations_step2 AS (
    -- Calculate a running total of received quantity.
    SELECT
        *,
        SUM(IFNULL(quantity, 0)) OVER (PARTITION BY product_code, warehouse_code ORDER BY sequence) AS running_total
    FROM
        calculations_step1
),

calculations_step3 AS (
    -- Determine the total sold quantity for each product.
    SELECT
        *,
        (MAX(running_total) OVER (PARTITION BY product_code, warehouse_code)) - IFNULL(quantity_on_hand, 0) AS sold
    FROM
        calculations_step2
),

calculations_step4 AS (
    -- Rank receipts to identify which ones have been sold.
    SELECT
        *,
        CASE
            WHEN (running_total <= sold) THEN 0
            ELSE RANK() OVER (PARTITION BY product_code, warehouse_code, (running_total > sold) ORDER BY sequence ASC)
        END AS rnk
    FROM
        calculations_step3
),

final_calculations AS (
    -- Calculate the final remaining quantity and its associated cost.
    SELECT
        *,
        CASE
            WHEN id IS NULL AND quantity_on_hand > 0 THEN quantity_on_hand
            WHEN rnk = 0 THEN NULL
            WHEN rnk = 1 THEN running_total - sold
            ELSE quantity
        END AS final_quantity,
        (
            COALESCE(NULLIF(product_default_cost, 0), cost_price)
        )
        *
        (CASE -- Re-evaluating Final Quantity
            WHEN id IS NULL AND quantity_on_hand > 0 THEN quantity_on_hand
            WHEN rnk = 0 THEN NULL
            WHEN rnk = 1 THEN running_total - sold
            ELSE quantity
        END) AS final_cost_price
    FROM
        calculations_step4
),
final_aging AS (

      SELECT
          product_code,
          warehouse_name,warehouse_id,
          SUM(CASE 
                  WHEN aging BETWEEN 0 AND 90 
                  THEN final_quantity 
                  ELSE 0 
              END) AS `0-90 Days`,

          SUM(CASE 
                  WHEN aging BETWEEN 91 AND 180 
                  THEN final_quantity 
                  ELSE 0 
              END) AS `91-180 Days`,

          SUM(CASE 
                  WHEN aging BETWEEN 181 AND 360 
                  THEN final_quantity 
                  ELSE 0 
              END) AS `181-360 Days`,

          SUM(CASE 
                  WHEN aging > 360 
                  THEN final_quantity 
                  ELSE 0 
              END) AS `360+ Days`

      FROM final_calculations
      WHERE final_quantity > 0
      GROUP BY product_code,warehouse_name,warehouse_id
  )
  SELECT *
  FROM final_aging
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