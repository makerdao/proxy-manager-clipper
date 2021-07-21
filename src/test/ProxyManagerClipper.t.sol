// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2021 Dai Foundation
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU Affero General Public License for more details.
//
// You should have received a copy of the GNU Affero General Public License
// along with this program.  If not, see <https://www.gnu.org/licenses/>.
pragma solidity 0.6.12;

import "ds-test/test.sol";
import {ProxyManagerClipper} from "../ProxyManagerClipper.sol";
import {Vat} from "dss/vat.sol";
import {Vow} from "dss/vow.sol";
import {Dog} from "dss/dog.sol";
import {Spotter} from "dss/spot.sol";
import {DSToken} from "ds-token/token.sol";
// import {Usr} from './CropManager-unit.t.sol';

contract MockCropJoin {
    Vat         public immutable vat;    // cdp engine
    bytes32     public immutable ilk;    // collateral type
    DSToken     public immutable gem;    // collateral token
    uint256     public immutable dec;    // gem decimals
    DSToken     public immutable bonus;  // rewards token

    mapping (address => uint256) public stake; // gems per user   [wad]

    constructor(address vat_, bytes32 ilk_, address gem_, address bonus_) public {
        vat = Vat(vat_);
        ilk = ilk_;
        gem = DSToken(gem_);
        dec = 18;
        bonus = DSToken(bonus_);
    }

    function add(uint256 x, uint256 y) public pure returns (uint256 z) {
        require((z = x + y) >= x, "ds-math-add-overflow");
    }
    function sub(uint256 x, uint256 y) public pure returns (uint256 z) {
        require((z = x - y) <= x, "ds-math-sub-underflow");
    }
    function join(address urn, address, uint256 wad) public {
        require(gem.transferFrom(msg.sender, address(this), wad));
        vat.slip(ilk, urn, int256(wad));
        stake[urn] = add(stake[urn], wad);
    }

    function exit(address urn, address usr, uint256 wad) public {
        require(gem.transfer(usr, wad));
        vat.slip(ilk, urn, -int256(wad));
        stake[urn] = sub(stake[urn], wad);
    }

    function tack(address src, address dst, uint256 wad) public {
        uint256 ss = stake[src];
        stake[src] = sub(ss, wad);
        stake[dst] = add(stake[dst], wad);
    }
}

contract UrnProxy {
    address immutable public usr;

    constructor(address vat_, address usr_) public {
        usr = usr_;
        Vat(vat_).hope(msg.sender);
    }
}

contract MockManager {
    mapping (address => address) public proxy; // UrnProxy per user

    address public immutable vat;

    constructor(address vat_) public {
        vat = vat_;
    }

    function getOrCreateProxy(address usr) public returns (address urp) {
        urp = proxy[usr];
        if (urp == address(0)) {
            urp = proxy[usr] = address(new UrnProxy(address(vat), usr));
        }
    }

    function join(address crop, address usr, uint256 val) external {
        DSToken(MockCropJoin(crop).gem()).transferFrom(msg.sender, address(this), val);
        DSToken(MockCropJoin(crop).gem()).approve(crop, val);
        MockCropJoin(crop).join(getOrCreateProxy(usr), usr, val);
    }

    function exit(address crop, address usr, uint256 val) external {
        MockCropJoin(crop).exit(proxy[msg.sender], usr, val);
    }

    function frob(address crop, address u, address, address w, int256 dink, int256 dart) external {
        address urp = getOrCreateProxy(u);
        Vat(vat).frob(MockCropJoin(crop).ilk(), urp, urp, w, dink, dart);
    }

    function onLiquidation(address crop, address usr, uint256 wad) external {
        address urp = proxy[usr];
        MockCropJoin(crop).join(urp, usr, 0);
        MockCropJoin(crop).tack(urp, msg.sender, wad);
    }

    function onVatFlux(address crop, address from, address to, uint256 wad) external {
        MockCropJoin(crop).tack(from, to, wad);
    }
}

contract MockPip {
    uint256 public val;
    function set(uint256 val_) external {
        val = val_;
    }
    function peek() external view returns (bytes32, bool) {
        return (bytes32(val), true);
    }
}

contract MockAbacus is MockPip {
    function price(uint256, uint256) external view returns (uint256) {
        return val;
    }
}

