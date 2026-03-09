let 
    Period = Number.ToText(#"Analysis Period (Years)"),
    Source = Value.NativeQuery(
        GoogleBigQuery.Database(
            [BillingProject = BillingProjectID, UseStorageApi = false]
        ){[Name = BillingProjectID]}[Data],
        "SELECT  #(lf)
          moves.product_template_name,  #(lf)
          moves.product_code,#(lf)
          products.variant_name,#(lf)
          moves.product_category,  #(lf)
          SUM(moves.quantity) AS quantity,  #(lf)
          shipment.id AS shipment_id,#(lf)
          shipment.priority,#(lf)
          shipment.number as shipment_number,#(lf)
          shipment.customer_name,#(lf)
          shipment.reference,#(lf)
          shipment.assigned_time,#(lf)
          shipment.shipping_batch_number,#(lf)
          shipment.warehouse,#(lf)
          shipment.planned_date,#(lf)
          CONCAT(#(lf)
            shipment.shipment_address_line1, ', ',#(lf)
            shipment.shipment_address_city, ', ',#(lf)
            shipment.shipment_region_name, ', ',#(lf)
            shipment.shipment_country_name#(lf)
          ) AS delivery_address,#(lf)
          shipment.shipment_region_name#(lf)
        FROM `" & BillingProjectID & "." & DatasetName & ".shipments` AS shipment#(lf)
        JOIN UNNEST(shipment.moves) AS moves#(lf)
        LEFT JOIN `" & BillingProjectID & "." & DatasetName & ".products` AS products#(lf)
          ON moves.product_code = products.code#(lf)
        --WHERE shipment.warehouse = 'Distribution Center'#(lf)
          WHERE moves.move_type = 'picking'#(lf)
          AND moves.state IN ('assigned')#(lf)
          AND shipment.state IN ('assigned', 'waiting')#(lf)
          AND products.active = TRUE#(lf)
          AND planned_date between DATE_ADD(current_date(), INTERVAL -" & Period & " YEAR) AND CURRENT_DATE()#(lf)
        GROUP BY #(lf)
          moves.product_template_name,#(lf)
          moves.product_code,#(lf)
          products.variant_name,#(lf)
          moves.product_category,#(lf)
          shipment.id,#(lf)
          shipment.priority,#(lf)
          shipment.customer_name,#(lf)
          shipment.reference,#(lf)
          shipment.assigned_time,#(lf)
          shipment.number,#(lf)
          shipment.shipping_batch_number,#(lf)
          shipment.planned_date,#(lf)
          shipment.shipment_address_line1,#(lf)
          shipment.shipment_address_city,#(lf)
          shipment.shipment_region_name,#(lf)
          shipment.shipment_country_name,#(lf)
          shipment.warehouse",
        null,
        [EnableFolding=true]
    ),

    #"Replaced Value" = Table.ReplaceValue(Source,"0","Low",Replacer.ReplaceText,{"priority"}),
    #"Replaced Value1" = Table.ReplaceValue(#"Replaced Value","1","Normal",Replacer.ReplaceText,{"priority"}),
    #"Replaced Value2" = Table.ReplaceValue(#"Replaced Value1","2","High",Replacer.ReplaceText,{"priority"}),
    #"Changed Type" = Table.TransformColumnTypes(#"Replaced Value2",{{"assigned_time", type date}})

in
    #"Changed Type"