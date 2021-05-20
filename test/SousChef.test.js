const { expectRevert, time } = require('@openzeppelin/test-helpers');
const { assert } = require('chai');
const ButterToken = artifacts.require('ButterToken');
const CreamToken = artifacts.require('CreamToken');
const SousChef = artifacts.require('SousChef');
const MasterChef = artifacts.require('MasterChef');
const MockHRC20 = artifacts.require('libs/MockHRC20');

contract('SousChef', ([alice, bob, carol, dev, minter]) => {
    beforeEach(async () => {
        this.butter = await ButterToken.new({ from: minter });
        this.cream = await CreamToken.new(this.butter.address, { from: minter });
        this.rt1 = await MockHRC20.new('Reward Token1', 'RT1', '1000000', { from: minter });
        this.chef = await SousChef.new(this.cream.address, this.rt1.address, '40', '300', '10000', {
            from: minter
        });
        this.masterChef = await MasterChef.new(this.butter.address, this.cream.address, dev, '40', '100', {
            from: minter
        })

        // test ONLY
        await this.butter.mint(minter, '10000', { from: minter });
        await this.cream.mint(minter, '100000', { from: minter });
        this.rt1.transfer(this.chef.address, '100000', { from: minter })

        await this.butter.transferOwnership(this.masterChef.address, { from: minter });
        await this.cream.transferOwnership(this.masterChef.address, { from: minter });
    });

    it('sous chef now', async () => {
        await this.cream.transfer(bob, '1000', { from: minter });
        await this.cream.transfer(carol, '1000', { from: minter });
        await this.cream.transfer(alice, '1000', { from: minter });
        assert.equal((await this.cream.balanceOf(bob)).toString(), '1000');

        await this.cream.approve(this.chef.address, '1000', { from: bob });
        await this.cream.approve(this.chef.address, '1000', { from: alice });
        await this.cream.approve(this.chef.address, '1000', { from: carol });

        block = await web3.eth.getBlock("latest")
        if (block.number < 300) {
            await time.advanceBlockTo('320');
        }

        await this.chef.deposit('10', { from: bob });
        assert.equal(
            (await this.cream.balanceOf(this.chef.address)).toString(),
            '10'
        );

        await this.chef.deposit('30', { from: alice });
        assert.equal(
            (await this.cream.balanceOf(this.chef.address)).toString(),
            '40'
        );
        assert.equal(
            (await this.chef.pendingReward(bob, { from: bob })).toString(),
            '40'
        );

        await time.advanceBlock();
        assert.equal(
            (await this.chef.pendingReward(bob, { from: bob })).toString(),
            '50'
        );
        assert.equal(
            (await this.chef.pendingReward(alice, { from: alice })).toString(),
            '30'
        );

        await this.chef.deposit('40', { from: carol });
        assert.equal(
            (await this.cream.balanceOf(this.chef.address)).toString(),
            '80'
        ); // ==> reward bob 50 + 10, alice 30 + 30

        await time.advanceBlock();
        // stake bob 10, alice 30, carol 40
        assert.equal(
            (await this.chef.pendingReward(bob, { from: bob })).toString(),
            '65'
        );
        assert.equal(
            (await this.chef.pendingReward(alice, { from: alice })).toString(),
            '75'
        );
        assert.equal(
            (await this.chef.pendingReward(carol, { from: carol })).toString(),
            '20'
        );
        await this.chef.deposit('20', { from: alice }); // stake bob 10, alice 50, carol 40
        // pending reward bob 65 + 5, alice 0, carol 20 + 20
        assert.equal(
            (await this.rt1.balanceOf(alice)).toString(),
            '90'
        )

        await this.chef.deposit('30', { from: bob }); // stake bob 40, alice 50, carol 40
        // pending reward bob 0, alice 20, carol 40 + 16

        assert.equal(
            (await this.rt1.balanceOf(bob)).toString(),
            '74'
        );
        assert.equal(
            (await this.chef.pendingReward(alice, { from: alice })).toString(),
            '20'
        );

        await time.advanceBlock();
        assert.equal(
            (await this.chef.pendingReward(bob, { from: bob })).toString(),
            '12'
        ); // 4/13*40
        assert.equal(
            (await this.chef.pendingReward(alice, { from: alice })).toString(),
            '35'
        ); // 20 + 5/13*40
        // carol 56 + 4/13*40 = 68

        await time.advanceBlock();
        await time.advanceBlock();
        assert.equal(
            (await this.chef.pendingReward(bob, { from: bob })).toString(),
            '36'
        ); // 4/13*40 * 3
        assert.equal(
            (await this.chef.pendingReward(alice, { from: alice })).toString(),
            '66'
        ); // 20 + 5/13*40 * 3

        await this.chef.withdraw('20', { from: alice }); // stake bob 40, alice 30, carol 40
        assert.equal(
            (await this.rt1.balanceOf(alice)).toString(),
            '171'
        );  // 20 + 5/13*40 * [4] = 81  +  90,   reward debet = 8630769230769*30 / 1e12
        // alice  0
        // bob    4/13*40 * [4]
        // carol  56 + 4/13*40 * [4]
        // console.log('==========> pool info: ', (await this.chef.poolInfo()).accRewardPerShare.toString())

        await this.chef.withdraw('30', { from: bob }); // stake  bob 10, alice 30, carol 40
        assert.equal(
            (await this.rt1.balanceOf(bob)).toString(),
            '137'
        );  // 4/13*40 * [4] + 4/11*40 + 74
        // alice  3/11*40
        // bob    0
        // carol  56 + 4/13*40 * [4] + 4/11*40

        // console.log('==========> pool info: ', (await this.chef.poolInfo()).accRewardPerShare.toString()) // 8630769230769 + 1/110*40*1e12

        await time.advanceBlock();
        assert.equal(
            (await this.chef.pendingReward(bob, { from: bob })).toString(),
            '5'
        );  // 1/8*40
        assert.equal(
            (await this.chef.pendingReward(alice, { from: alice })).toString(),
            '26'
        );  // annoying float!!!  // (8630769230769 + 1/110*40*1e12 + 1/80*40*1e12) * 30 / 1e12
        assert.equal(
            (await this.chef.pendingReward(carol, { from: carol })).toString(),
            '139'
        );  // carol  56 + 4/13*40 * [4] + 4/11*40 + 4/8*40
        assert.equal(
            (await this.cream.balanceOf(this.chef.address)).toString(),
            '80'
        );

        await this.chef.stopReward({ from: minter });
        assert.equal(
            (await this.chef.pendingReward(bob, { from: bob })).toString(),
            '10'
        );
        assert.equal(
            (await this.chef.pendingReward(alice, { from: alice })).toString(),
            '41'
        );
        assert.equal(
            (await this.chef.pendingReward(carol, { from: alice })).toString(),
            '159'
        );

        await time.advanceBlock();
        await time.advanceBlock();
        assert.equal(
            (await this.chef.pendingReward(bob, { from: bob })).toString(),
            '10'
        );
        assert.equal(
            (await this.chef.pendingReward(alice, { from: alice })).toString(),
            '41'
        );
        assert.equal(
            (await this.chef.pendingReward(carol, { from: alice })).toString(),
            '159'
        );

        await this.chef.withdraw('10', { from: bob });
        await this.chef.withdraw('30', { from: alice });
        await expectRevert(this.chef.withdraw('50', { from: carol }), 'withdraw: not enough');

        await this.chef.deposit('30', { from: carol });
        await time.advanceBlock();
        await time.advanceBlock();

        await this.chef.withdraw('70', { from: carol });

        assert.equal(
            (await this.rt1.balanceOf(bob, { from: bob })).toString(),
            '147'
        );  // 137 + 10
        assert.equal(
            (await this.rt1.balanceOf(alice, { from: alice })).toString(),
            '212'
        );  // 171 + 41
        assert.equal(
            (await this.rt1.balanceOf(carol, { from: alice })).toString(),
            '159'
        );

        assert.equal(
            (await this.cream.balanceOf(bob, { from: bob })).toString(),
            '1000'
        );
        assert.equal(
            (await this.cream.balanceOf(alice, { from: alice })).toString(),
            '1000'
        );
        assert.equal(
            (await this.cream.balanceOf(carol, { from: alice })).toString(),
            '1000'
        );
    });

    it('stake butter for cream then deposit cream for other token', async () => {
        await this.butter.transfer(alice, '1000', { from: minter });
        await this.butter.transfer(bob, '1000', { from: minter });
        await this.butter.approve(this.masterChef.address, '1000', { from: alice });
        await this.butter.approve(this.masterChef.address, '1000', { from: bob });

        await this.masterChef.enterStaking('500', { from: alice });
        await this.masterChef.enterStaking('500', { from: bob });
        assert.equal((await this.cream.balanceOf(alice)).toString(), '500');
        assert.equal((await this.cream.balanceOf(bob)).toString(), '500');

        await this.cream.approve(this.chef.address, '100', { from: alice });
        await this.cream.approve(this.chef.address, '100', { from: bob });
        await this.chef.deposit('10', { from: alice });
        await this.chef.deposit('30', { from: bob });


        await time.advanceBlock();
        await time.advanceBlock();

        assert.equal(
            (await this.cream.balanceOf(this.chef.address)).toString(),
            '40'
        );
        assert.equal(
            (await this.chef.pendingReward(alice, { from: alice })).toString(),
            '60'
        );

        await this.chef.withdraw('10', { from: alice} );
        assert.equal(
            (await this.rt1.balanceOf(alice)).toString(),
            '70'
        );

        await this.chef.withdraw('30', { from: bob} );
        assert.equal(
            (await this.rt1.balanceOf(bob)).toString(),
            '129'
        );
        // 90 + (40 * 1e12 / 30) * 30 / 1e12 = 90 + 39 of course float cutting tail!!!
    });

    it('emergencyWithdraw', async () => {
        await this.cream.transfer(alice, '1000', { from: minter });
        assert.equal((await this.cream.balanceOf(alice)).toString(), '1000');

        await this.cream.approve(this.chef.address, '1000', { from: alice });
        await this.chef.deposit('10', { from: alice });
        assert.equal((await this.cream.balanceOf(alice)).toString(), '990');
        await this.chef.emergencyWithdraw({ from: alice });
        assert.equal((await this.cream.balanceOf(alice)).toString(), '1000');
        assert.equal(
            (await this.chef.pendingReward(alice, { from: alice })).toString(),
            '0'
        );
    });
});