contract Usr {
    MockCropJoin adapter;
    MockManager  manager;

    constructor(MockCropJoin adapter_, MockManager  manager_) public {
        adapter = adapter_;
        manager = manager_;
    }
    function approve(address token, address usr) public {
        DSToken(token).approve(usr, uint256(-1));
    }
    function join(uint256 wad) public {
        manager.join(address(adapter), address(this), wad);
    }
    function exit(address usr, uint256 wad) public {
        manager.exit(address(adapter), usr, wad);
    }
    function proxy() public view returns (address) {
        return manager.proxy(address(this));
    }
    function stake() public view returns (uint256) {
        return adapter.stake(proxy());
    }
    function frob(int256 dink, int256 dart) public {
        manager.frob(address(adapter), address(this), address(this), address(this), dink, dart);
    }
}

contract ProxyManagerClipperTest is DSTest {
    
    DSToken gem;
    MockCropJoin join;
    MockManager manager;
    ProxyManagerClipper clipper;
    MockPip pip;
    MockAbacus abacus;
    bytes32 constant ILK = "GEM-A";

    Usr usr;

    Vat     vat;
    Vow     vow;
    Dog     dog;
    Spotter spotter;

    uint256 constant WAD = 10**18;
    uint256 constant RAY = 10**27;
    uint256 constant RAD = 10**45;

    function add(uint256 x, uint256 y) public pure returns (uint256 z) {
        require((z = x + y) >= x, "ds-math-add-overflow");
    }
    function sub(uint256 x, uint256 y) public pure returns (uint256 z) {
        require((z = x - y) <= x, "ds-math-sub-underflow");
    }
    function mul(uint256 x, uint256 y) public pure returns (uint256 z) {
        require(y == 0 || (z = x * y) / y == x, "ds-math-mul-overflow");
    }

    function setUp() public {
        vat     = new Vat();
        vow     = new Vow(address(vat), address(0), address(0));
        dog     = new Dog(address(vat));
        spotter = new Spotter(address(vat));

        vat.rely(address(dog));
        vat.rely(address(spotter));
        vow.rely(address(dog));

        // Initialize GEM-A in the Vat
        vat.init(ILK);

        vat.file(ILK, "line", 10**6 * RAD);
        vat.file("Line", add(vat.Line(), 10**6 * RAD));  // Ensure there is room in the global debt ceiling

        // Initialize price feed
        pip = new MockPip();
        pip.set(WAD);  // Initial price of $1 per gem
        spotter.file(ILK, "pip", address(pip));
        spotter.file(ILK, "mat", 2 * RAY);  // 200% collateralization ratio
        spotter.poke(ILK);

        gem     = new DSToken("GEM");
        gem.mint(10**6 * WAD);
        join    = new MockCropJoin(address(vat), ILK, address(gem), address(0));
        manager = new MockManager(address(vat));
        clipper = new ProxyManagerClipper(address(vat), address(spotter), address(dog), address(join), address(manager));

        // Auth setup
        clipper.rely(address(dog));
        dog.rely(address(clipper));
        vat.rely(address(join));

        dog.file("vow", address(vow));

        // Initialize GEM-A in the Dog
        dog.file(ILK, "hole", 10**6 * RAD);
        dog.file("Hole", add(dog.Hole(), 10**6 * RAD));
        dog.file(ILK, "clip", address(clipper));
        dog.file(ILK, "chop", 110 * WAD / 100);

        // Set up pricing
        abacus = new MockAbacus();
        abacus.set(mul(pip.val(), 10**9));
        clipper.file("calc", address(abacus));

        // Create Vault
        usr = new Usr(join, manager);
        gem.transfer(address(usr), 10**3 * WAD);
        usr.approve(address(gem), address(manager));
        usr.join(10**3 * WAD);
        usr.frob(int256(10**3 * WAD), int256(500 * WAD));  // Draw maximum possible debt

        // Draw some DAI for this contract for bidding on auctions.
        // This conveniently provisions an UrnProxy for the test contract as well.
        gem.approve(address(manager), uint256(-1));
        manager.join(address(join), address(this), 10**4 * WAD);
        manager.frob(address(join), address(this), address(this), address(this), int256(10**4 * WAD), int256(1000 * WAD));

        // Hope the clipper so we can bid.
        vat.hope(address(clipper));

        // Simulate fee collection; usr's Vault becomes unsafe.
        vat.fold(ILK, address(vow), int256(RAY / 5));
    }

    function test_kick_via_bark() public {
        assertEq(usr.stake(), 10**3 * WAD);
        assertEq(join.stake(address(clipper)), 0);
        dog.bark(ILK, usr.proxy(), address(this));
        assertEq(usr.stake(), 0);
        assertEq(join.stake(address(clipper)), 10**3 * WAD);
    }

    function test_take_all() public {
        address urp = manager.proxy(address(this));
        uint256 initialStake    = join.stake(urp);
        uint256 initialGemBal   = gem.balanceOf(address(this));

        uint256 id = dog.bark(ILK, usr.proxy(), address(this));

        // Quarter of a DAI per gem--this means the total value of collateral is 250 DAI,
        // which is less than the tab. Thus we'll purchase 100% of the collateral.
        uint256 price = 25 * RAY / 100;
        abacus.set(price);

        // Assert that the statement above is indeed true.
        (, uint256 tab, uint256 lot,,,) = clipper.sales(id);
        assertTrue(mul(lot, price) < tab);

        // Ensure that we have enough DAI to cover our purchase.
        assertTrue(mul(lot, price) < vat.dai(address(this)));

        bytes memory emptyBytes;
        clipper.take(id, lot, price, address(this), emptyBytes);

        (, tab, lot,,,) = clipper.sales(id);
        assertEq(tab, 0);
        assertEq(lot, 0);

        // The collateral has been transferred to us.
        assertEq(join.stake(urp), add(10**3 * WAD, initialStake));

        // We can exit without needing to tack.
        manager.exit(address(join), address(this), 10**3 * WAD);
        assertEq(join.stake(urp), initialStake);
        assertEq(gem.balanceOf(address(this)), add(initialGemBal, 10**3 * WAD));
    }

    function test_take_return_collateral() public {
        address urp = manager.proxy(address(this));
        uint256 initialStake    = join.stake(urp);
        uint256 initialGemBal   = gem.balanceOf(address(this));

        uint256 id = dog.bark(ILK, usr.proxy(), address(this));

        // One DAI per gem; will be able to fully cover tab, leaving leftover collateral.
        uint256 price = RAY;
        abacus.set(price);

        // Assert that the statement above is indeed true.
        (, uint256 tab, uint256 lot,,,) = clipper.sales(id);
        assertTrue(mul(lot, price) > tab);

        // Ensure that we have enough DAI to cover our purchase.
        assertTrue(tab < vat.dai(address(this)));

        uint256 expectedPurchaseSize = tab / price;

        bytes memory emptyBytes;
        clipper.take(id, lot, price, address(this), emptyBytes);

        (, tab, lot,,,) = clipper.sales(id);
        assertEq(tab, 0);
        assertEq(lot, 0);

        // The collateral has been transferred to us.
        assertEq(join.stake(urp), add(expectedPurchaseSize, initialStake));

        // The remainder returned to the liquidated Vault.
        uint256 collateralReturned = sub(10**3 * WAD, expectedPurchaseSize);
        assertEq(usr.stake(), collateralReturned);

        // We can exit without needing to tack.
        manager.exit(address(join), address(this), expectedPurchaseSize);
        assertEq(join.stake(urp), initialStake);
        assertEq(gem.balanceOf(address(this)), add(initialGemBal, expectedPurchaseSize));

        // Liquidated urn can exit and get its fair share of rewards as well.
        usr.exit(address(usr), collateralReturned);
        assertEq(usr.stake(), 0);
        assertEq(gem.balanceOf(address(usr)), collateralReturned);
    }

    function test_yank() public {
        address urp = manager.proxy(address(this));
        uint256 initialStake    = join.stake(urp);
        uint256 initialGemBal   = gem.balanceOf(address(this));

        uint256 id = dog.bark(ILK, usr.proxy(), address(this));

        clipper.yank(id);

        // The collateral has been transferred to this contract specifically--
        // yank gets called by the End, which has no UrnProxy.
        assertEq(join.stake(address(this)), 10**3 * WAD);

        // We can exit if we flux and tack to our UrnProxy.
        vat.flux(ILK, address(this), urp, 10**3 * WAD);
        join.tack(address(this), urp, 10**3 * WAD);
        assertEq(join.stake(urp), add(10**3 * WAD, initialStake));
        manager.exit(address(join), address(this), 10**3 * WAD);
        assertEq(join.stake(urp), initialStake);
        assertEq(gem.balanceOf(address(this)), add(initialGemBal, 10**3 * WAD));
    }
}
