const BigNumber = require('bignumber.js')

const CFavelaCrowdFunding = artifacts.require('CFavelaCrowdFunding')

contract('CFavelaCrownFunding', async (accounts) => {
    
    let CFavelaCrowdFundingContract;

    before(async () => {
        CFavelaCrowdFundingContract= await CFavelaCrowdFunding.new()
    })

    it('should allow to donate eth',  async () => {
        const amount = new BigNumber(0.5 ** Math.pow(10 , 18));
        const sendData = await CFavelaCrowdFundingContract.send(amount, {from: accounts[0]})
        console.log('send',sendData)
        console.log(await CFavelaCrowdFundingContract.totalETHDonation())
    })

    it('should allow to invest To COmpound', async ()=> {
        const amount = new BigNumber(0.4 ** Math.pow(10 , 18));
        const investData = await CFavelaCrowdFundingContract.investETHtoCompound(amount)
        console.log('invest', investData)
    })

    it('should allow to set Distribution Amount among Users', async () => {
        const length = 3
        const setDistributionData = await CFavelaCrowdFundingContract.setDistributionAmount(length)
        console.log('setDistributionData',setDistributionData)
    })

    it('should transfer to Users the equal amount', async( ) => {
        const address = ["0x98c1841E41E840d8B9f9F2987eb8Cf489E10Da36", "0x71CfA8c5aEb22052f95A38663396a6e21eE17BB7", "0x54917CBA8FC06f4E7f6bDc33b56d07d07B32663E"]
        const distributeCDAI = await CFavelaCrowdFundingContract.distributeCDAItoUsers(address);
        console.log('distributeCDAI',distributeCDAI)
    })
})