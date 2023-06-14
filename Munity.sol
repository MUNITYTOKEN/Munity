pragma solidity ^0.8.0;

import "./IERC20.sol";
import "./SafeMath.sol";
import "./IUniswapV2Router02.sol";
import "./IUniswapV2Factory.sol";

contract Munity is IERC20 {
    using SafeMath for uint256;

    string private constant _name = "Munity";
    string private constant _symbol = "MUN";
    uint8 private constant _decimals = 9;
    uint256 private constant _totalSupply = 1000000 * (10**9); // 1,000,000 tokens with 9 decimal places

    mapping(address => uint256) private _balances;
    mapping(address => mapping(address => uint256)) private _allowances;
    bool private _ownershipRenounced;
    address public _owner;
    address public _taxMarketingWallet(0x9483706195bdd8Ee425ca6Eb04109d4c78346241); // Marketing Wallet
    address public _taxLPWallet(0xDd9C9012A78E9D088FD8A4E1d309D4B9D31cfF60); // Tax lp wallet
    address public _taxFundWallet = (0x3616b5A9a0E3f1b38c7eDBD7A9ACd18352a33958); // REFund wallet adress
    address public _deadWallet = address(0x000000000000000000000000000000000000dEaD); // Dead wallet address

    uint256 public _taxPercentage = 3;
    uint256 private constant MAX = ~uint256(0);
    uint256 private constant _tTotal = (MAX - (MAX % _totalSupply));
    uint256 private _rTotal = (MAX - (MAX % _totalSupply));

    IUniswapV2Router02 private _uniswapRouter;
    address private _uniswapPair;

    bool private _uniswapEnabled;
    uint256 private _maxTxPercentage = 1; 
    uint256 private _maxOwnerWalletPercent = 100; 
    uint256 private _maxDeadWalletPercent = 100; 
    uint256 private _maxNonOwnerWalletPercent = 3;
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
    event SwapAndLiquify(uint256 tokensSwapped, uint256 ethReceived, uint256 tokensIntoLiquidity);
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    constructor(address taxMarketingWallet, address taxLPWallet, address taxFundWallet) {
        _owner = msg.sender;
        _taxMarketingWallet = taxMarketingWallet(0x9483706195bdd8Ee425ca6Eb04109d4c78346241);
        _taxLPWallet = taxLPWallet(0xDd9C9012A78E9D088FD8A4E1d309D4B9D31cfF60);
        _taxFundWallet = taxFundWallet(0x3616b5A9a0E3f1b38c7eDBD7A9ACd18352a33958);

        _balances[_owner] = _tTotal;
        emit Transfer(address(0), _owner, _tTotal);

        IUniswapV2Router02 uniswapRouter = IUniswapV2Router02(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D);
        _uniswapRouter = uniswapRouter;
        _uniswapPair = IUniswapV2Factory(uniswapRouter.factory()).createPair(address(this), uniswapRouter.WETH());
    }

    function name() external pure override returns (string memory) {
        return _name;
    }

    function symbol() external pure override returns (string memory) {
        return _symbol;
    }

    function decimals() external pure override returns (uint8) {
        return _decimals;
    }

    function totalSupply() external pure override returns (uint256) {
        return _totalSupply;
    }

    function balanceOf(address account) external view override returns (uint256) {
        return _balances[account];
    }

    function transfer(address recipient, uint256 amount) external override returns (bool) {
_transfer(msg.sender, recipient, amount);
return true;
}
function allowance(address owner, address spender) external view override returns (uint256) {
    return _allowances[owner][spender];
}

function approve(address spender, uint256 amount) external override returns (bool) {
    _approve(msg.sender, spender, amount);
    return true;
}

function transferFrom(address sender, address recipient, uint256 amount) external override returns (bool) {
    _transfer(sender, recipient, amount);
    _approve(sender, msg.sender, _allowances[sender][msg.sender].sub(amount, "ERC20: transfer amount exceeds allowance"));
    return true;
}

function increaseAllowance(address spender, uint256 addedValue) public returns (bool) {
    _approve(msg.sender, spender, _allowances[msg.sender][spender].add(addedValue));
    return true;
}

function decreaseAllowance(address spender, uint256 subtractedValue) public returns (bool) {
    _approve(msg.sender, spender, _allowances[msg.sender][spender].sub(subtractedValue, "ERC20: decreased allowance below zero"));
    return true;
}

function isExcludedFromReward(address account) external view returns (bool) {
    return (_balances[account] <= _rTotal.div(_totalSupply));
}

function totalFees() external view returns (uint256) {
    return _rTotal.sub(_tTotal);
}

function enableUniswap() external onlyOwner {
    require(!_uniswapEnabled, "Uniswap already enabled");
    _uniswapEnabled = true;
    _uniswapStartTime = block.timestamp;
}

function swapAndLiquify() external {
    require(_uniswapEnabled, "Uniswap not yet enabled");
    require(block.timestamp >= _uniswapStartTime.add(_numSecondsDelay), "Liquify operation not yet available");
    uint256 contractTokenBalance = balanceOf(address(this));
    bool overMinTokenBalance = contractTokenBalance >= _numTokensSellToAddToLiquidity;
    if (overMinTokenBalance && msg.sender != _uniswapPair) {
        swapTokensForEth(contractTokenBalance);
        uint256 ethBalance = address(this).balance;
        if (ethBalance > 0) {
            addLiquidity(contractTokenBalance, ethBalance);
            emit SwapAndLiquify(contractTokenBalance, ethBalance, contractTokenBalance);
        }
    }
}

function excludeFromReward(address account) external onlyOwner {
    require(!_isExcluded[account], "Account is already excluded");
    if (_balances[account] > 0) {
        _rOwned[account] = tokenFromReflection(_rOwned[account]);
    }
    _isExcluded[account] = true;
    _excluded.push(account);
}

function includeInReward(address account) external onlyOwner {
    require(_isExcluded[account], "Account is already included");
    for (uint256 i = 0; i < _excluded.length; i++) {
        if (_excluded[i] == account) {
            _excluded[i] = _excluded[_excluded.length - 1];
            _rOwned[account] = reflectionFromToken(_balances[account]);
            _isExcluded[account] = false;
            _excluded.pop();
            break;
        }
    }
}

function setTaxPercentage(uint256 taxPercentage) external onlyOwner {
    require(taxPercentage <= 10, "Tax percentage exceeds maximum");
    _taxPercentage= taxPercentage;
}
  function setTaxMarketingWallet(address taxMarketingWallet) external onlyOwner {
    require(taxMarketingWallet != address(0), "Invalid wallet address");
    _taxMarketingWallet = taxMarketingWallet;
}

function setTaxLPWallet(address taxLPWallet) external onlyOwner {
    require(taxLPWallet != address(0), "Invalid wallet address");
    _taxLPWallet = taxLPWallet;
}

function setTaxFundWallet(address taxFundWallet) external onlyOwner {
    require(taxFundWallet != address(0), "Invalid wallet address");
    _taxFundWallet = taxFundWallet;
}

  function setMaxTxAmount(uint256 maxTxPercentage) external onlyOwner {
    require(maxTxPercentage <= 100, "Max transaction percentage exceeds 100");
    _maxTxPercentage = maxTxPercentage;
    _maxTxAmount = _totalSupply.mul(maxTxPercentage).div(100);
}

function _approve(address owner, address spender, uint256 amount) private {
    require(owner != address(0), "ERC20: approve from the zero address");
    require(spender != address(0), "ERC20: approve to the zero address");

function _transfer(address sender, address recipient, uint256 amount) private {
    require(sender != address(0), "ERC20: transfer from the zero address");
    require(recipient != address(0), "ERC20: transfer to the zero address");
    require(amount > 0, "Transfer amount must be greater than zero");

    // Check if the transfer involves the owner account
    if (sender == _owner || recipient == _owner) {
        // No restrictions on transfer for the owner account until the contract is renounced
        _balances[sender] = _balances[sender].sub(amount);
        _balances[recipient] = _balances[recipient].add(amount);
    } else {
        // Calculate the maximum transfer amount as 1% of the total supply
        uint256 maxTransferAmount = totalSupply().div(100);

        // Check if the transfer amount exceeds the maximum limit
        require(amount <= maxTransferAmount, "Transfer amount exceeds the maximum limit");

        // Deduct the transfer amount from the sender's balance
        _balances[sender] = _balances[sender].sub(amount);
        // Add the transfer amount to the recipient's balance
        _balances[recipient] = _balances[recipient].add(amount);
    }

    emit Transfer(sender, recipient, amount);
}

    emit Approval(owner, spender, amount);
}

function _transfer(address sender, address recipient, uint256 amount) private {
    require(sender != address(0), "ERC20: transfer from the zero address");
    require(recipient != address(0), "ERC20: transfer to the zero address");
    require(amount > 0, "Transfer amount must be greater than zero");
    if (recipient != owner() && recipient != deadWallet) {
        require(amount <= _maxNonOwnerWalletPercent.mul(_totalSupply).div(100), "Wallet amount exceeds the maximum limit");
    }

    if (sender == _owner || recipient == _owner) {
        // No restrictions on transfer for the owner account until the contract is renounced
        _balances[sender] = _balances[sender].sub(amount);
        _balances[recipient] = _balances[recipient].add(amount);
    } else {
        // Calculate the maximum transfer amount as 1% of the total supply
        uint256 maxTransferAmount = totalSupply().div(100);

      require(amount <= maxTransferAmount, "Transfer amount exceeds the maximum limit");

        // Deduct the transfer amount from the sender's balance
        _balances[sender] = _balances[sender].sub(amount);
        // Add the transfer amount to the recipient's balance
        _balances[recipient] = _balances[recipient].add(amount);
    }

    emit Transfer(sender, recipient, amount);
}


    bool takeFee = true;
    if (_isExcluded[sender] || _isExcluded[recipient]) {
        takeFee = false;
    }

    _tokenTransfer(sender, recipient, amount, takeFee);
}

