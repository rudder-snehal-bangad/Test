let
    BillingProject = BillingProjectID,
    Dataset = DatasetName,

    BasePath = BillingProject & "." & Dataset,
    Period = Number.ToText(#"Analysis Period (Years)"),
    SQLQuery ="
    WITH all_receipts_unioned AS (

    -- Unify all incoming inventory from suppliers and manufacturing orders.
    SELECT
        'supplier_shipment' AS source_document,
        ss.id,
        ss.number,
        DATE(ss.effective_date) AS receipt_date,
        m.product_code,
        m.cost_price,
        m.quantity,
        ss.warehouse_code,
        ss.warehouse_name
    FROM
        `" & BasePath & ".supplier_shipments` AS ss
    LEFT JOIN
        UNNEST(moves) AS m
    WHERE
        m.from_location_type = 'supplier'
        AND m.to_location_type = 'storage'
        AND m.order_id IS NOT NULL
        AND ss.state = 'done'
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
        mo.warehouse_code,
        mo.warehouse_name
    FROM
        `" & BasePath & ".manufacturing_orders` AS mo
    LEFT JOIN
        UNNEST(moves) AS m
    WHERE
        mo.state = 'done'
        AND m.from_location_type = 'production'
        AND m.to_location_type = 'storage'
        AND DATE(mo.create_date) between DATE_ADD(current_date(), INTERVAL -" & Period & " YEAR) AND CURRENT_DATE()
),

/* Sum ONLY positive inventory_current.quantity_on_hand for rows that have no matching receipt.
   This prevents allocating negative QOH to receipts. Grouped by product_code. */
inventory_only_adj AS (
    SELECT
        ic.product_code,
        SUM(CASE WHEN ic.quantity_on_hand > 0 THEN ic.quantity_on_hand ELSE 0 END) AS adj_qty
    FROM
        `" & BasePath & ".inventory_current` ic
    LEFT JOIN
        all_receipts_unioned fr
        ON ic.product_code = fr.product_code
           AND ic.warehouse_code = fr.warehouse_code
    WHERE
        fr.id IS NULL AND fr.source_document IS NULL
    GROUP BY
        ic.product_code
),

/* Latest receipt row per product (used to determine the target warehouse for applying adj_qty). */
latest_receipt_row AS (
    SELECT
        product_code,
        id AS latest_receipt_id,
        warehouse_code AS latest_receipt_warehouse,
        receipt_date AS latest_receipt_date
    FROM (
        SELECT
            *,
            ROW_NUMBER() OVER (PARTITION BY product_code ORDER BY receipt_date DESC, id DESC) AS rn
        FROM
            all_receipts_unioned
    )
    WHERE rn = 1
),

/* FULL OUTER JOIN so products that exist only in inventory_current are preserved.
   We create original_quantity_on_hand (display) and allocated_quantity_on_hand (used in calculations).
   IMPORTANT: inventory-only rows are set to allocated = 0 ONLY WHEN a receipt exists for that product.
   If no receipt exists (lr is NULL), inventory-only rows keep their quantity.
   Also, we only apply inv_adj.adj_qty when inv_adj.adj_qty > 0 (prevents allocating negatives).
   When adding adj_qty to a receipt row, negative existing ic.quantity_on_hand is ignored (treated as 0).
*/
base_with_inventory AS (

    SELECT DISTINCT
        fr.source_document,
        fr.id,
        fr.number,
        fr.receipt_date,

        -- take product/warehouse from whichever side has it
        COALESCE(ic.product_code, fr.product_code) AS product_code,
        COALESCE(ic.warehouse_code, fr.warehouse_code) AS warehouse_code,

        fr.cost_price,
        fr.quantity,

        -- preserve raw QOH for visibility (NULL if no inventory_current row)
        ic.quantity_on_hand AS original_quantity_on_hand,

        -- allocated_quantity_on_hand: the value used in downstream calculations.
        CASE
            /*
             * If this is an inventory-only row (no receipt) AND there exists at least one receipt
             * for the product (lr.latest_receipt_id IS NOT NULL) then deallocate here (set to 0)
             * because the qty will be redistributed to receipt rows.
             */
            WHEN fr.source_document IS NULL AND fr.id IS NULL AND lr.latest_receipt_id IS NOT NULL THEN 0

            /*
             * If this receipt row's product+warehouse matches the latest_receipt's warehouse for the product,
             * and the product-level adj_qty is positive, add the product-level adj_qty (apply to ALL such receipt rows).
             * Also ignore negative ic.quantity_on_hand by using COALESCE(GREATEST(ic.quantity_on_hand,0),0)
             * so negative existing QOH doesn't reduce the adj_qty.
             */
            WHEN lr.latest_receipt_warehouse IS NOT NULL
                 AND COALESCE(ic.product_code, fr.product_code) = lr.product_code
                 AND COALESCE(ic.warehouse_code, fr.warehouse_code) = lr.latest_receipt_warehouse
                 AND COALESCE(inv_adj.adj_qty, 0) > 0
                THEN COALESCE(GREATEST(ic.quantity_on_hand, 0), 0) + COALESCE(inv_adj.adj_qty, 0)

            -- default: use existing inventory_current quantity_on_hand (or 0 if NULL)
            ELSE COALESCE(ic.quantity_on_hand, 0)
        END AS allocated_quantity_on_hand,

        COALESCE(ic.warehouse, fr.warehouse_name) AS warehouse_name,
        p.active,
        (SELECT AVG(cost) FROM UNNEST(p.costs)) AS product_default_cost,
        lr.latest_receipt_id,
        lr.latest_receipt_date

    FROM
        all_receipts_unioned fr
    FULL OUTER JOIN
        `" & BasePath & ".inventory_current` ic
        ON fr.product_code = ic.product_code
           AND fr.warehouse_code = ic.warehouse_code

    LEFT JOIN
        `" & BasePath & ".products` p
        ON COALESCE(ic.product_code, fr.product_code) = p.code

    LEFT JOIN
        inventory_only_adj inv_adj
        ON COALESCE(ic.product_code, fr.product_code) = inv_adj.product_code

    LEFT JOIN
        latest_receipt_row lr
        ON COALESCE(ic.product_code, fr.product_code) = lr.product_code
),

calculations_step1 AS (

    -- Add a row index and calculate the age of each receipt.
    SELECT
        *,
        ROW_NUMBER() OVER (PARTITION BY product_code, warehouse_code ORDER BY receipt_date ASC, id ASC) AS sequence,
        CASE
            WHEN receipt_date IS NULL THEN 10000000000
            ELSE DATE_DIFF(CURRENT_DATE(), receipt_date, DAY)
        END AS aging
    FROM
        base_with_inventory
),

calculations_step2 AS (

    -- Calculate a running total of received quantity for each product+warehouse.
    SELECT
        *,
        SUM(IFNULL(quantity, 0)) OVER (PARTITION BY product_code, warehouse_code ORDER BY sequence) AS running_total
    FROM
        calculations_step1
),

calculations_step3 AS (

    -- Determine sold quantity using allocated_quantity_on_hand (prevents double-count).
    SELECT
        *,
        (MAX(running_total) OVER (PARTITION BY product_code, warehouse_code)) - IFNULL(allocated_quantity_on_hand, 0) AS sold
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
            -- For inventory-only rows, if allocated_quantity_on_hand > 0 (no receipts exist), keep it.
            WHEN id IS NULL AND allocated_quantity_on_hand > 0 THEN allocated_quantity_on_hand
            WHEN rnk = 0 THEN NULL
            WHEN rnk = 1 THEN running_total - sold
            ELSE quantity
        END AS final_quantity,

        -- final_cost_price = unit_cost * final_quantity; choose product_default_cost if present otherwise cost_price
        (COALESCE(NULLIF(product_default_cost, 0), cost_price)
         *
         CASE
            WHEN id IS NULL AND allocated_quantity_on_hand > 0 THEN allocated_quantity_on_hand
            WHEN rnk = 0 THEN NULL
            WHEN rnk = 1 THEN running_total - sold
            ELSE quantity
         END
        ) AS final_cost_price

    FROM
        calculations_step4
),

aging_buckets AS (

    -- Generate text-based aging buckets and numeric sort columns.
    SELECT
        *,
        CASE WHEN receipt_date IS NULL THEN 'N/A' WHEN aging >= 330 THEN '330+' ELSE FORMAT('%d-%d', (SAFE_CAST(FLOOR((GREATEST(aging, 1)-1)/30) AS INT64)*30)+1, (SAFE_CAST(FLOOR((GREATEST(aging, 1)-1)/30) AS INT64)+1)*30) END AS days_30,
        CASE WHEN receipt_date IS NULL THEN 'N/A' WHEN aging >= 495 THEN '495+' ELSE FORMAT('%d-%d', (SAFE_CAST(FLOOR((GREATEST(aging, 1)-1)/45) AS INT64)*45)+1, (SAFE_CAST(FLOOR((GREATEST(aging, 1)-1)/45) AS INT64)+1)*45) END AS days_45,
        CASE WHEN receipt_date IS NULL THEN 'N/A' WHEN aging >= 540 THEN '540+' ELSE FORMAT('%d-%d', (SAFE_CAST(FLOOR((GREATEST(aging, 1)-1)/60) AS INT64)*60)+1, (SAFE_CAST(FLOOR((GREATEST(aging, 1)-1)/60) AS INT64)+1)*60) END AS days_60,
        CASE WHEN receipt_date IS NULL THEN 'N/A' WHEN aging >= 630 THEN '630+' ELSE FORMAT('%d-%d', (SAFE_CAST(FLOOR((GREATEST(aging, 1)-1)/90) AS INT64)*90)+1, (SAFE_CAST(FLOOR((GREATEST(aging, 1)-1)/90) AS INT64)+1)*90) END AS days_90,
        CASE WHEN receipt_date IS NULL THEN 'N/A' WHEN aging >= 600 THEN '600+' ELSE FORMAT('%d-%d', (SAFE_CAST(FLOOR((GREATEST(aging, 1)-1)/120) AS INT64)*120)+1, (SAFE_CAST(FLOOR((GREATEST(aging, 1)-1)/120) AS INT64)+1)*120) END AS days_120,
        CASE WHEN receipt_date IS NULL THEN 'N/A' WHEN aging >= 540 THEN '540+' ELSE FORMAT('%d-%d', (SAFE_CAST(FLOOR((GREATEST(aging, 1)-1)/180) AS INT64)*180)+1, (SAFE_CAST(FLOOR((GREATEST(aging, 1)-1)/180) AS INT64)+1)*180) END AS days_180,

        CASE WHEN aging >= 330 THEN 11 ELSE SAFE_CAST(FLOOR((GREATEST(aging, 1) - 1) / 30) AS INT64) END AS days_30_sort,
        CASE WHEN aging >= 495 THEN 11 ELSE SAFE_CAST(FLOOR((GREATEST(aging, 1) - 1) / 45) AS INT64) END AS days_45_sort,
        CASE WHEN aging >= 540 THEN 9 ELSE SAFE_CAST(FLOOR((GREATEST(aging, 1) - 1) / 60) AS INT64) END AS days_60_sort,
        CASE WHEN aging >= 630 THEN 7 ELSE SAFE_CAST(FLOOR((GREATEST(aging, 1) - 1) / 90) AS INT64) END AS days_90_sort,
        CASE WHEN aging >= 600 THEN 5 ELSE SAFE_CAST(FLOOR((GREATEST(aging, 1) - 1) / 120) AS INT64) END AS days_120_sort,
        CASE WHEN aging >= 540 THEN 3 ELSE SAFE_CAST(FLOOR((GREATEST(aging, 1) - 1) / 180) AS INT64) END AS days_180_sort

    FROM
        final_calculations
)

SELECT
    source_document,
    id,
    number,
    receipt_date,
    product_code,
    warehouse_code,
    warehouse_name,
    active,
    round(cost_price,2) as cost_price,
    quantity,
    original_quantity_on_hand,
    allocated_quantity_on_hand,
    sequence,
    aging,
    running_total,
    sold,
    rnk,
    final_quantity,
    Round(final_cost_price,2) as final_cost_price,
    days_30,
    days_45,
    days_60,
    days_90,
    days_120,
    days_180,
    days_30_sort,
    days_45_sort,
    days_60_sort,
    days_90_sort,
    days_120_sort,
    days_180_sort
FROM
    aging_buckets
ORDER BY
    product_code,
    warehouse_code,
    sequence",
    Source = Value.NativeQuery(
        GoogleBigQuery.Database(
            [BillingProject = BillingProject, UseStorageApi = false]
        ){[Name = BillingProject]}[Data],
        SQLQuery,
        null,
        [EnableFolding = true]
    ),
    #"Renamed Columns" = Table.RenameColumns(Source,{{"number", "number 1"}})
in
    #"Renamed Columns"