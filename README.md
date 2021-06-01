# mai-protocol-v3

> Mai Protocol V3 designed by MCDEX is an AMM-based decentralized perpetual swap protocol. Perpetual swap is one of the most popular derivatives that has no expiration date, supports margin trading, and has its price soft pegged to index price.
>
> The name Mai comes from two Chinese characters "买" which means buy and "卖" which means sell. Using pinyin (the modern system for transliterating Chinese characters to Latin letters) "买" is spelled Mǎi and "卖" is spelled Mài. Thus, "Mai" means "Buy" and "Sell".

**If not specified in advance, we always use decimals 18 as default in the code and documents.**

## Overview
[Overview](./contracts/Readme.md) of mai-protocol-v3.

## Reference
[Terms](./docs/term.md)

[References](https://mcdex.io/references/)

[AMMDesign](https://mcdexio.github.io/documents/en/Shared-Liquidity-AMM-of-MAI-PROTOCOL-v3.pdf)

## Audit

The smart contracts were audited by quantstamp: [MCDEX Audit Report](https://certificate.quantstamp.com/full/mcdex).

## Deployed Contracts

### Arbitrum Kovan5 Testnet

|Contract|Description|Address|
|---|---|---|
|[`PoolCreator(proxy)`](https://github.com/OpenZeppelin/openzeppelin-contracts/blob/v3.4.0/contracts/proxy/TransparentUpgradeableProxy.sol) |A proxy to PoolCreator |[0x59edD5AEBf97955F53a094B49221E63F544ddA5a](https://explorer5.arbitrum.io/#/address/0x59edD5AEBf97955F53a094B49221E63F544ddA5a)|
|[`PoolCreator(implementation)`](contracts/factory/PoolCreator.sol) |PoolCreator manages the liquidity pools and global variables. |[0x1520D5561Dfb209c6dF5149CB6146f6B18d7ad2a](https://explorer5.arbitrum.io/#/address/0x1520D5561Dfb209c6dF5149CB6146f6B18d7ad2a)|
|[`SymbolService`](contracts/symbolService/SymbolService.sol) |Provide a shorter symbol for each perpetuals |[0x465fB17aCc62Efd26D5B3bE9B3FFC984Cebd03d1](https://explorer5.arbitrum.io/#/address/0x465fB17aCc62Efd26D5B3bE9B3FFC984Cebd03d1)|
|[`Broker`](contracts/broker/Broker.sol) |A relay to execute pre-signed transactions |[0x9CaDa02fC03671EA66BaAC7929Cb769214621947](https://explorer5.arbitrum.io/#/address/0x9CaDa02fC03671EA66BaAC7929Cb769214621947)|
|[`Reader`](contracts/reader/Reader.sol) |A tool to read status of liquidity pool |[0x74F5b3581d70FfdEcE47090E568a8743f9659787](https://explorer5.arbitrum.io/#/address/0x74F5b3581d70FfdEcE47090E568a8743f9659787)|
|[`LiquidityPool(implementation)`](contracts/LiquidityPool.sol) |A liquidity pool provides liquidity for multiple perpetuals using the same collateral |[0xA158E9f79917892Ce3E7735B3B946a5e06157409](https://explorer5.arbitrum.io/#/address/0xA158E9f79917892Ce3E7735B3B946a5e06157409)|
|[`LpGovernor(implementation)`](contracts/LiquidityPool.sol) |Share token and governance functions |[0x49FF180FDF2D473F7a38eC53741d7631147DDDa3](https://explorer5.arbitrum.io/#/address/0x49FF180FDF2D473F7a38eC53741d7631147DDDa3)|

## Development
### Compile contracts
```
npm install
npx hardhat compile
npx hardhat run scripts/s10test.ts
```