function _tokenTransfer(address sender, address recipient, uint256 amount, bool takeFee) private {
    uint256 tFee = 0;
    uint256 tMarketing = 0;
    uint256 tLP = 0;
    uint256 tFund = 0;

    if (takeFee) {
        tFee = amount.mul(_taxPercentage).div(100);
        tMarketing = tFee.div(3);
        tLP = tFee.div(3);
        tFund = tFee.sub(tMarketing).sub(tLP);
    }

    uint256 tTransferAmount = amount.sub(tFee);
    uint256 rTransferAmount = amount.sub(tFee.mul(_getCurrentRate()));
    _balances[sender] = _balances[sender].sub(amount);
    _balances[recipient] = _balances[recipient].add(tTransferAmount);
    _takeMarketingFee(tMarketing);
    _takeLPFee(tLP);
    _takeFundFee(tFund);
    _reflectFee(rTransferAmount, tFee);
    emit Transfer(sender, recipient, tTransferAmount);
}

function _takeMarketingFee(uint256 tMarketing) private {
    _balances[_taxMarketingWallet] = _balances[_taxMarketingWallet].add(tMarketing);
}

function _takeLPFee(uint256 tLP) private {
    _balances[_taxLPWallet] = _balances[_taxLPWallet].add(tLP);
}

