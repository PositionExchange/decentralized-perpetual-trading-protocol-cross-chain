deploy_testnet_insurance_fund:
	yarn compile
	npx hardhat deploy --network arbitrumGoerli --stage test --task 'deploy insurance fund'
deploy_testnet_futures_gateway:
	yarn compile
	npx hardhat deploy --network arbitrumGoerli --stage test --task 'deploy dptp futures gateway'
deploy_mainnet_insurance_fund:
	npx hardhat compile
	npx hardhat deploy --network arbitrumOne --stage production --task 'deploy insurance fund'
deploy_mainnet_futures_gateway:
	npx hardhat compile
	npx hardhat deploy --network arbitrumOne --stage production --task 'deploy dptp futures gateway'
deploy_mainnet_futures_adapter:
	npx hardhat compile
	npx hardhat deploy --network arbitrumOne --stage production --task 'deploy dptp futures adapter'
