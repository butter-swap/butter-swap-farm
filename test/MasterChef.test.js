const { expectRevert, time } = require('@openzeppelin/test-helpers');
const ButterToken = artifacts.require('ButterToken');
const CreamToken = artifacts.require('CreamToken');
const MasterChef = artifacts.require('MasterChef');
const MockHRC20 = artifacts.require('libs/MockHRC20');

contract('MasterChef', ([alice, bob, carol, dev, minter]) => {
    beforeEach(async () => {
        this.butter = await ButterToken.new({ from: minter });
        this.cream = await CreamToken.new(this.butter.address, { from: minter });
        this.lp1 = await MockHRC20.new('LPToken', 'LP1', '1000000', { from: minter });
        this.lp2 = await MockHRC20.new('LPToken', 'LP2', '1000000', { from: minter });
        this.lp3 = await MockHRC20.new('LPToken', 'LP3', '1000000', { from: minter });
        this.chef = await MasterChef.new(this.butter.address, this.cream.address, dev, '1000', '100', { from: minter });
        await this.butter.transferOwnership(this.chef.address, { from: minter });
        await this.cream.transferOwnership(this.chef.address, { from: minter });

        await this.lp1.transfer(bob, '2000', { from: minter });
        await this.lp2.transfer(bob, '2000', { from: minter });
        await this.lp3.transfer(bob, '2000', { from: minter });

        await this.lp1.transfer(alice, '2000', { from: minter });
        await this.lp2.transfer(alice, '2000', { from: minter });
        await this.lp3.transfer(alice, '2000', { from: minter });
    });

    it('add same lp token should fail', async () => {
        await this.chef.add('2000', this.lp1.address, true, { from: minter });
        await expectRevert(this.chef.add('100', this.lp1.address, true, { from: minter }), 'add: lp token already exists');
        await this.chef.add('1000', this.lp2.address, true, { from: minter });
        await this.chef.add('500', this.lp3.address, true, { from: minter });
        await expectRevert(this.chef.add('100', this.lp2.address, true, { from: minter }), 'add: lp token already exists');

        await this.chef.set(3, '100', true, { from: minter })
        await expectRevert(this.chef.set(4, '100', true, { from: minter }), 'pool does not exist');

        assert.equal((await this.chef.poolLength()).toString(), "4");
    });

    it('real case', async () => {
        this.lp4 = await MockHRC20.new('LPToken', 'LP1', '1000000', { from: minter });
        this.lp5 = await MockHRC20.new('LPToken', 'LP2', '1000000', { from: minter });
        this.lp6 = await MockHRC20.new('LPToken', 'LP3', '1000000', { from: minter });
        this.lp7 = await MockHRC20.new('LPToken', 'LP1', '1000000', { from: minter });
        this.lp8 = await MockHRC20.new('LPToken', 'LP2', '1000000', { from: minter });
        this.lp9 = await MockHRC20.new('LPToken', 'LP3', '1000000', { from: minter });
        await this.chef.add('2000', this.lp1.address, true, { from: minter });
        await this.chef.add('1000', this.lp2.address, true, { from: minter });
        await this.chef.add('500', this.lp3.address, true, { from: minter });
        await this.chef.add('500', this.lp4.address, true, { from: minter });
        await this.chef.add('500', this.lp5.address, true, { from: minter });
        await this.chef.add('500', this.lp6.address, true, { from: minter });
        await this.chef.add('500', this.lp7.address, true, { from: minter });
        await this.chef.add('100', this.lp8.address, true, { from: minter });
        await this.chef.add('100', this.lp9.address, true, { from: minter });
        assert.equal((await this.chef.poolLength()).toString(), "10");

        // await time.advanceBlockTo('170');
        block = await web3.eth.getBlock("latest")
        if (block.number < 100) {
            await time.advanceBlockTo('120');
        }
        
        await time.advanceBlock();
        await this.lp1.approve(this.chef.address, '1000', { from: alice });
        assert.equal((await this.butter.balanceOf(alice)).toString(), '0');
        await this.chef.deposit(1, '20', { from: alice });
        await this.chef.withdraw(1, '20', { from: alice });
        assert.equal((await this.butter.balanceOf(alice)).toString(), '263');

        await this.butter.approve(this.chef.address, '1000', { from: alice });
        await this.chef.enterStaking('20', { from: alice });
        await this.chef.enterStaking('0', { from: alice });
        await this.chef.enterStaking('0', { from: alice });
        await this.chef.enterStaking('0', { from: alice });
        assert.equal((await this.butter.balanceOf(alice)).toString(), '993');
        // assert.equal((await this.chef.getPoolPoint(0, { from: minter })).toString(), '1900');
    });

    it('deposit/withdraw', async () => {
        await this.chef.add('1000', this.lp1.address, true, { from: minter });
        await this.chef.add('1000', this.lp2.address, true, { from: minter });
        await this.chef.add('1000', this.lp3.address, true, { from: minter });

        await this.lp1.approve(this.chef.address, '100', { from: alice });
        await this.chef.deposit(1, '20', { from: alice });
        await this.chef.deposit(1, '0', { from: alice });
        await this.chef.deposit(1, '40', { from: alice });
        await this.chef.deposit(1, '0', { from: alice });
        assert.equal((await this.lp1.balanceOf(alice)).toString(), '1940');
        await this.chef.withdraw(1, '10', { from: alice });
        assert.equal((await this.lp1.balanceOf(alice)).toString(), '1950');
        assert.equal((await this.butter.balanceOf(alice)).toString(), '999');
        assert.equal((await this.butter.balanceOf(dev)).toString(), '100');

        await this.lp1.approve(this.chef.address, '100', { from: bob });
        assert.equal((await this.lp1.balanceOf(bob)).toString(), '2000');
        await this.chef.deposit(1, '50', { from: bob });
        assert.equal((await this.lp1.balanceOf(bob)).toString(), '1950');
        await this.chef.deposit(1, '0', { from: bob });
        assert.equal((await this.butter.balanceOf(bob)).toString(), '125');
        await this.chef.emergencyWithdraw(1, { from: bob });
        assert.equal((await this.lp1.balanceOf(bob)).toString(), '2000');
    });

    it('staking/unstaking', async () => {
        await this.chef.add('1000', this.lp1.address, true, { from: minter });
        await this.chef.add('1000', this.lp2.address, true, { from: minter });
        await this.chef.add('1000', this.lp3.address, true, { from: minter });

        await this.lp1.approve(this.chef.address, '10', { from: alice });
        await this.chef.deposit(1, '2', { from: alice }); //0
        await this.chef.withdraw(1, '2', { from: alice }); //1

        await this.butter.approve(this.chef.address, '250', { from: alice });
        await this.chef.enterStaking('240', { from: alice }); //3
        assert.equal((await this.cream.balanceOf(alice)).toString(), '240');
        assert.equal((await this.butter.balanceOf(alice)).toString(), '10');
        await this.chef.enterStaking('10', { from: alice }); //4
        assert.equal((await this.cream.balanceOf(alice)).toString(), '250');
        assert.equal((await this.butter.balanceOf(alice)).toString(), '249');
        await this.chef.leaveStaking('250', { from: alice });
        assert.equal((await this.cream.balanceOf(alice)).toString(), '0');
        assert.equal((await this.butter.balanceOf(alice)).toString(), '749');

    });

    it('update multiplier', async () => {
        await this.chef.add('1000', this.lp1.address, true, { from: minter });
        await this.chef.add('1000', this.lp2.address, true, { from: minter });
        await this.chef.add('1000', this.lp3.address, true, { from: minter });

        await this.lp1.approve(this.chef.address, '100', { from: alice });
        await this.lp1.approve(this.chef.address, '100', { from: bob });
        await this.chef.deposit(1, '100', { from: alice });
        await this.chef.deposit(1, '100', { from: bob });
        await this.chef.deposit(1, '0', { from: alice });
        await this.chef.deposit(1, '0', { from: bob });

        await this.butter.approve(this.chef.address, '100', { from: alice });
        await this.butter.approve(this.chef.address, '100', { from: bob });
        await this.chef.enterStaking('50', { from: alice });
        await this.chef.enterStaking('100', { from: bob });

        await this.chef.updateMultiplier('0', { from: minter });

        await this.chef.enterStaking('0', { from: alice });
        await this.chef.enterStaking('0', { from: bob });
        await this.chef.deposit(1, '0', { from: alice });
        await this.chef.deposit(1, '0', { from: bob });

        assert.equal((await this.butter.balanceOf(alice)).toString(), '700');
        assert.equal((await this.butter.balanceOf(bob)).toString(), '150');
        
        await time.advanceBlock();

        await this.chef.enterStaking('0', { from: alice });
        await this.chef.enterStaking('0', { from: bob });
        await this.chef.deposit(1, '0', { from: alice });
        await this.chef.deposit(1, '0', { from: bob });

        assert.equal((await this.butter.balanceOf(alice)).toString(), '700');
        assert.equal((await this.butter.balanceOf(bob)).toString(), '150');

        await this.chef.leaveStaking('50', { from: alice });
        await this.chef.leaveStaking('100', { from: bob });
        await this.chef.withdraw(1, '100', { from: alice });
        await this.chef.withdraw(1, '100', { from: bob });

    });

    it('should allow dev and only dev to update dev', async () => {
        assert.equal((await this.chef.devaddr()).valueOf(), dev);
        await expectRevert(this.chef.dev(bob, { from: bob }), 'dev: wut?');
        await this.chef.dev(bob, { from: dev });
        assert.equal((await this.chef.devaddr()).valueOf(), bob);
        await this.chef.dev(alice, { from: bob });
        assert.equal((await this.chef.devaddr()).valueOf(), alice);
    });
});