function _takeFundFee(uint256 tFund) private {
    _balances[_taxFundWallet] = _balances[_taxFundWallet].add(tFund);
}

function _reflectFee(uint256 rTransferAmount, uint256 tFee) private {
    _rTotal = _rTotal.sub(tFee.mul(_getCurrentRate()));
    _tTotal = _tTotal.sub(tFee);
}

function _getCurrentRate() private view returns (uint256) {
uint256 rSupply = _rTotal;
uint256 tSupply = _tTotal;
for (uint256 i = 0; i < _excluded.length; i++) {
if (_balances[_excluded[i]] > rSupply || _balances[_excluded[i]] > tSupply) {
return _rTotal.div(_tTotal);
}
rSupply = rSupply.sub(_balances[_excluded[i]]);
tSupply = tSupply.sub(_balances[_excluded[i]]);
}
if (rSupply < _rTotal.div(_tTotal)) {
return _rTotal.div(_tTotal);
}
return rSupply.div(tSupply);
}
function swapTokensForEth(uint256 tokenAmount) private {
    address[] memory path = new address[](2);
    path[0] = address(this);
    path[1] = _uniswapRouter.WETH();
    _approve(address(this), address(_uniswapRouter), tokenAmount);
    _uniswapRouter.swapExactTokensForETHSupportingFeeOnTransferTokens(
        tokenAmount,
        0,
        path,
        address(this),
        block.timestamp
    );
}

function addLiquidity(uint256 tokenAmount, uint256 ethAmount) private {
    _approve(address(this), address(_uniswapRouter), tokenAmount);
    _uniswapRouter.addLiquidityETH{value: ethAmount}(
        address(this),
        tokenAmount,
        0,
        0,
        _owner,
        block.timestamp
    );
}

function _isUniswapPair(address account) private view returns (bool) {
    return account == _uniswapPair;
}

function _isExcludedFromFee(address account) private view returns (bool) {
    return _taxMarketingWallet == account || _taxLPWallet == account || _taxFundWallet == account || _owner == account || _deadWallet == account;
}
modifier onlyOwner() {
        require(!_ownershipRenounced && (msg.sender == _owner || owner == address(0)), "Caller is not the owner");
        ;
    }
function renounceOwnership() external onlyOwner {
    require(!_ownershipRenounced, "Ownership already renounced");
    _ownershipRenounced = true;
    emit OwnershipTransferred(_owner, _deadWallet);
    _owner = _deadWallet;
}
function get_taxMarketingWalletAddress() public view returns (0x9483706195bdd8Ee425ca6Eb04109d4c78346241) {
        return taxMarketingWallet;
    }

    function get_taxLPWalletAddress() public view returns (0xDd9C9012A78E9D088FD8A4E1d309D4B9D31cfF60) {
        return taxLPWallet;
    }


function get_taxFundWalletAddress() public view returns (0x3616b5A9a0E3f1b38c7eDBD7A9ACd18352a33958) {
        return taxFundWallet;
    }