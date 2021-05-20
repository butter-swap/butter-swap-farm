const { assert } = require("chai");

const ButterToken = artifacts.require('ButterToken');

contract('ButterToken', ([alice, bob, carol, dev, minter]) => {
    beforeEach(async () => {
        this.butter = await ButterToken.new({ from: minter });
    });


    it('mint', async () => {
        await this.butter.mint(alice, 1000, { from: minter });
        assert.equal((await this.butter.balanceOf(alice)).toString(), '1000');
    })
});
