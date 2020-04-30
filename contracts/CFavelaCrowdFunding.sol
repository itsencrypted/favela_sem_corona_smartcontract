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
    function approve(address, uint256) external returns (bool);
}

interface CEth {
    function mint() external payable;
    function borrow(uint256) external returns (uint256);
    function repayBorrow() external payable;
    function borrowBalanceCurrent(address) external returns (uint256);
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

interface Comptroller {
    function markets(address) external returns (bool, uint256);

    function enterMarkets(address[] calldata)
        external
        returns (uint256[] memory);

    function getAccountLiquidity(address)
        external
        view
        returns (uint256, uint256, uint256);
}

contract CFavelaCrowdFunding is Ownable {

  event DonationReceived(address sender, uint amount, uint totalBalance);
  event ETHInvested(address executor, uint amount);
  event DAIInvested(address executor, uint amount);
  event DonationAmountSet(uint amount);
  event DistributionAction(address[10] failedUsers);

  using SafeMath for uint;

  address _cdaiAddress = 0xe7bc397DBd069fC7d0109C0636d06888bb50668c;
  address _daiAddress = 0x4F96Fe3b7A6Cf9725f59d353F723c1bDb64CA6Aa;
  address KYBER_INTERFACE = 0x692f391bCc85cefCe8C237C01e1f636BbD70EA4D;
  address EtherAddress = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
  address cethAddress = 0xf92FbE0D3C0dcDAE407923b2Ac17eC223b1084E4;
  address comptrollerAddress = 0x1f5D7F3CaAC149fE41b8bd62A3673FE6eC0AB73b;

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
  function investETHtoCompound(uint ethForCollateral) public onlyOwner {
      require(ethForCollateral > 0, 'Amount Invalid');
      require(ethForCollateral < address(this).balance, 'Contract Wallet doesnt have enough ETH balance');
      
      //uint daiAmount = ethToDai(amount);
      
      CEth cEth = CEth(cethAddress);
      //Erc20 dai = Erc20(_daiAddress);
      
      cEth.mint.value(ethForCollateral)();
      
      emit ETHInvested(msg.sender, ethForCollateral);
  }
  
  function borrowCDAI(uint daiAmount) public onlyOwner {
      address[] memory cTokens = new address[](1);
      cTokens[0] = _cdaiAddress;
      
      
      CErc20 cDai = CErc20(_cdaiAddress);
      Comptroller comptroller = Comptroller(comptrollerAddress);
      uint256[] memory errors = comptroller.enterMarkets(cTokens);

      if (errors[0] != 0) {
            revert("Comptroller.enterMarkets failed.");
      }
      
      uint success = cDai.borrow(daiAmount);
      require(success == 0, "Borrow failed");
      
      Erc20 dai = Erc20(_daiAddress);
      dai.approve(_cdaiAddress, daiAmount);
      
      uint error = cDai.mint(daiAmount);
      sessioncDAIBalance = cDai.balanceOf(address(this));
      
      require(error == 0, "CErc20.mint Error... Try Again");
      emit DAIInvested(msg.sender, daiAmount);
  }

  function myEthRepayBorrow(uint256 amount)
        public
        returns (bool)
    {
        CErc20 cDai = CErc20(_cdaiAddress);

        cDai.approve(_cdaiAddress,amount);
        cDai.repayBorrow(amount);
        return true;
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