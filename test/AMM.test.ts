import { expect } from "chai";
import BigNumber from 'bignumber.js';

import "./helper";
import { createContract } from '../scripts/utils';

const weis = new BigNumber('1000000000000000000');
const toWad = (x: any) => {
    return new BigNumber(x).times(weis).toFixed(0);
}
const _0 = toWad('0')

const params = {
    ammMaxLeverage: toWad('5'),
    indexPrice: toWad('100'),
    state: 2
}

// [-2] emergency
const ammEmergency = {
    cash: toWad('10000'),
    positionAmount1: toWad('-50'),
    positionAmount2: toWad('-52'),
    // available cash = 10000 - 1.9 * (-50) - 1.9 * (-52) = 10193.8
    // pool margin = emergency
}

// [-1] init
const ammInit = {
    cash: _0,
    positionAmount1: _0,
    positionAmount2: _0,
    // available cash = 0
    // pool margin = 0
}

// [0] flat
const amm0 = {
    cash: toWad('10000'),
    positionAmount1: _0,
    positionAmount2: _0,
    // available cash = 10000
    // pool margin = 10000
}

// [1] short 1: normal
const amm1 = {
    cash: toWad('10100'),
    positionAmount1: toWad('-10'),
    positionAmount2: toWad('10'),
    // available cash = 10100 - 1.9 * (-10) - 1.9 * (10) = 10100
    // pool margin = 10000
}

// [2] short 2: loss but safe
const amm2 = {
    cash: toWad('14599'),
    positionAmount1: toWad('-50'),
    positionAmount2: toWad('10'),
    // available cash = 14599 - 1.9 * (-50) - 1.9 * (10) = 14675
    // pool margin = 9273.09477715884768908142691791
}

// [3] short 3: unsafe
const amm3 = {
    cash: toWad('17692'),
    positionAmount1: toWad('-80'),
    positionAmount2: toWad('10'),
    // available cash = 17692 - 1.9 * (-80) - 1.9 * (10) = 17825
    // pool margin = unsafe
}

// [4] long 1: normal
const amm4 = {
    cash: toWad('8138'),
    positionAmount1: toWad('10'),
    positionAmount2: toWad('10'),
    // available cash = 8138 - 1.9 * (10) - 1.9 * (10)= 8100
    // pool margin = 10000
}

// [5] long 2: loss but safe
const amm5 = {
    cash: toWad('1664'),
    positionAmount1: toWad('50'),
    positionAmount2: toWad('10'),
    // available cash = 1664 - 1.9 * (50) - 1.9 * (10) = 1550
    // pool margin = 4893.31346231725208539935787445
}

// [6] long 3: unsafe
const amm6 = {
    cash: toWad('1996'),
    positionAmount1: toWad('80'),
    positionAmount2: toWad('10'),
    // available cash = 1996 - 1.9 * (80) - 1.9 * (10) = 1825
    // pool margin = unsafe
}

// [7] negative price
const amm7 = {
    cash: toWad('9733.5'),
    positionAmount1: toWad('60'),
    positionAmount2: toWad('-50'),
    // available cash = 9733.5 - 1.9 * (60) - 1.9 * (-50) = 9714.5
    // pool margin = open unsafe, close 5368.54
}

