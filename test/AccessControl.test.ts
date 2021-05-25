const { ethers } = require("hardhat");
const { expect } = require("chai");

import {
    toWei,
    toBytes32,
    getAccounts,
    createContract,
    createFactory,
} from '../scripts/utils';

describe('AccessControl', () => {
    let accounts;
    let user0;
    let user1;
    let accessControl;
    let TestAccessControl;

    before(async () => {
        accounts = await getAccounts();
        user0 = accounts[0];
        user1 = accounts[1];

        TestAccessControl = await createFactory("TestAccessControl");
        accessControl = await TestAccessControl.deploy();
    })

    it("privileges", async () => {
        await expect(accessControl.deposit(user1.address)).to.be.revertedWith("operation forbidden");
        await expect(accessControl.withdraw(user1.address)).to.be.revertedWith("operation forbidden");
        await expect(accessControl.trade(user1.address)).to.be.revertedWith("operation forbidden");

        await expect(accessControl.connect(user1).grantPrivilege(user0.address, 0x16)).to.be.revertedWith("privilege is invalid");
        await expect(accessControl.connect(user1).revokePrivilege(user0.address, 0x16)).to.be.revertedWith("privilege is invalid");

        await accessControl.deposit(user0.address);
        await accessControl.withdraw(user0.address);
        await accessControl.trade(user0.address);

        await accessControl.connect(user1).grantPrivilege(user0.address, 0x1);
        expect(await accessControl.isGranted(user1.address, user0.address, 0x1)).to.be.true;
        await accessControl.deposit(user1.address);
        await expect(accessControl.withdraw(user1.address)).to.be.revertedWith("operation forbidden");
        await expect(accessControl.trade(user1.address)).to.be.revertedWith("operation forbidden");

        await accessControl.connect(user1).grantPrivilege(user0.address, 0x2);
        expect(await accessControl.isGranted(user1.address, user0.address, 0x2)).to.be.true;
        await accessControl.deposit(user1.address);
        await accessControl.withdraw(user1.address);
        await expect(accessControl.trade(user1.address)).to.be.revertedWith("operation forbidden");

        await accessControl.connect(user1).grantPrivilege(user0.address, 0x4);
        expect(await accessControl.isGranted(user1.address, user0.address, 0x4)).to.be.true;
        await accessControl.deposit(user1.address);
        await accessControl.withdraw(user1.address);
        await accessControl.trade(user1.address);

        await accessControl.connect(user1).revokePrivilege(user0.address, 0x7);
        await accessControl.deposit(user0.address);
        await accessControl.withdraw(user0.address);
        await accessControl.trade(user0.address);

        await accessControl.isGranted(user1.address, user0.address, 0x1);
        await accessControl.isGranted(user1.address, user0.address, 0x2);
        await accessControl.isGranted(user1.address, user0.address, 0x4);
        await accessControl.isGranted(user1.address, user0.address, 0x8);

        await accessControl.connect(user1).grantPrivilege(user0.address, 0x4);
        await expect(accessControl.connect(user1).grantPrivilege(user0.address, 0x4)).to.be.revertedWith("privilege is already granted");
        await expect(accessControl.connect(user1).revokePrivilege(user0.address, 0x1)).to.be.revertedWith("privilege is not grante");
    })

})