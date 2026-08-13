.PHONY: coverage gas_snapshot

coverage:
	forge coverage --report lcov --no-match-coverage "(test/)"
	genhtml --ignore-errors inconsistent --ignore-errors corrupt --ignore-errors category -o ./coverage_report ./lcov.info
	open ./coverage_report/index.html
	rm -rf lcov.info

gas_snapshot:
	FOUNDRY_PROFILE=prod forge snapshot --mt "_gas"
