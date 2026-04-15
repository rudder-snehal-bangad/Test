let
    Period = Number.ToText(#"Analysis Period (Years)"),
    Source = Value.NativeQuery(
        GoogleBigQuery.Database(
            [BillingProject = BillingProjectID, UseStorageApi=false]
        ){[Name = BillingProjectID]}[Data],
        "WITH sales_orders AS (#(lf)
            SELECT#(lf)
                line.product_id AS product_id,#(lf)
                line.product_name AS product_name,#(lf)
                p.code AS product_code,#(lf)
                p.variant_name as variant_name,#(lf)
                product_category,#(lf)
                p.template_name AS template,#(lf)
                MAX(so.order_date) AS oldest_sale_date,#(lf)
                SUM(line.quantity) AS total_quantity#(lf)
            FROM `" & BillingProjectID & "." & DatasetName & ".sales_orders` so#(lf)
            LEFT JOIN UNNEST(so.lines) AS line  #(lf)
            LEFT JOIN `" & BillingProjectID & "." & DatasetName & ".products` p#(lf)
                ON line.product_id = p.id  #(lf)
            GROUP BY product_name, product_id, p.code, p.variant_name, p.template_name, product_category#(lf)
        ),#(lf)#(lf)

        inventory_data AS (#(lf)
            SELECT#(lf)
                product_id,#(lf)
                SUM(quantity_available) AS quantity_available#(lf)
            FROM `" & BillingProjectID & "." & DatasetName & ".inventory_current`#(lf)
            GROUP BY product_id#(lf)
        ),#(lf)#(lf)

        shipments_data AS (#(lf)
            SELECT#(lf)
                move.product_code AS product_code,#(lf)
                SUM(move.quantity) AS total_quantity,#(lf)
                planned_date,#(lf)
                move.order_id,#(lf)
                move.order_number,#(lf)
                s.priority,#(lf)
                s.customer_name,#(lf)
                s.reference,#(lf)
                s.shipping_batch_number,#(lf)
                s.shipment_address_line1,#(lf)
                s.shipment_address_city,#(lf)
                s.shipment_region_name,#(lf)
                s.shipment_country_name,#(lf)
                s.id AS total_shipments,#(lf)
                s.number AS shipment_number,#(lf)
                s.warehouse,#(lf)
                s.warehouse_id
            FROM `" & BillingProjectID & "." & DatasetName & ".shipments` s#(lf)
            LEFT JOIN UNNEST(s.moves) AS move#(lf)
            WHERE move.move_type = 'picking'#(lf)
              AND move.state = 'draft'#(lf)
              AND s.state = 'waiting'#(lf)
              AND s.planned_date between DATE_ADD(current_date(), INTERVAL -" & Period & " YEAR) AND CURRENT_DATE()#(lf)
            GROUP BY #(lf)
                move.product_code, planned_date, s.id, move.order_id, move.order_number,s.shipping_batch_number,#(lf)
                s.customer_name, s.shipment_address_line1, s.shipment_address_city,#(lf)
                s.shipment_region_name, s.priority, s.shipment_country_name, s.number, s.reference,#(lf)
s.warehouse,#(lf)
s.warehouse_id
        ),#(lf)#(lf)

        forecast_data AS (#(lf)
            SELECT#(lf)
                line.product_code AS product_code,#(lf)
                SUM(line.quantity) AS forecast_quantity#(lf)
            FROM `" & BillingProjectID & "." & DatasetName & ".inventory_forecasts`#(lf)
            LEFT JOIN UNNEST(lines) AS line#(lf)
            GROUP BY product_code#(lf)
        )#(lf)#(lf)

        SELECT#(lf)
            s.product_code,#(lf)
            s.variant_name,#(lf)
            s.template,#(lf)
            s.product_name,#(lf)
            sd.planned_date,#(lf)
            sd.priority,#(lf)
            sd.reference,#(lf)
            sd.shipping_batch_number,#(lf)
            sd.customer_name,#(lf)
            CONCAT(#(lf)
                sd.shipment_address_line1, ', ',#(lf)
                sd.shipment_address_city, ', ',#(lf)
                sd.shipment_region_name, ', ',#(lf)
                sd.shipment_country_name#(lf)
            ) AS delivery_address,#(lf)
            sd.total_shipments,#(lf)
            sd.shipment_number,#(lf)
            sd.warehouse,#(lf)
sd.warehouse_id,#(lf)
            SUM(sd.total_quantity) AS quantity,#(lf)
            product_category,#(lf)
            COALESCE(fd.forecast_quantity, 0) AS forecast_quantity,#(lf)
            COALESCE(id.quantity_available, 0) AS quantity_available,#(lf)
            sd.shipment_region_name,
sd.shipment_address_city,
sd.shipment_country_name,
            s.oldest_sale_date AS oldest_sale_date#(lf)
        FROM shipments_data sd#(lf)
        LEFT JOIN sales_orders s#(lf)
            ON s.product_code = sd.product_code#(lf)
        LEFT JOIN inventory_data id#(lf)
            ON s.product_id = id.product_id#(lf)
        LEFT JOIN forecast_data fd#(lf)
            ON s.product_code = fd.product_code#(lf)
        GROUP BY #(lf)
            s.product_code, s.variant_name, s.template, s.oldest_sale_date,sd.shipping_batch_number,#(lf)
            sd.reference,sd.total_shipments, fd.forecast_quantity, #(lf)
            sd.planned_date, sd.priority, sd.customer_name, #(lf)
            sd.shipment_number, id.quantity_available, sd.warehouse, sd.shipment_region_name,#(lf)
            s.product_name, sd.warehouse_id,
product_category,
sd.shipment_address_city,
sd.shipment_country_name,
            CONCAT(#(lf)
                sd.shipment_address_line1, ', ',#(lf)
                sd.shipment_address_city, ', ',#(lf)
                sd.shipment_region_name, ', ',#(lf)
                sd.shipment_country_name#(lf)
            )",
        null,
        [EnableFolding=true]
    ),

    #"Renamed Columns" = Table.RenameColumns(Source,{{"product_code", "Product_code"}}),
    #"Replaced Value" = Table.ReplaceValue(#"Renamed Columns","0","Low",Replacer.ReplaceText,{"priority"}),
    #"Replaced Value1" = Table.ReplaceValue(#"Replaced Value","1","Normal",Replacer.ReplaceText,{"priority"}),
    #"Replaced Value2" = Table.ReplaceValue(#"Replaced Value1","2","High",Replacer.ReplaceText,{"priority"})

in
    #"Replaced Value2"