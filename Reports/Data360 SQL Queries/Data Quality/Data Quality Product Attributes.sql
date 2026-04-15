let
    // Build full table reference dynamically
    FullTableName = 
        "`" & BillingProjectID & "." & DatasetName & ".products`",

    // Build dynamic SQL
    SQLStatement = 
		" SELECT 
			product.id,
			product.code as product_code,
			attr.attribute_name,
			attr.value as attribute_value
			FROM " & FullTableName & "  product 
			left join UNNEST(attributes) as attr
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
	#"Sorted Rows" = Table.Sort(Source,{{"id", Order.Descending}}),
    #"Capitalized Each Word" = Table.TransformColumns(#"Sorted Rows",{{"attribute_name", Text.Proper, type text}}),
    #"Filtered Rows" = Table.SelectRows(#"Capitalized Each Word", each ([attribute_name] <> "Year")),
    #"Replaced Value" = Table.ReplaceValue(#"Filtered Rows","_"," ",Replacer.ReplaceText,{"attribute_name"}),
    #"Replaced Value1" = Table.ReplaceValue(#"Replaced Value","_"," ",Replacer.ReplaceText,{"attribute_name"}),
    #"Replaced Value2" = Table.ReplaceValue(#"Replaced Value1","Ba","BA",Replacer.ReplaceValue,{"attribute_name"}),
    #"Replaced Value3" = Table.ReplaceValue(#"Replaced Value2","Sku","SKU",Replacer.ReplaceValue,{"attribute_name"}),
    #"Replaced Value4" = Table.ReplaceValue(#"Replaced Value3","-"," ",Replacer.ReplaceText,{"attribute_name"})
in
    #"Replaced Value4"