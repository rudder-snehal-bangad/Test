let
    BillingProject = BillingProjectID,
    Dataset = DatasetName,

    SQLQuery = "
with inventory_current_data as
(
SELECT product_id,product_code,
sum(quantity_on_hand) as quantity_on_hand, sum(quantity_available) as quantity_available
FROM " & BillingProject & "." & Dataset & ".inventory_current
group by product_code, product_id
),
inventory_moves_data as
(
SELECT product_id,product_code,
sum(case when to_location_type='storage' and from_location_type in ('view','storage') and state = 'draft' and  shipment_type = 'stock.shipment.out' then quantity else 0 end) as quantity_outbound,
FROM " & BillingProject & "." & Dataset & ".inventory_moves
where state not in ('cancel', 'done')
group by product_code, product_id
),
inventory_inbound_data as
(
SELECT product_id,product_code,
sum(case when from_location_type in ('supplier','storage') and shipment_type in('stock.shipment.in','stock.shipment.internal') and state = 'draft' then quantity else 0 end) as quantity_inbound
FROM " & BillingProject & "." & Dataset & ".inventory_moves
where state not in ('cancel', 'done')
group by product_code, product_id
)
 
 
select
coalesce(inventory_current_data.product_id,inventory_moves_data.product_id, inventory_inbound_data.product_id) as product_id,
coalesce(inventory_current_data.product_code,inventory_moves_data.product_code, inventory_inbound_data.product_code) as product_code,
sum(case when quantity_on_hand is not null then quantity_on_hand else 0 end) as quantity_on_hand,
sum(case when quantity_available is not null then quantity_available else 0 end) as quantity_available,
sum(case when quantity_inbound is not null then quantity_inbound else 0 end) as quantity_inbound,
sum( case when quantity_outbound is not null then quantity_outbound else 0 end) as quantity_outbound,
from inventory_current_data
FULL OUTER JOIN inventory_moves_data
on inventory_current_data.product_id = inventory_moves_data.product_id and inventory_current_data.product_code = inventory_moves_data.product_code
FULL OUTER JOIN inventory_inbound_data
on inventory_current_data.product_id = inventory_inbound_data.product_id and inventory_current_data.product_code = inventory_inbound_data.product_code
group by product_code, product_id
",

    Source =
        Value.NativeQuery(
            GoogleBigQuery.Database(
                [BillingProject = BillingProject, UseStorageApi = false]
            ){[Name = BillingProject]}[Data],
            SQLQuery,
            null,
            [EnableFolding = true]
        )
in
    Source