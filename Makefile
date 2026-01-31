.PHONY: test compile build install 
include .env
install:
	forge install OpenZeppelin/openzeppelin-contracts
	forge remappings > remappings.txt 
compile:
	forge compile
build:; forge build