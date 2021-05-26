const hre = require("hardhat")
const ethers = hre.ethers

import { Deployer, DeploymentOptions } from './deployer/deployer'
import { restorableEnviron } from './deployer/environ'
import { sleep, ensureFinished, printInfo, printError } from './deployer/utils'

const ENV: DeploymentOptions = {
    network: hre.network.name,
    artifactDirectory: './artifacts/contracts',
    addressOverride: {
        WETH9: "0xfA53FD78b5176B4d772194511cC16C02c7F183F9",
    }
}

const oracleAddresses = {
    "USD - ETH": "0xf82a6673B1f0CC56f59E0A92bfEaa6aac16411B4",
    "BTC - ETH": "0x37E54B5489056dCE875590bCD791C38093D562b8",
    "ETH - USD": "0x2a7563E9818ABDdbCF575F6f4988F313b4B05ee4",
    "BTC - USD": "0x9B50A6f2b7a04C46773a22Cd388b3dF8Dd8D2FBb",
    "DPI - USD": "0x0c4aD862379B995b019f245C8f5C8D169ef26969",
    "DOT - USD": "0x9F34a3D64a44AA47a50B71FE7388d6C1549B2d77",
    "SP500 - USD": "0xEa37Aa8326aC730e474D09aA1C613Fa6DD118877",
    "TSLA - USD": "0x2fE3bEfBCfd6Cc312ee2A14450176c87AE01495A",
    "DEFI++ - USD": "0x2A1428d5dB9a266b98E1da563896F419E078F28f",
    "DEFI5 - USD": "0x6BC8b97b4fc6fe4023255C09dFDe1618BC265F38",
}

function toWei(n) { return hre.ethers.utils.parseEther(n) };
function fromWei(n) { return hre.ethers.utils.formatEther(n); }

async function main(_, deployer, accounts) {
    const upgradeAdmin = "0x1a3F275b9Af71D597219899151140a0049DB557b"
    const vault = "0xa2aAD83466241232290bEbcd43dcbFf6A7f8d23a"
    const vaultFeeRate = toWei("0.00015");

    // infrastructure
    await deployer.deployOrSkip("Broker")
    await deployer.deployOrSkip("SymbolService", 10000)
    // await deployer.deploy("WETH9")
    // await deployer.deployOrSkip("CustomERC20", "USDC", "USDC", 6)

    // upgradeable pool / add whitelist
    const tx = await deployer.deployAsUpgradeable("PoolCreator", upgradeAdmin)
    const poolCreator = await deployer.getDeployedContract("PoolCreator")
    await deployer.deployOrSkip("Reader", poolCreator.address)
    await ensureFinished(poolCreator.initialize(
        deployer.addressOf("SymbolService"),
        vault,
        vaultFeeRate
    ))
    const symbolService = await deployer.getDeployedContract("SymbolService")
    await ensureFinished(symbolService.addWhitelistedFactory(poolCreator.address))

    // add version
    const liquidityPool = await deployer.deployOrSkip("LiquidityPool")
    const governor = await deployer.deployOrSkip("LpGovernor")
    await ensureFinished(poolCreator.addVersion(liquidityPool.address, governor.address, 0, "initial version"))

    // printInfo("deploying preset1")
    // await preset1(deployer, accounts)
    // printInfo("deploying preset1 done")

    printInfo("deploying preset2")
    await preset2(deployer, accounts)
    printInfo("deploying preset2 done")
}

