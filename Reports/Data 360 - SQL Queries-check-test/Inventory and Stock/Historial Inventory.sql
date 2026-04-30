let
    BillingProject = BillingProjectID,
    Dataset = DatasetName,

    BasePath = BillingProject & "." & Dataset,

    SQLQuery = "
    WITH summary AS (
      SELECT effective_date, product_id, warehouse_id, SUM(quantity) AS quantity FROM (
        
        -- First calculate quantity inbound
        SELECT  
          effective_date,
          product_id,
          to_warehouse AS warehouse_id,
          SUM(quantity_in_default_uom) AS quantity
        FROM `" & BasePath & ".inventory_moves` 
        WHERE 
          effective_date <= CURRENT_DATE('America/Chicago')
          AND state = 'done'
          AND to_warehouse IS NOT NULL
          AND (
              (from_warehouse IS NULL)
              OR (from_warehouse != to_warehouse)
          )
        GROUP BY effective_date, product_id, to_warehouse
     
        UNION ALL
     
        -- Now reduce outbound
        SELECT  
          effective_date,
          product_id,
          from_warehouse AS warehouse_id,
          -SUM(quantity_in_default_uom) AS quantity
        FROM `" & BasePath & ".inventory_moves` 
        WHERE 
          effective_date <= CURRENT_DATE('America/Chicago') 
          AND state = 'done'
          AND from_warehouse IS NOT NULL
          AND (
              (to_warehouse IS NULL)
              OR (from_warehouse != to_warehouse)
          )
        GROUP BY effective_date, product_id, from_warehouse
      ) 
      GROUP BY effective_date, product_id, warehouse_id
    ),

    max_date AS (
      SELECT MAX(effective_date) AS max_effective_date
      FROM summary
    )

    SELECT
    product_id,
        SUM(s.quantity) AS quantity_on_hand
    FROM summary s
    CROSS JOIN max_date m
    LEFT JOIN `" & BasePath & ".products` AS products
        ON products.id = s.product_id
    WHERE 
        s.effective_date BETWEEN DATE_SUB(m.max_effective_date, INTERVAL 30 DAY)
                             AND m.max_effective_date
    GROUP BY product_id
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