account :usd_gateway
account :scott
account :andrew

payment :master, :usd_gateway, [:native, 1000_000000]
payment :master, :scott, [:native, 1000_000000]
payment :master, :andrew, [:native, 1000_000000]

close_ledger

trust :scott,  :usd_gateway, "USD"
trust :andrew, :usd_gateway, "USD"

close_ledger

payment :usd_gateway, :scott,  ["USD", :usd_gateway, 1000_000000]

close_ledger

payment :scott, :andrew, ["USD", :usd_gateway, 500_000000]