async function preset1(deployer, accounts) {
    const poolCreator = await deployer.getDeployedContract("PoolCreator")
    await ensureFinished(poolCreator.createLiquidityPool(
        deployer.addressOf("WETH9"),
        18,
        Math.floor(Date.now() / 1000),
        ethers.utils.defaultAbiCoder.encode(["bool", "int256"], [true, toWei("1000000")])
    ))
    const n = await poolCreator.getLiquidityPoolCount();
    const allLiquidityPools = await poolCreator.listLiquidityPools(0, n.toString());
    const liquidityPool = await deployer.getContractAt("LiquidityPool", allLiquidityPools[allLiquidityPools.length - 1]);

    await ensureFinished(liquidityPool.createPerpetual(
        oracleAddresses["USD - ETH"],
        // imr          mmr            operatorfr        lpfr              rebate        penalty         keeper           insur          oi
        [toWei("0.04"), toWei("0.02"), toWei("0.00000"), toWei("0.00055"), toWei("0.2"), toWei("0.005"), toWei("0.0005"), toWei("0.25"), toWei("5")],
        // alpha         beta1            beta2             frLimit          lev         maxClose       frFactor
        [toWei("0.0008"), toWei("0.0075"), toWei("0.00525"), toWei("0.01"), toWei("3"), toWei("0.05"), toWei("0.005")],
        [toWei("0"), toWei("0"), toWei("0"), toWei("0"), toWei("0"), toWei("0"), toWei("0")],
        [toWei("1"), toWei("1"), toWei("1"), toWei("1"), toWei("10"), toWei("1"), toWei("1")]
    ))
    await ensureFinished(liquidityPool.createPerpetual(
        oracleAddresses["BTC - ETH"],
        // imr          mmr            operatorfr        lpfr              rebate        penalty         keeper           insur          oi
        [toWei("0.04"), toWei("0.02"), toWei("0.00000"), toWei("0.00055"), toWei("0.2"), toWei("0.005"), toWei("0.0005"), toWei("0.25"), toWei("5")],
        // alpha         beta1            beta2             frLimit          lev         maxClose       frFactor
        [toWei("0.0008"), toWei("0.0075"), toWei("0.00525"), toWei("0.01"), toWei("3"), toWei("0.05"), toWei("0.005")],
        [toWei("0"), toWei("0"), toWei("0"), toWei("0"), toWei("0"), toWei("0"), toWei("0")],
        [toWei("1"), toWei("1"), toWei("1"), toWei("1"), toWei("10"), toWei("1"), toWei("1")]
    ))
    await ensureFinished(liquidityPool.runLiquidityPool())
    await ensureFinished(liquidityPool.addLiquidity(toWei("0"), { value: toWei("6600") }));
    return liquidityPool
}

