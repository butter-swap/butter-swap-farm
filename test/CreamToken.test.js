const { expectRevert, time } = require('@openzeppelin/test-helpers');
const { assert } = require('chai');
const ButterToken = artifacts.require('ButterToken');
const CreamToken = artifacts.require('CreamToken');

contract('CreamToken', ([alice, bob, carol, dev, minter]) => {
    beforeEach(async () => {
        this.butter = await ButterToken.new({ from: minter });
        this.cream = await CreamToken.new(this.butter.address, { from: minter });
    });

    it('mint', async () => {
        await this.cream.mint(alice, 1000, { from: minter });
        assert.equal((await this.cream.balanceOf(alice)).toString(), '1000');
    });

    it('burn', async () => {
        // await advanceBlockTo('650');
        await time.advanceBlock();
        await this.cream.mint(alice, 1000, { from: minter });
        await this.cream.mint(bob, 1000, { from: minter });
        assert.equal((await this.cream.totalSupply()).toString(), '2000');
        await this.cream.burn(alice, 200, { from: minter });

        assert.equal((await this.cream.balanceOf(alice)).toString(), '800');
        assert.equal((await this.cream.totalSupply()).toString(), '1800');
    });

    it('safeButterTransfer', async () => {
        assert.equal(
            (await this.butter.balanceOf(this.cream.address)).toString(),
            '0'
        );
        await this.butter.mint(this.cream.address, 1000, { from: minter });
        await this.cream.safeButterTransfer(bob, 200, { from: minter });
        assert.equal((await this.butter.balanceOf(bob)).toString(), '200');
        assert.equal(
            (await this.butter.balanceOf(this.cream.address)).toString(),
            '800'
        );
        await this.cream.safeButterTransfer(bob, 2000, { from: minter });
        assert.equal((await this.butter.balanceOf(bob)).toString(), '1000');
    });
});
