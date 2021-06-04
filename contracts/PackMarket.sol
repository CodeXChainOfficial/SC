// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "./Pack.sol";

contract PackMarket is Ownable, ReentrancyGuard {
  using SafeMath for uint256;

  Pack public packToken;
  address public protocolTreasury;

  event PackTokenChanged(address newPackTokenAddress);
  event TreasuryAddressChanged(address newTreasuryAddress);

  event NewListing(
    address indexed seller, 
    uint256 indexed tokenId, 
    bool active, 
    address currency, 
    uint256 price, 
    uint256 quantity
  );
  event NewSale(
    address indexed seller, 
    address indexed buyer, 
    uint256 indexed tokenId, 
    address currency, 
    uint256 price, 
    uint256 quantity
  );
  event ListingUpdate(
    address indexed seller, 
    uint256 indexed tokenId, 
    bool active, 
    address currency, 
    uint256 price, 
    uint256 quantity
  );

  uint256 public constant MAX_BPS = 10000; // 100%
  uint256 public protocolFeeBps = 500; // 5%
  uint256 public creatorFeeBps = 500; // 5%

  struct Listing {
    address owner;
    uint256 tokenId;
    bool active;

    address currency;
    uint256 price;
    uint256 quantity;
  }

  // owner => tokenId => Listing
  mapping(address => mapping(uint256 => Listing)) public listings;

  modifier eligibleToList(uint tokenId, uint _quantity, address _currency) {
    require(packToken.isApprovedForAll(msg.sender, address(this)), "Must approve market contract to manage tokens.");
    require(packToken.balanceOf(msg.sender, tokenId) >= _quantity, "Must own the amount of tokens being listed.");
    require(_quantity > 0, "Must list at least one token");
    _;
  }

  modifier onlySeller(uint tokenId) {
    require(listings[msg.sender][tokenId].owner != address(0), "Only the seller can modify the listing.");

    _;
  }

  constructor(address _packToken, address _treasuryAddress) {
    packToken = Pack(_packToken);
    protocolTreasury = _treasuryAddress;
  }

  /**
   * @notice Sets the token address of the ERC1155 Pack token contract associated with the market.
   *
   * @param _packToken The address of an ERC1155 token contract.
   */
  function setPackToken(address _packToken) external onlyOwner {
    packToken = Pack(_packToken);
    emit PackTokenChanged(_packToken);
  }

  /**
   * @notice Sets the protocol treasury address, in control of `protcolFees`
   *
   * @param _treasuryAddress The address of an ERC1155 token contract.
   */
  function setProtocolTreasury(address _treasuryAddress) external onlyOwner {
    protocolTreasury = _treasuryAddress;
    emit PackTokenChanged(_treasuryAddress);
  }

  /**
   * @notice Lets pack or reward token owner list a given amount of tokens for sale.
   *
   * @param tokenId The ERC1155 tokenId of the token being listed for sale.
   * @param currency The smart contract address of the desired ERC20 token accepted for sale.
   * @param price The price of each unit of token listed for sale.
   * @param quantity The number of ERC1155 tokens of id `tokenId` being listed for sale.
   */
  function sell(
    uint256 tokenId, 
    address currency, 
    uint256 price, 
    uint256 quantity
  ) external eligibleToList(tokenId, quantity, currency) {

    listings[msg.sender][tokenId] = Listing({
      owner: msg.sender,
      tokenId: tokenId,
      active: true,
      currency: currency,
      price: price,
      quantity: quantity
    });

    emit NewListing(msg.sender, tokenId, true, currency, price, quantity);
  }

  /**
   * @notice Lets a seller set an existing listing as active or inactive.
   *
   * @param tokenId The ERC1155 tokenId of the token being unlisted.
   * @param _active The new status of the listing -- either active or inactive.
   */
  function setListingStatus(uint256 tokenId, bool _active) external onlySeller(tokenId) {
    listings[msg.sender][tokenId].active = _active;

    emit ListingUpdate(
      msg.sender,
      tokenId,
      listings[msg.sender][tokenId].active, 
      listings[msg.sender][tokenId].currency, 
      listings[msg.sender][tokenId].price, 
      listings[msg.sender][tokenId].quantity
    );
  }

  /**
   * @notice Lets a seller change the price of a listing.
   * 
   * @param tokenId The ERC1155 tokenId associated with the listing.
   * @param _newPrice The new price for the listing.
   */
  function setListingPrice(uint256 tokenId, uint256 _newPrice) external onlySeller(tokenId) {
    listings[msg.sender][tokenId].price = _newPrice;
    
    emit ListingUpdate(
      msg.sender,
      tokenId,
      listings[msg.sender][tokenId].active, 
      listings[msg.sender][tokenId].currency, 
      listings[msg.sender][tokenId].price, 
      listings[msg.sender][tokenId].quantity
    );
  }

  /**
   * @notice Lets a seller change the currency they want to accept for the listing.
   * 
   * @param tokenId The ERC1155 tokenId associated with the listing.
   * @param _newCurrency The new currency for the listing. 
   */
  function setListingCurrency(uint256 tokenId, address _newCurrency) external onlySeller(tokenId) {
    listings[msg.sender][tokenId].currency = _newCurrency;

    emit ListingUpdate(
      msg.sender,
      tokenId,
      listings[msg.sender][tokenId].active, 
      listings[msg.sender][tokenId].currency, 
      listings[msg.sender][tokenId].price, 
      listings[msg.sender][tokenId].quantity
    );
  }

  /**
   * @notice Lets a seller change the quantity of token to be listed for sale.
   * 
   * @param tokenId The ERC1155 tokenId associated with the listing.
   * @param _newQuantity The new quantity of token to be listed. 
   */
  function setListingQuantity(uint256 tokenId, uint _newQuantity) external onlySeller(tokenId) {
    require(packToken.balanceOf(msg.sender, tokenId) >= _newQuantity, "Must own the amount of tokens being listed.");

    listings[msg.sender][tokenId].quantity = _newQuantity;

    emit ListingUpdate(
      msg.sender,
      tokenId,
      listings[msg.sender][tokenId].active, 
      listings[msg.sender][tokenId].currency, 
      listings[msg.sender][tokenId].price, 
      listings[msg.sender][tokenId].quantity
    );
  }

  /**
   * @notice Lets buyer buy a given amount of tokens listed for sale in the relevant listing.
   *
   * @param from The address of the listing's seller.
   * @param tokenId The ERC1155 tokenId associated with the listing.
   * @param quantity The quantity of tokens to buy from the relevant listing.
   */
  function buy(address from, uint256 tokenId, uint256 quantity) external payable nonReentrant {
    require(listings[from][tokenId].owner == from, "The listing does not exist.");
    require(quantity > 0, "must buy at least one token");
    require(quantity <= listings[from][tokenId].quantity, "attempting to buy more tokens than listed");

    Listing memory listing = listings[from][tokenId];
    (address creator,,,,) = packToken.tokens(tokenId);
    
    if(listing.currency == address(0)) {
      distributeEther(listing.owner, creator, listing.price, quantity);
    } else {
      distributeERC20(listing.owner, creator, listing.currency, listing.price, quantity);
    }

    packToken.safeTransferFrom(listing.owner, msg.sender, tokenId, quantity, "");
    listings[from][tokenId].quantity -= quantity;

    emit NewSale(from, msg.sender, tokenId, listing.currency, listing.price, quantity);
  }

  /**
   * @notice Distributes some share of the sale value (in ERC20 token) to the seller, creator and protocol.
   *
   * @param seller The seller associated with the listing.
   * @param creator The creator of the ERC1155 token on sale.
   * @param currency The ERC20 curreny accepted by the listing.
   * @param price The price per ERC1155 token of the listing.
   * @param quantity The quantity of ERC1155 tokens being purchased.  
   */
  function distributeERC20(address seller, address creator, address currency, uint price, uint quantity) internal {
    uint256 totalPrice = price.mul(quantity);
    uint256 protocolCut = totalPrice.mul(protocolFeeBps).div(MAX_BPS);
    uint256 creatorCut = seller == creator ? 0 : totalPrice.mul(creatorFeeBps).div(MAX_BPS);
    uint256 sellerCut = totalPrice - protocolCut - creatorCut;

    IERC20 priceToken = IERC20(currency);
    priceToken.approve(address(this), sellerCut + creatorCut);
    require(
      priceToken.allowance(msg.sender, address(this)) >= totalPrice, 
      "Not approved PackMarket to handle price amount."
    );

    require(priceToken.transferFrom(msg.sender, address(this), totalPrice), "ERC20 price transfer failed.");
    require(priceToken.transferFrom(address(this), seller, sellerCut), "ERC20 price transfer failed.");
    if (creatorCut > 0) {
      require(priceToken.transferFrom(address(this), creator, creatorCut), "ERC20 price transfer failed.");
    }
  }

  /**
   * @notice Distributes some share of the sale value (in Ether) to the seller, creator and protocol.
   *
   * @param seller The seller associated with the listing.
   * @param creator The creator of the ERC1155 token on sale.
   * @param price The price per ERC1155 token of the listing.
   * @param quantity The quantity of ERC1155 tokens being purchased.
   */
  function distributeEther(address seller, address creator, uint price, uint quantity) internal {
    uint256 totalPrice = price.mul(quantity);
    uint256 protocolCut = totalPrice.mul(protocolFeeBps).div(MAX_BPS);
    uint256 creatorCut = seller == creator ? 0 : totalPrice.mul(creatorFeeBps).div(MAX_BPS);
    uint256 sellerCut = totalPrice - protocolCut - creatorCut;

    require(msg.value >= totalPrice, "Must sent enough eth to buy the given amount.");

    (bool success,) = seller.call{value: sellerCut}("");
    require(success, "ETH transfer of seller cut failed.");
    if (creatorCut > 0) {
        (success,) = creator.call{value: creatorCut}("");
      require(success, "ETH transfer of creator cut failed.");
    }
  }

  function transferProtocolFees(address _to, address _currency, uint _amount) public {
    require(msg.sender == protocolTreasury, "Only the treasury contract can transfer protocol fees.");

    if(_currency == address(0)) {
      IERC20 feeToken = IERC20(_currency);
      require(feeToken.balanceOf(address(this)) >= _amount, "Not enough fees generated to withdraw the specified amount.");

      feeToken.approve(address(this), _amount);
      require(
        feeToken.transfer(_to, _amount),
        "ERC20 withdrawal of protocol fees failed."
      );
    } else {
      require(address(this).balance >= _amount, "Not enough fees generated to withdraw the specified amount.");

      (bool success,) = (_to).call{value: _amount}("");
      require(success, "ETH withdrawal of protocol fees failed.");
    }
  }
}