async function preset2(deployer, accounts) {
    const usd = await deployer.getContractAt("CustomERC20", "0x4B442fB2b62BacCe41c202FB244B1D0CA4c7BF8f")
    const poolCreator = await deployer.getDeployedContract("PoolCreator")

    await ensureFinished(poolCreator.createLiquidityPool(
        usd.address,
        6,
        Math.floor(Date.now() / 1000),
        ethers.utils.defaultAbiCoder.encode(["bool", "int256"], [true, toWei("1000000")])
    ))

    const n = await poolCreator.getLiquidityPoolCount();
    const allLiquidityPools = await poolCreator.listLiquidityPools(0, n.toString());
    const liquidityPool = await deployer.getContractAt("LiquidityPool", allLiquidityPools[allLiquidityPools.length - 1]);

    await ensureFinished(liquidityPool.createPerpetual(
        oracleAddresses["ETH - USD"],
        // imr          mmr            operatorfr        lpfr              rebate        penalty        keeper       insur         oi
        [toWei("0.04"), toWei("0.03"), toWei("0.00000"), toWei("0.00055"), toWei("0.2"), toWei("0.01"), toWei("30"), toWei("0.5"), toWei("3")],
        // alpha          beta1            beta2             frLimit        lev         maxClose       frFactor        defaultLev
        [toWei("0.0008"), toWei("0.0075"), toWei("0.00525"), toWei("0.01"), toWei("3"), toWei("0.05"), toWei("0.005"), toWei("10")],
        [toWei("0"),      toWei("0"),      toWei("0"),       toWei("0"),    toWei("0"), toWei("0"),    toWei("0"),     toWei("0")],
        [toWei("0.1"),    toWei("0.5"),    toWei("0.5"),     toWei("0.1"),  toWei("5"), toWei("1"),    toWei("0.1"),   toWei("10000000")]
    ))
    await ensureFinished(liquidityPool.createPerpetual(
        oracleAddresses["BTC - USD"],
        // imr          mmr            operatorfr        lpfr              rebate        penalty        keeper       insur         oi
        [toWei("0.04"), toWei("0.03"), toWei("0.00000"), toWei("0.00055"), toWei("0.2"), toWei("0.01"), toWei("30"), toWei("0.5"), toWei("3")],
        // alpha          beta1            beta2             frLimit        lev         maxClose       frFactor        defaultLev
        [toWei("0.0008"), toWei("0.0075"), toWei("0.00525"), toWei("0.01"), toWei("3"), toWei("0.05"), toWei("0.005"), toWei("10")],
        [toWei("0"),      toWei("0"),      toWei("0"),       toWei("0"),    toWei("0"), toWei("0"),    toWei("0"),     toWei("0")],
        [toWei("0.1"),    toWei("0.5"),    toWei("0.5"),     toWei("0.1"),  toWei("5"), toWei("1"),    toWei("0.1"),   toWei("10000000")]
    ))
    await ensureFinished(liquidityPool.createPerpetual(
        oracleAddresses["DPI - USD"],
        // imr          mmr            operatorfr        lpfr              rebate        penalty        keeper       insur         oi
        [toWei("0.04"), toWei("0.03"), toWei("0.00000"), toWei("0.00055"), toWei("0.2"), toWei("0.01"), toWei("30"), toWei("0.5"), toWei("3")],
        // alpha          beta1            beta2             frLimit        lev         maxClose       frFactor        defaultLev
        [toWei("0.0008"), toWei("0.0075"), toWei("0.00525"), toWei("0.01"), toWei("3"), toWei("0.05"), toWei("0.005"), toWei("10")],
        [toWei("0"),      toWei("0"),      toWei("0"),       toWei("0"),    toWei("0"), toWei("0"),    toWei("0"),     toWei("0")],
        [toWei("0.1"),    toWei("0.5"),    toWei("0.5"),     toWei("0.1"),  toWei("5"), toWei("1"),    toWei("0.1"),   toWei("10000000")]
    ))
    await ensureFinished(liquidityPool.createPerpetual(
        oracleAddresses["DOT - USD"],
        // imr          mmr            operatorfr        lpfr              rebate        penalty        keeper       insur         oi
        [toWei("0.04"), toWei("0.03"), toWei("0.00000"), toWei("0.00055"), toWei("0.2"), toWei("0.01"), toWei("30"), toWei("0.5"), toWei("3")],
        // alpha          beta1            beta2             frLimit        lev         maxClose       frFactor        defaultLev
        [toWei("0.0008"), toWei("0.0075"), toWei("0.00525"), toWei("0.01"), toWei("3"), toWei("0.05"), toWei("0.005"), toWei("10")],
        [toWei("0"),      toWei("0"),      toWei("0"),       toWei("0"),    toWei("0"), toWei("0"),    toWei("0"),     toWei("0")],
        [toWei("0.1"),    toWei("0.5"),    toWei("0.5"),     toWei("0.1"),  toWei("5"), toWei("1"),    toWei("0.1"),   toWei("10000000")]
    ))
    await ensureFinished(liquidityPool.createPerpetual(
        oracleAddresses["SP500 - USD"],
        // imr          mmr            operatorfr        lpfr              rebate        penalty        keeper       insur         oi
        [toWei("0.04"), toWei("0.03"), toWei("0.00000"), toWei("0.00055"), toWei("0.2"), toWei("0.01"), toWei("30"), toWei("0.5"), toWei("3")],
        // alpha          beta1            beta2             frLimit        lev         maxClose       frFactor        defaultLev
        [toWei("0.0008"), toWei("0.0075"), toWei("0.00525"), toWei("0.01"), toWei("3"), toWei("0.05"), toWei("0.005"), toWei("10")],
        [toWei("0"),      toWei("0"),      toWei("0"),       toWei("0"),    toWei("0"), toWei("0"),    toWei("0"),     toWei("0")],
        [toWei("0.1"),    toWei("0.5"),    toWei("0.5"),     toWei("0.1"),  toWei("5"), toWei("1"),    toWei("0.1"),   toWei("10000000")]
    ))
    await ensureFinished(liquidityPool.createPerpetual(
        oracleAddresses["TSLA - USD"],
        // imr          mmr            operatorfr        lpfr              rebate        penalty        keeper       insur         oi
        [toWei("0.04"), toWei("0.03"), toWei("0.00000"), toWei("0.00055"), toWei("0.2"), toWei("0.01"), toWei("30"), toWei("0.5"), toWei("3")],
        // alpha          beta1            beta2             frLimit        lev         maxClose       frFactor        defaultLev
        [toWei("0.0008"), toWei("0.0075"), toWei("0.00525"), toWei("0.01"), toWei("3"), toWei("0.05"), toWei("0.005"), toWei("10")],
        [toWei("0"),      toWei("0"),      toWei("0"),       toWei("0"),    toWei("0"), toWei("0"),    toWei("0"),     toWei("0")],
        [toWei("0.1"),    toWei("0.5"),    toWei("0.5"),     toWei("0.1"),  toWei("5"), toWei("1"),    toWei("0.1"),   toWei("10000000")]
    ))

    await ensureFinished(liquidityPool.runLiquidityPool())

    // await ensureFinished(usd.mint(accounts[0].address, "25000000" + "000000"))
    await ensureFinished(usd.approve(liquidityPool.address, "25000000" + "000000"))
    await ensureFinished(liquidityPool.addLiquidity(toWei("25000000")))

    return liquidityPool;
}

ethers.getSigners()
    .then(accounts => restorableEnviron(ethers, ENV, main, accounts))
    .then(() => process.exit(0))
    .catch(error => {
        printError(error);
        process.exit(1);
    });


