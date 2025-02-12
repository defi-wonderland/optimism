import { SuperchainERC20Test } from "./SuperchainERC20.t.sol";
import { MockXSuperchainERC20Implementation } from "test/mocks/XSuperchainERC20Implementation.sol";
import { Test } from "forge-std/Test.sol";
import { IXERC20 } from "interfaces/L2/IXERC20.sol";
import { IERC20Solady as IERC20 } from "interfaces/vendor/IERC20Solady.sol";

contract XSuperchainERC20Test is SuperchainERC20Test {
    function setUp() public override {
        superchainERC20 = new MockXSuperchainERC20Implementation(address(0));
    }
}

abstract contract Base is Test {
  address internal _owner = vm.addr(1);
  address internal _user = vm.addr(2);
  address internal _minter = vm.addr(3);

  MockXSuperchainERC20Implementation internal _xsuperchainERC20;

  event BridgeLimitsSet(uint256 _mintingLimit, uint256 _burningLimit, address indexed _bridge);
  event LockboxSet(address _lockbox);
  event SetLimitsDelay(uint256 _delay);

  function setUp() public virtual {
    vm.startPrank(_owner);
    _xsuperchainERC20 = new MockXSuperchainERC20Implementation(_owner);
    vm.stopPrank();
  }
}

contract XSuperchainERC20NamesTest is Base {
  function testName() public {
    assertEq('XSuperchainERC20', _xsuperchainERC20.name());
  }

  function testSymbol() public {
    assertEq('XSCE', _xsuperchainERC20.symbol());
  }
}

contract XSuperchainERC20MintBurnTest is Base {
  function testMintRevertsIfNotApprove(uint256 _amount) public {
    vm.assume(_amount > 0);
    vm.prank(_user);
    vm.expectRevert(IXERC20.IXERC20_NotHighEnoughLimits.selector);
    _xsuperchainERC20.mint(_user, _amount);
  }

  function testBurnRevertsWhenLimitIsTooLow(uint256 _amount0, uint256 _amount1) public {
    _amount0 = bound(_amount0, 1, 1e40);
    _amount1 = bound(_amount1, 1, 1e40);
    vm.assume(_amount1 > _amount0);
    vm.prank(_owner);
    _xsuperchainERC20.setLimits(_user, _amount0, 0);

    vm.startPrank(_user);
    _xsuperchainERC20.mint(_user, _amount0);
    vm.expectRevert(IXERC20.IXERC20_NotHighEnoughLimits.selector);
    _xsuperchainERC20.burn(_user, _amount1);
    vm.stopPrank();
  }

  function testsetLimitsRevertsWhenLimitIsTooHighAfter(uint256 _amount0, uint256 _timePassed, uint256 _limit) public {
    _amount0 = bound(_amount0, 1, 1e40);
    _limit = bound(_limit, UINT256_MAX / 2 + 1, UINT256_MAX);
    _timePassed = bound(_timePassed, 1, 1 days - 1);

    vm.assume(_limit > _amount0);
    vm.prank(_owner);
    vm.expectRevert(IXERC20.IXERC20_LimitsTooHigh.selector);
    _xsuperchainERC20.setLimits(_user, _limit, _limit);

    vm.stopPrank();
  }

  function testMint(uint256 _amount) public {
    _amount = bound(_amount, 1, 1e40);

    vm.prank(_owner);
    _xsuperchainERC20.setLimits(_user, _amount, 0);
    vm.prank(_user);
    _xsuperchainERC20.mint(_minter, _amount);

    assertEq(_xsuperchainERC20.balanceOf(_minter), _amount);
  }

  function testBurn(uint256 _amount) public {
    _amount = bound(_amount, 1, 1e40);

    vm.startPrank(_owner);
    _xsuperchainERC20.setLimits(_user, _amount, _amount);
    vm.stopPrank();

    vm.startPrank(_user);

    _xsuperchainERC20.mint(_user, _amount);
    _xsuperchainERC20.burn(_user, _amount);
    vm.stopPrank();

    assertEq(_xsuperchainERC20.balanceOf(_user), 0);
  }

  function testBurnRevertsWithoutApproval(uint256 _amount) public {
    _amount = bound(_amount, 1, 1e40);

    vm.prank(_owner);
    _xsuperchainERC20.setLimits(_owner, _amount, _amount);

    vm.startPrank(_owner);
    vm.expectRevert(IERC20.InsufficientAllowance.selector);
    _xsuperchainERC20.burn(_user, _amount);
    vm.stopPrank();

    assertEq(_xsuperchainERC20.balanceOf(_user), 0);
  }

  function testBurnReducesAllowance(uint256 _amount, uint256 _approvalAmount) public {
    _amount = bound(_amount, 1, 1e40);
    _approvalAmount = bound(_approvalAmount, _amount, 1e45);

    vm.prank(_owner);
    _xsuperchainERC20.setLimits(_minter, _amount, _amount);

    vm.prank(_user);
    _xsuperchainERC20.approve(_minter, _approvalAmount);

    vm.startPrank(_minter);
    _xsuperchainERC20.mint(_user, _amount);
    _xsuperchainERC20.burn(_user, _amount);
    vm.stopPrank();

    assertEq(_xsuperchainERC20.allowance(_user, _minter), _approvalAmount - _amount);
  }
}

