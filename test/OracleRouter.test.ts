const { ethers } = require("hardhat");
const { expect } = require("chai");
import { BigNumber, BigNumber as BN } from "ethers";
import {
    toWei,
    fromWei,
    createFactory,
    createContract,
    createLiquidityPoolFactory
} from "../scripts/utils";
import "./helper";

describe("OracleRouter", () => {
    let oracle1;
    let oracle2;
    let oracle3;
    let oracle4;
    let routerCreator;

    before(async () => {
        oracle1 = await createContract("OracleWrapper", ["USD", "ETH"]);
        oracle2 = await createContract("OracleWrapper", ["USD", "BTC"]);
        oracle3 = await createContract("OracleWrapper", ["ETH", "USD"]);
        oracle4 = await createContract("OracleWrapper", ["BTC", "XXX"]);
    })

    beforeEach(async () => {
        routerCreator = await createContract("OracleRouterCreator");
        await updatePrice(toWei("1000"), toWei("10000"), toWei("0.001"), toWei("2"));
    })

    let updatePrice = async (price1, price2, price3, price4) => {
        await oracle1.setMarkPrice(price1, 1);
        await oracle1.setIndexPrice(price1, 1);
        await oracle2.setMarkPrice(price2, 2);
        await oracle2.setIndexPrice(price2, 2);
        await oracle3.setMarkPrice(price3, 3);
        await oracle3.setIndexPrice(price3, 3);
        await oracle4.setMarkPrice(price4, 4);
        await oracle4.setIndexPrice(price4, 4);
    }

    let getPathHash = function(path) {
        const encodedPath = ethers.utils.defaultAbiCoder.encode(["tuple(address oracle, bool isInverse)[]"], [path]);
        const hash = ethers.utils.keccak256(encodedPath);
        return hash
    }

    let describeOracleByAddress = function(address) {
        if (address == oracle1.address) {
            return { collateral: 'USD', underlyingAsset: 'ETH' }
        }
        if (address == oracle2.address) {
            return { collateral: 'USD', underlyingAsset: 'BTC' }
        }
        if (address == oracle3.address) {
            return { collateral: 'ETH', underlyingAsset: 'USD' }
        }
        if (address == oracle4.address) {
            return { collateral: 'BTC', underlyingAsset: 'XXX' }
        }
        throw new Error('unknown oracle')
    }

    it("hash", async () => {
        const path = [
            { oracle: oracle1.address, isInverse: false },
            { oracle: oracle2.address, isInverse: true },
        ]
        expect(await routerCreator.getPathHash(path)).to.equal(getPathHash(path));
    })

    it("normal", () => {
        describe("normal", () => {
            const cases = [
                {
                    // Example 1: underlying = eth, collateral = usd, oracle1 = eth/usd = 1000
                    // [(oracle1, false)], return oracle1 = 1000
                    name: "1 oracle, vanilla",
                    path: [
                        { oracle: oracle1.address, isInverse: false },
                    ],
                    price: toWei('1000'),
                    time: 1,
                    underlying: 'ETH',
                    collateral: 'USD',
                },
                {
                    // Example 2: underlying = usd, collateral = eth, oracle1 = eth/usd = 1000
                    // [(oracle1, true)], return (1 / oracle1) = 0.001
                    name: "1 oracle, inverse",
                    path: [
                        { oracle: oracle1.address, isInverse: true },
                    ],
                    price: toWei('0.001'),
                    time: 1,
                    underlying: 'USD',
                    collateral: 'ETH',
                },
                {
                    // Example 3: underlying = btc, collateral = eth, oracle2 = btc/usd = 10000, oracle1 = eth/usd = 1000
                    // [(oracle1, true), (oracle2, false)], return (1 / oracle1) * oracle2 = 10
                    name: "2 oracles, vanilla",
                    path: [
                        { oracle: oracle1.address, isInverse: true },
                        { oracle: oracle2.address, isInverse: false },
                    ],
                    price: toWei('10'),
                    time: 2,
                    underlying: 'BTC',
                    collateral: 'ETH',
                },
                {
                    // Example 4: underlying = eth, collateral = btc, oracle2 = btc/usd = 10000, oracle4 = usd/eth = 0.001
                    // [(oracle2, true), (oracle3, true)], return (1 / oracle2) * (1 / oracle3) = 0.1
                    name: "2 oracles, inverse",
                    path: [
                        { oracle: oracle2.address, isInverse: true },
                        { oracle: oracle3.address, isInverse: true },
                    ],
                    price: toWei('0.1'),
                    time: 3,
                    underlying: 'ETH',
                    collateral: 'BTC',
                },
                {
                    // Example 5: underlying = xxx, collateral = eth, oracle2 = btc/usd = 10000, oracle1 = eth/usd = 1000, oracle4 = xxx/btc = 2
                    // [(oracle1, true), (oracle2, false), (oracle4, false)], return (1 / oracle1) * oracle2 * oracle4
                    name: "3 oracles",
                    path: [
                        { oracle: oracle1.address, isInverse: true },
                        { oracle: oracle2.address, isInverse: false },
                        { oracle: oracle4.address, isInverse: false },
                    ],
                    price: toWei('20'),
                    time: 4,
                    underlying: 'XXX',
                    collateral: 'ETH',
                },
            ];
            cases.forEach(element => {
                it(element.name, async () => {
                    const hash = getPathHash(element.path);
                    expect(await routerCreator.getPathHash(element.path)).to.equal(hash);
                    expect(await routerCreator.routers(hash)).to.equal('0x0000000000000000000000000000000000000000');
                    await routerCreator.createOracleRouter(element.path);
                    let routerAddress = await routerCreator.routers(hash);
                    expect(routerAddress).to.not.equal('0x0000000000000000000000000000000000000000');
                    await expect(routerCreator.createOracleRouter(element.path)).to.be.revertedWith('already deployed');

                    const router = await (await createFactory("OracleRouter")).attach(routerAddress)
                    {
                        const { newPrice, newTimestamp } = await router.callStatic.priceTWAPShort()
                        expect(newPrice).approximateBigNumber(element.price)
                        expect(newTimestamp).to.equal(element.time)
                    }
                    {
                        const { newPrice, newTimestamp } = await router.callStatic.priceTWAPLong()
                        expect(newPrice).approximateBigNumber(element.price)
                        expect(newTimestamp).to.equal(element.time)
                    }
                    expect(await router.underlyingAsset()).to.equal(element.underlying)
                    expect(await router.collateral()).to.equal(element.collateral)
                    const path = await router.getPath()
                    expect(path.length).to.equal(element.path.length)
                    for (let i = 0; i < path.length; i++) {
                        expect(path[i].oracle).to.equal(element.path[i].oracle)
                        expect(path[i].isInverse).to.equal(element.path[i].isInverse)
                    }
                    const dump = await router.dumpPath()
                    expect(dump.length).to.equal(element.path.length)
                    for (let i = 0; i < dump.length; i++) {
                        expect(dump[i].oracle).to.equal(element.path[i].oracle)
                        expect(dump[i].isInverse).to.equal(element.path[i].isInverse)
                        const { underlyingAsset, collateral } = describeOracleByAddress(element.path[i].oracle)
                        expect(dump[i].underlyingAsset).to.equal(underlyingAsset)
                        expect(dump[i].collateral).to.equal(collateral)
                    }
                });
            });
        });
    })

    it("closed / terminated", async () => {
        const path = [
            { oracle: oracle2.address, isInverse: true },
            { oracle: oracle4.address, isInverse: true },
        ]
        const hash = getPathHash(path);
        await routerCreator.createOracleRouter(path);
        let routerAddress = await routerCreator.routers(hash);
        const router = await (await createFactory("OracleRouter")).attach(routerAddress);
        
        expect(await router.callStatic.isMarketClosed()).to.be.false;
        expect(await router.callStatic.isTerminated()).to.be.false;

        await oracle2.setTerminated(true);
        await oracle2.setMarketClosed(true);

        expect(await router.callStatic.isMarketClosed()).to.be.true;
        expect(await router.callStatic.isTerminated()).to.be.true;

    })
})

