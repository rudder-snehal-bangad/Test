let
    BillingProject = BillingProjectID,
    Dataset = DatasetName,

    BasePath = BillingProject & "." & Dataset,
    Period = Number.ToText(#"Analysis Period (Years)"),
    SQLQuery ="--item_master_report
 
 WITH 
products_data AS (
  SELECT
     distinct prod.id as product_id,prod.active,prod.code as product_code,prod.variant_name as product_variant_name,
     prod.template_name,
      prod.category_root_name AS parent_product_category,
      prod.category_name,
      prod.brand_name,
      prod.purchasable,
      prod.consumable,
      prod.sellable,
      prod.manufacturable,
      prod.fulfil_strategy,
      lp.list_price,
      cp.cost as cost_price,channel_cutback,
      hs_code, country_of_origin_code,
      --  to_be_archived,
    product_type, 
    Date(create_date) as launch_date  
  FROM " & BasePath & ".products prod
  LEFT JOIN UNNEST(prod.list_prices) as lp
  LEFT JOIN UNNEST(prod.costs) as cp

    LEFT JOIN (
      SELECT id, code, STRING_AGG(CONCAT(channel_name, ': ', CAST(inventory_level_cutback_value AS STRING)), ', ' ORDER BY channel_name)    AS  channel_cutback
      FROM (
        SELECT DISTINCT p.id, p.code, l.channel_name, l.inventory_level_cutback_value
        FROM `" & BasePath & ".products` p
        LEFT JOIN UNNEST(listings) AS l 
        WHERE p.active = TRUE AND l.inventory_level_cutback_value IS NOT NULL
      )
      GROUP BY id, code
    ) p on prod.code = p.code
    

),

last_po_inv AS (
  SELECT pl.product_code, pl.unit_price AS po_price, NULL AS inv_price, po.purchase_date AS dt, po.create_date AS created, 'po' AS src
  FROM `" & BasePath & ".purchase_orders` po, UNNEST(po.lines) AS pl
  WHERE pl.line_type = 'purchase'

  UNION ALL

  SELECT il.product_code, NULL AS po_price, il.unit_price AS inv_price, ai.invoice_date AS dt, ai.create_date AS created, 'inv' AS src
  FROM `" & BasePath & ".account_invoices` ai, UNNEST(ai.lines) AS il
  WHERE ai.invoice_type = 'out' AND il.type = 'sale'
),

product_prices AS (
  SELECT
    pd.product_code,
    TRUNC(SAFE_DIVIDE(list_price - cost_price, list_price) * 100,2) AS imu_percent,    
    list_price as ff_list_price, cost_price as ff_cost_price, 
    -- sh_list_price, sh_compare_at_price, 
    last_po_price, last_unit_price
  FROM products_data pd
    LEFT JOIN (
      SELECT distinct product_code, MAX(po_price)  AS last_po_price, MAX(inv_price) AS last_unit_price
      FROM (SELECT * FROM last_po_inv QUALIFY ROW_NUMBER() OVER (PARTITION BY product_code, src ORDER BY dt DESC, created DESC) = 1)
      GROUP BY product_code
    ) poinv on pd.product_code = poinv.product_code
),

suppliers AS (
  SELECT
    a1.product_code,
    STRING_AGG(a1.  supplier_name, ', ' ORDER BY CASE WHEN sequence=10 THEN 0 ELSE 1 END, sequence) AS supplier,
    ARRAY_AGG(moq IGNORE NULLS ORDER BY CASE WHEN sequence=10 THEN 0 ELSE 1 END, sequence)[OFFSET(0)] AS moq,
    -- MAX(a2.avg_lead_time) as avg_lead_time
  FROM (
    SELECT product_code, supplier_name, moq, sequence
    FROM (
      SELECT ps.*, ROW_NUMBER() OVER (PARTITION BY product_code, supplier_name ORDER BY CASE WHEN sequence=10 THEN 0 ELSE 1 END, sequence) rn
      FROM `" & BasePath & ".product_suppliers` ps
    )
    WHERE rn = 1
  ) a1 
  -- LEFT JOIN mbm-etl.demand_prediction_views.pvm_lead_time a2 on a1.product_code = a2.product_code
  GROUP BY product_code
  ORDER BY product_code
),


inventory_aging as (
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
            
            WHEN fr.source_document IS NULL AND fr.id IS NULL AND lr.latest_receipt_id IS NOT NULL THEN 0
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
final_aging AS (

      SELECT
          product_code,

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
      GROUP BY product_code
  )
  SELECT *
  FROM final_aging
),

inventory_on_hand AS (
  SELECT 
    invc.product_code, 
    SUM(quantity_on_hand) as quantity_on_hand,
    SUM(quantity_available) as quantity_available,
    SUM(quantity_outbound) as quantity_outbound,
    SUM(quantity_inbound) as quantity_inbound,
    SUM(quantity_on_hand) * MAX(list_price) as on_hand_retail_lp,
    SUM(quantity_on_hand) * MAX(cost_price) as on_hand_cost_cp,  
    SUM(quantity_available) * MAX(list_price) as qty_available_retail_lp,
    SUM(quantity_available) * MAX(cost_price) as qty_available_cost_cp,  
    SUM(quantity_outbound) * MAX(list_price) as quantity_outbound_retail_lp,
    SUM(quantity_outbound) * MAX(cost_price) as quantity_outbound_cost_cp,
    SUM(quantity_inbound) * MAX(list_price) as quantity_inbound_retail_lp,
    SUM(quantity_inbound) * MAX(cost_price) as quantity_inbound_cost_cp
  FROM `" & BasePath & ".inventory_current` invc
    LEFT JOIN products_data pro on invc.product_code = pro.product_code
  -- WHERE warehouse_id = 4
  GROUP By 1
),

on_orders AS (
  SELECT
    q.product_code,
    q.on_order_quantity,
    pd.list_price * q.on_order_quantity AS on_orders_retail_lp, on_orders_cost_cp
    -- pd.cost_price * q.on_order_quantity AS on_orders_cost_cp
  FROM (
    SELECT l.product_code, SUM(IFNULL(l.quantity, 0)) AS on_order_quantity, SUM(IFNULL(l.quantity, 0)*l.unit_price) AS on_orders_cost_cp
    FROM `" & BasePath & ".purchase_orders` AS p,
      UNNEST(p.lines) AS l
    WHERE p.state IN ('confirmed', 'processing') AND l.line_type = 'purchase'
    GROUP BY l.product_code
  ) AS q LEFT JOIN products_data AS pd ON q.product_code = pd.product_code
),

last_received AS (
  SELECT
    m.product_code,
    m.quantity_in_default_uom AS last_received_units,
    pd.list_price * m.quantity_in_default_uom as last_received_retail_lp,
    pd.cost_price * m.quantity_in_default_uom as last_received_cost_cp
  FROM `" & BasePath & ".supplier_shipments` AS s,
    UNNEST(s.moves) AS m
    LEFT JOIN products_data pd on m.product_code = pd.product_code
  WHERE s.state = 'done' AND m.state = 'done' AND m.from_location_type   = 'supplier'
  QUALIFY ROW_NUMBER() OVER ( PARTITION BY m.product_code ORDER BY m.effective_date DESC) = 1
),

ltd_received AS (
  SELECT
    m.product_code,
    SUM(IFNULL(m.quantity_in_default_uom, 0)) AS ltd_received_units,
    SUM(pd.list_price * IFNULL(m.quantity_in_default_uom, 0)) AS ltd_received_retail_lp,
    SUM(pd.cost_price * IFNULL(m.quantity_in_default_uom, 0)) AS ltd_received_cost_cp
  FROM `" & BasePath & ".supplier_shipments` AS s
    LEFT JOIN UNNEST(s.moves) AS m
    LEFT JOIN products_data AS pd ON m.product_code = pd.product_code
  WHERE s.state = 'done' AND m.state = 'done' AND m.from_location_type   = 'supplier'
  GROUP BY m.product_code
),

final AS (
  SELECT
    active,product_id, pd.product_code,
    launch_date, 
    sp1.*EXCEPT(product_code),
    CASE 
    WHEN quantity_available <= 0 
         
    THEN 'Out of Stock'
    ELSE 'In Stock'
    END AS stock_status,
    -- CASE WHEN Coalesce(quantity_on_hand,0)>0 THEN 'In Stock' ELSE  'Out of Stock' END AS stock_status,
    -- CASE WHEN l90d_gross_u IS NULL OR l90d_gross_u = 0 THEN NULL ELSE CEIL( (l90d_gross_u / 90) * (avg_lead_time + 7)) END AS reorder_point,
    channel_cutback,
    -- inventory_aging
    invag.*EXCEPT(product_code),
    -- on hand
    inv1.*EXCEPT(product_code), 
    -- on_orders
    inv2.*EXCEPT(product_code),
    -- last received
    inv3.*EXCEPT(product_code),
    -- ltd received    
    inv4.*EXCEPT(product_code),

       
  FROM products_data pd 
    LEFT JOIN suppliers sp1 on pd.product_code = sp1.product_code
    LEFT JOIN inventory_aging invag on pd.product_code = invag.product_code
    LEFT JOIN inventory_on_hand inv1 on pd.product_code = inv1.product_code
    LEFT JOIN on_orders inv2 on pd.product_code = inv2.product_code
    LEFT JOIN last_received inv3 on pd.product_code = inv3.product_code
    LEFT JOIN ltd_received inv4 on pd.product_code = inv4.product_code
  ORDER BY 2
 )

 SELECT * from final",
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