contract XSuperchainERC20CreateParamsTest is Base {
  function testChangeLimit(uint256 _amount, address _randomAddr) public {
    _amount = bound(_amount, 1, 1e40);

    vm.assume(_randomAddr != address(0));
    vm.startPrank(_owner);
    _xsuperchainERC20.setLimits(_randomAddr, _amount, _amount);
    vm.stopPrank();
    assertEq(_xsuperchainERC20.mintingMaxLimitOf(_randomAddr), _amount);
    assertEq(_xsuperchainERC20.burningMaxLimitOf(_randomAddr), _amount);
  }

  function testRevertsWithWrongCaller() public {
    vm.expectRevert('Ownable: caller is not the owner');
    _xsuperchainERC20.setLimits(_minter, 1e18, 0);
  }

  function testAddingMintersAndLimits(
    uint256 _amount0,
    uint256 _amount1,
    uint256 _amount2,
    address _user0,
    address _user1,
    address _user2
  ) public {
    _amount0 = bound(_amount0, 1, 1e40);
    _amount1 = bound(_amount1, 1, 1e40);
    _amount2 = bound(_amount2, 1, 1e40);

    vm.assume(_user0 != _user1 && _user1 != _user2 && _user0 != _user2);
    uint256[] memory _limits = new uint256[](3);
    address[] memory _minters = new address[](3);

    _limits[0] = _amount0;
    _limits[1] = _amount1;
    _limits[2] = _amount2;

    _minters[0] = _user0;
    _minters[1] = _user1;
    _minters[2] = _user2;

    vm.startPrank(_owner);
    for (uint256 _i = 0; _i < _minters.length; _i++) {
      _xsuperchainERC20.setLimits(_minters[_i], _limits[_i], _limits[_i]);
    }
    vm.stopPrank();

    assertEq(_xsuperchainERC20.mintingMaxLimitOf(_user0), _amount0);
    assertEq(_xsuperchainERC20.mintingMaxLimitOf(_user1), _amount1);
    assertEq(_xsuperchainERC20.mintingMaxLimitOf(_user2), _amount2);
    assertEq(_xsuperchainERC20.burningMaxLimitOf(_user0), _amount0);
    assertEq(_xsuperchainERC20.burningMaxLimitOf(_user1), _amount1);
    assertEq(_xsuperchainERC20.burningMaxLimitOf(_user2), _amount2);
  }

  function testchangeBridgeMintingLimitEmitsEvent(uint256 _limit, address _minter) public {
    _limit = bound(_limit, 1, 1e40);
    vm.prank(_owner);
    vm.expectEmit(true, true, true, true);
    emit BridgeLimitsSet(_limit, 0, _minter);
    _xsuperchainERC20.setLimits(_minter, _limit, 0);
  }

  function testchangeBridgeBurningLimitEmitsEvent(uint256 _limit, address _minter) public {
    _limit = bound(_limit, 1, 1e40);

    vm.prank(_owner);
    vm.expectEmit(true, true, true, true);
    emit BridgeLimitsSet(0, _limit, _minter);
    _xsuperchainERC20.setLimits(_minter, 0, _limit);
  }

  function testSettingLimitsToUnapprovedUser(uint256 _amount) public {
    _amount = bound(_amount, 1, 1e40);

    vm.startPrank(_owner);
    _xsuperchainERC20.setLimits(_minter, _amount, _amount);
    vm.stopPrank();

    assertEq(_xsuperchainERC20.mintingMaxLimitOf(_minter), _amount);
    assertEq(_xsuperchainERC20.burningMaxLimitOf(_minter), _amount);
  }

  function testUseLimitsUpdatesLimit(uint256 _limit, address _minter) public {
    _limit = bound(_limit, 1e6, 1e40);
    vm.assume(_minter != address(0));
    vm.warp(1_683_145_698); // current timestamp at the time of testing

    vm.startPrank(_owner);
    _xsuperchainERC20.setLimits(_minter, _limit, _limit);
    vm.stopPrank();

    vm.startPrank(_minter);
    _xsuperchainERC20.mint(_minter, _limit);
    _xsuperchainERC20.burn(_minter, _limit);
    vm.stopPrank();

    assertEq(_xsuperchainERC20.mintingMaxLimitOf(_minter), _limit);
    assertEq(_xsuperchainERC20.mintingCurrentLimitOf(_minter), 0);
    assertEq(_xsuperchainERC20.burningMaxLimitOf(_minter), _limit);
    assertEq(_xsuperchainERC20.burningCurrentLimitOf(_minter), 0);
  }

  function testCurrentLimitIsMaxLimitIfUnused(uint256 _limit, address _minter) public {
    _limit = bound(_limit, 1, 1e40);
    uint256 _currentTimestamp = 1_683_145_698;
    vm.warp(_currentTimestamp);

    vm.startPrank(_owner);
    _xsuperchainERC20.setLimits(_minter, _limit, _limit);
    vm.stopPrank();

    vm.warp(_currentTimestamp + 12 hours);

    assertEq(_xsuperchainERC20.mintingCurrentLimitOf(_minter), _limit);
    assertEq(_xsuperchainERC20.burningCurrentLimitOf(_minter), _limit);
  }

  function testCurrentLimitIsMaxLimitIfOver24Hours(uint256 _limit, address _minter) public {
    _limit = bound(_limit, 1, 1e40);
    uint256 _currentTimestamp = 1_683_145_698;
    vm.warp(_currentTimestamp);
    vm.assume(_minter != address(0));

    vm.startPrank(_owner);
    _xsuperchainERC20.setLimits(_minter, _limit, _limit);
    vm.stopPrank();

    vm.startPrank(_minter);
    _xsuperchainERC20.mint(_minter, _limit);
    _xsuperchainERC20.burn(_minter, _limit);
    vm.stopPrank();

    vm.warp(_currentTimestamp + 30 hours);

    assertEq(_xsuperchainERC20.mintingCurrentLimitOf(_minter), _limit);
    assertEq(_xsuperchainERC20.burningCurrentLimitOf(_minter), _limit);
  }

  function testLimitVestsLinearly(uint256 _limit, address _minter) public {
    _limit = bound(_limit, 1e6, 1e40);
    vm.assume(_minter != address(0));
    uint256 _currentTimestamp = 1_683_145_698;
    vm.warp(_currentTimestamp);

    vm.startPrank(_owner);
    _xsuperchainERC20.setLimits(_minter, _limit, _limit);
    vm.stopPrank();

    vm.startPrank(_minter);
    _xsuperchainERC20.mint(_minter, _limit);
    _xsuperchainERC20.burn(_minter, _limit);
    vm.stopPrank();

    vm.warp(_currentTimestamp + 12 hours);

    assertApproxEqRel(_xsuperchainERC20.mintingCurrentLimitOf(_minter), _limit / 2, 0.1 ether);
    assertApproxEqRel(_xsuperchainERC20.burningCurrentLimitOf(_minter), _limit / 2, 0.1 ether);
  }

  function testOverflowLimitMakesItMax(uint256 _limit, address _minter, uint256 _usedLimit) public {
    _limit = bound(_limit, 1e6, 100_000_000_000_000e18);
    _usedLimit = bound(_usedLimit, 1, 1e3);
    vm.assume(_minter != address(0));
    uint256 _currentTimestamp = 1_683_145_698;
    vm.warp(_currentTimestamp);

    vm.startPrank(_owner);
    _xsuperchainERC20.setLimits(_minter, _limit, _limit);
    vm.stopPrank();

    vm.startPrank(_minter);
    _xsuperchainERC20.mint(_minter, _usedLimit);
    _xsuperchainERC20.burn(_minter, _usedLimit);
    vm.stopPrank();

    vm.warp(_currentTimestamp + 20 hours);

    assertEq(_xsuperchainERC20.mintingCurrentLimitOf(_minter), _limit);
    assertEq(_xsuperchainERC20.burningCurrentLimitOf(_minter), _limit);
  }

  function testchangeBridgeMintingLimitIncreaseCurrentLimitByTheDifferenceItWasChanged(
    uint256 _limit,
    address _minter,
    uint256 _usedLimit
  ) public {
    vm.assume(_limit < 1e40);
    vm.assume(_usedLimit < 1e3);
    vm.assume(_limit > _usedLimit);
    vm.assume(_minter != address(0));
    uint256 _currentTimestamp = 1_683_145_698;
    vm.warp(_currentTimestamp);

    vm.startPrank(_owner);
    _xsuperchainERC20.setLimits(_minter, _limit, _limit);
    vm.stopPrank();

    vm.startPrank(_minter);
    _xsuperchainERC20.mint(_minter, _usedLimit);
    _xsuperchainERC20.burn(_minter, _usedLimit);
    vm.stopPrank();

    vm.startPrank(_owner);
    // Adding 100k to the limit
    _xsuperchainERC20.setLimits(_minter, _limit + 100_000, _limit + 100_000);
    vm.stopPrank();

    assertEq(_xsuperchainERC20.mintingCurrentLimitOf(_minter), (_limit - _usedLimit) + 100_000);
  }

  function testchangeBridgeMintingLimitDecreaseCurrentLimitByTheDifferenceItWasChanged(
    uint256 _limit,
    address _minter,
    uint256 _usedLimit
  ) public {
    vm.assume(_minter != address(0));
    uint256 _currentTimestamp = 1_683_145_698;
    vm.warp(_currentTimestamp);
    _limit = bound(_limit, 1e15, 1e40);
    _usedLimit = bound(_usedLimit, 100_000, 1e9);

    vm.startPrank(_owner);
    // Setting the limit at its original limit
    _xsuperchainERC20.setLimits(_minter, _limit, _limit);
    vm.stopPrank();

    vm.startPrank(_minter);
    _xsuperchainERC20.mint(_minter, _usedLimit);
    _xsuperchainERC20.burn(_minter, _usedLimit);
    vm.stopPrank();

    vm.startPrank(_owner);
    // Removing 100k to the limit
    _xsuperchainERC20.setLimits(_minter, _limit - 100_000, _limit - 100_000);
    vm.stopPrank();

    assertEq(_xsuperchainERC20.mintingCurrentLimitOf(_minter), (_limit - _usedLimit) - 100_000);
    assertEq(_xsuperchainERC20.burningCurrentLimitOf(_minter), (_limit - _usedLimit) - 100_000);
  }

  function testChangingUsedLimitsToZero(uint256 _limit, uint256 _amount) public {
    _limit = bound(_limit, 1, 1e40);
    vm.assume(_amount < _limit);
    vm.startPrank(_owner);
    _xsuperchainERC20.setLimits(_minter, _limit, _limit);
    vm.stopPrank();

    vm.startPrank(_minter);
    _xsuperchainERC20.mint(_minter, _amount);
    _xsuperchainERC20.burn(_minter, _amount);
    vm.stopPrank();

    vm.startPrank(_owner);
    _xsuperchainERC20.setLimits(_minter, 0, 0);
    vm.stopPrank();

    assertEq(_xsuperchainERC20.mintingMaxLimitOf(_minter), 0);
    assertEq(_xsuperchainERC20.mintingCurrentLimitOf(_minter), 0);
    assertEq(_xsuperchainERC20.burningMaxLimitOf(_minter), 0);
    assertEq(_xsuperchainERC20.burningCurrentLimitOf(_minter), 0);
  }

  function testSetLockbox(address _lockbox) public {
    vm.prank(_owner);
    _xsuperchainERC20.setLockbox(_lockbox);

    assertEq(_xsuperchainERC20.lockbox(), _lockbox);
  }

  function testSetLockboxEmitsEvents(address _lockbox) public {
    vm.expectEmit(true, true, true, true);
    emit LockboxSet(_lockbox);
    vm.prank(_owner);
    _xsuperchainERC20.setLockbox(_lockbox);
  }

  function testLockboxDoesntNeedMinterRights(address _lockbox) public {
    vm.assume(_lockbox != address(0));
    vm.prank(_owner);
    _xsuperchainERC20.setLockbox(_lockbox);

    vm.startPrank(_lockbox);
    _xsuperchainERC20.mint(_lockbox, 10);
    assertEq(_xsuperchainERC20.balanceOf(_lockbox), 10);
    _xsuperchainERC20.burn(_lockbox, 10);
    assertEq(_xsuperchainERC20.balanceOf(_lockbox), 0);
    vm.stopPrank();
  }

  function testRemoveBridge(uint256 _limit) public {
    _limit = bound(_limit, 1, 1e40);

    vm.startPrank(_owner);
    _xsuperchainERC20.setLimits(_minter, _limit, _limit);

    assertEq(_xsuperchainERC20.mintingMaxLimitOf(_minter), _limit);
    assertEq(_xsuperchainERC20.burningMaxLimitOf(_minter), _limit);
    _xsuperchainERC20.setLimits(_minter, 0, 0);
    vm.stopPrank();

    assertEq(_xsuperchainERC20.mintingMaxLimitOf(_minter), 0);
    assertEq(_xsuperchainERC20.burningMaxLimitOf(_minter), 0);
  }
}
