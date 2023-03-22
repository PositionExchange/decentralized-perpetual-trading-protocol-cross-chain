deploy_testnet_insurance_fund:
	yarn compile
	npx hardhat deploy --network bsc --stage test --task 'deploy insurance fund'
deploy_testnet_futures_gateway:
	yarn compile
	npx hardhat deploy --network bsc --stage test --task 'deploy futures gateway'
deploy_mainnet_insurance_fund:
	npx hardhat compile
	npx hardhat deploy --network bsc --stage production --task 'deploy insurance fund'
deploy_mainnet_futures_gateway:
	npx hardhat compile
	npx hardhat deploy --network bsc --stage production --task 'deploy futures gateway'
deploy_mainnet_futures_adapter:
	npx hardhat compile
	npx hardhat deploy --network bsc --stage production --task 'deploy futures adapter'
