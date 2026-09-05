module example.com/zigo/materialized-purego

require example.com/zigo/runtime-contracts v0.0.0

replace example.com/zigo/runtime-contracts => ../../../tests/runtime_contracts

go 1.24

require github.com/ebitengine/purego v0.10.2
