pragma solidity >= 0.5.0 < 0.7.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";

interface Erc20 {
    function approve(address, uint256) external returns (bool);
    function transfer(address, uint256) external returns (bool);
    function transferFrom(address, address, uint256) external returns (bool);
}

interface CErc20 {
    function mint(uint256) external returns (uint256);
    function borrow(uint256) external returns (uint256);
    function borrowRatePerBlock() external view returns (uint256);
    function borrowBalanceCurrent(address) external returns (uint256);
    function repayBorrow(uint256) external returns (uint256);
    function balanceOf(address) external view returns (uint256);
    function transfer(address, uint256) external returns (bool);
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

contract CFavelaCrowdFunding is Ownable {

  event DonationReceived(address sender, uint amount, uint totalBalance);
  event ETHInvested(address executor, uint amount);
  event DAIInvested(address executor, uint amount);
  event DonationAmountSet(uint amount);
  event DistributionAction(address[10] failedUsers);

  using SafeMath for uint;

  address _cdaiAddress = 0x6D7F0754FFeb405d23C51CE938289d4835bE3b14;
  address _daiAddress = 0x5592EC0cfb4dbc12D3aB100b257153436a1f0FEa;
  address KYBER_INTERFACE = 0xF77eC7Ed5f5B9a5aee4cfa6FFCaC6A4C315BaC76;
  address EtherAddress = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

  uint public totalETHDonation;

  uint public sessioncDAIBalance;
  uint public amountToDistribute;

  receive() external payable {
    totalETHDonation = totalETHDonation.add(msg.value);
    emit DonationReceived(msg.sender, msg.value, totalETHDonation);
  }

  function ethToDai(uint _amount) internal returns(uint _daiAmount){
    uint minRate;

    Erc20 token = Erc20(_daiAddress);
    Erc20 etherToken = Erc20(EtherAddress);
    KyberNetworkProxyInterface _kyberNetworkProxy = KyberNetworkProxyInterface(KYBER_INTERFACE);
    (, minRate) = _kyberNetworkProxy.getExpectedRate(token, etherToken, _amount);
    _daiAmount = _kyberNetworkProxy.swapEtherToToken.value(_amount)(token, minRate);

    require(_daiAmount > 0,"Kyber Swap ETH to DAI error");
    return _daiAmount;
  }

  // Invest ETH to given protocol
  function investETHtoCompound(uint amount) public onlyOwner returns(uint) {
      require(amount > 0, 'Amount Invalid');
      require(amount < address(this).balance, 'Contract Wallet doesnt have enough ETH balance');
      
      uint daiAmount = ethToDai(amount);
      
      Erc20 dai = Erc20(_daiAddress);
      CErc20 cDai = CErc20(_cdaiAddress);

      dai.approve(_cdaiAddress, daiAmount);
      uint error = cDai.mint(daiAmount);
      
      sessioncDAIBalance = cDai.balanceOf(address(this));

      require(error == 0, "CErc20.mint Error... Try Again");
      emit ETHInvested(msg.sender, amount);

      return error;
  }

  function investDAItoCompound(uint amount) public onlyOwner returns(uint) {
      require(amount > 0, "Amount Invalid");

      Erc20 dai = Erc20(_daiAddress);
      CErc20 cDai = CErc20(_cdaiAddress);

      dai.approve(_cdaiAddress, amount);
      uint error = cDai.mint(amount);
      
      sessioncDAIBalance = cDai.balanceOf(address(this));

      require(error == 0, "CErc20.mint Error... Try Again");
      emit DAIInvested(msg.sender, amount);

      return error;
  }

  function setDistributionAmount(uint favelaUsersLength) public onlyOwner returns (uint) {
      require(sessioncDAIBalance > 0,"Contract has no DAI or Investments");
      CErc20 cDai = CErc20(_cdaiAddress);
      
      delete amountToDistribute;
      uint contractCdaiBalance = cDai.balanceOf(address(this));
      amountToDistribute = contractCdaiBalance.div(favelaUsersLength);

      emit DonationAmountSet(amountToDistribute);

      return amountToDistribute;
  }

  function distributeCDAItoUsers(address[] memory favelaUsers) public onlyOwner {
      require(amountToDistribute > 0, "Amount To Distribute not Set");
      CErc20 cDai = CErc20(_cdaiAddress);
      for(uint i = 0; i < favelaUsers.length; i++) {
          cDai.transfer(favelaUsers[i], amountToDistribute);
      }
  }
}