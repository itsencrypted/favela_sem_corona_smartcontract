pragma solidity >= 0.5.0 < 0.7.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";

interface Erc20 {
    function approve(address, uint256) external returns (bool);
    function transfer(address, uint256) external returns (bool);
    function transferFrom(address, address, uint256) external returns (bool);
}

interface LendingPoolAddressesProvider {
    function getLendingPool() external view returns (address);
    function getLendingPoolCore() external view returns (address payable);
}

interface LendingPoolCore {
    function getUserBorrowBalances(address _reserve, address _user) external view returns (uint256, uint256 compoundedBalance, uint256);
}

interface LendingPool {
    function repay(address _reserve, uint256 _amount, address payable _onBehalfOf) external payable;
    function deposit( address _reserve, uint256 _amount, uint16 _referralCode) external payable;
}

interface AToken {
    function approve(address, uint256) external returns (bool);
    function transfer(address, uint256) external returns (bool);
    function transferFrom(address, address, uint256) external returns (bool);
    function underlyingAssetAddress() external view returns (address);
    function balanceOf(address) external view returns(uint);
}

interface KyberNetworkProxyInterface {
    function maxGasPrice() external view returns(uint);
    function getUserCapInWei(address user) external view returns(uint);
    function getUserCapInTokenWei(address user, Erc20 token) external view returns(uint);
    function enabled() external view returns(bool);
    function info(bytes32 id) external view returns(uint);
    function getExpectedRate(Erc20 src, Erc20 dest, uint srcQty) external view returns (uint expectedRate, uint slippageRate);
    function swapEtherToToken(Erc20 token, uint minRate) external payable returns (uint);
    function swapTokenToEther(Erc20 token, uint tokenQty, uint minRate) external returns (uint);
}

contract AFavelaCrowdFunding is Ownable {

  event DonationReceived(address sender, uint amount, uint totalBalance);
  event ETHInvested(address executor, uint amount);
  event DAIInvested(address executor, uint amount);
  event DonationAmountSet(uint amount);
  event DistributionAction(address[10] failedUsers);

  using SafeMath for uint;

  address _daiAddress = 0xf80A32A835F79D7787E8a8ee5721D0fEaFd78108;
  address _aDaiAddress = 0xcB1Fe6F440c49E9290c3eb7f158534c2dC374201;
  address KYBER_INTERFACE = 0x818E6FECD516Ecc3849DAf6845e3EC868087B755;
  address EtherAddress = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
  address _lendingPoolProviderAddress = 0x1c8756FD2B28e9426CDBDcC7E3c4d64fa9A54728;

  uint public totalETHDonation;

  uint public sessionaDAIBalance;
  uint public amountToDistribute;

  receive() external payable {
    totalETHDonation = totalETHDonation.add(msg.value);
    emit DonationReceived(msg.sender, msg.value, totalETHDonation);
  }

  function ethToDai(uint _amount) internal returns(uint daiAmount){
    uint minRate;

    Erc20 token = Erc20(_daiAddress);
    Erc20 etherToken = Erc20(EtherAddress);
    KyberNetworkProxyInterface _kyberNetworkProxy = KyberNetworkProxyInterface(KYBER_INTERFACE);
    (, minRate) = _kyberNetworkProxy.getExpectedRate(token, etherToken, _amount);
    daiAmount = _kyberNetworkProxy.swapEtherToToken.value(_amount)(token, minRate);

    require(daiAmount > 0,"Kyber Swap ETH to DAI error");
    return daiAmount;
  }

  // Invest ETH to given protocol
  function investETHtoAave(uint amount) public onlyOwner {
      require(amount > 0, 'Amount Invalid');
      require(amount < address(this).balance, 'Contract Wallet doesnt have enough ETH balance');
      
      uint daiAmount = ethToDai(amount);
      
      Erc20 dai = Erc20(_daiAddress);
      AToken aDai = AToken(_aDaiAddress);

      LendingPoolAddressesProvider provider = LendingPoolAddressesProvider(_lendingPoolProviderAddress); // mainnet address, for other addresses: https://docs.aave.com/developers/developing-on-aave/deployed-contract-instances
      LendingPool lendingPool = LendingPool(provider.getLendingPool());

      dai.approve(provider.getLendingPoolCore(), daiAmount);
      lendingPool.deposit(_daiAddress, daiAmount, 0);
      
      sessionaDAIBalance = aDai.balanceOf(address(this));

      emit DAIInvested(msg.sender, daiAmount);
  }

  // Invest ETH to given protocol
  function investDAItoAAVE(uint amount) public onlyOwner {
      require(amount > 0, 'Amount Invalid');
            
      Erc20 dai = Erc20(_daiAddress);
      AToken aDai = AToken(_aDaiAddress);

      LendingPoolAddressesProvider provider = LendingPoolAddressesProvider(_lendingPoolProviderAddress); // mainnet address, for other addresses: https://docs.aave.com/developers/developing-on-aave/deployed-contract-instances
      LendingPool lendingPool = LendingPool(provider.getLendingPool());
      
      dai.approve(provider.getLendingPoolCore(), amount);
      lendingPool.deposit(_daiAddress, amount, 0);
      
      sessionaDAIBalance = aDai.balanceOf(address(this));
  }

  function setDistributionAmount(uint favelaUsersLength) public onlyOwner returns (uint) {
      require(sessionaDAIBalance > 0,"Contract has no DAI or Investments");
      AToken aDai = AToken(_aDaiAddress);
      
      delete amountToDistribute;
      uint contractaDaiBalance = aDai.balanceOf(address(this));
      amountToDistribute = contractaDaiBalance.div(favelaUsersLength);

      emit DonationAmountSet(amountToDistribute);

      return amountToDistribute;
  }

  function distributeCDAItoUsers(address[] memory _favelaUsers) public onlyOwner {
      require(amountToDistribute > 0, "Amount To Distribute not Set");
      AToken aDai = AToken(_aDaiAddress);

      for(uint i = 0; i < _favelaUsers.length; i++) {
          aDai.transfer(_favelaUsers[i], amountToDistribute);
      }
  }
}

