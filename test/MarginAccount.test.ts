const { ethers } = require("hardhat");
import { expect } from "chai";
import {
    toWei,
    toBytes32,
    getAccounts,
    createContract,
} from '../scripts/utils';

describe('MarginModule', () => {
    let accounts;

    before(async () => {
        accounts = await getAccounts();
    })

    describe('Getters', async () => {
        let testMargin;

        beforeEach(async () => {
            const oracle = await createContract("OracleWrapper", ["ctk", "ctk"]);
            const AMMModule = await createContract("AMMModule");
            const CollateralModule = await createContract("CollateralModule")
            const OrderModule = await createContract("OrderModule");
            const PerpetualModule = await createContract("PerpetualModule");
            const LiquidityPoolModule = await createContract("LiquidityPoolModule", [], { CollateralModule, AMMModule, PerpetualModule });
            const TradeModule = await createContract("TradeModule", [], { AMMModule, CollateralModule, PerpetualModule, LiquidityPoolModule });
            testMargin = await createContract("TestMarginAccount", [], {
                AMMModule,
                CollateralModule,
                OrderModule,
                PerpetualModule,
                LiquidityPoolModule,
                TradeModule,
            });

            await testMargin.createPerpetual(
                oracle.address,
                // imr         mmr            operatorfr      lpfr            rebate        penalty        keeper       insur
                [toWei("1"), toWei("1"), toWei("0.0001"), toWei("0.0007"), toWei("0"), toWei("0.005"), toWei("1"), toWei("0"), toWei("1000")],
                [toWei("0.01"), toWei("0.1"), toWei("0.06"), toWei("0.1"), toWei("5")],
            )
        })

        const testCases = [
            {
                name: "+getInitialMargin",
                method: "getInitialMargin",
                markPrice: toWei("500"),
                marginAccount: {
                    cash: toWei("100"),
                    position: toWei("1"),
                },
                parameters: {
                    initialMarginRate: toWei("0.1"),
                },
                unitAccumulativeFunding: toWei("0"),
                trader: 0,
                expect: toWei("50")
            },
            {
                name: "-getInitialMargin",
                method: "getInitialMargin",
                markPrice: toWei("500"),
                marginAccount: {
                    cash: toWei("100"),
                    position: toWei("-1"),
                },
                parameters: {
                    initialMarginRate: toWei("0.1"),
                },
                unitAccumulativeFunding: toWei("0"),
                trader: 0,
                expect: toWei("50")
            },
            {
                name: "+getMaintenanceMargin",
                method: "getMaintenanceMargin",
                markPrice: toWei("500"),
                marginAccount: {
                    cash: toWei("100"),
                    position: toWei("1"),
                },
                parameters: {
                    maintenanceMarginRate: toWei("0.05"),
                },
                unitAccumulativeFunding: toWei("0"),
                trader: 0,
                expect: toWei("25")
            },
            {
                name: "-getMaintenanceMargin",
                method: "getMaintenanceMargin",
                markPrice: toWei("500"),
                marginAccount: {
                    cash: toWei("100"),
                    position: toWei("-1"),
                },
                parameters: {
                    maintenanceMarginRate: toWei("0.05"),
                },
                unitAccumulativeFunding: toWei("0"),
                trader: 0,
                expect: toWei("25")
            },
            {
                name: "+margin",
                method: "getMargin2",
                markPrice: toWei("500"),
                marginAccount: {
                    cash: toWei("100"),
                    position: toWei("1"),
                },
                parameters: {
                    initialMarginRate: toWei("0.1")
                },
                unitAccumulativeFunding: toWei("0"),
                trader: 0,
                expect: toWei("600")
            },
            {
                name: "-margin",
                method: "getMargin2",
                markPrice: toWei("500"),
                marginAccount: {
                    cash: toWei("100"),
                    position: toWei("-1"),
                },
                parameters: {
                    initialMarginRate: toWei("0.1")
                },
                unitAccumulativeFunding: toWei("0"),
                trader: 0,
                expect: toWei("-400")
            },
            {
                name: "+position",
                method: "getPosition",
                markPrice: toWei("500"),
                marginAccount: {
                    cash: toWei("100"),
                    position: toWei("1"),
                },
                unitAccumulativeFunding: toWei("0"),
                trader: 0,
                expect: toWei("1")
            },
            {
                name: "-position",
                method: "getPosition",
                markPrice: toWei("500"),
                marginAccount: {
                    cash: toWei("100"),
                    position: toWei("1"),
                },
                unitAccumulativeFunding: toWei("0"),
                trader: 0,
                expect: toWei("1")
            },
            {
                name: "getAvailableCash + funding",
                method: "getAvailableCash",
                markPrice: toWei("500"),
                marginAccount: {
                    cash: toWei("100"),
                    position: toWei("1"),
                },
                unitAccumulativeFunding: toWei("10"),
                trader: 0,
                expect: toWei("90") // 100 - (1*10 - 0)
            },
            {
                name: "getAvailableCash - funding 1",
                method: "getAvailableCash",
                markPrice: toWei("500"),
                marginAccount: {
                    cash: toWei("100"),
                    position: toWei("1"),
                },
                unitAccumulativeFunding: toWei("10"),
                trader: 0,
                expect: toWei("90") // 100 + (1*10 - 20)
            },
            {
                name: "getAvailableCash - funding 2",
                method: "getAvailableCash",
                markPrice: toWei("500"),
                marginAccount: {
                    cash: toWei("100"),
                    position: toWei("1"),
                },
                unitAccumulativeFunding: toWei("-10"),
                trader: 0,
                expect: toWei("110")
            },
            {
                name: "+isInitialMarginSafe yes",
                method: "isInitialMarginSafe",
                markPrice: toWei("500"),
                marginAccount: {
                    cash: toWei("-450"),
                    position: toWei("1"),
                },
                parameters: {
                    initialMarginRate: toWei("0.1"),
                },
                unitAccumulativeFunding: toWei("0"),
                trader: 0,
                expect: true, // 500 - 450 vs 50
            },
            {
                name: "-isInitialMarginSafe yes",
                method: "isInitialMarginSafe",
                markPrice: toWei("500"),
                marginAccount: {
                    cash: toWei("550"),
                    position: toWei("-1"),
                },
                parameters: {
                    initialMarginRate: toWei("0.1"),
                },
                unitAccumulativeFunding: toWei("0"),
                trader: 0,
                expect: true, // -500 + 550 vs 50
            },
            {
                name: "+isInitialMarginSafe no",
                method: "isInitialMarginSafe",
                markPrice: toWei("500"),
                marginAccount: {
                    cash: toWei("-450.1"),
                    position: toWei("1"),
                },
                parameters: {
                    initialMarginRate: toWei("0.1"),
                },
                unitAccumulativeFunding: toWei("0"),
                trader: 0,
                expect: false, // 500 - 450.1 vs 50
            },
            {
                name: "-isInitialMarginSafe no",
                method: "isInitialMarginSafe",
                markPrice: toWei("500"),
                marginAccount: {
                    cash: toWei("549.9"),
                    position: toWei("-1"),
                },
                parameters: {
                    initialMarginRate: toWei("0.1"),
                },
                unitAccumulativeFunding: toWei("0"),
                trader: 0,
                expect: false, // -500 + 549.9 vs 50
            },
            {
                name: "+isMaintenanceMarginSafe yes",
                method: "isMaintenanceMarginSafe",
                markPrice: toWei("500"),
                marginAccount: {
                    cash: toWei("-450"),
                    position: toWei("1"),
                },
                parameters: {
                    maintenanceMarginRate: toWei("0.1"),
                },
                unitAccumulativeFunding: toWei("0"),
                trader: 0,
                expect: true,
            },
            {
                name: "-isMaintenanceMarginSafe yes",
                method: "isMaintenanceMarginSafe",
                markPrice: toWei("500"),
                marginAccount: {
                    cash: toWei("550"),
                    position: toWei("-1"),
                },
                parameters: {
                    maintenanceMarginRate: toWei("0.1"),
                },
                unitAccumulativeFunding: toWei("0"),
                trader: 0,
                expect: true,
            },
            {
                name: "+isMaintenanceMarginSafe no",
                method: "isMaintenanceMarginSafe",
                markPrice: toWei("500"),
                marginAccount: {
                    cash: toWei("-450.1"),
                    position: toWei("1"),
                },
                parameters: {
                    maintenanceMarginRate: toWei("0.1"),
                },
                unitAccumulativeFunding: toWei("0"),
                trader: 0,
                expect: false,
            },
            {
                name: "-isMaintenanceMarginSafe no",
                method: "isMaintenanceMarginSafe",
                markPrice: toWei("500"),
                marginAccount: {
                    cash: toWei("549.9"),
                    position: toWei("-1"),
                },
                parameters: {
                    maintenanceMarginRate: toWei("0.1"),
                },
                unitAccumulativeFunding: toWei("0"),
                trader: 0,
                expect: false, // 549.9 -500 >= |-1 * 500 * 0.1|
            },
            {
                method: "isEmptyAccount",
                markPrice: toWei("500"),
                marginAccount: {
                    cash: toWei("0"),
                    position: toWei("0"),
                },
                parameters: {
                    initialMarginRate: toWei("0.1"),
                },
                unitAccumulativeFunding: toWei("10"),
                trader: 0,
                expect: true,
            },
            {
                name: "isEmptyAccount - 1",
                method: "isEmptyAccount",
                markPrice: toWei("500"),
                marginAccount: {
                    cash: toWei("1"),
                    position: toWei("0"),
                },
                parameters: {
                    initialMarginRate: toWei("0.1"),
                },
                unitAccumulativeFunding: toWei("10"),
                trader: 0,
                expect: false,
            },
            {
                name: "isEmptyAccount - 2",
                method: "isEmptyAccount",
                markPrice: toWei("500"),
                marginAccount: {
                    cash: toWei("0"),
                    position: toWei("1"),
                },
                parameters: {
                    initialMarginRate: toWei("0.1"),
                },
                unitAccumulativeFunding: toWei("10"),
                trader: 0,
                expect: false,
            }
        ]

        testCases.forEach((testCase) => {
            it(testCase["name"] || testCase.method, async () => {
                await testMargin.setState(0, 2);
                await testMargin.setMarkPrice(0, testCase.markPrice);
                await testMargin.setMarginAccount(
                    0,
                    accounts[testCase.trader].address,
                    testCase.marginAccount.cash,
                    testCase.marginAccount.position);
                for (var key in testCase.parameters || {}) {
                    await testMargin.setPerpetualBaseParameter(0, toBytes32(key), testCase.parameters[key]);
                }
                await testMargin.setUnitAccumulativeFunding(0, testCase.unitAccumulativeFunding);
                if (typeof testCase.expect != "undefined") {
                    const result = await testMargin.callStatic[testCase.method](0, accounts[testCase.trader].address);
                    expect(result).to.equal(testCase["expect"])
                } else {
                    const result = await testMargin.callStatic[testCase.method](0, accounts[testCase.trader].address);
                    expect(result).to.be.revertedWith(testCase["expectError"])
                }
            })
        })
    })


    describe('Setters', async () => {
        let testMargin;

        before(async () => {
            const oracle = await createContract("OracleWrapper", ["ctk", "ctk"]);
            const AMMModule = await createContract("AMMModule");
            const CollateralModule = await createContract("CollateralModule")
            const OrderModule = await createContract("OrderModule");
            const PerpetualModule = await createContract("PerpetualModule");
            const LiquidityPoolModule = await createContract("LiquidityPoolModule", [], { CollateralModule, AMMModule, PerpetualModule });
            const TradeModule = await createContract("TradeModule", [], { AMMModule, CollateralModule, PerpetualModule, LiquidityPoolModule });
            testMargin = await createContract("TestMarginAccount", [], {
                AMMModule,
                CollateralModule,
                OrderModule,
                PerpetualModule,
                LiquidityPoolModule,
                TradeModule,
            });

            await testMargin.createPerpetual(
                oracle.address,
                // imr         mmr            operatorfr      lpfr            rebate        penalty        keeper       insur
                [toWei("1"), toWei("1"), toWei("0.0001"), toWei("0.0007"), toWei("0"), toWei("0.005"), toWei("1"), toWei("0"), toWei("1000")],
                [toWei("0.01"), toWei("0.1"), toWei("0.06"), toWei("0.1"), toWei("5")],
            )
        })

        it("setMarginAccount", async () => {
            let trader = accounts[0].address;
            await testMargin.setMarkPrice(0, toWei("500"));
            await testMargin.setUnitAccumulativeFunding(0, toWei("-100"));

            await testMargin.setMarginAccount(0, trader, toWei("100"), toWei("2")) // +100 + 2*100
            expect(await testMargin.getAvailableCash(0, trader)).to.equal(toWei("300"));
            expect(await testMargin.getPosition(0, trader)).to.equal(toWei("2"));

            await testMargin.setUnitAccumulativeFunding(0, toWei("-200"));
            await testMargin.setMarginAccount(0, trader, toWei("100"), toWei("0.5")) // +100 + 0.5*200
            expect(await testMargin.getAvailableCash(0, trader)).to.equal(toWei("200"));
            expect(await testMargin.getPosition(0, trader)).to.equal(toWei("0.5"));

            await testMargin.setUnitAccumulativeFunding(0, toWei("0"));
            await testMargin.setMarginAccount(0, trader, toWei("-100"), toWei("-1"))
            expect(await testMargin.getAvailableCash(0, trader)).to.equal(toWei("-100"));
            expect(await testMargin.getPosition(0, trader)).to.equal(toWei("-1"));

            await testMargin.setUnitAccumulativeFunding(0, toWei("-100"));
            await testMargin.setMarginAccount(0, trader, toWei("-100"), toWei("-5"))
            expect(await testMargin.getAvailableCash(0, trader)).to.equal(toWei("-600"));
            expect(await testMargin.getPosition(0, trader)).to.equal(toWei("-5"));
        })
    })
})