describe('AMM', () => {
    let amm;

    beforeEach(async () => {
        const ammModule = await createContract("AMMModule")
        amm = await createContract("TestAMM", [], { "AMMModule": ammModule });
    });

    describe('isAMMSafe', function () {

        const cases = [
            {
                name: 'init - ok',
                amm: ammInit,
                isSafe: true
            },
            {
                name: 'flat - ok',
                amm: amm0,
                isSafe: true
            },
            {
                name: 'short - ok',
                amm: amm1,
                isSafe: true
            },
            {
                name: 'short - fail',
                amm: amm3,
                isSafe: false
            },
            {
                name: 'long - ok',
                amm: amm4,
                isSafe: true
            },
            {
                name: 'long - fail',
                amm: amm6,
                isSafe: false
            }
        ]

        cases.forEach(element => {
            it(element.name, async () => {
                await amm.setParams(params.ammMaxLeverage, element.amm.cash, element.amm.positionAmount1, element.amm.positionAmount2, params.indexPrice, params.indexPrice, params.state)
                if (element.isSafe) {
                    expect(await amm.isAMMSafe()).to.be.true
                } else {
                    expect(await amm.isAMMSafe()).to.be.false
                }
            })
        })
    })

    describe('getPoolMargin', function () {

        const successCases = [
            {
                amm: ammInit,
                poolMargin: _0,
            },
            {
                amm: amm0,
                poolMargin: toWad('10000'),
            },
            {
                amm: amm1,
                poolMargin: toWad('10000'),
            },
            {
                amm: amm2,
                poolMargin: toWad(' 9273.09477715884768908142691791'),
            },
            {
                amm: amm4,
                poolMargin: toWad('10000'),
            },
            {
                amm: amm5,
                poolMargin: toWad('4893.31346231725208539935787445'),
            }
        ]

        successCases.forEach((element, index) => {
            it(`success-${index}`, async () => {
                await amm.setParams(params.ammMaxLeverage, element.amm.cash, element.amm.positionAmount1, element.amm.positionAmount2, params.indexPrice, params.indexPrice, params.state)
                expect(await amm.getPoolMargin()).approximateBigNumber(element.poolMargin);
            })
        })

        const failCases = [
            {
                name: 'short unsafe',
                amm: amm3
            },
            {
                name: 'long unsafe',
                amm: amm6
            }
        ]

        failCases.forEach(element => {
            it(element.name, async () => {
                await amm.setParams(params.ammMaxLeverage, element.amm.cash, element.amm.positionAmount1, element.amm.positionAmount2, params.indexPrice, params.indexPrice, params.state)
                await expect(amm.getPoolMargin()).to.be.revertedWith('AMM is unsafe when calculating pool margin')
            })
        })
    })

    describe('getDeltaCash', function () {

        const cases = [
            {
                name: '0 -> +5',
                amm: amm0,
                amount: toWad('5'),
                deltaCash: toWad('-487.5')
            },
            {
                name: '0 -> -5',
                amm: amm0,
                amount: toWad('-5'),
                deltaCash: toWad('512.5')
            }
        ]

        cases.forEach(element => {
            it(element.name, async () => {
                await amm.setParams(params.ammMaxLeverage, element.amm.cash, element.amm.positionAmount1, element.amm.positionAmount2, params.indexPrice, params.indexPrice, params.state)
                expect(await amm.getDeltaCash(element.amount)).approximateBigNumber(element.deltaCash)
            })
        })
    })

    describe('safePosition', function () {
        const cases = [
            {
                name: 'init',
                amm: ammInit,
                isLongSide: false,
                ammMaxLeverage: params.ammMaxLeverage,
                positionAmount2: ammInit.positionAmount2,
                maxPosition: _0
            },
            {
                name: 'short, infinite max position2, choose max position1',
                amm: amm1,
                isLongSide: false,
                ammMaxLeverage: params.ammMaxLeverage,
                positionAmount2: amm1.positionAmount2,
                maxPosition: toWad('-141.067359796658844252321636909')
            },
            {
                name: 'short, choose max position1',
                amm: amm1,
                isLongSide: false,
                ammMaxLeverage: toWad('0.991'),
                positionAmount2: toWad('200'),
                maxPosition: toWad('-128.653323548597695348814505356')
            },
            {
                name: 'short, choose max position2',
                amm: amm1,
                isLongSide: false,
                ammMaxLeverage: toWad('0.5'),
                positionAmount2: amm1.positionAmount2,
                maxPosition: toWad('-45.403751662596934803491571167')
            },
            {
                name: 'long, choose max position3',
                amm: amm4,
                isLongSide: true,
                ammMaxLeverage: params.ammMaxLeverage,
                positionAmount2: amm4.positionAmount2,
                maxPosition: toWad('100')
            }
        ]

        cases.forEach(element => {
            it(element.name, async () => {
                await amm.setParams(element.ammMaxLeverage, element.amm.cash, element.amm.positionAmount1, element.positionAmount2, params.indexPrice, params.indexPrice, params.state)
                expect(await amm.maxPosition(element.isLongSide)).approximateBigNumber(element.maxPosition)
            })
        })

        it('zero index price', async () => {
            await amm.setParams(params.ammMaxLeverage, amm1.cash, amm1.positionAmount1, amm1.positionAmount2, _0, params.indexPrice, params.state)
            await expect(amm.maxPosition(0)).to.be.revertedWith('index price must be positive')
        })
    })

    describe('trade - success', function () {

        const successCases = [
            {
                name: 'open 0 -> -141.421, near pos2 limit',
                amm: amm0,
                amount: toWad('-141.421'),
                partialFill: false,
                deltaCash: toWad('24142.0496205'),
                deltaPosition: toWad('-141.421')
            },
            {
                name: 'open 0 -> -0.1, effected by spread',
                amm: amm0,
                amount: toWad('-0.1'),
                partialFill: false,
                deltaCash: toWad('10.01'),
                deltaPosition: toWad('-0.1')
            },
            {
                name: 'open -10 -> -141.067, near pos2 limit',
                amm: amm1,
                amount: toWad('-131.067'),
                partialFill: false,
                deltaCash: toWad('23006.6492445'),
                deltaPosition: toWad('-131.067')
            },
            {
                name: 'open -10 -> -10.1, effected by spread',
                amm: amm1,
                amount: toWad('-0.1'),
                partialFill: false,
                deltaCash: toWad('11.011'),
                deltaPosition: toWad('-0.1')
            },
            {
                name: 'open 0 -> 100, near pos2 limit',
                amm: amm0,
                amount: toWad('100'),
                deltaCash: toWad('-5000'),
                deltaPosition: toWad('100')
            },
            {
                name: 'open 0 -> 0.1, effected by spread',
                amm: amm0,
                amount: toWad('0.1'),
                partialFill: false,
                deltaCash: toWad('-9.99'),
                deltaPosition: toWad('0.1')
            },
            {
                name: 'open 10 -> 100, near pos2 limit',
                amm: amm4,
                amount: toWad('90'),
                deltaCash: toWad('-4050'),
                deltaPosition: toWad('90')
            },
            {
                name: 'open 10 -> 10.1, effected by spread',
                amm: amm4,
                amount: toWad('0.1'),
                partialFill: false,
                deltaCash: toWad('-8.991'),
                deltaPosition: toWad('0.1')
            },
            {
                name: 'close -10 -> -9, normal',
                amm: amm1,
                amount: toWad('1'),
                deltaCash: toWad('-108.5456861964445578147169'),
                deltaPosition: toWad('1')
            },
            {
                name: 'open -10 -> -9.9, effected by spread',
                amm: amm1,
                amount: toWad('0.1'),
                partialFill: false,
                deltaCash: toWad('-10.88864636949980139546338319'),
                deltaPosition: toWad('0.1')
            },
            {
                name: 'close -10 -> 0, to zero',
                amm: amm1,
                amount: toWad('10'),
                deltaCash: toWad('-1044.977295770760830603773'),
                deltaPosition: toWad('10')
            },
            {
                name: 'close 10 -> 9, normal',
                amm: amm4,
                amount: toWad('-1'),
                deltaCash: toWad('91.4543138035554421852831'),
                deltaPosition: toWad('-1')
            },
            {
                name: 'close 10 -> 9.9, effected by spread',
                amm: amm4,
                amount: toWad('-0.1'),
                partialFill: false,
                deltaCash: toWad('9.109554538669368171312465896'),
                deltaPosition: toWad('-0.1')
            },
            {
                name: 'close 10 -> 0',
                amm: amm4,
                amount: toWad('-10'),
                deltaCash: toWad('955.022704229239169396227'),
                deltaPosition: toWad('-10')
            },
            {
                name: 'close unsafe -10 -> -9, normal',
                amm: amm3,
                amount: toWad('1'),
                deltaCash: toWad('-100'),
                deltaPosition: toWad('1')
            },
            {
                name: 'close unsafe -10 -> -9.9, small',
                amm: amm3,
                amount: toWad('0.1'),
                deltaCash: toWad('-10'),
                deltaPosition: toWad('0.1')
            },
            {
                name: 'close unsafe 10 -> 9, normal',
                amm: amm6,
                amount: toWad('-1'),
                deltaCash: toWad('100'),
                deltaPosition: toWad('-1')
            },
            {
                name: 'close unsafe 10 -> 9, small',
                amm: amm6,
                amount: toWad('-0.1'),
                deltaCash: toWad('10'),
                deltaPosition: toWad('-0.1')
            },
            {
                name: 'close negative price, clip to index*(1-discount)',
                amm: amm7,
                amount: toWad('-0.01'),
                deltaCash: toWad('0.8'),
                deltaPosition: toWad('-0.01')
            },
            {
                name: 'open 0 -> -141.422, partialFill',
                amm: amm0,
                amount: toWad('-141.422'),
                partialFill: true,
                deltaCash: toWad('24142.1356237309504880168872421'),
                deltaPosition: toWad('-141.421356237309504880168872421')
            },
            {
                name: 'open -10 -> -141.068, pos2 too large, partialFill',
                amm: amm1,
                amount: toWad('-131.068'),
                partialFill: true,
                deltaCash: toWad('23006.7359796658844252321636909'),
                deltaPosition: toWad('-131.067359796658844252321636909')
            },
            {
                name: 'open -10 already unsafe, partialFill',
                amm: amm3,
                amount: toWad('-0.01'),
                partialFill: true,
                deltaCash: _0,
                deltaPosition: _0
            },
            {
                name: 'open 0 -> 100.001, partialFill',
                amm: amm0,
                amount: toWad('100.001'),
                partialFill: true,
                deltaCash: toWad('-5000'),
                deltaPosition: toWad('100')
            },
            {
                name: 'open 10 -> 100.001, partialFill',
                amm: amm4,
                amount: toWad('90.001'),
                partialFill: true,
                deltaCash: toWad('-4050'),
                deltaPosition: toWad('90')
            },
            {
                name: 'open 10 already unsafe, partialFill',
                amm: amm6,
                amount: toWad('0.01'),
                partialFill: true,
                deltaCash: _0,
                deltaPosition: _0
            }
        ]

        successCases.forEach(element => {
            it(element.name, async () => {
                await amm.setParams(params.ammMaxLeverage, element.amm.cash, element.amm.positionAmount1, element.amm.positionAmount2, params.indexPrice, params.indexPrice, params.state)
                const context = await amm.queryTradeWithAMM(element.amount, element.partialFill)
                expect(context[0]).approximateBigNumber(element.deltaCash)
                expect(context[1]).approximateBigNumber(element.deltaPosition)
            })
        })
    })

    describe('trade - fail', function () {

        const failCases = [
            {
                name: 'emergency',
                amm: ammEmergency,
                amount: toWad('1'),
                partialFill: false,
                errorMsg: 'AMM is mm unsafe'
            },
            {
                name: 'zero trade amount',
                amm: amm0,
                amount: _0,
                partialFill: false,
                errorMsg: 'trading amount is zero'
            },
            {
                name: 'poolMargin = 0',
                amm: ammInit,
                amount: toWad('1'),
                partialFill: false,
                errorMsg: 'pool margin must be positive'
            },
            {
                name: 'open 0 -> -141.422, pos2 too large',
                amm: amm0,
                amount: toWad('-141.422'),
                partialFill: false,
                errorMsg: 'trade amount exceeds max amount'
            },
            {
                name: 'open -10 -> -141.068, pos2 too large',
                amm: amm1,
                amount: toWad('-131.068'),
                partialFill: false,
                errorMsg: 'trade amount exceeds max amount'
            },
            {
                name: 'open -10 already unsafe',
                amm: amm3,
                amount: toWad('-0.01'),
                partialFill: false,
                errorMsg: 'AMM is unsafe when open'
            },
            {
                name: 'open 0 -> 100.001',
                amm: amm0,
                amount: toWad('100.001'),
                partialFill: false,
                errorMsg: 'trade amount exceeds max amount'
            },
            {
                name: 'open 10 -> 100.001',
                amm: amm4,
                amount: toWad('90.001'),
                partialFill: false,
                errorMsg: 'trade amount exceeds max amount'
            },
            {
                name: 'open 10 already unsafe',
                amm: amm6,
                amount: toWad('0.01'),
                partialFill: false,
                errorMsg: 'AMM is unsafe when open'
            }
        ]

        failCases.forEach(element => {
            it(element.name, async () => {
                await amm.setParams(params.ammMaxLeverage, element.amm.cash, element.amm.positionAmount1, element.amm.positionAmount2, params.indexPrice, params.indexPrice, params.state)
                await expect(amm.queryTradeWithAMM(element.amount, element.partialFill)).to.be.revertedWith(element.errorMsg)
            })
        })
    })

    describe('get share to mint', async () => {

        const successCases = [
            {
                name: 'init',
                amm: ammInit,
                totalShare: _0,
                cashToAdd: toWad('1000'),
                share: toWad('1000')
            },
            {
                name: 'before safe, after safe',
                amm: amm1,
                totalShare: toWad('100'),
                cashToAdd: toWad('1000'),
                share: toWad('10.0916660306314520522392020897')
            },
            {
                name: 'short, before unsafe, after unsafe',
                amm: amm3,
                totalShare: toWad('100'),
                cashToAdd: toWad('576'),
                share: toWad('5.321016166281755196304849885')
            },
            {
                name: 'short, before unsafe, after safe',
                amm: amm3,
                totalShare: toWad('100'),
                cashToAdd: toWad('577'),
                share: toWad('6.021800176340430529365414419')
            },
            {
                name: 'long, before unsafe, after unsafe',
                amm: amm6,
                totalShare: toWad('100'),
                cashToAdd: toWad('576'),
                share: toWad('5.321016166281755196304849885')
            },
            {
                name: 'long, before unsafe, after safe',
                amm: amm6,
                totalShare: toWad('100'),
                cashToAdd: toWad('577'),
                share: toWad('6.021800176340430529365414419')
            }
        ]

        successCases.forEach(element => {
            it(element.name, async () => {
                await amm.setParams(params.ammMaxLeverage, element.amm.cash, element.amm.positionAmount1, element.amm.positionAmount2, params.indexPrice, params.indexPrice, params.state)
                var context = await amm.getShareToMint(element.totalShare, element.cashToAdd);
                expect(context[0]).approximateBigNumber(element.share);
            })
        })

        it("poolMargin = 0 && totalShare != 0", async () => {
            await amm.setParams(params.ammMaxLeverage, ammInit.cash, ammInit.positionAmount1, ammInit.positionAmount2, params.indexPrice, params.indexPrice, params.state)
            await expect(amm.getShareToMint(toWad('100'), toWad('100'))).to.be.revertedWith("share token has no value");
        })
    })

    describe('get cash to add', async () => {

        const successCases = [
            {
                name: 'init',
                amm: ammInit,
                totalShare: _0,
                shareToMint: toWad('1000'),
                cash: toWad('1000')
            },
            {
                name: 'before safe, after safe',
                amm: amm1,
                totalShare: toWad('100'),
                shareToMint: toWad('10.0916660306314520522392020897'),
                cash: toWad('1000')
            },
            {
                name: 'short, before unsafe, after unsafe',
                amm: amm3,
                totalShare: toWad('100'),
                shareToMint: toWad('5.321016166281755196304849885'),
                cash: toWad('576')
            },
            {
                name: 'short, before unsafe, after safe',
                amm: amm3,
                totalShare: toWad('100'),
                shareToMint: toWad('6.021800176340430529365414419'),
                cash: toWad('577')
            },
            {
                name: 'long, before unsafe, after unsafe',
                amm: amm6,
                totalShare: toWad('100'),
                shareToMint: toWad('5.321016166281755196304849885'),
                cash: toWad('576')
            },
            {
                name: 'long, before unsafe, after safe',
                amm: amm6,
                totalShare: toWad('100'),
                shareToMint: toWad('6.021800176340430529365414419'),
                cash: toWad('577')
            }
        ]

        successCases.forEach(element => {
            it(element.name, async () => {
                await amm.setParams(params.ammMaxLeverage, element.amm.cash, element.amm.positionAmount1, element.amm.positionAmount2, params.indexPrice, params.indexPrice, params.state)
                expect(await amm.getCashToAdd(element.totalShare, element.shareToMint)).approximateBigNumber(element.cash);
            })
        })

        it("poolMargin = 0 && totalShare != 0", async () => {
            await amm.setParams(params.ammMaxLeverage, ammInit.cash, ammInit.positionAmount1, ammInit.positionAmount2, params.indexPrice, params.indexPrice, params.state)
            await expect(amm.getCashToAdd(toWad('100'), toWad('100'))).to.be.revertedWith("share token has no value");
        })
    })

    describe('get cash to return', function () {

        const successCases = [
            {
                name: 'no position',
                amm: amm0,
                totalShare: toWad('100'),
                shareToRemove: toWad('10'),
                marginToRemove: toWad('1000'),
                state: params.state,
                allCleared: false,
                removedInsuranceFund: toWad('0'),
                removedDonatedInsuranceFund: toWad('0')
            },
            {
                name: 'no position, remove all',
                amm: amm0,
                totalShare: toWad('100'),
                shareToRemove: toWad('100'),
                marginToRemove: toWad('10000'),
                state: params.state,
                allCleared: false,
                removedInsuranceFund: toWad('0'),
                removedDonatedInsuranceFund: toWad('0')
            },
            {
                name: 'short',
                amm: amm1,
                totalShare: toWad('100'),
                shareToRemove: toWad('10'),
                marginToRemove: toWad('988.888888888888888888888888889'),
                state: params.state,
                allCleared: false,
                removedInsuranceFund: toWad('0'),
                removedDonatedInsuranceFund: toWad('0')
            },
            {
                name: 'long',
                amm: amm4,
                totalShare: toWad('100'),
                shareToRemove: toWad('10'),
                marginToRemove: toWad('988.888888888888888888888888889'),
                state: params.state,
                allCleared: false,
                removedInsuranceFund: toWad('0'),
                removedDonatedInsuranceFund: toWad('0')
            },
            {
                name: 'state != NORMAL',
                amm: amm4,
                totalShare: toWad('100'),
                shareToRemove: toWad('10'),
                marginToRemove: toWad('900.25420688843233693447638834'),
                state: 3,
                allCleared: false,
                removedInsuranceFund: toWad('0'),
                removedDonatedInsuranceFund: toWad('0')
            },
            {
                name: 'all states CLEARED',
                amm: amm4,
                totalShare: toWad('100'),
                shareToRemove: toWad('10'),
                marginToRemove: toWad('824.8'),
                state: params.state,
                allCleared: true,
                removedInsuranceFund: toWad('10'),
                removedDonatedInsuranceFund: toWad('1')
            },
        ]

        successCases.forEach(element => {
            it(element.name, async () => {
                await amm.setParams(params.ammMaxLeverage, element.amm.cash, element.amm.positionAmount1, element.amm.positionAmount2, params.indexPrice, params.indexPrice, element.state)
                await amm.setInsuranceFund(toWad('100'), toWad('10'))
                if (element.allCleared) {
                    await amm.setAllCleared()
                }
                var context = await amm.getCashToReturn(element.totalShare, element.shareToRemove)
                expect(context.cashToReturn).approximateBigNumber(element.marginToRemove);
                expect(context.removedInsuranceFund).approximateBigNumber(element.removedInsuranceFund);
                expect(context.removedDonatedInsuranceFund).approximateBigNumber(element.removedDonatedInsuranceFund);
            })
        })

        const failCases = [
            {
                name: 'poolMargin = 0',
                amm: ammInit,
                totalShare: toWad('100'),
                shareToRemove: toWad('10'),
                ammMaxLeverage: params.ammMaxLeverage,
                errorMsg: 'pool margin must be positive',
            },
            {
                name: 'short, before unsafe',
                amm: amm3,
                totalShare: toWad('100'),
                shareToRemove: toWad('10'),
                ammMaxLeverage: params.ammMaxLeverage,
                errorMsg: 'AMM is unsafe before removing liquidity',
            },
            {
                name: 'long, before unsafe',
                amm: amm6,
                totalShare: toWad('100'),
                shareToRemove: toWad('10'),
                ammMaxLeverage: params.ammMaxLeverage,
                errorMsg: 'AMM is unsafe before removing liquidity',
            },
            {
                name: 'short, after unsafe',
                amm: amm1,
                totalShare: toWad('100'),
                shareToRemove: toWad('90.001'),
                ammMaxLeverage: params.ammMaxLeverage,
                errorMsg: 'AMM is unsafe after removing liquidity',
            },
            {
                name: 'long, after unsafe',
                amm: amm4,
                totalShare: toWad('100'),
                shareToRemove: toWad('90.001'),
                ammMaxLeverage: params.ammMaxLeverage,
                errorMsg: 'AMM is unsafe after removing liquidity',
            },
            {
                name: 'long, after negative price',
                amm: amm5,
                totalShare: toWad('100'),
                shareToRemove: toWad('0.001'),
                ammMaxLeverage: params.ammMaxLeverage,
                errorMsg: 'AMM is unsafe after removing liquidity',
            },
            {
                name: 'long, after exceed leverage',
                amm: amm4,
                totalShare: toWad('100'),
                shareToRemove: toWad('0.001'),
                ammMaxLeverage: toWad('0.1'),
                errorMsg: 'AMM exceeds max leverage after removing liquidity',
            }
        ]

        failCases.forEach(element => {
            it(element.name, async () => {
                await amm.setParams(element.ammMaxLeverage, element.amm.cash, element.amm.positionAmount1, element.amm.positionAmount2, params.indexPrice, params.indexPrice, params.state)
                await expect(amm.getCashToReturn(element.totalShare, element.shareToRemove)).to.be.revertedWith(element.errorMsg);
            })
        })
        it("zero index", async () => {
            await amm.setParams(params.ammMaxLeverage, amm4.cash, amm4.positionAmount1, amm4.positionAmount2, params.indexPrice, _0, params.state)
            await expect(amm.getCashToReturn(toWad('100'), toWad('1'))).to.be.revertedWith("index price must be positive");
        })
        it("zero supply of share token", async () => {
            await amm.setParams(params.ammMaxLeverage, amm4.cash, amm4.positionAmount1, amm4.positionAmount2, params.indexPrice, params.indexPrice, params.state)
            await expect(amm.getCashToReturn(_0, _0)).to.be.revertedWith("total supply of share token is zero when removing liquidity");
        })
    })

    describe('get share to remove', function () {

        const successCases = [
            {
                name: 'no position',
                amm: amm0,
                totalShare: toWad('100'),
                shareToRemove: toWad('10'),
                marginToRemove: toWad('1000'),
                state: params.state,
                allCleared: false,
                removedInsuranceFund: toWad('0'),
                removedDonatedInsuranceFund: toWad('0')
            },
            {
                name: 'no position, remove all',
                amm: amm0,
                totalShare: toWad('100'),
                shareToRemove: toWad('100'),
                marginToRemove: toWad('10000'),
                state: params.state,
                allCleared: false,
                removedInsuranceFund: toWad('0'),
                removedDonatedInsuranceFund: toWad('0')
            },
            {
                name: 'short',
                amm: amm1,
                totalShare: toWad('100'),
                shareToRemove: toWad('10'),
                marginToRemove: toWad('988.888888888888888888888888889'),
                state: params.state,
                allCleared: false,
                removedInsuranceFund: toWad('0'),
                removedDonatedInsuranceFund: toWad('0')
            },
            {
                name: 'long',
                amm: amm4,
                totalShare: toWad('100'),
                shareToRemove: toWad('10'),
                marginToRemove: toWad('988.888888888888888888888888889'),
                state: params.state,
                allCleared: false,
                removedInsuranceFund: toWad('0'),
                removedDonatedInsuranceFund: toWad('0')
            },
            {
                name: 'state != NORMAL',
                amm: amm4,
                totalShare: toWad('100'),
                shareToRemove: toWad('10'),
                marginToRemove: toWad('900.25420688843233693447638834'),
                state: 3,
                allCleared: false,
                removedInsuranceFund: toWad('0'),
                removedDonatedInsuranceFund: toWad('0')
            },
            {
                name: 'all cleared',
                amm: amm4,
                totalShare: toWad('100'),
                shareToRemove: toWad('10'),
                marginToRemove: toWad('824.8'),
                state: params.state,
                allCleared: true,
                removedInsuranceFund: toWad('10'),
                removedDonatedInsuranceFund: toWad('1')
            },
        ]

        successCases.forEach(element => {
            it(element.name, async () => {
                await amm.setParams(params.ammMaxLeverage, element.amm.cash, element.amm.positionAmount1, element.amm.positionAmount2, params.indexPrice, params.indexPrice, element.state)
                await amm.setInsuranceFund(toWad('100'), toWad('10'))
                if (element.allCleared) {
                    await amm.setAllCleared()
                }
                var context = await amm.getShareToRemove(element.totalShare, element.marginToRemove)
                expect(context.shareToRemove).approximateBigNumber(element.shareToRemove);
                expect(context.removedInsuranceFund).approximateBigNumber(element.removedInsuranceFund);
                expect(context.removedDonatedInsuranceFund).approximateBigNumber(element.removedDonatedInsuranceFund);
            })
        })

        const failCases = [
            {
                name: 'poolMargin = 0',
                amm: ammInit,
                totalShare: toWad('100'),
                marginToRemove: toWad('10'),
                ammMaxLeverage: params.ammMaxLeverage,
                errorMsg: 'AMM is unsafe after removing liquidity',
            },
            {
                name: 'short, before unsafe',
                amm: amm3,
                totalShare: toWad('100'),
                marginToRemove: toWad('10'),
                ammMaxLeverage: params.ammMaxLeverage,
                errorMsg: 'AMM is unsafe before removing liquidity',
            },
            {
                name: 'long, before unsafe',
                amm: amm6,
                totalShare: toWad('100'),
                marginToRemove: toWad('10'),
                ammMaxLeverage: params.ammMaxLeverage,
                errorMsg: 'AMM is unsafe before removing liquidity',
            },
            {
                name: 'short, after unsafe',
                amm: amm1,
                totalShare: toWad('100'),
                marginToRemove: toWad('8101'),
                ammMaxLeverage: params.ammMaxLeverage,
                errorMsg: 'AMM is unsafe after removing liquidity',
            },
            {
                name: 'long, after unsafe',
                amm: amm4,
                totalShare: toWad('100'),
                marginToRemove: toWad('8101'),
                ammMaxLeverage: params.ammMaxLeverage,
                errorMsg: 'AMM is unsafe after removing liquidity',
            },
            {
                name: 'long, after negative price',
                amm: amm5,
                totalShare: toWad('100'),
                marginToRemove: toWad('0.001'),
                ammMaxLeverage: params.ammMaxLeverage,
                errorMsg: 'AMM is unsafe after removing liquidity',
            },
            {
                name: 'long, after exceed leverage',
                amm: amm4,
                totalShare: toWad('100'),
                marginToRemove: toWad('0.001'),
                ammMaxLeverage: toWad('0.1'),
                errorMsg: 'AMM exceeds max leverage after removing liquidity',
            }
        ]

        failCases.forEach(element => {
            it(element.name, async () => {
                await amm.setParams(element.ammMaxLeverage, element.amm.cash, element.amm.positionAmount1, element.amm.positionAmount2, params.indexPrice, params.indexPrice, params.state)
                await expect(amm.getShareToRemove(element.totalShare, element.marginToRemove)).to.be.revertedWith(element.errorMsg);
            })
        })
        it("zero index", async () => {
            await amm.setParams(params.ammMaxLeverage, amm4.cash, amm4.positionAmount1, amm4.positionAmount2, params.indexPrice, _0, params.state)
            await expect(amm.getShareToRemove(toWad('100'), toWad('1'))).to.be.revertedWith("index price must be positive");
        })
        it("zero supply of share token", async () => {
            await amm.setParams(params.ammMaxLeverage, amm4.cash, amm4.positionAmount1, amm4.positionAmount2, params.indexPrice, params.indexPrice, params.state)
            await expect(amm.getShareToRemove(_0, toWad('1'))).to.be.revertedWith("total supply of share token is zero when removing liquidity");
        })
    })

});
