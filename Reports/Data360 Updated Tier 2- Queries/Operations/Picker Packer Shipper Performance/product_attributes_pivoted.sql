let
    Source = Value.NativeQuery(GoogleBigQuery.Database([BillingProject="rudder-data360-etl", UseStorageApi=false]){[Name="rudder-data360-etl"]}[Data], "SELECT #(lf)product.id,#(lf)product.code as product_code,#(lf)attr.attribute_name,#(lf)attr.value as attribute_value#(lf)FROM `rudder-data360-etl.fulfil_gruntstyle_bqdwh.products` product #(lf)left join UNNEST(attributes) as attr", null, [EnableFolding=true]),
    #"Replaced Value" = Table.ReplaceValue(Source,"_"," ",Replacer.ReplaceText,{"attribute_name"}),
    #"Capitalized Each Word" = Table.TransformColumns(#"Replaced Value",{{"attribute_name", Text.Proper, type text}}),
    #"Replaced Value1" = Table.ReplaceValue(#"Capitalized Each Word","-"," ",Replacer.ReplaceText,{"attribute_name"}),
    #"Replaced Value2" = Table.ReplaceValue(#"Replaced Value1","Sku","SKU",Replacer.ReplaceText,{"attribute_name"}),
    #"Replaced Value3" = Table.ReplaceValue(#"Replaced Value2","Ba","BA",Replacer.ReplaceText,{"attribute_name"}),
    #"Filtered Rows" = Table.SelectRows(#"Replaced Value3", each true),
    #"Replaced Value4" = Table.ReplaceValue(#"Filtered Rows",null,"(Blank)",Replacer.ReplaceValue,{"attribute_name"}),
    #"Pivoted Column" = Table.Pivot(#"Replaced Value4", List.Distinct(#"Replaced Value4"[attribute_name]), "attribute_name", "attribute_value"),
    #"Filtered Rows1" = Table.SelectRows(#"Pivoted Column", each true)
in
    #"Filtered Rows1"